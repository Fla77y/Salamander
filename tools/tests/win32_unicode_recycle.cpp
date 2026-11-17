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

    // Arrange: test-owned directory and file. Type mismatches must fail
    // before IFileOperation can recycle anything, even on an unlocked GUI.
    wchar_t temporary[MAX_PATH] = {};
    const DWORD length = GetTempPathW(MAX_PATH, temporary);
    if (length == 0 || length >= MAX_PATH)
        return std::puts("FAIL: temporary directory unavailable"), 1;
    const std::wstring root = std::wstring(temporary) +
        L"OpenSal-RecycleType-" + std::to_wstring(GetCurrentProcessId()) +
        L"-" + std::to_wstring(GetTickCount64());
    if (!CreateDirectoryW(root.c_str(), nullptr))
        return std::puts("FAIL: create type-check fixture"), 1;
    const std::wstring leaf = root + L"\\file-東京.txt";
    HANDLE handle = CreateFileW(leaf.c_str(), GENERIC_WRITE, 0, nullptr,
                                CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (handle == INVALID_HANDLE_VALUE)
        return std::puts("FAIL: create type-check leaf"), 1;
    CloseHandle(handle);

    Salamander::Utf16DiskPath ownedRoot, ownedFile;
    if (!Salamander::Utf16DiskPath::TryCreateAbsolute(
            std::u16string(root.begin(), root.end()), ownedRoot, validationError) ||
        !Salamander::Utf16DiskPath::TryCreateAbsolute(
            std::u16string(leaf.begin(), leaf.end()), ownedFile, validationError))
        return std::puts("FAIL: own type-check paths"), 1;

    // Act / Assert: no shell operation and no filesystem mutation.
    if (Salamander::TryRecycleUnicodeFile(ownedRoot, nullptr, error) ||
        error != HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED) ||
        Salamander::TryRecycleUnicodeDirectory(ownedFile, nullptr, error) ||
        error != HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED) ||
        GetFileAttributesW(root.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(leaf.c_str()) == INVALID_FILE_ATTRIBUTES)
        return std::puts("FAIL: recycle type contract did not fail closed"), 1;

    if (!DeleteFileW(leaf.c_str()) || !RemoveDirectoryW(root.c_str()))
        return std::puts("FAIL: cleanup type-check fixture"), 1;
    return std::puts("PASS: Unicode recycle rejects missing paths and mismatched directory/file types"), 0;
}
