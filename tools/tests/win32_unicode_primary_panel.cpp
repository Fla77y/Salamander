// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/common/win32_unicode_primary_panel.h"

#include <windows.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <utility>

int main()
{
    // Arrange: two distinct rows whose CP_ACP aliases may coincide.
    char first[] = "same-ansi-alias";
    char second[] = "same-ansi-alias";
    Salamander::UnicodePanelRowIdentities rows;
    rows.Record(first, L"東京_😀.txt");
    rows.Record(second, L"大阪_😀.txt");

    // Act: sorting exchanges row records, not their allocated Name pointers.
    struct Row { char* name; };
    Row left{first}, right{second};
    std::swap(left, right);
    std::wstring name;

    // Assert: identity follows the original heap allocation, not an alias.
    if (!rows.TryGet(left.name, name) || name != L"大阪_😀.txt" ||
        !rows.TryGet(right.name, name) || name != L"東京_😀.txt")
        return std::puts("FAIL: Unicode row identity lost after sort"), 1;

    rows.Clear();
    if (rows.TryGet(first, name) || !name.empty())
        return std::puts("FAIL: Unicode identity persisted across refresh"), 1;

    // The Win32-wide primary adapter must not narrow a file into a
    // different row identity. It can reject an unrepresentable output.
    const WIN32_FIND_DATAW wide = [] {
        WIN32_FIND_DATAW d = {};
        wcscpy_s(d.cFileName, _countof(d.cFileName), L"Größe_東京_😀.txt");
        d.dwFileAttributes = FILE_ATTRIBUTE_ARCHIVE;
        d.nFileSizeLow = 123;
        return d;
    }();
    WIN32_FIND_DATAA legacy = {};
    DWORD error = ERROR_SUCCESS;
    if (!Salamander::TryConvertUnicodePanelFindData(wide, legacy, error))
        return std::puts("FAIL: wide panel metadata conversion failed"), 1;
    if (legacy.nFileSizeLow != 123 || legacy.dwFileAttributes != FILE_ATTRIBUTE_ARCHIVE ||
        legacy.cFileName[0] == '\0')
        return std::puts("FAIL: primary metadata contract changed"), 1;

    // A max-length Unicode component may expand beyond the legacy ANSI
    // WIN32_FIND_DATAA array; rejecting it is safer than truncating it.
    WIN32_FIND_DATAW oversized = {};
    for (int i = 0; i < 255; ++i)
        oversized.cFileName[i] = L'東';
    oversized.cFileName[255] = 0;
    if (Salamander::TryConvertUnicodePanelFindData(
            oversized, legacy, error) && std::strlen(legacy.cFileName) >= MAX_PATH)
        return std::puts("FAIL: legacy ANSI buffer overflow accepted"), 1;

    return std::puts("PASS: per-row Unicode identities and wide find-data adapter"), 0;
}
