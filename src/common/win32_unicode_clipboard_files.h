// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_unicode_file_ops.h"
#include "win32_long_directory.h"

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
                                         BY_HANDLE_FILE_INFORMATION& info, DWORD& error,
                                         bool allowDelete = false, bool allowDirectories = false)
{
    const bool moving = effect == DROPEFFECT_MOVE;
    HANDLE source = CreateFileW(path.c_str(), moving ? DELETE | FILE_READ_ATTRIBUTES : GENERIC_READ,
        moving ? FILE_SHARE_READ | FILE_SHARE_WRITE : FILE_SHARE_READ | (allowDelete ? FILE_SHARE_DELETE : 0),
        nullptr, OPEN_EXISTING,
        FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (source == INVALID_HANDLE_VALUE)
    {
        error = GetLastError();
        return source;
    }

    if (!GetFileInformationByHandle(source, &info))
        error = GetLastError();
    else if ((info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
             (!moving && !allowDirectories && (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)))
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

// Hold a read handle that allows deletion but denies writes throughout this
// operation. A separate handle pins the exact name before deleting the source.
inline bool MoveUnicodeClipboardFileByCopy(const Utf16DiskPath& source,
                                           const Utf16DiskPath& destination,
                                           const BY_HANDLE_FILE_INFORMATION& expected, DWORD& error)
{
    std::wstring path;
    HANDLE copiedFile = INVALID_HANDLE_VALUE;
    if (!UnicodeFileOperationsDetail::TryGetExtendedPath(source, path, error) ||
        !TryCopyUnicodeFileNoOverwrite(source, destination, error, &expected, &copiedFile))
        return false;

    struct CopyGuard { HANDLE file; ~CopyGuard() { CloseHandle(file); } } copy{copiedFile};
    const HANDLE original = CreateFileW(path.c_str(), DELETE | FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (original == INVALID_HANDLE_VALUE)
    {
        error = GetLastError();
        return false;
    }

    BY_HANDLE_FILE_INFORMATION actual{};
    if (!GetFileInformationByHandle(original, &actual))
        error = GetLastError();
    else if (!UnicodeFileOperationsDetail::IsSameRegularFile(expected, actual))
        error = ERROR_FILE_INVALID;
    else
    {
        FILE_DISPOSITION_INFO disposition{TRUE};
        error = SetFileInformationByHandle(original, FileDispositionInfo, &disposition, sizeof(disposition))
            ? ERROR_SUCCESS : GetLastError();
    }
    CloseHandle(original);
    return error == ERROR_SUCCESS;
}

inline bool RenameUnicodeClipboardSource(HANDLE source, const Utf16DiskPath& destination, DWORD& error)
{
    std::wstring target;
    return UnicodeFileOperationsDetail::TryGetExtendedPath(destination, target, error) &&
        UnicodeFileOperationsDetail::TryRenameOpenFileNoOverwrite(source, target, error);
}

inline std::wstring UnicodeClipboardVolumeName(HANDLE file)
{
    // Native device names distinguish cloned volume serials and remain
    // available on Windows volumes that have no registered GUID path.
    const DWORD options = VOLUME_NAME_NT | FILE_NAME_OPENED;
    const DWORD capacity = GetFinalPathNameByHandleW(file, nullptr, 0, options);
    if (!capacity || capacity > 32767)
        return {};
    std::wstring path(capacity, L'\0');
    const DWORD length = GetFinalPathNameByHandleW(file, path.data(), capacity, options);
    if (!length || length >= capacity)
        return {};
    path.resize(length);
    constexpr wchar_t prefix[] = L"\\Device\\";
    if (path.compare(0, _countof(prefix) - 1, prefix) != 0)
        return {};
    const auto end = path.find(L'\\', _countof(prefix) - 1);
    if (end == std::wstring::npos)
        return {};
    path.resize(end);
    if (path.rfind(L"\\Device\\HarddiskVolume", 0) != 0 && path.rfind(L"\\Device\\Volume{", 0) != 0)
        return {};
    return path;
}

inline bool CopyUnicodeClipboardTree(const Utf16DiskPath& source, const Utf16DiskPath& parent,
                                     const Utf16DiskPath& destination, ULONGLONG& remainingBytes,
                                     DWORD& error)
{
    struct Entry
    {
        std::size_t parent = 0;
        Utf16FileName name;
        Utf16DiskPath path;
        BY_HANDLE_FILE_INFORMATION info{};
    };
    struct LockedEntries
    {
        std::vector<HANDLE> handles;
        ~LockedEntries() { for (HANDLE handle : handles) CloseHandle(handle); }
    } locked;
    constexpr std::size_t maxEntries = 1024;
    locked.handles.reserve(maxEntries);
    std::vector<Entry> tree(1);
    tree.front().path = source;
    for (std::size_t index = 0; index < tree.size(); ++index)
    {
        auto& entry = tree[index];
        std::wstring extended;
        if (!UnicodeFileOperationsDetail::TryGetExtendedPath(entry.path, extended, error))
            return false;
        const HANDLE handle = OpenUnicodeClipboardSource(extended, DROPEFFECT_COPY, entry.info, error, false, true);
        if (handle == INVALID_HANDLE_VALUE)
            return false;
        locked.handles.push_back(handle);
        if (!(entry.info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
        {
            const ULONGLONG size = (static_cast<ULONGLONG>(entry.info.nFileSizeHigh) << 32) | entry.info.nFileSizeLow;
            if (size > remainingBytes)
            {
                error = ERROR_FILE_TOO_LARGE;
                return false;
            }
            remainingBytes -= size;
            continue;
        }

        const auto& value = entry.path.Value();
        const std::wstring name(value.begin(), value.end());
        std::vector<LongDirectoryEntry> children;
        if (!TryEnumerateLongDirectory(name.c_str(), children, error, maxEntries - tree.size()))
            return false;
        for (const auto& child : children)
        {
            Entry item;
            item.parent = index;
            Utf16PathError pathError;
            if (!Utf16FileName::TryCreate(std::u16string(child.name.begin(), child.name.end()), item.name, pathError) ||
                !tree[index].path.TryAppend(item.name, item.path, pathError))
            {
                error = pathError == Utf16PathError::PathTooLong ? ERROR_FILENAME_EXCED_RANGE : ERROR_INVALID_NAME;
                return false;
            }
            tree.push_back(std::move(item));
        }
    }

    static std::atomic<unsigned long long> nextStage{0};
    wchar_t stageName[64];
    swprintf_s(stageName, L".opensal-tree-%08lX-%016llX-%016llX", GetCurrentProcessId(),
               static_cast<unsigned long long>(GetTickCount64()), ++nextStage);
    Utf16FileName stageComponent;
    Utf16PathError pathError;
    std::vector<Utf16DiskPath> staged(tree.size());
    if (!Utf16FileName::TryCreate(std::u16string(stageName, stageName + wcslen(stageName)), stageComponent, pathError) ||
        !parent.TryAppend(stageComponent, staged.front(), pathError))
    {
        error = ERROR_FILENAME_EXCED_RANGE;
        return false;
    }
    std::wstring stagePath, finalPath;
    if (!UnicodeFileOperationsDetail::TryGetExtendedPath(staged.front(), stagePath, error) ||
        !UnicodeFileOperationsDetail::TryGetExtendedPath(destination, finalPath, error))
        return false;
    for (std::size_t index = 1; index < tree.size(); ++index)
    {
        if (!staged[tree[index].parent].TryAppend(tree[index].name, staged[index], pathError))
        {
            error = ERROR_FILENAME_EXCED_RANGE;
            return false;
        }
    }
    const auto& original = source.Value();
    const auto& target = destination.Value();
    const std::wstring originalName(original.begin(), original.end());
    const std::wstring targetName(target.begin(), target.end());
    if (target.size() > original.size() && target[original.size()] == u'\\' &&
        CompareStringOrdinal(targetName.c_str(), static_cast<int>(original.size()),
                             originalName.c_str(), static_cast<int>(original.size()), TRUE) == CSTR_EQUAL)
    {
        error = ERROR_INVALID_PARAMETER;
        return false;
    }
    if (!CreateDirectoryW(stagePath.c_str(), nullptr))
    {
        error = GetLastError();
        return false;
    }
    const HANDLE stage = CreateFileW(stagePath.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (stage == INVALID_HANDLE_VALUE)
    {
        error = GetLastError();
        return false;
    }
    struct StageGuard
    {
        HANDLE handle;
        ~StageGuard() { if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle); }
    } stageGuard{stage};
    BY_HANDLE_FILE_INFORMATION stageInfo{};
    if (!GetFileInformationByHandle(stage, &stageInfo) ||
        (stageInfo.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != FILE_ATTRIBUTE_DIRECTORY)
    {
        error = ERROR_DIRECTORY;
        return false;
    }
    for (std::size_t index = 1; index < tree.size(); ++index)
    {
        const auto& entry = tree[index];
        if (entry.info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
        {
            std::wstring path;
            if (!UnicodeFileOperationsDetail::TryGetExtendedPath(staged[index], path, error))
                return false;
            if (!CreateDirectoryW(path.c_str(), nullptr))
            {
                error = GetLastError();
                return false;
            }
        }
        else if (!TryCopyUnicodeFileNoOverwrite(entry.path, staged[index], error, &entry.info))
            return false;
    }
    CloseHandle(stageGuard.handle);
    stageGuard.handle = CreateFileW(stagePath.c_str(), DELETE | FILE_READ_ATTRIBUTES, FILE_SHARE_READ,
        nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (stageGuard.handle == INVALID_HANDLE_VALUE)
    {
        error = GetLastError();
        return false;
    }
    BY_HANDLE_FILE_INFORMATION published{};
    if (!GetFileInformationByHandle(stageGuard.handle, &published))
    {
        error = GetLastError();
        return false;
    }
    if ((published.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != FILE_ATTRIBUTE_DIRECTORY ||
        published.dwVolumeSerialNumber != stageInfo.dwVolumeSerialNumber ||
        published.nFileIndexHigh != stageInfo.nFileIndexHigh || published.nFileIndexLow != stageInfo.nFileIndexLow ||
        (!published.nFileIndexHigh && !published.nFileIndexLow))
    {
        error = ERROR_FILE_INVALID;
        return false;
    }
    // Never clean an unverified subtree after a publication failure.
    return UnicodeFileOperationsDetail::TryRenameOpenFileNoOverwrite(stageGuard.handle, finalPath, error);
}

inline bool TryTransferUnicodeClipboardFiles(const std::vector<Utf16DiskPath>& files,
                                             const Utf16DiskPath& directory, DWORD effect,
                                             std::size_t& completed, DWORD& error,
                                             const std::vector<BY_HANDLE_FILE_INFORMATION>* expectedSources = nullptr)
{
    completed = 0;
    error = ERROR_INVALID_PARAMETER;
    if (files.empty() || files.size() > 16 ||
        (expectedSources != nullptr && expectedSources->size() != files.size()))
        return false;
    if (effect != DROPEFFECT_COPY && effect != DROPEFFECT_MOVE)
    {
        error = ERROR_NOT_SUPPORTED;
        return false;
    }
    DWORD destinationVolume = 0;
    std::wstring destinationVolumeName;
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
        if (inspected)
            destinationVolumeName = UnicodeClipboardVolumeName(target);
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
        bool copyThenDelete = false;
    };
    std::vector<Destination> destinations;
    destinations.reserve(files.size());
    for (std::size_t fileIndex = 0; fileIndex < files.size(); ++fileIndex)
    {
        const auto& file = files[fileIndex];
        std::wstring source;
        if (!UnicodeFileOperationsDetail::TryGetExtendedPath(file, source, error))
            return false;
        Destination target;
        const HANDLE handle = OpenUnicodeClipboardSource(source, effect, target.sourceInfo, error, false, true);
        if (handle == INVALID_HANDLE_VALUE)
            return false;
        // A GUI operation can retain the exact file ID selected before its
        // modal confirmation; never copy/delete a different file later
        // substituted at the same path, even with identical bytes.
        if (expectedSources != nullptr &&
            !UnicodeFileOperationsDetail::IsSameRegularFile(
                (*expectedSources)[fileIndex], target.sourceInfo))
        {
            CloseHandle(handle);
            error = ERROR_FILE_INVALID;
            return false;
        }
        sources.handles.push_back(handle);
        if (effect == DROPEFFECT_MOVE)
        {
            const auto sourceVolumeName = UnicodeClipboardVolumeName(handle);
            target.copyThenDelete = target.sourceInfo.dwVolumeSerialNumber != destinationVolume ||
                (!sourceVolumeName.empty() && !destinationVolumeName.empty() &&
                 sourceVolumeName != destinationVolumeName);
        }
        if (target.copyThenDelete)
        {
            BY_HANDLE_FILE_INFORMATION readableInfo{};
            const HANDLE readable = OpenUnicodeClipboardSource(source, DROPEFFECT_COPY, readableInfo, error, true);
            if (readable == INVALID_HANDLE_VALUE)
                return false;
            const bool sameFile = UnicodeFileOperationsDetail::IsSameRegularFile(target.sourceInfo, readableInfo);
            CloseHandle(handle);
            sources.handles.back() = readable;
            if (!sameFile)
            {
                error = ERROR_FILE_INVALID;
                return false;
            }
            target.sourceInfo = readableInfo;
        }
        if (target.copyThenDelete ||
            (effect == DROPEFFECT_COPY && !(target.sourceInfo.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)))
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

    ULONGLONG remainingBytes = maxSynchronousBytes - totalBytes;
    for (std::size_t index = 0; index < files.size(); ++index)
    {
        const auto& destination = destinations[index];
        const bool success = effect == DROPEFFECT_COPY
            ? (destination.sourceInfo.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                ? CopyUnicodeClipboardTree(files[index], directory, destination.path, remainingBytes, error)
                : TryCopyUnicodeFileNoOverwrite(files[index], destination.path, error, &destination.sourceInfo)
            : destination.copyThenDelete
                ? MoveUnicodeClipboardFileByCopy(files[index], destination.path, destination.sourceInfo, error)
                : RenameUnicodeClipboardSource(sources.handles[index], destination.path, error);
        if (!success)
        {
            // Each rename is atomic. Undo earlier moves if a later one fails.
            // A new file at an original name is never overwritten during rollback.
            if (effect == DROPEFFECT_MOVE)
            {
                for (std::size_t moved = index; moved > 0; --moved)
                {
                    DWORD rollbackError;
                    if (!destinations[moved - 1].copyThenDelete &&
                        RenameUnicodeClipboardSource(sources.handles[moved - 1], files[moved - 1], rollbackError))
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
