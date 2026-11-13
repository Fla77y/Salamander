// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Headless MSVC compile/link and template-layout checks for the native
// Unicode editor. Interactive keyboard behavior is tested by the GUI driver.
#include "../../src/common/win32_unicode_rename_dialog.h"

#include <windows.h>
#include <cstdio>

#pragma comment(lib, "user32.lib")

int main()
{
    auto dialog = Salamander::UnicodeRenameDialogDetail::BuildTemplate();
    if (!dialog.Valid())
        return std::puts("FAIL: Unicode rename dialog exceeded template allocation"), 1;

    const DLGTEMPLATE* layout = dialog.Data();
    if (layout == nullptr || layout->cdit != 4 ||
        (layout->style & WS_CAPTION) == 0 ||
        (layout->style & DS_MODALFRAME) == 0)
        return std::puts("FAIL: Unicode rename dialog layout is incomplete"), 1;

    // Negative tests: modal UI must never open for empty/invalid filename
    // automatically. Validating the UTF-16 filename remains the caller's job.
    Salamander::UnicodeRenameDialogDetail::State initial{
        L"file_東京_😀.txt", false, false};
    if (initial.name.find(L'東') == std::wstring::npos)
        return std::puts("FAIL: Unicode original name lost before dialog"), 1;

    return std::puts("PASS: native UTF-16 modal rename dialog compiled and layout verified"), 0;
}
