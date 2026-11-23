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
    std::wstring loaded = L"C:\\fallback";
    if (Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Missing ||
        loaded != L"C:\\fallback")
        failure = Fail("missing path retains fallback");

    const std::string longPath = "C:\\" + std::string(409, 'a'); // 412 + NUL == 413 bytes
    if (!failure &&
        (longPath.size() + 1 != 413 ||
         RegSetValueExA(key, "Path", 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(longPath.c_str()),
                        static_cast<DWORD>(longPath.size() + 1)) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Loaded ||
         loaded != std::wstring(longPath.begin(), longPath.end())))
        failure = Fail("413-byte legacy saved path loads exactly as UTF-16");

    const std::string smallPath = "D:\\folder";
    if (!failure &&
        (RegSetValueExA(key, "Path", 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(smallPath.c_str()),
                        static_cast<DWORD>(smallPath.size() + 1)) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Loaded ||
         loaded != L"D:\\folder"))
        failure = Fail("ordinary path loads exactly");

    // Wrong type must not overwrite the last known-good path.
    if (!failure &&
        (RegSetValueExA(key, "Path", 0, REG_BINARY,
                        reinterpret_cast<const BYTE*>(longPath.c_str()),
                        static_cast<DWORD>(longPath.size() + 1)) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Invalid ||
         loaded != L"D:\\folder"))
        failure = Fail("invalid value type preserves fallback");

    const std::string embeddedNul("E:\\abc\0bad", 10);
    if (!failure &&
        (RegSetValueExA(key, "Path", 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(embeddedNul.c_str()),
                        static_cast<DWORD>(embeddedNul.size() + 1)) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Invalid ||
         loaded != L"D:\\folder"))
        failure = Fail("embedded NUL is rejected without changing fallback");

    // Save and load a path containing several scripts and a surrogate pair.
    const std::wstring retainedPath = L"Z:\\" + std::wstring(240, L'x') + L"\\" +
        std::wstring(80, L'y') + L"\\\u0141\u6771\u4EAC_\U0001F600";
    if (!failure &&
        (Salamander::WriteSavedPanelPath(key, retainedPath) != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Loaded ||
         loaded != retainedPath))
        failure = Fail("Unicode path survives native registry save and load unchanged");

    const std::wstring invalidWidePath(L"Z:\\x\0y", 6);
    if (!failure && (Salamander::WriteSavedPanelPath(key, invalidWidePath) != ERROR_INVALID_PARAMETER ||
                     Salamander::ReadSavedPanelPath(key, loaded) != Salamander::SavedPanelPathStatus::Loaded ||
                     loaded != retainedPath))
        failure = Fail("invalid UTF-16 value must not overwrite the saved path");

    const std::wstring historyPath = retainedPath + L"\\" + std::wstring(225, L'z');
    if (!failure &&
        (historyPath.size() <= 2 * MAX_PATH ||
         Salamander::WriteSavedPanelPath(key, historyPath, L"1") != ERROR_SUCCESS ||
         Salamander::ReadSavedPanelPath(key, loaded, L"1") != Salamander::SavedPanelPathStatus::Loaded ||
         loaded != historyPath ||
         Salamander::ReadSavedPanelPath(key, loaded, L"2") != Salamander::SavedPanelPathStatus::Missing ||
         loaded != historyPath))
        failure = Fail("numbered history value retains the complete path beyond the legacy buffer");

    DWORD originalSize = 0;
    DWORD originalType = REG_NONE;
    if (!failure && (RegQueryValueExW(key, L"Path", nullptr, &originalType,
                                     nullptr, &originalSize) != ERROR_SUCCESS ||
                     originalType != REG_SZ ||
                     originalSize != static_cast<DWORD>((retainedPath.size() + 1) * sizeof(wchar_t))))
        failure = Fail("reading does not mutate the registry");

    RegCloseKey(key);
    if (RegDeleteKeyA(HKEY_CURRENT_USER, keyName.c_str()) != ERROR_SUCCESS && !failure)
        failure = Fail("clean up disposable registry key");

    if (!failure)
        std::puts("PASS: saved panel paths preserve legacy REG_SZ and native UTF-16 exactly");
    return failure;
}
