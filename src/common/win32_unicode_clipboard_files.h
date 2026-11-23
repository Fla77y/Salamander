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
inline bool TryEncodeUnicodeFileDrop(const std::vector<Utf16DiskPath>& files,
                                    std::vector<unsigned char>& bytes)
{
    bytes.clear();
    if (files.empty() || files.size() > 1024)
        return false;
    std::size_t units = 1;
    for (const auto& file : files)
    {
        if (file.Value().empty())
            return false;
        units += file.Value().size() + 1;
    }
    const std::size_t size = sizeof(DROPFILES) + units * sizeof(char16_t);
    if (size > 8 * 1024 * 1024)
        return false;
    DROPFILES header{};
    header.pFiles = sizeof(header);
    header.fWide = TRUE;
    bytes.resize(size);
    memcpy(bytes.data(), &header, sizeof(header));
    std::size_t offset = sizeof(header);
    for (const auto& file : files)
    {
        const std::size_t length = (file.Value().size() + 1) * sizeof(char16_t);
        memcpy(bytes.data() + offset, file.Value().c_str(), length);
        offset += length;
    }
    return true;
}

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

// Keep the validated file open until the transfer completes. A copy also
// prevents writes while its size and identity are used by the copy engine.
inline HANDLE OpenUnicodeClipboardSource(const std::wstring& path, DWORD effect,
                                         BY_HANDLE_FILE_INFORMATION& info, DWORD& error)
{
    const bool moving = effect == DROPEFFECT_MOVE;
    HANDLE source = CreateFileW(path.c_str(), moving ? DELETE | FILE_READ_ATTRIBUTES : GENERIC_READ,
        moving ? FILE_SHARE_READ | FILE_SHARE_WRITE : FILE_SHARE_READ, nullptr, OPEN_EXISTING,
        FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (source == INVALID_HANDLE_VALUE)
    {
        error = GetLastError();
        return source;
    }

    if (!GetFileInformationByHandle(source, &info))
        error = GetLastError();
    else if ((info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
             (!moving && (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)))
        error = ERROR_NOT_SUPPORTED;
    else if (!moving && !info.nFileIndexHigh && !info.nFileIndexLow)
        error = ERROR_FILE_INVALID;
    else
    {
        error = ERROR_SUCCESS;
        return source;
    }
    CloseHandle(source);
    return INVALID_HANDLE_VALUE;
}

inline bool RenameUnicodeClipboardSource(HANDLE source, const Utf16DiskPath& destination, DWORD& error)
{
    std::wstring target;
    return UnicodeFileOperationsDetail::TryGetExtendedPath(destination, target, error) &&
        UnicodeFileOperationsDetail::TryRenameOpenFileNoOverwrite(source, target, error);
}

inline bool TryTransferUnicodeClipboardFiles(const std::vector<Utf16DiskPath>& files,
                                             const Utf16DiskPath& directory, DWORD effect,
                                             std::size_t& completed, DWORD& error)
{
    completed = 0;
    error = ERROR_INVALID_PARAMETER;
    if (files.empty() || files.size() > 16)
        return false;
    if (effect != DROPEFFECT_COPY && effect != DROPEFFECT_MOVE)
    {
        error = ERROR_NOT_SUPPORTED;
        return false;
    }
    DWORD destinationVolume = 0;
    if (effect == DROPEFFECT_MOVE)
    {
        std::wstring extendedDirectory;
        if (!UnicodeFileOperationsDetail::TryGetExtendedPath(directory, extendedDirectory, error))
            return false;
        const HANDLE target = CreateFileW(extendedDirectory.c_str(), FILE_READ_ATTRIBUTES,
                                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                         nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
        if (target == INVALID_HANDLE_VALUE)
        {
            error = GetLastError();
            return false;
        }
        BY_HANDLE_FILE_INFORMATION info{};
        const BOOL inspected = GetFileInformationByHandle(target, &info);
        error = inspected ? ERROR_DIRECTORY : GetLastError();
        CloseHandle(target);
        if (!inspected || !(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
            return false;
        destinationVolume = info.dwVolumeSerialNumber;
    }

    constexpr ULONGLONG maxSynchronousBytes = 16ULL * 1024 * 1024;
    ULONGLONG totalBytes = 0;
    struct SourceGuard
    {
        std::vector<HANDLE> handles;
        ~SourceGuard()
        {
            for (HANDLE handle : handles)
                CloseHandle(handle);
        }
    } sources;
    sources.handles.reserve(files.size());

    struct Destination
    {
        std::wstring name;
        Utf16DiskPath path;
        BY_HANDLE_FILE_INFORMATION sourceInfo{};
    };
    std::vector<Destination> destinations;
    destinations.reserve(files.size());
    for (const auto& file : files)
    {
        std::wstring source;
        if (!UnicodeFileOperationsDetail::TryGetExtendedPath(file, source, error))
            return false;
        Destination target;
        const HANDLE handle = OpenUnicodeClipboardSource(source, effect, target.sourceInfo, error);
        if (handle == INVALID_HANDLE_VALUE)
            return false;
        sources.handles.push_back(handle);
        if (effect == DROPEFFECT_COPY)
        {
            const ULONGLONG bytes = (static_cast<ULONGLONG>(target.sourceInfo.nFileSizeHigh) << 32) |
                                    target.sourceInfo.nFileSizeLow;
            if (bytes > maxSynchronousBytes - totalBytes)
            {
                error = ERROR_FILE_TOO_LARGE;
                return false;
            }
            totalBytes += bytes;
        }
        else if (target.sourceInfo.dwVolumeSerialNumber != destinationVolume)
        {
            error = ERROR_NOT_SAME_DEVICE;
            return false;
        }

        const auto& absolute = file.Value();
        const auto component = std::u16string_view(absolute).substr(absolute.find_last_of(u'\\') + 1);
        Utf16FileName name;
        Utf16PathError pathError;
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
            ? RenameUnicodeClipboardSource(sources.handles[index], destinations[index].path, error)
            : TryCopyUnicodeFileNoOverwrite(files[index], destinations[index].path, error,
                                           &destinations[index].sourceInfo);
        if (!success)
        {
            // Each rename is atomic. Undo earlier moves if a later one fails.
            // A new file at an original name is never overwritten during rollback.
            if (effect == DROPEFFECT_MOVE)
            {
                for (std::size_t moved = index; moved > 0; --moved)
                {
                    DWORD rollbackError;
                    if (RenameUnicodeClipboardSource(sources.handles[moved - 1], files[moved - 1], rollbackError))
                        --completed;
                }
            }
            return false;
        }
        ++completed;
    }
    return true;
}
} // namespace Salamander
