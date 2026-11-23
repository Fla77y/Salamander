// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "utf16_disk_path.h"

#include <windows.h>
#include <string>
#include <string_view>
#include <vector>
#include <utility>

namespace Salamander
{
// Look in treats doubled semicolons as literal name characters and a single
// semicolon as a separator. Keep the original UTF-16 units of each root.
inline std::vector<std::wstring> ParseLegacyFindRoots(std::wstring_view text)
{
    std::vector<std::wstring> roots;
    std::wstring root;
    const auto appendRoot = [&]() {
        const size_t begin = root.find_first_not_of(L' ');
        if (begin != std::wstring::npos)
        {
            size_t end = root.size();
            while (end > begin && root[end - 1] <= L' ')
                --end;
            const bool beginsWithUncPrefix = root.compare(begin, 2, L"\\\\") == 0 ||
                                             root.compare(begin, 2, L"//") == 0;
            const size_t minimumEnd = begin + (beginsWithUncPrefix ? 2 : 1);
            while (end > minimumEnd &&
                   (root[end - 1] == L'\\' || root[end - 1] == L'/') &&
                   (root[end - 2] == L'\\' || root[end - 2] == L'/'))
                --end;
            if (end > begin)
                roots.emplace_back(root.substr(begin, end - begin));
        }
        root.clear();
    };

    for (size_t i = 0; i < text.size(); ++i)
    {
        if (text[i] == L';')
        {
            if (i + 1 == text.size() || text[i + 1] != L';')
            {
                appendRoot();
                continue;
            }
            ++i;
        }
        root.push_back(text[i]);
    }
    appendRoot();
    return roots;
}

inline std::wstring EscapeLegacyFindRoot(std::wstring_view root)
{
    std::wstring escaped;
    for (const wchar_t ch : root)
    {
        if (ch == L';')
            escaped.push_back(ch);
        escaped.push_back(ch);
    }
    return escaped;
}

// Resolve DOS input through the current directory and preserve explicit extended
// spelling. An invalid or unsafe input leaves the output empty.
inline bool TryResolveLegacyFindDirectory(std::wstring input, std::wstring& path, DWORD& error)
{
    path.clear();
    if (input.empty() || input.find(L'\0') != std::wstring::npos)
    {
        error = ERROR_INVALID_NAME;
        return false;
    }
    std::wstring resolved;
    if (input.compare(0, 4, L"\\\\?\\") == 0)
    {
        // Preserve an explicitly extended path. Do not normalize it through
        // DOS semantics or allow Win32 device or NT object-manager namespaces.
        if (input.size() >= 8 &&
            CompareStringOrdinal(input.data() + 4, 4, L"UNC\\", 4, TRUE) == CSTR_EQUAL)
            resolved = L"\\\\" + input.substr(8);
        else if (input.size() >= 7 && input[5] == L':' && input[6] == L'\\')
            resolved = input.substr(4);
        else
        {
            error = ERROR_INVALID_NAME;
            return false;
        }
    }
    else
    {
        if (input.compare(0, 4, L"\\\\.\\") == 0)
        {
            error = ERROR_INVALID_NAME;
            return false;
        }
        // A drive letter alone has historically searched its root in Find.
        const std::wstring source = input.size() == 2 && input[1] == L':' ? input + L'\\' : input;
        const DWORD capacity = GetFullPathNameW(source.c_str(), 0, NULL, NULL);
        if (capacity == 0)
        {
            error = GetLastError();
            return false;
        }
        if (capacity > 32767)
        {
            error = ERROR_FILENAME_EXCED_RANGE;
            return false;
        }
        resolved.resize(capacity);
        const DWORD length = GetFullPathNameW(source.c_str(), capacity, resolved.data(), NULL);
        if (length == 0 || length >= capacity)
        {
            error = length == 0 ? GetLastError() : ERROR_INSUFFICIENT_BUFFER;
            return false;
        }
        resolved.resize(length);
    }

    if (resolved.size() > 3 && resolved.back() == L'\\')
        resolved.pop_back();
    const std::u16string utf16(resolved.begin(), resolved.end());
    Utf16DiskPath valid;
    Utf16PathError pathError;
    if (!Utf16DiskPath::TryCreateAbsolute(utf16, valid, pathError))
    {
        error = pathError == Utf16PathError::PathTooLong ?
            ERROR_FILENAME_EXCED_RANGE : ERROR_INVALID_NAME;
        return false;
    }
    path = std::move(resolved);
    error = ERROR_SUCCESS;
    return true;
}
}
