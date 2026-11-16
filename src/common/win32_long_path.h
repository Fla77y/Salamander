// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <windows.h>
#include <string>
#include <cstring>

namespace Salamander
{
// A Win32 extended-length path must be fully qualified and must not contain
// unnormalized "." / ".." components. It also disables slash normalization.
// No registry or longPathAware manifest setting is needed for callers using
// explicit Unicode file I/O functions with this prefix.
//
// The caller owns resolution of relative paths and validation of component
// lengths according to the actual filesystem.
inline bool TryMakeExtendedLengthPath(const wchar_t* absolutePath,
                                      std::wstring& extendedPath,
                                      DWORD& error)
{
    extendedPath.clear();
    error = ERROR_INVALID_NAME;

    if (absolutePath == nullptr)
    {
        error = ERROR_INVALID_PARAMETER;
        return false;
    }

    const std::wstring path(absolutePath);
    if (path.empty() || path.find(L'/') != std::wstring::npos)
        return false;

    const bool drivePath =
        path.size() >= 3 &&
        ((path[0] >= L'A' && path[0] <= L'Z') ||
         (path[0] >= L'a' && path[0] <= L'z')) &&
        path[1] == L':' && path[2] == L'\\';

    bool uncPath = false;
    std::size_t firstComponent = 0;

    if (drivePath)
    {
        firstComponent = 3;
    }
    else if (path.size() >= 5 && path[0] == L'\\' && path[1] == L'\\' &&
             path[2] != L'?' && path[2] != L'.' && path[2] != L'\\')
    {
        const auto serverEnd = path.find(L'\\', 2);
        if (serverEnd == std::wstring::npos || serverEnd == 2)
            return false;

        const auto shareStart = serverEnd + 1;
        if (shareStart == path.size() || path[shareStart] == L'\\')
            return false;

        const auto shareEnd = path.find(L'\\', shareStart);
        if (shareEnd == std::wstring::npos)
            firstComponent = path.size();
        else
            firstComponent = shareEnd + 1;
        uncPath = true;
    }
    else
    {
        return false;
    }

    // The extended-length namespace does no normalization of "." or "..".
    // Reject ambiguous and empty interior components instead of accidentally
    // accessing a different file from the one requested.
    for (std::size_t start = firstComponent; start < path.size();)
    {
        const auto end = path.find(L'\\', start);
        const auto count = (end == std::wstring::npos ? path.size() : end) - start;
        if (count == 0 ||
            (count == 1 && path[start] == L'.') ||
            (count == 2 && path[start] == L'.' && path[start + 1] == L'.'))
            return false;

        if (end == std::wstring::npos || end == path.size() - 1)
            break;
        start = end + 1;
    }

    constexpr std::size_t maxExtendedPathWithNull = 32767;
    const std::size_t prefixExtra = drivePath ? 4 : 6;
    if (path.size() + prefixExtra >= maxExtendedPathWithNull)
    {
        error = ERROR_FILENAME_EXCED_RANGE;
        return false;
    }

    if (uncPath)
    {
        extendedPath.assign(L"\\\\?\\UNC\\");
        extendedPath.append(path, 2, std::wstring::npos);
    }
    else
    {
        extendedPath.assign(L"\\\\?\\");
        extendedPath.append(path);
    }

    error = ERROR_SUCCESS;
    return true;
}
// Transitional adapter for Salamander APIs that still pass CP_ACP filenames.
// It cannot recover Unicode characters that were already lost during ANSI
// enumeration; new code should use the wchar_t overload directly.
inline bool TryMakeExtendedLengthPathFromAnsi(const char* absolutePath,
                                              std::wstring& extendedPath,
                                              DWORD& error)
{
    extendedPath.clear();
    if (absolutePath == nullptr)
    {
        error = ERROR_INVALID_PARAMETER;
        return false;
    }

    const int wideLength = MultiByteToWideChar(
        CP_ACP, MB_ERR_INVALID_CHARS, absolutePath, -1, nullptr, 0);
    if (wideLength == 0)
    {
        error = GetLastError();
        return false;
    }

    std::wstring widePath(static_cast<std::size_t>(wideLength), L'\0');
    if (MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS, absolutePath, -1,
                            &widePath[0], wideLength) != wideLength)
    {
        error = GetLastError();
        return false;
    }

    widePath.resize(static_cast<std::size_t>(wideLength - 1));
    return TryMakeExtendedLengthPath(widePath.c_str(), extendedPath, error);
}

// Shared opening path for the legacy SAFE_FILE code. The same route is used
// for initial open and for read/write retries, preventing a retry from falling
// back to an ANSI API that cannot reopen the long file.
inline HANDLE OpenFileWithLegacyPath(const char* fileName,
                                    DWORD desiredAccess,
                                    DWORD shareMode,
                                    DWORD creationDisposition,
                                    DWORD flagsAndAttributes)
{
    if (fileName == nullptr)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return INVALID_HANDLE_VALUE;
    }

    if (std::strlen(fileName) < MAX_PATH)
    {
        return CreateFileA(fileName, desiredAccess, shareMode, nullptr,
                           creationDisposition, flagsAndAttributes, nullptr);
    }

    std::wstring extendedPath;
    DWORD pathError = ERROR_SUCCESS;
    if (!TryMakeExtendedLengthPathFromAnsi(fileName, extendedPath, pathError))
    {
        SetLastError(pathError);
        return INVALID_HANDLE_VALUE;
    }

    return CreateFileW(extendedPath.c_str(), desiredAccess, shareMode, nullptr,
                       creationDisposition, flagsAndAttributes, nullptr);
}

// A retry must NEVER repeat CREATE_ALWAYS, CREATE_NEW or TRUNCATE_EXISTING:
// it must preserve bytes written before the failure.
inline HANDLE ReopenExistingFileWithLegacyPath(const char* fileName,
                                               DWORD desiredAccess,
                                               DWORD shareMode,
                                               DWORD flagsAndAttributes)
{
    return OpenFileWithLegacyPath(fileName, desiredAccess, shareMode,
                                  OPEN_EXISTING, flagsAndAttributes);
}

} // namespace Salamander
