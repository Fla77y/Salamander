// SPDX-FileCopyrightText: 2026 Open Salamander contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <cstring>

// Copies one path into SHFileOperationA's double-NUL-terminated name list.
// Returns false without modifying the destination when arguments are invalid
// or the path and its two terminators do not fit.
inline bool BuildShellFileOperationNameList(const char* path, char* destination, size_t capacity)
{
    if (path == nullptr || destination == nullptr || capacity < 3 || path[0] == '\0')
        return false;

    const size_t length = std::strlen(path);
    if (length > capacity - 2)
        return false;

    std::memcpy(destination, path, length + 1);
    destination[length + 1] = '\0';
    return true;
}
