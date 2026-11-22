// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_unicode_file_ops.h"

#include <shlobj.h>
#include <cstring>
#include <string_view>
#include <vector>

namespace Salamander
{
inline DWORD UnicodeClipboardTransferEffect(DWORD advertisedEffect)
{
    const DWORD transfer = advertisedEffect & (DROPEFFECT_COPY | DROPEFFECT_MOVE);
    return transfer == DROPEFFECT_COPY || transfer == DROPEFFECT_MOVE ? transfer : DROPEFFECT_NONE;
}

// Parse the HGLOBAL snapshot returned by IDataObject. Never pass a malformed
// list, an ANSI alias or an unvalidated device path to a filesystem API.
inline bool TryReadUnicodeClipboardFiles(const void* data, std::size_t bytes,
                                         std::vector<Utf16DiskPath>& files, DWORD& error)
{
    files.clear();
    error = ERROR_INVALID_DATA;
    DROPFILES header{};
    if (!data || bytes < sizeof(header) || bytes > 8 * 1024 * 1024)
        return false;
    memcpy(&header, data, sizeof(header));
    if (!header.fWide || header.pFiles < sizeof(header) || header.pFiles >= bytes ||
        header.pFiles % alignof(wchar_t) != 0)
        return false;

    const auto* text = reinterpret_cast<const wchar_t*>(
        static_cast<const unsigned char*>(data) + header.pFiles);
    const auto capacity = (bytes - header.pFiles) / sizeof(wchar_t);
    std::vector<Utf16DiskPath> snapshot;
    for (std::size_t start = 0; start < capacity;)
    {
        if (text[start] == L'\0')
        {
            if (snapshot.empty())
                return false;
            files.swap(snapshot);
            error = ERROR_SUCCESS;
            return true;
        }
        std::size_t end = start;
        while (end < capacity && text[end] != L'\0' && end - start < 32767)
            ++end;
        if (end == capacity || end - start == 32767 || snapshot.size() == 1024)
            return false;

        std::wstring_view path(text + start, end - start);
        std::u16string absolute;
        if (path.size() >= 8 && CompareStringOrdinal(path.data(), 8, L"\\\\?\\UNC\\", 8, TRUE) == CSTR_EQUAL)
        {
            absolute = u"\\\\";
            path.remove_prefix(8);
        }
        else if (path.size() >= 4 && path.substr(0, 4) == L"\\\\?\\")
        {
            path.remove_prefix(4);
            if (path.size() < 3 || path[1] != L':' || path[2] != L'\\')
                return false;
        }
        absolute.append(path.begin(), path.end());
        Utf16DiskPath file;
        Utf16PathError pathError;
        if (!Utf16DiskPath::TryCreateAbsolute(absolute, file, pathError))
        {
            error = ERROR_INVALID_NAME;
            return false;
        }
        snapshot.push_back(std::move(file));
        start = end + 1;
    }
    return false; // Missing final list terminator.
}

inline bool TryTransferUnicodeClipboardFiles(const std::vector<Utf16DiskPath>& files,
                                             const Utf16DiskPath& directory, DWORD effect,
                                             std::size_t& completed, DWORD& error)
{
    completed = 0;
    error = ERROR_INVALID_PARAMETER;
    if (files.empty() || files.size() > 16)
        return false;
    // A single same-volume rename is atomic. Moving a whole cut selection
    // needs a separate recovery contract for failures partway through.
    if (effect != DROPEFFECT_COPY && (effect != DROPEFFECT_MOVE || files.size() != 1))
    {
        error = ERROR_NOT_SUPPORTED;
        return false;
    }
    constexpr ULONGLONG maxSynchronousBytes = 16ULL * 1024 * 1024;
    ULONGLONG totalBytes = 0;

    struct Destination
    {
        std::wstring name;
        Utf16DiskPath path;
    };
    std::vector<Destination> destinations;
    destinations.reserve(files.size());
    for (const auto& file : files)
    {
        std::wstring source;
        if (!UnicodeFileOperationsDetail::TryGetExtendedPath(file, source, error))
            return false;
        WIN32_FILE_ATTRIBUTE_DATA attributes{};
        if (!GetFileAttributesExW(source.c_str(), GetFileExInfoStandard, &attributes))
        {
            error = GetLastError();
            return false;
        }
        if (attributes.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))
        {
            error = ERROR_NOT_SUPPORTED;
            return false;
        }
        const ULONGLONG bytes = (static_cast<ULONGLONG>(attributes.nFileSizeHigh) << 32) |
                                attributes.nFileSizeLow;
        if (effect == DROPEFFECT_COPY && bytes > maxSynchronousBytes - totalBytes)
        {
            error = ERROR_FILE_TOO_LARGE;
            return false;
        }
        totalBytes += bytes;

        const auto& absolute = file.Value();
        const auto component = std::u16string_view(absolute).substr(absolute.find_last_of(u'\\') + 1);
        Utf16FileName name;
        Utf16PathError pathError;
        Destination target;
        if (!Utf16FileName::TryCreate(component, name, pathError) ||
            !directory.TryAppend(name, target.path, pathError))
        {
            error = pathError == Utf16PathError::PathTooLong ? ERROR_FILENAME_EXCED_RANGE : ERROR_INVALID_NAME;
            return false;
        }
        target.name.assign(component.begin(), component.end());
        for (const auto& existing : destinations)
        {
            if (CompareStringOrdinal(existing.name.c_str(), -1, target.name.c_str(), -1, TRUE) == CSTR_EQUAL)
            {
                error = ERROR_DUP_NAME;
                return false;
            }
        }
        std::wstring extendedTarget;
        if (!UnicodeFileOperationsDetail::TryGetExtendedPath(target.path, extendedTarget, error))
            return false;
        if (GetFileAttributesW(extendedTarget.c_str()) != INVALID_FILE_ATTRIBUTES)
        {
            error = ERROR_FILE_EXISTS;
            return false;
        }
        error = GetLastError();
        if (error != ERROR_FILE_NOT_FOUND)
            return false;
        destinations.push_back(std::move(target));
    }

    for (std::size_t index = 0; index < files.size(); ++index)
    {
        const bool success = effect == DROPEFFECT_MOVE
            ? TryMoveUnicodeFileNoOverwrite(files[index], destinations[index].path, error)
            : TryCopyUnicodeFileNoOverwrite(files[index], destinations[index].path, error);
        if (!success)
            return false;
        ++completed;
    }
    return true;
}
} // namespace Salamander
