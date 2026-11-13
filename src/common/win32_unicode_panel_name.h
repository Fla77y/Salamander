// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_long_directory.h"
#include "legacy_disk_name_safety.h"

#include <windows.h>
#include <string>
#include <cwchar>
#include <vector>
#include <unordered_map>
#include <utility>

namespace Salamander
{
// Equality after ANSI -> UTF-16 conversion is stricter than merely
// checking for '?' substitution: Windows ACP best-fit can silently map
// different Unicode characters to existing ASCII/ANSI bytes.
inline bool IsExactAnsiName(const char* ansiName, const wchar_t* originalName)
{
    if (ansiName == nullptr || originalName == nullptr || *ansiName == '\0')
        return false;

    const int units = MultiByteToWideChar(CP_ACP, 0, ansiName, -1,
                                          nullptr, 0);
    if (units <= 0)
        return false;

    std::wstring roundTrip(static_cast<std::size_t>(units), L'\0');
    if (MultiByteToWideChar(CP_ACP, 0, ansiName, -1,
                            &roundTrip[0], units) != units)
        return false;

    return wcscmp(roundTrip.c_str(), originalName) == 0;
}

// A legacy ANSI panel name is not necessarily a unique filesystem identity.
// Resolve only when precisely one real UTF-16 directory entry maps to it.
enum class UnicodePanelNameResult
{
    Unique,
    NotFound,
    Ambiguous,
    Error
};

inline UnicodePanelNameResult ResolveUnicodePanelFileName(
    const wchar_t* absoluteDirectory,
    const char* legacyName,
    std::wstring& originalName,
    DWORD& error)
{
    originalName.clear();
    error = ERROR_INVALID_PARAMETER;
    if (absoluteDirectory == nullptr || legacyName == nullptr ||
        *legacyName == '\0')
        return UnicodePanelNameResult::Error;

    std::vector<LongDirectoryEntry> entries;
    if (!TryEnumerateLongDirectory(absoluteDirectory, entries, error))
        return UnicodePanelNameResult::Error;

    for (const LongDirectoryEntry& entry : entries)
    {
        const int bytes = WideCharToMultiByte(CP_ACP, 0, entry.name.c_str(),
                                               -1, nullptr, 0, nullptr, nullptr);
        if (bytes == 0)
        {
            error = GetLastError();
            originalName.clear();
            return UnicodePanelNameResult::Error;
        }

        std::string encoded(static_cast<std::size_t>(bytes), '\0');
        if (WideCharToMultiByte(CP_ACP, 0, entry.name.c_str(),
                                -1, &encoded[0], bytes, nullptr, nullptr) != bytes)
        {
            error = GetLastError();
            originalName.clear();
            return UnicodePanelNameResult::Error;
        }
        encoded.pop_back();
        if (encoded != legacyName)
            continue;

        if (!originalName.empty())
        {
            originalName.clear();
            error = ERROR_DUP_NAME;
            return UnicodePanelNameResult::Ambiguous;
        }
        originalName = entry.name;
    }

    error = ERROR_SUCCESS;
    return originalName.empty()
               ? UnicodePanelNameResult::NotFound
               : UnicodePanelNameResult::Unique;
}

// Snapshot of original names for one disk directory. It must be cleared
// whenever the panel changes directories or refreshes its listing. Keys
// are legacy ACP aliases; an empty value denotes an identity collision.
class UnicodePanelNameCache
{
public:
    void Clear()
    {
        names_.clear();
        complete_ = false;
    }

