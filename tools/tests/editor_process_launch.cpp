// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
// Windows regression: preserve the application identity for an absolute
// configured .exe; do not alter historical searches for relative commands.
#include "../../src/common/win32_editor_process_launch.h"

#include <windows.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

static int Fail(const char* message)
{
    std::fprintf(stderr, "FAIL: %s\n", message);
    return 1;
}

int main()
{
    char systemDirectory[MAX_PATH]{};
    const UINT length = GetSystemDirectoryA(systemDirectory, MAX_PATH);
    if (length == 0 || length >= MAX_PATH - 12)
        return Fail("Windows system directory unavailable");

    const std::string command = std::string(systemDirectory) + "\\cmd.exe";
    if (Salamander::GetExplicitEditorApplicationName(command.c_str()) == nullptr)
        return Fail("a valid absolute .exe must be used as application name");
    if (std::strcmp(Salamander::GetExplicitEditorApplicationName(command.c_str()), command.c_str()) != 0)
        return Fail("absolute executable identity changed");
    if (Salamander::GetExplicitEditorApplicationName("cmd.exe") != nullptr ||
        Salamander::GetExplicitEditorApplicationName("C:relative.exe") != nullptr ||
        Salamander::GetExplicitEditorApplicationName("C:\\missing-editor-for-regression.exe") != nullptr ||
        Salamander::GetExplicitEditorApplicationName("C:\\example\\editor.cmd") != nullptr ||
        Salamander::GetExplicitEditorApplicationName(nullptr) != nullptr)
        return Fail("relative, unverified or non-EXE commands must retain old process discovery");

    // The same path + arguments layout used by EditFile. The command line is
    // writable as required by CreateProcess; exit code proves child identity.
    std::string commandLine = "\"" + command + "\" /D /C exit 7";
    std::vector<char> mutableCommandLine(commandLine.begin(), commandLine.end());
    mutableCommandLine.push_back('\0');
    STARTUPINFOA startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    // Same exact executable identity passed to the tracked CreateProcess
    // call in CFilesWindow::EditFile; this standalone test has no handles
    // monitor and invokes the Win32 API directly.
    if (!CreateProcessA(
            Salamander::GetExplicitEditorApplicationName(command.c_str()),
            mutableCommandLine.data(), nullptr, nullptr, FALSE,
            NORMAL_PRIORITY_CLASS, nullptr, systemDirectory,
            &startup, &process))
        return Fail("explicit executable failed to launch using editor path");
    const DWORD result = WaitForSingleObject(process.hProcess, 15000);
    DWORD exitCode = 0;
    const BOOL exitReadable = GetExitCodeProcess(process.hProcess, &exitCode);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    if (result != WAIT_OBJECT_0 || !exitReadable || exitCode != 7)
        return Fail("explicit configured editor did not run with exact arguments");
    std::puts("PASS: external editor launches absolute .exe without ambiguous command-line resolution");
    return 0;
}
