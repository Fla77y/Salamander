// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <cstdio>
#include <cstring>

namespace Salamander
{
// Crash reporting cannot allocate a 32K path into a fixed 1K diagnostics
// buffer. Keep the measured length and enough identity context for diagnosis.
// This helper performs no heap allocations and never exceeds outputCapacity.
inline bool FormatBugReportPanelPath(const char* path,
                                     char* output,
                                     std::size_t outputCapacity) noexcept
{
    if (output == nullptr || outputCapacity == 0)
        return false;

    output[0] = '\0';
    if (path == nullptr)
        path = "<null>";

    const std::size_t length = std::strlen(path);
    int printed = 0;
    if (length <= 300)
    {
        printed = std::snprintf(output, outputCapacity, "Path = %s", path);
    }
    else
    {
        constexpr std::size_t prefixLength = 160;
        constexpr std::size_t suffixLength = 80;
        printed = std::snprintf(
            output, outputCapacity,
            "Path length = %zu ANSI bytes; prefix = %.160s; omitted = %zu bytes; suffix = %s",
            length, path, length - prefixLength - suffixLength,
            path + length - suffixLength);
    }
    return printed >= 0 && static_cast<std::size_t>(printed) < outputCapacity;
}
} // namespace Salamander
