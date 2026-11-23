// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/common/isolated_test_configuration.h"
#include <cstdio>

int main()
{
    // Arrange
    const std::string id = "0123456789abcdef0123456789abcdef";
    const std::string prefix = "Software\\Open Salamander\\CodexTests\\" + id;
    std::string current, previous;
    // Act / Assert: version discovery cannot leave the private namespace.
    if (!Salamander::TryBuildIsolatedConfigurationRoot(id, 0, current) ||
        !Salamander::TryBuildIsolatedConfigurationRoot(id, 999, previous) ||
        current != prefix + "\\Config0" || previous != prefix + "\\Config999" ||
        current == previous || current.size() + 32 >= 200)
        return std::puts("FAIL: private configuration roots"), 1;
    // Arrange / Act / Assert: reject injected paths and stale outputs.
    const char* invalid[] = {"", "short", "Software\\user", "0123456789abcdef0123456789abcdeg",
        "0123456789ABCDEF0123456789ABCDEF"};
    for (const char* value : invalid)
    {
        current = "stale";
        if (Salamander::TryBuildIsolatedConfigurationRoot(value, 0, current) || !current.empty())
            return std::puts("FAIL: unsafe test configuration ID"), 1;
    }
    if (Salamander::TryBuildIsolatedConfigurationRoot(id, 1000, current) || !current.empty())
        return std::puts("FAIL: excessive configuration root index"), 1;
    return std::puts("PASS: isolated configuration roots, version separation and invalid IDs"), 0;
}
