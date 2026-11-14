// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <windows.h>
#include <cstring>

namespace Salamander
{
// DefaultDir remains a fixed-size ANSI legacy cache. This reader must not
// truncate a registry path to a different, possibly existing directory.
// Unusable values are preserved in the registry by the caller on save.
enum class LegacyDefaultDirectoryStatus
{
    Missing,
    Loaded,
    Preserve
};

inline LegacyDefaultDirectoryStatus ReadLegacyDefaultDirectory(
    HKEY key, char drive, char (&destination)[MAX_PATH])
{
    if (key == nullptr || drive < 'A' || drive > 'Z')
        return LegacyDefaultDirectoryStatus::Preserve;

    const char valueName[] = {drive, '\0'};
    DWORD type = REG_NONE;
    DWORD length = 0;
    LONG result = RegQueryValueExA(key, valueName, nullptr, &type, nullptr, &length);
    if (result == ERROR_FILE_NOT_FOUND)
        return LegacyDefaultDirectoryStatus::Missing;
    if (result != ERROR_SUCCESS || type != REG_SZ ||
        length < 4 || length > MAX_PATH)
        return LegacyDefaultDirectoryStatus::Preserve;

    // Read into a separate buffer. Never modify the destination on errors,
    // concurrent growth, missing termination or invalid drive identity.
    char candidate[MAX_PATH] = {};
    DWORD capacity = sizeof(candidate);
    result = RegQueryValueExA(key, valueName, nullptr, &type,
                              reinterpret_cast<LPBYTE>(candidate), &capacity);
    if (result == ERROR_FILE_NOT_FOUND)
        return LegacyDefaultDirectoryStatus::Missing;
    if (result != ERROR_SUCCESS || type != REG_SZ ||
        capacity < 4 || capacity > MAX_PATH)
        return LegacyDefaultDirectoryStatus::Preserve;

    const char first = candidate[0] >= 'A' && candidate[0] <= 'Z'
                           ? static_cast<char>(candidate[0] + ('a' - 'A'))
                           : candidate[0];
    if (first != static_cast<char>(drive + ('a' - 'A')) ||
        candidate[1] != ':' || candidate[2] != '\\' ||
        candidate[capacity - 1] != '\0' ||
        std::memchr(candidate, '\0', capacity - 1) != nullptr)
        return LegacyDefaultDirectoryStatus::Preserve;

    std::memcpy(destination, candidate, capacity);
    return LegacyDefaultDirectoryStatus::Loaded;
}
} // namespace Salamander
