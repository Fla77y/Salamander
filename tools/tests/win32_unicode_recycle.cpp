// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// No real deletion in CI: tests reject invalid/unavailable inputs before COM.
#include "../../src/common/win32_unicode_recycle.h"
#include <windows.h>
#include <cstdio>
#include <string>

int main()
{
    // Arrange: an invalid, uninitialized path cannot refer to any user data.
    Salamander::Utf16DiskPath empty;
    HRESULT error = S_OK;
    // Act: must not reach the shell with an uninitialized source.
    const bool unexpected = Salamander::TryRecycleUnicodeFile(
        empty, nullptr, error);
    // Assert: fail closed and communicate the precise contract failure.
    if (unexpected || error != E_INVALIDARG)
        return std::puts("FAIL: invalid path reached Unicode recycle"), 1;

    // Arrange: a definitely nonexistent file path, without a shell item.
    const std::wstring missing = L"C:\\OpenSal-Nonexistent-20261113-UNICODE-東京\\missing_😀.txt";
    Salamander::Utf16DiskPath path;
    Salamander::Utf16PathError validationError;
    if (!Salamander::Utf16DiskPath::TryCreateAbsolute(
        std::u16string(missing.begin(), missing.end()), path,
        validationError))
        return std::puts("FAIL: UTF-16 test path validation"), 1;
    // Act: no shell operation should run for a missing source.
    const bool nonexistentDeleted = Salamander::TryRecycleUnicodeFile(
        path, nullptr, error);
    // Assert: an unavailable source cannot be treated as recycled.
    if (nonexistentDeleted || SUCCEEDED(error))
        return std::puts("FAIL: nonexistent Unicode source accepted"), 1;

    return std::puts("PASS: Unicode recycle refuses invalid and missing paths"), 0;
}
