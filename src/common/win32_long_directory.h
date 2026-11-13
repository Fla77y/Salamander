// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_long_path.h"

#include <cstdint>
#include <cwchar>
#include <utility>
#include <string>
#include <vector>

namespace Salamander
{
// Preserve the full UTF-16 filename; ANSI conversion is intentionally absent.
struct LongDirectoryEntry
{
    std::wstring name;
    DWORD attributes = 0;
    std::uint64_t size = 0;
    FILETIME lastWrite = {};
};

// Enumerates one absolute filesystem directory. The existing Salamander panel
// data model is still ANSI; callers must not truncate these entries to fit it.
// An empty directory is a successful result with zero entries.
inline bool TryEnumerateLongDirectory(const wchar_t* absoluteDirectory,
                                      std::vector<LongDirectoryEntry>& entries,
                                      DWORD& error)
{
    entries.clear();

    std::wstring searchPath;
    if (!TryMakeExtendedLengthPath(absoluteDirectory, searchPath, error))
        return false;

    // The wildcard itself must also fit inside the extended Win32 path.
    const std::size_t additional = searchPath.back() == L'\\' ? 1 : 2;
    if (searchPath.size() + additional >= 32767)
    {
        error = ERROR_FILENAME_EXCED_RANGE;
        return false;
    }
    if (searchPath.back() != L'\\')
        searchPath.push_back(L'\\');
    searchPath.push_back(L'*');

    WIN32_FIND_DATAW data = {};
    HANDLE handle = FindFirstFileW(searchPath.c_str(), &data);
    if (handle == INVALID_HANDLE_VALUE)
    {
        error = GetLastError();
        if (error == ERROR_FILE_NOT_FOUND || error == ERROR_NO_MORE_FILES)
        {
            error = ERROR_SUCCESS;
            return true;
        }
        return false;
    }

    struct FindHandleGuard
    {
        HANDLE handle;
        ~FindHandleGuard() { FindClose(handle); }
    } guard{handle};

    for (;;)
    {
        if (wcscmp(data.cFileName, L".") != 0 &&
            wcscmp(data.cFileName, L"..") != 0)
        {
            LongDirectoryEntry entry;
            entry.name.assign(data.cFileName);
            entry.attributes = data.dwFileAttributes;
            entry.size = (static_cast<std::uint64_t>(data.nFileSizeHigh) << 32) |
                         data.nFileSizeLow;
            entry.lastWrite = data.ftLastWriteTime;
            entries.push_back(std::move(entry));
        }

        if (!FindNextFileW(handle, &data))
        {
            error = GetLastError();
            if (error == ERROR_NO_MORE_FILES)
            {
                error = ERROR_SUCCESS;
                return true;
            }

            entries.clear();
            return false;
        }
    }
}
} // namespace Salamander
