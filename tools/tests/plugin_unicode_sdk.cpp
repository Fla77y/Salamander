// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#include "../../src/plugins/shared/spl_unicode.h"
#include <string>
#include <cstdio>

using namespace SalamanderSdk;
static std::wstring expected;
static int viewCalls = 0;
static int mode = 0;

static BOOL WINAPI CanView(const WCHAR* name)
{
    return name && expected == name;
}

static BOOL WINAPI View(const WCHAR* name, int, int, int, int, UINT, BOOL,
                        BOOL, HANDLE*, BOOL*, CSalamanderPluginViewerData*, int, int)
{
    ++viewCalls;
    return CanView(name);
}

static BOOL WINAPI Query(DWORD version, DWORD capacity, UnicodeViewerV1* table)
{
    if (version != UnicodeViewerVersion1 || capacity != sizeof(*table) || !table)
        return FALSE;
    table->Size = static_cast<DWORD>(sizeof(*table));
    table->Version = version;
    table->CanViewFileW = CanView;
    table->ViewFileW = View;
    if (mode == 1) return FALSE;
    if (mode == 2) table->Version++;
    if (mode == 3) table->Size--;
    if (mode == 4) table->ViewFileW = nullptr;
    if (mode == 5) table->CanViewFileW = nullptr;
    return TRUE;
}

int main()
{
    UnicodeViewerV1 table{};
    if (NegotiateUnicodeViewerV1(nullptr, table) || table.ViewFileW)
        return 1;
    expected = L"\\\\?\\C:\\";
    for (int i = 0; i < 4; ++i)
        expected += std::wstring(100, L'a') + L"\\";
    expected += L"\u6771\u4eac-\U0001f600.png";
    if (expected.size() <= MAX_PATH ||
        !NegotiateUnicodeViewerV1(Query, table) ||
        !table.CanViewFileW(expected.c_str()) ||
        table.CanViewFileW(L"C:\\wrong.png") ||
        !table.ViewFileW(expected.c_str(), 0, 0, 640, 480, SW_SHOW,
                         FALSE, FALSE, nullptr, nullptr, nullptr, -1, -1) ||
        viewCalls != 1)
        return 2;
    // A failed query must clear a previously negotiated table, not retain
    // stale callbacks into a different/unloaded module.
    for (int i = 1; i <= 5; ++i)
    {
        mode = 0;
        if (!NegotiateUnicodeViewerV1(Query, table))
            return 5;
        mode = i;
        if (NegotiateUnicodeViewerV1(Query, table) ||
            table.Size || table.Version || table.CanViewFileW || table.ViewFileW)
            return 6;
    }
    std::puts("PASS: optional Unicode viewer SDK negotiation and exact long UTF-16 callback identity");
    return 0;
}
