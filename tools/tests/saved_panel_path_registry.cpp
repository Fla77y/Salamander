// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/common/saved_panel_path_registry.h"
#include <cstdio>
#include <string>

static int Fail(const char* message)
{
    std::fprintf(stderr, "FAIL: saved panel path registry: %s\n", message);
    return 1;
}

int main()
{
    const std::string keyName = "Software\\OpenSalamanderPanelPathTest-" +
                                std::to_string(GetCurrentProcessId());
    HKEY key = nullptr;
    const LONG created = RegCreateKeyExA(HKEY_CURRENT_USER, keyName.c_str(), 0,
                                        nullptr, REG_OPTION_NON_VOLATILE,
                                        KEY_ALL_ACCESS, nullptr, &key, nullptr);
    if (created != ERROR_SUCCESS)
        return Fail("create disposable registry key");

    int failure = 0;
    std::string loaded = "C:\\fallback";
    if (Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Missing ||
        loaded != "C:\\fallback")
        failure = Fail("missing path retains fallback");

    const std::string longPath = "C:\\" + std::string(409, 'a'); // 412 + NUL == 413 bytes
    if (!failure &&
        (longPath.size() + 1 != 413 ||
         RegSetValueExA(key, "Path", 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(longPath.c_str()),
                        static_cast<DWORD>(longPath.size() + 1)) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Loaded ||
         loaded != longPath))
        failure = Fail("413-byte saved path loads exactly without MAX_PATH truncation");

    const std::string smallPath = "D:\\folder";
    if (!failure &&
        (RegSetValueExA(key, "Path", 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(smallPath.c_str()),
                        static_cast<DWORD>(smallPath.size() + 1)) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Loaded ||
         loaded != smallPath))
        failure = Fail("ordinary path loads exactly");

    // Wrong type must not overwrite the last known-good path.
    if (!failure &&
        (RegSetValueExA(key, "Path", 0, REG_BINARY,
                        reinterpret_cast<const BYTE*>(longPath.c_str()),
                        static_cast<DWORD>(longPath.size() + 1)) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Invalid ||
         loaded != smallPath))
        failure = Fail("invalid value type preserves fallback");

    const std::string embeddedNul("E:\\abc\0bad", 10);
    if (!failure &&
        (RegSetValueExA(key, "Path", 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(embeddedNul.c_str()),
                        static_cast<DWORD>(embeddedNul.size() + 1)) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Invalid ||
         loaded != smallPath))
        failure = Fail("embedded NUL is rejected without changing fallback");

    // No in-place rewriting of the original saved path is permitted.
    const std::string retainedPath = "Z:\\" + std::string(409, 'x');
    if (!failure &&
        (RegSetValueExA(key, "Path", 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(retainedPath.c_str()),
                        static_cast<DWORD>(retainedPath.size() + 1)) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Loaded ||
         loaded != retainedPath))
        failure = Fail("long path survives reading unchanged");

    DWORD originalSize = 0;
    DWORD originalType = REG_NONE;
    if (!failure && (RegQueryValueExA(key, "Path", nullptr, &originalType,
                                     nullptr, &originalSize) != ERROR_SUCCESS ||
                     originalType != REG_SZ ||
                     originalSize != static_cast<DWORD>(retainedPath.size() + 1)))
        failure = Fail("reading does not mutate the registry");

    RegCloseKey(key);
    if (RegDeleteKeyA(HKEY_CURRENT_USER, keyName.c_str()) != ERROR_SUCCESS && !failure)
        failure = Fail("clean up disposable registry key");

    if (!failure)
        std::puts("PASS: saved panel paths restore 413-byte and short REG_SZ without truncation or modification");
    return failure;
}
