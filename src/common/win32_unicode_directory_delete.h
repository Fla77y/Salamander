// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_unicode_file_ops.h"

#include <filesystem>
#include <system_error>

namespace Salamander
{
// Permanently delete only a validated, ordinary directory. Every descendant
// is addressed through an extended-length UTF-16 path. Filesystem traversal
// removes reparse-point entries themselves; it must not follow their targets.
// Callers must obtain explicit permanent-delete consent and preserve recycle
// policy before invoking this helper. Partial failures are reported, not hidden.
inline bool TryDeleteUnicodeDirectoryTree(const Utf16DiskPath& directory,
                                          DWORD& error)
{
    std::wstring extended;
    if (!UnicodeFileOperationsDetail::TryGetExtendedPath(
            directory, extended, error))
        return false;

    const DWORD attributes = GetFileAttributesW(extended.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        error = GetLastError();
        return false;
    }
    if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        error = ERROR_ACCESS_DENIED;
        return false;
    }

    // MSVC's std::filesystem uses wide Win32 paths, and remove_all does not
    // follow directory symlinks or junctions. Passing the canonical \\?\ form
    // avoids MAX_PATH truncation in descendants.
    std::error_code filesystemError;
    const auto removed = std::filesystem::remove_all(
        std::filesystem::path(extended), filesystemError);
    if (filesystemError)
    {
        error = static_cast<DWORD>(filesystemError.value());
        return false;
    }
    if (removed == 0 ||
        GetFileAttributesW(extended.c_str()) != INVALID_FILE_ATTRIBUTES)
    {
        error = ERROR_GEN_FAILURE;
        return false;
    }
    error = ERROR_SUCCESS;
    return true;
}
} // namespace Salamander
