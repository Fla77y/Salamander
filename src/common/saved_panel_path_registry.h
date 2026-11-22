// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <windows.h>
#include <cwchar>
#include <string>

namespace Salamander
{
enum class SavedPanelPathStatus
{
    Missing,
    Loaded,
    Invalid
};

inline constexpr wchar_t SavedPanelPathValue[] = L"Path";
inline constexpr DWORD MaxSavedPanelPathUnits = 32767;

inline LONG WriteSavedPanelPath(HKEY key, const std::wstring& path)
{
    if (!key || path.size() < 3 || path.size() >= MaxSavedPanelPathUnits ||
        path.find(L'\0') != std::wstring::npos)
        return ERROR_INVALID_PARAMETER;
    return RegSetValueExW(key, SavedPanelPathValue, 0, REG_SZ,
                         reinterpret_cast<const BYTE*>(path.c_str()),
                         static_cast<DWORD>((path.size() + 1) * sizeof(wchar_t)));
}

// REG_SZ already stores UTF-16, including when older builds wrote it via A APIs.
// Invalid values never modify the fallback or truncate the stored path.
inline SavedPanelPathStatus ReadSavedPanelPath(HKEY key, std::wstring& destination)
{
    if (key == nullptr)
        return SavedPanelPathStatus::Invalid;

    DWORD type = REG_NONE;
    DWORD bytes = 0;
    LONG result = RegQueryValueExW(key, SavedPanelPathValue, nullptr, &type, nullptr, &bytes);
    if (result == ERROR_FILE_NOT_FOUND)
        return SavedPanelPathStatus::Missing;

    constexpr DWORD MaxRegistryPathBytes = MaxSavedPanelPathUnits * sizeof(wchar_t);
    if (result != ERROR_SUCCESS || type != REG_SZ ||
        bytes < 4 * sizeof(wchar_t) || bytes > MaxRegistryPathBytes || bytes % sizeof(wchar_t))
        return SavedPanelPathStatus::Invalid;

    std::wstring candidate(bytes / sizeof(wchar_t), L'\0');
    DWORD capacity = bytes;
    result = RegQueryValueExW(key, SavedPanelPathValue, nullptr, &type,
                              reinterpret_cast<LPBYTE>(candidate.data()), &capacity);
    const auto units = capacity / sizeof(wchar_t);
    if (result != ERROR_SUCCESS || type != REG_SZ ||
        units < 4 || capacity > bytes || capacity % sizeof(wchar_t) ||
        candidate[units - 1] != L'\0' ||
        std::wmemchr(candidate.data(), L'\0', units - 1) != nullptr)
        return SavedPanelPathStatus::Invalid;

    candidate.resize(units - 1);
    destination.swap(candidate);
    return SavedPanelPathStatus::Loaded;
}
} // namespace Salamander
