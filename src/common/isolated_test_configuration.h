// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include <utility>

namespace Salamander
{
// Test configuration IDs are generated GUIDs, never arbitrary registry paths.
// All version roots stay under one independently removable test namespace.
inline bool TryBuildIsolatedConfigurationRoot(std::string_view id, std::size_t index,
                                              std::string& output)
{
    if (id.size() != 32 || index >= 1000)
    {
        output.clear();
        return false;
    }
    for (char c : id)
    {
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
        {
            output.clear();
            return false;
        }
    }
    std::string root = "Software\\Open Salamander\\CodexTests\\";
    root.append(id);
    root += "\\Config" + std::to_string(index);
    output = std::move(root);
    return true;
}
} // namespace Salamander
