// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "utf16_disk_path.h"
#include "win32_long_path.h"

#include <windows.h>
#include <string>

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

    if (!CopyFileW(sourcePath.c_str(), destinationPath.c_str(), TRUE))
    {
        error = GetLastError();
        return false;
    }
    error = ERROR_SUCCESS;
    return true;
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
