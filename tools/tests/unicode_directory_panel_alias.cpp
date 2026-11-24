// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Real filesystem fixture: Windows 8.3 aliases are optional, so the
// Unicode-positive branch is conditional on the volume providing one.
// Never consider a lossy ACP path or an unrelated existing directory safe.
#include "../../src/common/win32_unicode_panel_name.h"

#include <windows.h>
#include <cstdio>
#include <string>

static int Fail(const char* message)
{
    std::fprintf(stderr, "FAIL: %s\n", message);
    return 1;
}

int main()
{
    wchar_t tempRoot[MAX_PATH]{};
    const DWORD tempLength = GetTempPathW(MAX_PATH, tempRoot);
    if (tempLength == 0 || tempLength >= MAX_PATH - 90)
        return Fail("a private short temporary base path is required");

    wchar_t uniqueName[90]{};
    swprintf_s(uniqueName, L"OpenSal-UnicodeParent-%lu-%lu",
               GetCurrentProcessId(), GetTickCount());
    const std::wstring ownedRoot = std::wstring(tempRoot) + uniqueName;
    const std::wstring widePath = ownedRoot + L"\\\u6771\u4eac\u20ac\u5b57";
    if (!CreateDirectoryW(ownedRoot.c_str(), nullptr))
        return Fail("could not create owned root");
    if (!CreateDirectoryW(widePath.c_str(), nullptr))
    {
        RemoveDirectoryW(ownedRoot.c_str());
        return Fail("could not create Unicode directory");
    }

    int failures = 0;
    std::string alias;
    if (!Salamander::TryGetVerifiedAnsiShortDirectoryPath(ownedRoot, alias) ||
        GetFileAttributesA(alias.c_str()) == INVALID_FILE_ATTRIBUTES)
    {
        std::fputs("FAIL: ordinary directory must have a usable exact ANSI representation\n", stderr);
        ++failures;
    }

    alias.clear();
    const bool hasVerifiedAlias =
        Salamander::TryGetVerifiedAnsiShortDirectoryPath(widePath, alias);
    if (hasVerifiedAlias)
    {
        const DWORD aliasAttributes = GetFileAttributesA(alias.c_str());
        if (alias.empty() || aliasAttributes == INVALID_FILE_ATTRIBUTES ||
            (aliasAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
        {
            std::fputs("FAIL: Unicode short alias lacks verified directory identity\n", stderr);
            ++failures;
        }
        else
            std::puts("PASS: Unicode directory has a verified ANSI-safe short alias");
    }
    else if (!alias.empty())
    {
        std::fputs("FAIL: refusal must not publish a lossy or partial ANSI path\n", stderr);
        ++failures;
    }
    else
        std::puts("SKIP: Unicode 8.3 alias unavailable on this volume; navigation must refuse safely");

    if (Salamander::TryGetVerifiedAnsiShortDirectoryPath(
            ownedRoot + L"\\does-not-exist", alias) ||
        !alias.empty())
    {
        std::fputs("FAIL: nonexistent path must never be given a legacy alias\n", stderr);
        ++failures;
    }

    if (!RemoveDirectoryW(widePath.c_str()) ||
        !RemoveDirectoryW(ownedRoot.c_str()))
    {
        std::fputs("FAIL: remove owned Unicode navigation fixture\n", stderr);
        ++failures;
    }

    if (failures != 0)
        return 1;
    std::puts("PASS: Unicode directory bridge uses only original W identity and verified DOS aliases");
    return 0;
}