    bool Load(const wchar_t* absoluteDirectory, DWORD& error)
    {
        Clear();
        std::vector<LongDirectoryEntry> entries;
        if (!TryEnumerateLongDirectory(absoluteDirectory, entries, error))
            return false;

        for (const LongDirectoryEntry& entry : entries)
        {
            const int byteCount = WideCharToMultiByte(CP_ACP, 0,
                entry.name.c_str(), -1, nullptr, 0, nullptr, nullptr);
            if (byteCount == 0)
            {
                error = GetLastError();
                Clear();
                return false;
            }

            std::string alias(static_cast<std::size_t>(byteCount), '\0');
            if (WideCharToMultiByte(CP_ACP, 0, entry.name.c_str(),
                                    -1, &alias[0], byteCount,
                                    nullptr, nullptr) != byteCount)
            {
                error = GetLastError();
                Clear();
                return false;
            }
            alias.pop_back();

            // Preserve the real name separately from the plugin-visible
            // CFileData. Distinct Unicode names may share an ANSI alias.
            // A non-round-tripping alias is never safe for ANSI I/O, even
            // if its bytes contain no replacement question mark.
            const bool exact = IsExactAnsiName(alias.c_str(), entry.name.c_str());
            const auto inserted = names_.emplace(
                std::move(alias), CachedName{entry.name, exact});
            if (!inserted.second)
            {
                inserted.first->second.original.clear();
                inserted.first->second.exactAnsiIdentity = false;
            }
        }

        complete_ = true;
        error = ERROR_SUCCESS;
        return true;
    }

    // Read-only display/export may recover uniquely identified originals.
    bool TryGet(const char* legacyName, std::wstring& result) const
    {
        result.clear();
        if (!complete_ || legacyName == nullptr)
            return false;

        const auto found = names_.find(legacyName);
        if (found == names_.end() || found->second.original.empty())
            return false;

        result = found->second.original;
        return true;
    }

    // Draw/export UTF-16 only when ANSI representation loses information.
    bool TryGetLossy(const char* legacyName, std::wstring& result) const
    {
        result.clear();
        if (!complete_ || legacyName == nullptr)
            return false;

        const auto found = names_.find(legacyName);
        if (found == names_.end() ||
            found->second.original.empty() ||
            found->second.exactAnsiIdentity)
            return false;

        result = found->second.original;
        return true;
    }

    // Unavailable snapshots, missing entries, collisions, '?' replacements
    // and best-fit mappings ALL fail closed at legacy disk-operation entry.
    bool IsUnsafeAnsiName(const char* legacyName) const
    {
        if (!complete_ || legacyName == nullptr ||
            Salamander::IsLossyAnsiDiskName(legacyName))
            return true;

        const auto found = names_.find(legacyName);
        return found == names_.end() ||
               found->second.original.empty() ||
               !found->second.exactAnsiIdentity;
    }

private:
    struct CachedName
    {
        std::wstring original;
        bool exactAnsiIdentity;
    };

    std::unordered_map<std::string, CachedName> names_;
    bool complete_ = false;
};

// Strict conversion for legacy ANSI panel directories; it cannot recover
// Unicode characters already lost from a directory path.
inline bool TryGetUnicodePanelDirectory(const char* ansiDirectory,
                                       std::wstring& unicodeDirectory)
{
    unicodeDirectory.clear();
    if (ansiDirectory == nullptr)
        return false;
    const int chars = MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS,
                                          ansiDirectory, -1, nullptr, 0);
    if (chars <= 1)
        return false;
    unicodeDirectory.resize(static_cast<std::size_t>(chars));
    if (MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS, ansiDirectory,
                            -1, &unicodeDirectory[0], chars) != chars)
    {
        unicodeDirectory.clear();
        return false;
    }
    unicodeDirectory.pop_back();
    return true;
}

// Win32 takes ownership of the allocated memory only after a successful
// SetClipboardData. Do not publish partial UTF-16 strings.
inline bool TryCopyUnicodeNameToClipboard(HWND owner, const std::wstring& name)
{
    if (name.empty() || !OpenClipboard(owner))
        return false;

    const SIZE_T bytes = (name.size() + 1) * sizeof(wchar_t);
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (memory == nullptr)
    {
        CloseClipboard();
        return false;
    }

    wchar_t* target = static_cast<wchar_t*>(GlobalLock(memory));
    if (target == nullptr)
    {
        GlobalFree(memory);
        CloseClipboard();
        return false;
    }

    memcpy(target, name.c_str(), bytes);
    GlobalUnlock(memory);
    bool succeeded = EmptyClipboard() && SetClipboardData(CF_UNICODETEXT, memory) != nullptr;
    if (!succeeded)
        GlobalFree(memory);
    CloseClipboard();
    return succeeded;
}
} // namespace Salamander
