// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Regression: a crash reporter must never overflow its fixed output buffer
// when the active panel contains a near-maximum-length Windows path.
#include "../../src/common/bug_report_path.h"

#include <cstdio>
#include <cstring>
#include <string>

int main()
{
    // Arrange: an ordinary panel path must remain readable in diagnostics.
    char shortOutput[1024] = {};
    // Act / Assert.
    if (!Salamander::FormatBugReportPanelPath("C:\\folder", shortOutput, sizeof(shortOutput)) ||
        std::strcmp(shortOutput, "Path = C:\\folder") != 0)
    {
        std::fputs("FAIL: short panel path report changed\n", stderr);
        return 1;
    }

    // Arrange: the panel holds exactly 32,444 ANSI bytes, but the crash
    // reporter's output buffer has only 1,024 bytes plus adjacent canaries.
    std::string longPath = "C:\\";
    longPath.append(32444 - longPath.size() - 6, 'x');
    longPath += "\\final";
    if (longPath.size() != 32444)
        return 1;
    struct GuardedOutput
    {
        char before;
        char text[1024];
        char after;
    } guarded = {'B', {}, 'A'};

    // Act.
    const bool formatted = Salamander::FormatBugReportPanelPath(
        longPath.c_str(), guarded.text, sizeof(guarded.text));

    // Assert: the report is compact, terminated, has the true length and
    // leaves adjacent memory untouched even with a 32,444-byte input.
    if (!formatted || guarded.before != 'B' || guarded.after != 'A' ||
        std::strlen(guarded.text) >= sizeof(guarded.text) ||
        std::strstr(guarded.text, "32444") == nullptr ||
        std::strstr(guarded.text, "final") == nullptr ||
        std::strstr(guarded.text, "omitted") == nullptr)
    {
        std::fputs("FAIL: long panel path report overflow or information loss\n", stderr);
        return 1;
    }

    // Arrange / Act / Assert: a genuinely insufficient buffer must be
    // rejected without writing beyond its end.
    struct TinyOutput { char text[5]; char guard; } tiny = {{}, 'G'};
    const bool smallResult = Salamander::FormatBugReportPanelPath(
        "C:\\folder", tiny.text, sizeof(tiny.text));
    if (smallResult || tiny.guard != 'G' || tiny.text[4] != '\0')
    {
        std::fputs("FAIL: undersized crash-report output not handled safely\n", stderr);
        return 1;
    }

    std::puts("PASS: crash report formats 32444-byte panel paths without overflowing diagnostic buffers");
    return 0;
}
