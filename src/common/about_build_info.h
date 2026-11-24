// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <windows.h>
#include <cwchar>
#include <string>

#include "win32_long_path.h"

namespace Salamander
{
// The last-write time belongs to the executable produced by the linker.
// Unlike __DATE__/__TIME__, it remains correct for incremental builds where
// the About translation unit is not recompiled.
inline bool TryReadExecutableBuildTime(SYSTEMTIME& localTime)
{
    DWORD capacity = MAX_PATH;
    std::wstring executable;
    for (;;)
    {
        executable.resize(capacity);
        const DWORD length = GetModuleFileNameW(nullptr, &executable[0], capacity);
        if (length == 0)
            return false;
        if (length < capacity - 1)
        {
            executable.resize(length);
            break;
        }
        if (capacity >= 32768)
            return false;
        capacity = capacity > 16384 ? 32768 : capacity * 2;
    }

    // An executable may itself be launched from a >MAX_PATH directory.
    // Query its timestamp through the same normalized W path support as
    // the rest of the long-path migration.
    std::wstring extendedPath;
    if (executable.compare(0, 4, L"\\\\?\\") == 0)
        extendedPath = executable;
    else
    {
        DWORD pathError = ERROR_SUCCESS;
        if (!TryMakeExtendedLengthPath(executable.c_str(), extendedPath, pathError))
            return false;
    }

    WIN32_FILE_ATTRIBUTE_DATA attributes{};
    if (!GetFileAttributesExW(extendedPath.c_str(), GetFileExInfoStandard, &attributes) ||
        (attributes.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
        return false;

    FILETIME localFileTime{};
    return FileTimeToLocalFileTime(&attributes.ftLastWriteTime, &localFileTime) != FALSE &&
           FileTimeToSystemTime(&localFileTime, &localTime) != FALSE;
}

inline std::wstring FormatAboutBuildInfo(const SYSTEMTIME& time,
                                          bool debugBuild, bool x64Build)
{
    wchar_t label[96]{};
    const int written = swprintf_s(label, _countof(label),
                                   L"Build: %04u-%02u-%02u %02u:%02u:%02u (%ls %ls)",
                                   static_cast<unsigned>(time.wYear),
                                   static_cast<unsigned>(time.wMonth),
                                   static_cast<unsigned>(time.wDay),
                                   static_cast<unsigned>(time.wHour),
                                   static_cast<unsigned>(time.wMinute),
                                   static_cast<unsigned>(time.wSecond),
                                   debugBuild ? L"Debug" : L"Release",
                                   x64Build ? L"x64" : L"x86");
    return written < 0 ? std::wstring() : std::wstring(label);
}

inline std::wstring GetAboutBuildInfo()
{
#ifdef _DEBUG
    constexpr bool debugBuild = true;
#else
    constexpr bool debugBuild = false;
#endif
#ifdef _WIN64
    constexpr bool x64Build = true;
#else
    constexpr bool x64Build = false;
#endif

    SYSTEMTIME localTime{};
    if (TryReadExecutableBuildTime(localTime))
        return FormatAboutBuildInfo(localTime, debugBuild, x64Build);

    // Never substitute the current time: that would claim a new build when
    // the executable timestamp cannot be read.
    return std::wstring(L"Build: unavailable (") +
           (debugBuild ? L"Debug " : L"Release ") +
           (x64Build ? L"x64)" : L"x86)");
}
} // namespace Salamander
