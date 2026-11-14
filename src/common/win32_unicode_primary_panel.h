// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <windows.h>
#include <cstddef>
#include <cwchar>
#include <string>
#include <unordered_map>

namespace Salamander
{
// Associates a panel row's independently allocated Name buffer with the
// exact UTF-16 name returned by the same FindFirstFileW/FindNextFileW record.
// Moving or sorting CFileData preserves its Name allocation and its identity.
// This is internal only; the binary layout of plug-in-visible CFileData
// must not be modified.
class UnicodePanelRowIdentities
{
public:
    void Clear() { rows_.clear(); }

    void Record(const char* rowNameAllocation, const wchar_t* originalName)
    {
        if (rowNameAllocation != nullptr && originalName != nullptr &&
            originalName[0] != L'\0')
            rows_.insert_or_assign(rowNameAllocation, std::wstring(originalName));
    }

    bool TryGet(const char* rowNameAllocation, std::wstring& originalName) const
    {
        originalName.clear();
        if (rowNameAllocation == nullptr)
            return false;
        const auto found = rows_.find(rowNameAllocation);
        if (found == rows_.end())
            return false;
        originalName = found->second;
        return true;
    }

private:
    std::unordered_map<const char*, std::wstring> rows_;
};

// Adapt the metadata from a W enumeration to the existing ANSI CFileData
// construction code. This is strictly a compatibility boundary; callers
// must keep the independent original W name for identity-based operations.
// Do not truncate a component when it exceeds WIN32_FIND_DATAA capacity.
inline bool TryConvertUnicodePanelFindData(
    const WIN32_FIND_DATAW& wide, WIN32_FIND_DATAA& legacy, DWORD& error)
{
    WIN32_FIND_DATAA converted = {};
    converted.dwFileAttributes = wide.dwFileAttributes;
    converted.ftCreationTime = wide.ftCreationTime;
    converted.ftLastAccessTime = wide.ftLastAccessTime;
    converted.ftLastWriteTime = wide.ftLastWriteTime;
    converted.nFileSizeHigh = wide.nFileSizeHigh;
    converted.nFileSizeLow = wide.nFileSizeLow;
    converted.dwReserved0 = wide.dwReserved0;
    converted.dwReserved1 = wide.dwReserved1;

    const int nameBytes = WideCharToMultiByte(
        CP_ACP, 0, wide.cFileName, -1, converted.cFileName,
        static_cast<int>(sizeof(converted.cFileName)), nullptr, nullptr);
    if (nameBytes == 0)
    {
        error = GetLastError();
        if (error == ERROR_INSUFFICIENT_BUFFER)
            error = ERROR_FILENAME_EXCED_RANGE;
        return false;
    }

    // The optional short name is not part of the primary identity.
    if (wide.cAlternateFileName[0] != L'\0')
    {
        const int alternateBytes = WideCharToMultiByte(
            CP_ACP, 0, wide.cAlternateFileName, -1,
            converted.cAlternateFileName,
            static_cast<int>(sizeof(converted.cAlternateFileName)),
            nullptr, nullptr);
        if (alternateBytes == 0)
        {
            error = GetLastError();
            if (error == ERROR_INSUFFICIENT_BUFFER)
                error = ERROR_FILENAME_EXCED_RANGE;
            return false;
        }
    }

    legacy = converted;
    error = ERROR_SUCCESS;
    return true;
}

// Open a primary on-disk enumeration using Win32 W APIs. The Win32 handle
// remains owned by ReadDirectory, which closes it through FindClose exactly
// as before. Error is returned via GetLastError for legacy handling.
inline HANDLE FindFirstUnicodePanelFile(
    const char* ansiSearchPath, WIN32_FIND_DATAA& legacy,
    WIN32_FIND_DATAW& wide)
{
    if (ansiSearchPath == nullptr)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return INVALID_HANDLE_VALUE;
    }

    const int chars = MultiByteToWideChar(
        CP_ACP, MB_ERR_INVALID_CHARS, ansiSearchPath, -1, nullptr, 0);
    if (chars <= 0)
        return INVALID_HANDLE_VALUE;

    std::wstring search(static_cast<std::size_t>(chars), L'\0');
    if (MultiByteToWideChar(
            CP_ACP, MB_ERR_INVALID_CHARS, ansiSearchPath, -1,
            &search[0], chars) != chars)
        return INVALID_HANDLE_VALUE;

    HANDLE handle = FindFirstFileW(search.c_str(), &wide);
    if (handle == INVALID_HANDLE_VALUE)
        return handle;

    DWORD error = ERROR_SUCCESS;
    if (!TryConvertUnicodePanelFindData(wide, legacy, error))
    {
        FindClose(handle);
        SetLastError(error);
        return INVALID_HANDLE_VALUE;
    }
    return handle;
}

// This adapter intentionally returns FALSE and a specific Win32 error
// when the legacy metadata buffer cannot represent a W filename; it never
// invents an ANSI file identity by silently truncating the bytes.
inline BOOL FindNextUnicodePanelFile(
    HANDLE handle, WIN32_FIND_DATAA& legacy, WIN32_FIND_DATAW& wide)
{
    if (!FindNextFileW(handle, &wide))
        return FALSE;

    DWORD error = ERROR_SUCCESS;
    if (!TryConvertUnicodePanelFindData(wide, legacy, error))
    {
        SetLastError(error);
        return FALSE;
    }
    return TRUE;
}
} // namespace Salamander
