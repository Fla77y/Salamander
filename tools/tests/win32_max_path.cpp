// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Standalone Windows regression for real filesystem paths near the Win32
// extended-length namespace limit. Not a Salamander GUI or plugin test.
#include "../../src/common/win32_long_path.h"
#include "../../src/common/win32_long_directory.h"
#include "../../src/common/win32_unicode_file_ops.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace
{
int Fail(const char* reason)
{
    const DWORD error = GetLastError();
    std::fprintf(stderr, "FAIL: %s (GetLastError=%lu)\n", reason, error);
    return 1;
}

bool Extended(const std::wstring& path, std::wstring& extended)
{
    DWORD error = ERROR_SUCCESS;
    return Salamander::TryMakeExtendedLengthPath(path.c_str(), extended, error) &&
           error == ERROR_SUCCESS;
}

bool Owned(const std::wstring& path, Salamander::Utf16DiskPath& owned)
{
    static_assert(sizeof(wchar_t) == sizeof(char16_t), "Win32 UTF-16 required");
    const std::u16string utf16(path.begin(), path.end());
    Salamander::Utf16PathError error = Salamander::Utf16PathError::InvalidInput;
    return Salamander::Utf16DiskPath::TryCreateAbsolute(utf16, owned, error) &&
           error == Salamander::Utf16PathError::None;
}

struct DisposableFixture
{
    std::vector<std::wstring> directories;
    std::vector<std::wstring> files;

    // Work backwards using extended paths: neither MAX_PATH nor recursive
    // shell deletion can safely clean up this deliberately very deep tree.
    bool Cleanup() noexcept
    {
        bool success = true;
        for (auto it = files.rbegin(); it != files.rend(); ++it)
        {
            if (GetFileAttributesW(it->c_str()) != INVALID_FILE_ATTRIBUTES &&
                !DeleteFileW(it->c_str()))
                success = false;
        }
        files.clear();

        for (auto it = directories.rbegin(); it != directories.rend(); ++it)
        {
            if (!RemoveDirectoryW(it->c_str()))
                success = false;
        }
        directories.clear();
        if (!success)
            std::fputs("FAIL: maximum-path test fixture cleanup was incomplete\n", stderr);
        return success;
    }

    ~DisposableFixture() { Cleanup(); }
};
} // namespace

