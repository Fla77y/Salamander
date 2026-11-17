// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Native directory deletion regression: isolated test-owned Unicode subtree.
#include "../../src/common/win32_unicode_directory_delete.h"
#include <windows.h>
#include <cstdio>
#include <string>

namespace
{
bool Own(const std::wstring& input, Salamander::Utf16DiskPath& result)
{
    Salamander::Utf16PathError error;
    return Salamander::Utf16DiskPath::TryCreateAbsolute(
        std::u16string(input.begin(), input.end()), result, error);
}
}

int main()
{
    DWORD error = ERROR_SUCCESS;
    Salamander::Utf16DiskPath missing;
    if (Salamander::TryDeleteUnicodeDirectoryTree(missing, error) ||
        error != ERROR_INVALID_PARAMETER)
        return std::puts("FAIL: empty directory path not rejected"), 1;

    wchar_t temp[MAX_PATH] = {};
    const DWORD length = GetTempPathW(MAX_PATH, temp);
    if (length == 0 || length >= MAX_PATH)
        return std::puts("FAIL: test TEMP unavailable"), 1;

    const std::wstring root = std::wstring(temp) + L"OpenSal-DirectoryDelete-" +
        std::to_wstring(GetCurrentProcessId()) + L"-" +
        std::to_wstring(GetTickCount64());
    const std::wstring ownedDir = root + L"\\東京-😀";
    if (!CreateDirectoryW(root.c_str(), nullptr) ||
        !CreateDirectoryW(ownedDir.c_str(), nullptr))
        return std::puts("FAIL: create owned test root"), 1;

    std::wstring deep = ownedDir;
    for (int i = 0; i < 4; ++i)
    {
        deep += L"\\level-" + std::to_wstring(i) + L"-" + std::wstring(65, L'x');
        std::wstring extended;
        if (!Salamander::TryMakeExtendedLengthPath(deep.c_str(), extended, error) ||
            !CreateDirectoryW(extended.c_str(), nullptr))
            return std::puts("FAIL: create long nested directory"), 1;
    }
    const std::wstring leaf = deep + L"\\Größe-大阪-😀.dat";
    std::wstring wideLeaf;
    if (!Salamander::TryMakeExtendedLengthPath(leaf.c_str(), wideLeaf, error) ||
        leaf.size() <= MAX_PATH)
        return std::puts("FAIL: long Unicode fixture invalid"), 1;
    HANDLE file = CreateFileW(wideLeaf.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return std::puts("FAIL: create long Unicode leaf"), 1;
    CloseHandle(file);

    Salamander::Utf16DiskPath directory;
    Salamander::Utf16DiskPath filePath;
    if (!Own(ownedDir, directory) || !Own(leaf, filePath))
        return std::puts("FAIL: own UTF-16 fixture paths"), 1;
    // Never allow a file path to be treated as a directory tree.
    if (Salamander::TryDeleteUnicodeDirectoryTree(filePath, error) ||
        GetFileAttributesW(wideLeaf.c_str()) == INVALID_FILE_ATTRIBUTES)
        return std::puts("FAIL: file-only source not rejected"), 1;

    // Act: removal must traverse a >MAX_PATH Unicode directory tree.
    if (!Salamander::TryDeleteUnicodeDirectoryTree(directory, error))
    {
        std::printf("FAIL: Unicode directory deletion failed (Win32=%lu)\n", error);
        return 1;
    }
    // Assert: the exact subtree is gone and its parent was not touched.
    if (GetFileAttributesW(ownedDir.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(root.c_str()) == INVALID_FILE_ATTRIBUTES)
        return std::puts("FAIL: wrong subtree or parent affected"), 1;
    // Arrange: the original reported fixture uses an ASCII OpenSal-GuiLong
    // directory name, but has Unicode and >MAX_PATH descendants.
    const std::wstring asciiRoot = root + L"\\OpenSal-GuiLong-ascii";
    if (!CreateDirectoryW(asciiRoot.c_str(), nullptr))
        return std::puts("FAIL: create ASCII temp root"), 1;
    std::wstring asciiDeep = asciiRoot;
    for (int i = 0; i < 4; ++i)
    {
        asciiDeep += L"\\nested-" + std::to_wstring(i) + L"-" +
                     std::wstring(65, L'y');
        std::wstring extended;
        if (!Salamander::TryMakeExtendedLengthPath(
                asciiDeep.c_str(), extended, error) ||
            !CreateDirectoryW(extended.c_str(), nullptr))
            return std::puts("FAIL: create ASCII-named long subtree"), 1;
    }
    const std::wstring asciiLeaf = asciiDeep + L"\\file-大阪-😀.txt";
    std::wstring extendedLeaf;
    if (!Salamander::TryMakeExtendedLengthPath(
            asciiLeaf.c_str(), extendedLeaf, error))
        return std::puts("FAIL: extend ASCII subtree leaf"), 1;
    HANDLE second = CreateFileW(extendedLeaf.c_str(), GENERIC_WRITE, 0,
                                nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (second == INVALID_HANDLE_VALUE)
        return std::puts("FAIL: create ASCII subtree Unicode leaf"), 1;
    CloseHandle(second);

    Salamander::Utf16DiskPath asciiDirectory;
    if (!Own(asciiRoot, asciiDirectory))
        return std::puts("FAIL: own ASCII directory path"), 1;
    bool needsNative = false;
    if (!Salamander::TryNeedsNativeUnicodeDirectoryDelete(
            asciiDirectory, needsNative, error) || !needsNative)
        return std::puts("FAIL: missed long descendant under ASCII temp root"), 1;
    if (!Salamander::TryDeleteUnicodeDirectoryTree(asciiDirectory, error) ||
        GetFileAttributesW(asciiRoot.c_str()) != INVALID_FILE_ATTRIBUTES)
        return std::puts("FAIL: ASCII temp root with long Unicode child not deleted"), 1;

    // A simple ASCII-only empty directory keeps the original legacy F8 path.
    const std::wstring simple = root + L"\\simple-ascii";
    if (!CreateDirectoryW(simple.c_str(), nullptr))
        return std::puts("FAIL: create simple ASCII dir"), 1;
    Salamander::Utf16DiskPath simpleDirectory;
    if (!Own(simple, simpleDirectory))
        return std::puts("FAIL: own simple dir"), 1;
    needsNative = true;
    if (!Salamander::TryNeedsNativeUnicodeDirectoryDelete(
            simpleDirectory, needsNative, error) || needsNative)
        return std::puts("FAIL: ordinary directory should retain legacy UI"), 1;
    if (!RemoveDirectoryW(simple.c_str()) || !RemoveDirectoryW(root.c_str()))
        return std::puts("FAIL: owned fixture parent was not empty"), 1;
    return std::puts("PASS: UTF-16 deletion handles Unicode and ASCII temp roots with long descendants"), 0;
}
