// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <cstring>

// Build SHFileOperationA's double-NUL-terminated single-path list.
// The input must be NUL-terminated; source and destination must not overlap.
// On invalid arguments or insufficient capacity, destination is unchanged.
inline bool BuildShellFileOperationNameList(
    const char* path, char* destination, std::size_t capacity)
{
    if (path == nullptr || destination == nullptr ||
        capacity < 3 || path[0] == '\0')
        return false;

    const std::size_t length = std::strlen(path);
    if (length > capacity - 2)
        return false;

    std::memcpy(destination, path, length + 1);
    destination[length + 1] = '\0';
    return true;
}
