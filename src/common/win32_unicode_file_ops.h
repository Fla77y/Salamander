// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "utf16_disk_path.h"
#include "win32_long_path.h"

#include <windows.h>
#include <string>
#include <atomic>
#include <cwchar>

namespace Salamander
{
namespace UnicodeFileOperationsDetail
{
// Only valid on Windows, where wchar_t and char16_t are both UTF-16 units.
// Do not use CP_ACP, WideCharToMultiByte or a narrow filename intermediate.
inline bool TryGetExtendedPath(const Utf16DiskPath& path,
                               std::wstring& extended,
                               DWORD& error)
{
    static_assert(sizeof(wchar_t) == sizeof(char16_t),
                  "Unicode filesystem operations require Win32 UTF-16 wchar_t");
    extended.clear();
    if (path.Value().empty())
    {
        error = ERROR_INVALID_PARAMETER;
        return false;
    }
    const std::wstring widePath(path.Value().begin(), path.Value().end());
    return TryMakeExtendedLengthPath(widePath.c_str(), extended, error);
}
} // namespace UnicodeFileOperationsDetail

// All operations use fully qualified validated UTF-16 paths and reject an
// existing destination. They never access or truncate a legacy ANSI path.
// These helpers are not a replacement for Salamander's file-operation engine:
// progress, cancellation, policy, ACL and plugin integration still need migration.
inline bool TryCopyUnicodeFileNoOverwrite(const Utf16DiskPath& source,
                                          const Utf16DiskPath& destination,
                                          DWORD& error)
{
    std::wstring sourcePath, destinationPath;
    if (!UnicodeFileOperationsDetail::TryGetExtendedPath(source, sourcePath, error) ||
        !UnicodeFileOperationsDetail::TryGetExtendedPath(destination, destinationPath, error))
        return false;

    // Preserve the existing no-overwrite error contract for callers.
    if (GetFileAttributesW(destinationPath.c_str()) != INVALID_FILE_ATTRIBUTES)
    {
        error = ERROR_FILE_EXISTS;
        return false;
    }
    error = GetLastError();
    if (error != ERROR_FILE_NOT_FOUND)
        return false;

    // Publish only a fully copied file. CopyFileW directly to the final
    // name can expose incomplete bytes while the copy is still running.
    // Stage in the destination directory, then atomically rename on the
    // same volume without MOVEFILE_REPLACE_EXISTING.
    static std::atomic<unsigned long long> nextCopyId{0};
    const std::size_t slash = destinationPath.find_last_of(L'\\');
    if (slash == std::wstring::npos)
    {
        error = ERROR_INVALID_NAME;
        return false;
    }
    const std::wstring targetDirectory = destinationPath.substr(0, slash + 1);
    for (unsigned attempt = 0; attempt != 8; ++attempt)
    {
        wchar_t candidate[88];
        swprintf_s(candidate, L".opensal-copy-%08lX-%016llX-%016llX.tmp",
                   static_cast<unsigned long>(GetCurrentProcessId()),
                   static_cast<unsigned long long>(GetTickCount64()),
                   ++nextCopyId);
        const std::wstring temporary = targetDirectory + candidate;
        if (temporary.size() >= 32767)
        {
            error = ERROR_FILENAME_EXCED_RANGE;
            return false;
        }
        if (!CopyFileW(sourcePath.c_str(), temporary.c_str(), TRUE))
        {
            error = GetLastError();
            if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS)
                continue; // Never delete a candidate we did not create.
            // A failure does not prove that this process created the
            // temporary file: another process may have created a protected
            // entry of the same name immediately before CopyFileW. Never
            // delete an unowned path. No final destination was published.
            return false;
        }

        if (MoveFileExW(temporary.c_str(), destinationPath.c_str(), 0))
        {
            error = ERROR_SUCCESS;
            return true;
        }
        error = GetLastError();
        // Preserve the original Win32 error, not a cleanup error.
        SetFileAttributesW(temporary.c_str(), FILE_ATTRIBUTE_NORMAL);
        DeleteFileW(temporary.c_str());
        return false;
    }
    error = ERROR_ALREADY_EXISTS;
    return false;
}

// Same-volume move/rename; deliberately no MOVEFILE_COPY_ALLOWED fallback.
// Cross-volume copy+delete is not atomic and must be handled by the future
// full file-operation engine with appropriate verification and recovery.
inline bool TryMoveUnicodeFileNoOverwrite(const Utf16DiskPath& source,
                                          const Utf16DiskPath& destination,
                                          DWORD& error)
{
    std::wstring sourcePath, destinationPath;
    if (!UnicodeFileOperationsDetail::TryGetExtendedPath(source, sourcePath, error) ||
        !UnicodeFileOperationsDetail::TryGetExtendedPath(destination, destinationPath, error))
        return false;

    if (!MoveFileExW(sourcePath.c_str(), destinationPath.c_str(), 0))
    {
        error = GetLastError();
        return false;
    }
    error = ERROR_SUCCESS;
    return true;
}

// Same-volume directory move preserves the complete subtree without a
// recursive copy/delete or a fall back to the legacy ANSI operation engine.
// The source must be an ordinary directory (never a junction/symlink), and
// the destination must not exist. MOVEFILE_COPY_ALLOWED is intentionally off.
inline bool TryMoveUnicodeDirectoryNoOverwrite(const Utf16DiskPath& source,
                                               const Utf16DiskPath& destination,
                                               DWORD& error)
{
    std::wstring sourcePath, destinationPath;
    if (!UnicodeFileOperationsDetail::TryGetExtendedPath(source, sourcePath, error) ||
        !UnicodeFileOperationsDetail::TryGetExtendedPath(destination, destinationPath, error))
        return false;

    if (CompareStringOrdinal(sourcePath.c_str(), -1,
                             destinationPath.c_str(), -1, TRUE) == CSTR_EQUAL)
    {
        error = ERROR_ALREADY_EXISTS;
        return false;
    }

    const DWORD sourceAttributes = GetFileAttributesW(sourcePath.c_str());
    if (sourceAttributes == INVALID_FILE_ATTRIBUTES)
    {
        error = GetLastError();
        return false;
    }
    if ((sourceAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
        (sourceAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        error = ERROR_ACCESS_DENIED;
        return false;
    }

    const DWORD destinationAttributes = GetFileAttributesW(destinationPath.c_str());
    if (destinationAttributes != INVALID_FILE_ATTRIBUTES)
    {
        error = ERROR_ALREADY_EXISTS;
        return false;
    }
    error = GetLastError();
    if (error != ERROR_FILE_NOT_FOUND)
        return false;

    if (!MoveFileExW(sourcePath.c_str(), destinationPath.c_str(), 0))
    {
        error = GetLastError();
        return false;
    }
    error = ERROR_SUCCESS;
    return true;
}

inline bool TryDeleteUnicodeFile(const Utf16DiskPath& file, DWORD& error)
{
    std::wstring path;
    if (!UnicodeFileOperationsDetail::TryGetExtendedPath(file, path, error))
        return false;

    if (!DeleteFileW(path.c_str()))
    {
        error = GetLastError();
        return false;
    }
    error = ERROR_SUCCESS;
    return true;
}
} // namespace Salamander
