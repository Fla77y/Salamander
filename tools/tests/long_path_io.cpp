// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Standalone MSVC/Win32 regression test: does NOT require the Salamander UI.
#include "../../src/common/win32_long_path.h"

#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

namespace
{
int Fail(const char* message)
{
    std::fprintf(stderr, "FAIL: %s (GetLastError=%lu)\n", message, GetLastError());
    return 1;
}

bool Convert(const std::wstring& input, std::wstring& output)
{
    DWORD error = ERROR_SUCCESS;
    return Salamander::TryMakeExtendedLengthPath(input.c_str(), output, error) && error == ERROR_SUCCESS;
}

bool Reject(const std::wstring& input, DWORD expectedError)
{
    std::wstring result = L"must be cleared";
    DWORD error = ERROR_SUCCESS;
    return !Salamander::TryMakeExtendedLengthPath(input.c_str(), result, error) &&
           error == expectedError && result.empty();
}
} // namespace

int main()
{
    // Arrange / Act / Assert: syntactic transformation and invalid paths.
    std::wstring result;
    if (!Convert(L"C:\\folder\\name.txt", result) || result != L"\\\\?\\C:\\folder\\name.txt")
        return Fail("drive path prefix");
    if (!Convert(L"\\\\server\\share\\folder\\name.txt", result) ||
        result != L"\\\\?\\UNC\\server\\share\\folder\\name.txt")
        return Fail("UNC path prefix");
    if (!Convert(L"C:\\Unicode\\Größe_東京_😀.txt", result) ||
        result != L"\\\\?\\C:\\Unicode\\Größe_東京_😀.txt")
        return Fail("Unicode path fidelity");
    if (!Reject(L"relative\\file.txt", ERROR_INVALID_NAME) ||
        !Reject(L"C:relative.txt", ERROR_INVALID_NAME) ||
        !Reject(L"\\\\server", ERROR_INVALID_NAME) ||
        !Reject(L"\\\\?\\C:\\raw", ERROR_INVALID_NAME) ||
        !Reject(L"\\\\.\\PhysicalDrive0", ERROR_INVALID_NAME) ||
        !Reject(L"C:\\folder\\..\\file.txt", ERROR_INVALID_NAME) ||
        !Reject(L"C:\\folder\\.\\file.txt", ERROR_INVALID_NAME) ||
        !Reject(L"C:\\folder/file.txt", ERROR_INVALID_NAME))
        return Fail("invalid paths must be rejected");

    DWORD error = ERROR_SUCCESS;
    result = L"must be cleared";
    if (Salamander::TryMakeExtendedLengthPath(nullptr, result, error) ||
        error != ERROR_INVALID_PARAMETER || !result.empty())
        return Fail("null path must be rejected");

    std::wstring tooLong = L"C:\\";
    tooLong.append(32767, L'x');
    if (!Reject(tooLong, ERROR_FILENAME_EXCED_RANGE))
        return Fail("excessively long absolute paths must be rejected");

    // Arrange: short temporary root, Unicode and long path components.
    WCHAR tempDir[MAX_PATH];
    DWORD tempLen = GetTempPathW(MAX_PATH, tempDir);
    if (tempLen == 0 || tempLen >= MAX_PATH)
        return Fail("GetTempPathW");
    std::wstring root = std::wstring(tempDir) + L"OpenSal-LongIo-" +
                        std::to_wstring(GetCurrentProcessId()) + L"-" +
                        std::to_wstring(GetTickCount64());
    if (!CreateDirectoryW(root.c_str(), nullptr))
        return Fail("create test root");

    std::vector<std::wstring> directories;
    directories.push_back(root);
    std::wstring current = root;
    for (int i = 0; i != 5; ++i)
    {
        current += L"\\directory-" + std::to_wstring(i) + L"-" + std::wstring(60, L'x');
        if (!Convert(current, result) || !CreateDirectoryW(result.c_str(), nullptr))
            return Fail("create long Unicode-ready directory");
        directories.push_back(current);
    }

    // Act: create, write, read, enumerate, delete using explicit W APIs and
    // an extended-length path without changing Windows registry policy.
    std::wstring filename = current + L"\\Größe_東京_😀.txt";
    if (filename.size() <= MAX_PATH)
        return Fail("long path fixture was not long enough");
    if (!Convert(filename, result))
        return Fail("prepare long Unicode file path");
    HANDLE file = CreateFileW(result.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return Fail("CreateFileW");
    const char payload[] = "long-path-test";
    DWORD written = 0;
    bool wrote = WriteFile(file, payload, sizeof(payload), &written, nullptr) &&
                 written == sizeof(payload);
    CloseHandle(file);
    if (!wrote)
        return Fail("WriteFile");

    file = CreateFileW(result.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return Fail("reopen long file with CreateFileW");
    char actual[sizeof(payload)] = {};
    DWORD read = 0;
    bool readOk = ReadFile(file, actual, sizeof(actual), &read, nullptr) &&
                  read == sizeof(payload) && std::string(actual, read) == std::string(payload, sizeof(payload));
    CloseHandle(file);
    if (!readOk)
        return Fail("ReadFile payload");

    WIN32_FIND_DATAW findData;
    HANDLE found = FindFirstFileW(result.c_str(), &findData);
    if (found == INVALID_HANDLE_VALUE)
        return Fail("FindFirstFileW");
    bool nameOk = std::wstring(findData.cFileName) == L"Größe_東京_😀.txt";
    FindClose(found);
    if (!nameOk)
        return Fail("Unicode filename preserved during enumeration");

    if (!DeleteFileW(result.c_str()))
        return Fail("DeleteFileW");
    for (auto i = directories.rbegin(); i != directories.rend(); ++i)
    {
        if (!Convert(*i, result) || !RemoveDirectoryW(result.c_str()))
            return Fail("RemoveDirectoryW recursive cleanup");
    }
    std::puts("PASS: long Unicode paths and UNC prefix mapping, Win32 I/O and boundaries");
    return 0;
}
