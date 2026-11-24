// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <windows.h>
#include <cstring>

namespace Salamander
{

// Preserve the executable identity for a configured, existing absolute EXE.
// In particular, packaged WindowsApps tools need not be located by parsing
// a compound command line. Relative commands and other executable types must
// keep the legacy CreateProcess(NULL, ...) search/association behavior.
inline const char* GetExplicitEditorApplicationName(const char* command)
{
    if (command == nullptr || command[0] == '\0')
        return nullptr;

    const unsigned char drive = static_cast<unsigned char>(command[0]);
    const bool driveAbsolute =
        ((drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z')) &&
        command[1] == ':' && (command[2] == '\\' || command[2] == '/');
    const bool uncAbsolute =
        command[0] == '\\' && command[1] == '\\' &&
        command[2] != '\0' && command[2] != '\\';
    if (!driveAbsolute && !uncAbsolute)
        return nullptr;

    const char* extension = strrchr(command, '.');
    if (extension == nullptr || _stricmp(extension, ".exe") != 0)
        return nullptr;

    const DWORD attributes = GetFileAttributesA(command);
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
        return nullptr;

    return command;
}

inline BOOL CreateConfiguredEditorProcessA(
    const char* command, char* commandLine, const char* workingDirectory,
    DWORD creationFlags, STARTUPINFOA* startupInfo,
    PROCESS_INFORMATION* processInfo)
{
    return CreateProcessA(GetExplicitEditorApplicationName(command),
                          commandLine, nullptr, nullptr, FALSE,
                          creationFlags, nullptr, workingDirectory,
                          startupInfo, processInfo);
}

} // namespace Salamander
