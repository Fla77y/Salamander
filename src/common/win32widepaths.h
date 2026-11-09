// SPDX-FileCopyrightText: 2026 Open Salamander contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <windows.h>

#include <cwchar>
#include <string>
#include <vector>

// Windows filesystem adapter for the legacy ANSI Salamander core.
//
// Win32 filesystem paths are UTF-16. Extended-length absolute paths avoid
// MAX_PATH trimming and permit names ending with spaces or dots. The narrow
// overloads are a compatibility bridge only: ANSI names that were already
// replaced by '?' during enumeration cannot be recovered here.
namespace SalWidePaths
{

inline bool MakeExtendedPath(const wchar_t* path, std::wstring& extended)
{
    if (path == nullptr || path[0] == L'\0')
    {
        SetLastError(ERROR_INVALID_NAME);
        return false;
    }

    // Preserve callers that intentionally use Win32 device or extended paths.
    if (wcsncmp(path, L"\\\\?\\", 4) == 0 ||
        wcsncmp(path, L"\\\\.\\", 4) == 0)
    {
        extended.assign(path);
        return true;
    }

    // GetFullPathNameW resolves relative components before the \\?\ prefix,
    // where '.' and '..' would otherwise be treated literally by Win32.
    const DWORD required = GetFullPathNameW(path, 0, nullptr, nullptr);
    if (required == 0)
        return false;
    if (required > 32760)
    {
        SetLastError(ERROR_FILENAME_EXCED_RANGE);
        return false;
    }

    std::vector<wchar_t> buffer(required);
    const DWORD written = GetFullPathNameW(path, required, buffer.data(), nullptr);
    if (written == 0)
        return false;
    if (written >= required)
    {
        SetLastError(ERROR_INSUFFICIENT_BUFFER);
        return false;
    }
    std::wstring absolute(buffer.data(), written);
    for (wchar_t& character : absolute)
    {
        if (character == L'/')
            character = L'\\';
    }

    if (absolute.compare(0, 2, L"\\\\") == 0)
        extended = L"\\\\?\\UNC\\" + absolute.substr(2);
    else if (absolute.size() >= 3 && absolute[1] == L':' && absolute[2] == L'\\')
        extended = L"\\\\?\\" + absolute;
    else
    {
        SetLastError(ERROR_INVALID_NAME);
        return false;
    }

    if (extended.size() > 32760)
    {
        SetLastError(ERROR_FILENAME_EXCED_RANGE);
        return false;
    }
    return true;
}

inline bool MakeExtendedPathFromNarrow(const char* path, std::wstring& extended)
{
    if (path == nullptr || path[0] == '\0')
    {
        SetLastError(ERROR_INVALID_NAME);
        return false;
    }

    // Do not silently replace malformed UTF-8 if UTF-8 is the active code page.
    const DWORD flags = GetACP() == CP_UTF8 ? MB_ERR_INVALID_CHARS : 0;
    const int required = MultiByteToWideChar(CP_ACP, flags, path, -1, nullptr, 0);
    if (required <= 0)
        return false;

    std::vector<wchar_t> unicode(required);
    if (MultiByteToWideChar(CP_ACP, flags, path, -1, unicode.data(), required) != required)
        return false;

    return MakeExtendedPath(unicode.data(), extended);
}

inline DWORD GetFileAttributesFromWide(const wchar_t* name)
{
    std::wstring path;
    if (!MakeExtendedPath(name, path))
        return INVALID_FILE_ATTRIBUTES;
    return GetFileAttributesW(path.c_str());
}

inline DWORD GetFileAttributesFromNarrow(const char* name)
{
    std::wstring path;
    if (!MakeExtendedPathFromNarrow(name, path))
        return INVALID_FILE_ATTRIBUTES;
    return GetFileAttributesW(path.c_str());
}

inline BOOL SetFileAttributesFromNarrow(const char* name, DWORD attributes)
{
    std::wstring path;
    if (!MakeExtendedPathFromNarrow(name, path))
        return FALSE;
    return SetFileAttributesW(path.c_str(), attributes);
}

inline BOOL MoveFileFromWide(const wchar_t* source, const wchar_t* destination)
{
    std::wstring sourcePath, destinationPath;
    if (!MakeExtendedPath(source, sourcePath) || !MakeExtendedPath(destination, destinationPath))
        return FALSE;
    // MoveFileW does not overwrite an existing destination.
    return MoveFileW(sourcePath.c_str(), destinationPath.c_str());
}

inline BOOL MoveFileFromNarrow(const char* source, const char* destination)
{
    std::wstring sourcePath, destinationPath;
    if (!MakeExtendedPathFromNarrow(source, sourcePath) ||
        !MakeExtendedPathFromNarrow(destination, destinationPath))
        return FALSE;
    return MoveFileW(sourcePath.c_str(), destinationPath.c_str());
}

inline BOOL DeleteFileFromWide(const wchar_t* name)
{
    std::wstring path;
    if (!MakeExtendedPath(name, path))
        return FALSE;
    return DeleteFileW(path.c_str());
}

inline BOOL DeleteFileFromNarrow(const char* name)
{
    std::wstring path;
    if (!MakeExtendedPathFromNarrow(name, path))
        return FALSE;
    return DeleteFileW(path.c_str());
}

inline BOOL RemoveDirectoryFromWide(const wchar_t* name)
{
    std::wstring path;
    if (!MakeExtendedPath(name, path))
        return FALSE;
    return RemoveDirectoryW(path.c_str());
}

inline BOOL RemoveDirectoryFromNarrow(const char* name)
{
    std::wstring path;
    if (!MakeExtendedPathFromNarrow(name, path))
        return FALSE;
    return RemoveDirectoryW(path.c_str());
}

inline BOOL CreateDirectoryFromNarrow(const char* name, LPSECURITY_ATTRIBUTES security)
{
    std::wstring path;
    if (!MakeExtendedPathFromNarrow(name, path))
        return FALSE;
    return CreateDirectoryW(path.c_str(), security);
}

inline HANDLE CreateFileFromNarrow(
    const char* name, DWORD access, DWORD shareMode, LPSECURITY_ATTRIBUTES security,
    DWORD disposition, DWORD attributes, HANDLE templateFile)
{
    std::wstring path;
    if (!MakeExtendedPathFromNarrow(name, path))
        return INVALID_HANDLE_VALUE;
    return CreateFileW(path.c_str(), access, shareMode, security,
                       disposition, attributes, templateFile);
}

} // namespace SalWidePaths
