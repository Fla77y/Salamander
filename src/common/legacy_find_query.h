// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>
#include <string_view>
#include <vector>

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
}
