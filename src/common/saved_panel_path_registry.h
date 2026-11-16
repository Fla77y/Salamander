// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <windows.h>
#include <cstring>
#include <string>

namespace Salamander
{
enum class SavedPanelPathStatus
{
    Missing,
    Loaded,
    Invalid
};

// Reads a saved ANSI panel path without imposing the legacy MAX_PATH limit.
// Invalid values never modify the fallback or truncate the stored path.
inline SavedPanelPathStatus ReadSavedPanelPath(HKEY key, std::string& destination)
{
    if (key == nullptr)
        return SavedPanelPathStatus::Invalid;

    DWORD type = REG_NONE;
    DWORD bytes = 0;
    LONG result = RegQueryValueExA(key, "Path", nullptr, &type, nullptr, &bytes);
    if (result == ERROR_FILE_NOT_FOUND)
        return SavedPanelPathStatus::Missing;

    // The extended-length Win32 path limit is 32767 UTF-16 code units;
    // permit two bytes per unit in a legacy multibyte ANSI value.
    constexpr DWORD MaxRegistryPathBytes = 2 * 32767 + 1;
    if (result != ERROR_SUCCESS || type != REG_SZ ||
        bytes < 4 || bytes > MaxRegistryPathBytes)
        return SavedPanelPathStatus::Invalid;

    std::string candidate(bytes, '\0');
    DWORD capacity = bytes;
    result = RegQueryValueExA(key, "Path", nullptr, &type,
                              reinterpret_cast<LPBYTE>(&candidate[0]), &capacity);
    if (result != ERROR_SUCCESS || type != REG_SZ ||
        capacity < 4 || capacity > bytes ||
        candidate[capacity - 1] != '\0' ||
        memchr(candidate.data(), '\0', capacity - 1) != nullptr)
        return SavedPanelPathStatus::Invalid;

    candidate.resize(capacity - 1);
    destination.swap(candidate);
    return SavedPanelPathStatus::Loaded;
}
} // namespace Salamander
