// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <windows.h>
#include <string>
#include <string_view>
#include <vector>

namespace Salamander
{
// The original Find mask syntax, compiled once from the UTF-16 Named edit.
// No normalization is applied to the mask or to enumerated disk names.
class LegacyFindMasks
{
public:
    bool Prepare(std::wstring_view text, size_t& errorOffset, bool expandBareWords = true)
    {
        Include.clear();
        Exclude.clear();
        auto* group = &Include;
        std::wstring token;
        size_t separator = std::wstring_view::npos;
        const auto finishToken = [&]() {
            const size_t first = token.find_first_not_of(L' ');
            if (first != std::wstring::npos)
            {
                const size_t last = token.find_last_not_of(L' ');
                token = token.substr(first, last - first + 1);
                if (expandBareWords && token.find_first_of(L"*?.") == std::wstring::npos)
                    token = L"*" + token + L"*"; // a bare word is a substring
                group->push_back(token);
            }
            token.clear();
        };

        for (size_t i = 0; i < text.size(); ++i)
        {
            const wchar_t ch = text[i];
            if (ch == L';' && i + 1 < text.size() && text[i + 1] == L';')
            {
                token.push_back(ch);
                ++i;
            }
            else if (ch == L';' || (ch == L'|' && group == &Include))
            {
                finishToken();
                if (ch == L'|')
                {
                    separator = i;
                    group = &Exclude;
                }
            }
            else if (ch < L' ' || std::wstring_view(L"\\/<>:\"|").find(ch) != std::wstring_view::npos ||
                     (IS_HIGH_SURROGATE(ch) && (i + 1 == text.size() || !IS_LOW_SURROGATE(text[i + 1]))) ||
                     (IS_LOW_SURROGATE(ch) && (i == 0 || !IS_HIGH_SURROGATE(text[i - 1]))))
            {
                errorOffset = i;
                return false;
            }
            else
                token.push_back(ch);
        }
        finishToken();

        if (separator != std::wstring_view::npos && Exclude.empty())
        {
            errorOffset = separator;
            return false;
        }
        if (Include.empty() && (separator != std::wstring_view::npos ||
                                (expandBareWords && text.find_first_not_of(L' ') == std::wstring_view::npos)))
            Include.emplace_back(L"*");
        return true;
    }

    bool PrepareAnsiGroup(const char* text)
    {
        const int units = MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
        if (units <= 0)
            return false;
        std::wstring wide(units, L'\0');
        if (MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS, text, -1, wide.data(), units) != units)
            return false;
        wide.pop_back();
        size_t errorOffset;
        return Prepare(wide, errorOffset, false);
    }

    bool Matches(std::wstring_view name) const
    {
        const size_t dot = name.rfind(L'.');
        const bool hasExtension = dot != std::wstring_view::npos && dot + 1 < name.size();
        const auto matches = [&](std::wstring_view mask) {
            if (MatchesOne(name, mask))
                return true;
            // The original dialog lets a final dot or ".*" match a missing extension.
            if (!hasExtension && mask.size() >= 2 && mask.substr(mask.size() - 2) == L".*")
                return MatchesOne(name, mask.substr(0, mask.size() - 2));
            return !hasExtension && mask.back() == L'.' &&
                   MatchesOne(name, mask.substr(0, mask.size() - 1));
        };
        for (const auto& mask : Exclude)
            if (matches(mask))
                return false;
        for (const auto& mask : Include)
            if (matches(mask))
                return true;
        return false;
    }

private:
    static int CharacterLength(std::wstring_view text, size_t offset)
    {
        return offset + 1 < text.size() && IS_SURROGATE_PAIR(text[offset], text[offset + 1]) ? 2 : 1;
    }

    // Retry from the last asterisk. Retry positions and '?' advance by a
    // complete UTF-16 character, including supplementary characters.
    static bool MatchesOne(std::wstring_view name, std::wstring_view mask)
    {
        size_t n = 0;
        size_t m = 0;
        size_t star = std::wstring_view::npos;
        size_t retry = 0;
        while (n < name.size())
        {
            if (m < mask.size() && mask[m] == L'*')
            {
                star = ++m;
                retry = n;
                continue;
            }
            if (m < mask.size())
            {
                const int nameUnits = CharacterLength(name, n);
                const int maskUnits = CharacterLength(mask, m);
                if (mask[m] == L'?' ||
                    (nameUnits == maskUnits &&
                     ((name[n] == mask[m] && nameUnits == 1) ||
                      CompareStringOrdinal(name.data() + n, nameUnits, mask.data() + m, maskUnits, TRUE) == CSTR_EQUAL)))
                {
                    n += nameUnits;
                    m += maskUnits;
                    continue;
                }
            }
            if (star == std::wstring_view::npos)
                return false;
            retry += CharacterLength(name, retry);
            n = retry;
            m = star;
        }
        return mask.find_first_not_of(L'*', m) == std::wstring_view::npos;
    }

    std::vector<std::wstring> Include;
    std::vector<std::wstring> Exclude;
};
} // namespace Salamander
