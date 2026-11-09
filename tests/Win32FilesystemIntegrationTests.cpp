// SPDX-FileCopyrightText: 2026 Open Salamander contributors
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Filesystem integration tests: real Win32 file/directory operations.
// Must run on Windows, preferably on a local NTFS volume.

#include "../src/common/win32widepaths.h"

#include <windows.h>
#include <array>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
void Check(bool condition, const char* message)
{
    if (!condition)
        throw std::runtime_error(message);
}

std::wstring Join(const std::wstring& directory, const std::wstring& leaf)
{
    return directory + L"\\" + leaf;
}

std::wstring Extended(const std::wstring& path)
{
    std::wstring result;
    Check(SalWidePaths::MakeExtendedPath(path.c_str(), result), "MakeExtendedPath failed");
    return result;
}

bool Exists(const std::wstring& path)
{
    return GetFileAttributesW(Extended(path).c_str()) != INVALID_FILE_ATTRIBUTES;
}

void CreateDirectoryAt(const std::wstring& path)
{
    Check(CreateDirectoryW(Extended(path).c_str(), nullptr) != 0, "CreateDirectoryW failed");
}

void WriteFileAt(const std::wstring& path, const char* value)
{
    HANDLE handle = CreateFileW(Extended(path).c_str(), GENERIC_WRITE, 0, nullptr,
                               CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(handle != INVALID_HANDLE_VALUE, "CreateFileW failed");
    DWORD written = 0;
    const DWORD bytes = static_cast<DWORD>(strlen(value));
    const bool ok = WriteFile(handle, value, bytes, &written, nullptr) != 0;
    CloseHandle(handle);
    Check(ok && written == bytes, "WriteFile failed");
}

std::string ReadFileAt(const std::wstring& path)
{
    HANDLE handle = CreateFileW(Extended(path).c_str(), GENERIC_READ, FILE_SHARE_READ,
                               nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(handle != INVALID_HANDLE_VALUE, "ReadFile open failed");
    std::array<char, 128> buffer{};
    DWORD read = 0;
    const bool ok = ReadFile(handle, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr) != 0;
    CloseHandle(handle);
    Check(ok, "ReadFile failed");
    return std::string(buffer.data(), read);
}

bool TryEncodeWithoutSubstitution(const std::wstring& wide, std::string& narrow)
{
    BOOL usedDefault = FALSE;
    // WC_NO_BEST_FIT_CHARS is invalid for UTF-8, and UTF-8 never substitutes.
    const UINT codepage = GetACP();
    const DWORD flags = codepage == CP_UTF8 ? WC_ERR_INVALID_CHARS : WC_NO_BEST_FIT_CHARS;
    const int count = WideCharToMultiByte(codepage, flags, wide.c_str(), -1, nullptr, 0,
                                          nullptr, codepage == CP_UTF8 ? nullptr : &usedDefault);
    if (count <= 0 || usedDefault)
        return false;
    narrow.resize(static_cast<size_t>(count));
    usedDefault = FALSE;
    const int written = WideCharToMultiByte(codepage, flags, wide.c_str(), -1, narrow.data(), count,
                                            nullptr, codepage == CP_UTF8 ? nullptr : &usedDefault);
    if (written != count || usedDefault)
        return false;
    narrow.pop_back(); // exclude terminating null
    return true;
}

// Owns only the directories created by this test; never touches existing user files.
struct Sandbox
{
    std::wstring root;
    std::vector<std::wstring> directories;
    std::vector<std::wstring> files;

    Sandbox()
    {
        std::array<wchar_t, MAX_PATH + 1> temp{};
        DWORD length = GetTempPathW(static_cast<DWORD>(temp.size()), temp.data());
        Check(length != 0 && length < temp.size(), "GetTempPathW failed");
        root = std::wstring(temp.data()) + L"SalWidePathTests-" +
               std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
        CreateDirectoryAt(root);
        directories.push_back(root);
    }

    void AddDirectory(const std::wstring& name)
    {
        CreateDirectoryAt(name);
        directories.push_back(name);
    }

    void AddFile(const std::wstring& name, const char* data)
    {
        WriteFileAt(name, data);
        files.push_back(name);
    }

    ~Sandbox()
    {
        for (const auto& file : files)
            DeleteFileW(Extended(file).c_str());
        for (auto it = directories.rbegin(); it != directories.rend(); ++it)
            RemoveDirectoryW(Extended(*it).c_str());
    }
};

void TestLongUnicodeFileOperations()
{
    // Arrange: create a path longer than MAX_PATH with non-ASCII directories.
    Sandbox sandbox;
    std::wstring directory = sandbox.root;
    for (int i = 0; i < 5; ++i)
    {
        directory = Join(directory, L"\u65e5\u672c\u8a9e-" + std::wstring(51, L'x') + std::to_wstring(i));
        sandbox.AddDirectory(directory);
    }
    Check(directory.length() > MAX_PATH, "Test path did not exceed MAX_PATH");
    const auto source = Join(directory, L"\u00c4\u00d6\u00dc-\u65e5\u672c\u8a9e-\U0001f600.data");
    const auto moved = Join(directory, L"\u00c4\u00d6\u00dc-\u65e5\u672c\u8a9e-\U0001f600-moved.data");
    const auto other = Join(directory, L"other.txt");
    sandbox.AddFile(source, "important data");
    sandbox.AddFile(other, "unrelated");

    // Act: exercise the same extended-length UTF-16 backend used by Salamander.
    Check(SalWidePaths::GetFileAttributesFromWide(source.c_str()) != INVALID_FILE_ATTRIBUTES,
          "GetFileAttributesFromWide failed for long Unicode path");
    Check(SalWidePaths::MoveFileFromWide(source.c_str(), moved.c_str()) != 0,
          "MoveFileFromWide failed for long Unicode path");
    Check(SalWidePaths::DeleteFileFromWide(moved.c_str()) != 0,
          "DeleteFileFromWide failed for long Unicode path");

    // Assert: content and unrelated files must be preserved.
    Check(!Exists(source) && !Exists(moved), "Moved/deleted file still exists");
    Check(ReadFileAt(other) == "unrelated", "Unrelated file content changed");
}

void TestLongDirectoryRenameAndDelete()
{
    // Arrange.
    Sandbox sandbox;
    std::wstring parent = sandbox.root;
    for (int i = 0; i < 5; ++i)
    {
        parent = Join(parent, L"long-segment-" + std::wstring(47, L'a') + std::to_wstring(i));
        sandbox.AddDirectory(parent);
    }
    const auto oldDirectory = Join(parent, L"\u65e5\u672c\u8a9e");
    const auto newDirectory = Join(parent, L"\u65e5\u672c\u8a9e-renamed");
    sandbox.AddDirectory(oldDirectory);

    // Act.
    Check(SalWidePaths::MoveFileFromWide(oldDirectory.c_str(), newDirectory.c_str()) != 0,
          "Directory rename failed");
    Check(SalWidePaths::RemoveDirectoryFromWide(newDirectory.c_str()) != 0,
          "Directory remove failed");

    // Assert.
    Check(!Exists(oldDirectory) && !Exists(newDirectory), "Directory still exists after removal");
}

void TestMoveDoesNotOverwriteAndDoesNotDeleteWrongFile()
{
    // Arrange: two existing files are never to be overwritten.
    Sandbox sandbox;
    const auto from = Join(sandbox.root, L"source.txt");
    const auto to = Join(sandbox.root, L"target.txt");
    sandbox.AddFile(from, "source");
    sandbox.AddFile(to, "target");

    // Act.
    const BOOL moveResult = SalWidePaths::MoveFileFromWide(from.c_str(), to.c_str());

    // Assert: MoveFileW has non-overwrite semantics.
    Check(moveResult == FALSE, "Move unexpectedly overwrote existing target");
    Check(ReadFileAt(from) == "source", "Source changed on failed move");
    Check(ReadFileAt(to) == "target", "Target overwritten on failed move");
}

void TestNativeNarrowPathsWhenRepresentable()
{
    // Arrange: the core still stores ANSI strings; only test names that the active
    // code page can encode without lossy fallback.
    Sandbox sandbox;
    const auto src = Join(sandbox.root, L"\u00c4\u00d6\u00dc-file.txt");
    const auto dest = Join(sandbox.root, L"\u00c4\u00d6\u00dc-renamed.txt");
    std::string sourceAnsi, destAnsi;
    if (!TryEncodeWithoutSubstitution(src, sourceAnsi) ||
        !TryEncodeWithoutSubstitution(dest, destAnsi))
    {
        std::cout << "SKIP: active code page cannot represent narrow test paths\n";
        return;
    }
    sandbox.AddFile(src, "data");

    // Act.
    Check(SalWidePaths::GetFileAttributesFromNarrow(sourceAnsi.c_str()) != INVALID_FILE_ATTRIBUTES,
          "ANSI adapter could not query Unicode path");
    Check(SalWidePaths::MoveFileFromNarrow(sourceAnsi.c_str(), destAnsi.c_str()) != 0,
          "ANSI adapter could not rename file");
    Check(SalWidePaths::DeleteFileFromNarrow(destAnsi.c_str()) != 0,
          "ANSI adapter could not delete file");

    // Assert.
    Check(!Exists(src) && !Exists(dest), "ANSI adapter left renamed file behind");
}

void TestTrailingDotNameCannotDeleteOtherFile()
{
    // Arrange: extended-length paths distinguish names with trailing dots.
    Sandbox sandbox;
    const auto normal = Join(sandbox.root, L"report.txt");
    const auto unusual = Join(sandbox.root, L"report.txt.");
    sandbox.AddFile(normal, "keep");
    sandbox.AddFile(unusual, "remove");

    // Act: the unusual name must not alias the normal file.
    Check(SalWidePaths::DeleteFileFromWide(unusual.c_str()) != 0,
          "Failed to delete the trailing-dot entry");

    // Assert: the different, normal file must survive unchanged.
    Check(ReadFileAt(normal) == "keep", "Deleting trailing-dot name touched a different file");
    Check(!Exists(unusual), "Trailing-dot entry still exists");
}

void TestInvalidInputDoesNotTouchFiles()
{
    // Arrange.
    Sandbox sandbox;
    const auto valuable = Join(sandbox.root, L"valuable.txt");
    sandbox.AddFile(valuable, "unchanged");
    std::wstring converted = L"untouched";

    // Act.
    const bool invalid = SalWidePaths::MakeExtendedPath(L"", converted);
    const BOOL invalidDelete = SalWidePaths::DeleteFileFromNarrow(nullptr);

    // Assert.
    Check(!invalid && invalidDelete == FALSE, "Invalid input unexpectedly accepted");
    Check(ReadFileAt(valuable) == "unchanged", "Invalid input modified unrelated file");
}

} // namespace

int main()
{
    try
    {
        TestLongUnicodeFileOperations();
        TestLongDirectoryRenameAndDelete();
        TestMoveDoesNotOverwriteAndDoesNotDeleteWrongFile();
        TestTrailingDotNameCannotDeleteOtherFile();
        TestNativeNarrowPathsWhenRepresentable();
        TestInvalidInputDoesNotTouchFiles();
        std::cout << "Win32FilesystemIntegrationTests: PASS\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "Win32FilesystemIntegrationTests: FAIL: " << error.what()
                  << " (GetLastError=" << GetLastError() << ")\n";
        return 1;
    }
}
