// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_long_directory.h"

#include <windows.h>
#include <string>
#include <vector>

namespace Salamander
{
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
