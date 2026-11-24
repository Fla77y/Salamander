// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Regression for the build information shown in Help > About.
#include "../../src/common/about_build_info.h"

#include <cstdio>

int main()
{
    SYSTEMTIME time{};
    time.wYear = 2026;
    time.wMonth = 11;
    time.wDay = 24;
    time.wHour = 2;
    time.wMinute = 7;
    time.wSecond = 9;

    if (Salamander::FormatAboutBuildInfo(time, true, true) !=
            L"Build: 2026-11-24 02:07:09 (Debug x64)" ||
        Salamander::FormatAboutBuildInfo(time, false, true) !=
            L"Build: 2026-11-24 02:07:09 (Release x64)" ||
        Salamander::FormatAboutBuildInfo(time, true, false) !=
            L"Build: 2026-11-24 02:07:09 (Debug x86)" ||
        Salamander::FormatAboutBuildInfo(time, false, false) !=
            L"Build: 2026-11-24 02:07:09 (Release x86)")
    {
        std::fputs("FAIL: build date/time or configuration label\n", stderr);
        return 1;
    }

    SYSTEMTIME executableTime{};
    if (!Salamander::TryReadExecutableBuildTime(executableTime) ||
        executableTime.wYear < 2020 ||
        executableTime.wMonth < 1 || executableTime.wMonth > 12 ||
        executableTime.wDay < 1 || executableTime.wDay > 31 ||
        executableTime.wHour > 23 || executableTime.wMinute > 59 ||
        executableTime.wSecond > 59)
    {
        std::fputs("FAIL: executable build timestamp cannot be read\n", stderr);
        return 1;
    }

    std::puts("PASS: About displays executable build date/time and Debug/Release platform identity");
    return 0;
}