int main()
{
    // Arrange: Microsoft documents 32,767 as an approximate namespace bound.
    // 32,700 UTF-16 units is close to that limit while reserving room for
    // prefix expansion, the NUL terminator and directory search wildcards.
    constexpr std::size_t targetLength = 32700;
    constexpr std::size_t componentLength = 200;
    const std::wstring filename = L"Größe_東京_😀.bin";

    WCHAR tempDirectory[MAX_PATH] = {};
    const DWORD tempLength = GetTempPathW(MAX_PATH, tempDirectory);
    if (tempLength == 0 || tempLength >= MAX_PATH)
        return Fail("GetTempPathW for near-limit fixture");

    DisposableFixture fixture;
    std::wstring current(tempDirectory);
    current += L"OpenSal-MaxPath-" + std::to_wstring(GetCurrentProcessId()) +
               L"-" + std::to_wstring(GetTickCount64());
    if (!CreateDirectoryW(current.c_str(), nullptr))
        return Fail("create near-limit fixture root");

    std::wstring extended;
    if (!Extended(current, extended))
        return Fail("prefix fixture root");
    fixture.directories.push_back(extended);

    if (current.size() + 1 + filename.size() >= targetLength)
        return Fail("temporary fixture root is too long");

    const std::size_t parentLength = targetLength - filename.size() - 1;
    while (current.size() < parentLength)
    {
        const std::size_t remaining = parentLength - current.size();
        if (remaining < 2)
            return Fail("near-limit component construction");
        // Do not leave a single trailing separator. Every component is
        // individually valid and below the filesystem's usual 255-unit limit.
        const std::size_t length = remaining <= componentLength + 2
                                       ? remaining - 1 : componentLength;
        const std::wstring component(length, L'x');
        current.push_back(L'\\');
        current += component;
        if (!Extended(current, extended) ||
            !CreateDirectoryW(extended.c_str(), nullptr))
            return Fail("create near-limit directory component");
        fixture.directories.push_back(extended);
    }

    // Act: exercise Salamander's actual owned UTF-16 paths, W-backed
    // enumeration, and production copy/move/delete adapters at this length.
    const std::wstring longFile = current + L"\\" + filename;
    if (longFile.size() != targetLength)
        return Fail("near-limit absolute path is not 32700 UTF-16 units");
    std::wstring longExtended;
    Salamander::Utf16DiskPath longOwned;
    if (!Extended(longFile, longExtended) || !Owned(longFile, longOwned))
        return Fail("convert and own near-limit Unicode path");

    HANDLE file = CreateFileW(longExtended.c_str(), GENERIC_WRITE, 0,
                              nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return Fail("CreateFileW with 32700-unit path");
    fixture.files.push_back(longExtended);

    const char payload[] = "32700-unit path preserves Unicode identity and bytes";
    DWORD transferred = 0;
    const bool written = WriteFile(file, payload, sizeof(payload), &transferred, nullptr) &&
                         transferred == sizeof(payload);
    CloseHandle(file);
    if (!written)
        return Fail("write bytes at near-maximum path length");

    file = CreateFileW(longExtended.c_str(), GENERIC_READ, FILE_SHARE_READ,
                       nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return Fail("reopen 32700-unit path");
    char readback[sizeof(payload)] = {};
    transferred = 0;
    const bool bytesIntact =
        ReadFile(file, readback, sizeof(readback), &transferred, nullptr) &&
        transferred == sizeof(payload) &&
        std::memcmp(readback, payload, sizeof(payload)) == 0;
    CloseHandle(file);
    if (!bytesIntact)
        return Fail("read byte-identical payload from 32700-unit path");

    std::vector<Salamander::LongDirectoryEntry> entries;
    DWORD error = ERROR_SUCCESS;
    if (!Salamander::TryEnumerateLongDirectory(current.c_str(), entries, error) ||
        error != ERROR_SUCCESS ||
        entries.size() != 1 || entries[0].name != filename)
        return Fail("W-backed enumeration preserves near-limit Unicode filename");

    const std::wstring shortCopy = std::wstring(tempDirectory) +
                                   L"OpenSal-max-copy-" +
                                   std::to_wstring(GetCurrentProcessId()) + L".bin";
    const std::wstring shortMoved = std::wstring(tempDirectory) +
                                    L"OpenSal-max-moved-" +
                                    std::to_wstring(GetCurrentProcessId()) + L".bin";
    std::wstring copyExtended, movedExtended;
    Salamander::Utf16DiskPath copyOwned, movedOwned;
    if (!Extended(shortCopy, copyExtended) ||
        !Extended(shortMoved, movedExtended) ||
        !Owned(shortCopy, copyOwned) || !Owned(shortMoved, movedOwned))
        return Fail("prepare short copy and move targets");

    if (!Salamander::TryCopyUnicodeFileNoOverwrite(longOwned, copyOwned, error))
        return Fail("copy near-limit Unicode file to short path");
    fixture.files.push_back(copyExtended);

    if (!Salamander::TryMoveUnicodeFileNoOverwrite(longOwned, movedOwned, error))
        return Fail("move near-limit Unicode file to short path");
    fixture.files.push_back(movedExtended);

    // Assert: actual file bytes and identities survive the transfers.
    if (GetFileAttributesW(longExtended.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(copyExtended.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("copy and move preserve independent source identities");

    if (!Salamander::TryCopyUnicodeFileNoOverwrite(movedOwned, longOwned, error))
        return Fail("copy short Unicode file back to near-maximum path");
    file = CreateFileW(longExtended.c_str(), GENERIC_READ, FILE_SHARE_READ,
                       nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return Fail("reopen restored near-limit Unicode file");
    char restored[sizeof(payload)] = {};
    transferred = 0;
    const bool restoredOk =
        ReadFile(file, restored, sizeof(restored), &transferred, nullptr) &&
        transferred == sizeof(payload) &&
        std::memcmp(restored, payload, sizeof(payload)) == 0;
    CloseHandle(file);
    if (!restoredOk)
        return Fail("restored near-limit Unicode file retained all bytes");

    if (Salamander::TryCopyUnicodeFileNoOverwrite(longOwned, copyOwned, error))
        return Fail("near-limit file copy must not overwrite existing target");
    if (!Salamander::TryDeleteUnicodeFile(longOwned, error) ||
        GetFileAttributesW(longExtended.c_str()) != INVALID_FILE_ATTRIBUTES)
        return Fail("delete exact near-limit Unicode file");

    if (!fixture.Cleanup())
        return Fail("cleanup near-limit Win32 path fixture");

    std::puts("PASS: actual 32700-unit Win32 Unicode path, enumeration, byte integrity, copy, move, collision refusal and delete");
    return 0;
}
