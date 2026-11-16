// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
// RED regression suite for the Unicode Find core (F2).
// Requires a Windows x64 build host; uses only private disposable fixtures.

#include "../../src/common/win32_unicode_find.h"

#include <windows.h>
#include <atomic>
#include <cstdio>
#include <string>
#include <vector>

static bool MakeDirectory(const std::wstring& fullPath)
{
    std::wstring extended;
    DWORD error = ERROR_SUCCESS;
    return Salamander::TryMakeExtendedLengthPath(fullPath.c_str(), extended, error) &&
           CreateDirectoryW(extended.c_str(), nullptr) != 0;
}

static bool WriteFixture(const std::wstring& fullPath, const void* bytes, DWORD length)
{
    std::wstring extended;
    DWORD error = ERROR_SUCCESS;
    if (!Salamander::TryMakeExtendedLengthPath(fullPath.c_str(), extended, error))
        return false;
    HANDLE file = CreateFileW(extended.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return false;
    DWORD written = 0;
    const bool ok = WriteFile(file, bytes, length, &written, nullptr) && written == length;
    CloseHandle(file);
    return ok;
}

static bool RemoveFixture(const std::wstring& fullPath, bool directory)
{
    std::wstring extended;
    DWORD error = ERROR_SUCCESS;
    return Salamander::TryMakeExtendedLengthPath(fullPath.c_str(), extended, error) &&
           (directory ? RemoveDirectoryW(extended.c_str()) : DeleteFileW(extended.c_str())) != 0;
}

int main()
{
    wchar_t temp[MAX_PATH] = {};
    const DWORD count = GetTempPathW(MAX_PATH, temp);
    if (count == 0 || count >= MAX_PATH)
        return std::puts("FAIL: temporary path"), 1;

    const std::wstring root = std::wstring(temp) + L"OpenSal-Find-" +
        std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
    const std::wstring long1 = root + L"\\" + std::wstring(105, L'a');
    const std::wstring long2 = long1 + L"\\" + std::wstring(105, L'b');
    const std::wstring long3 = long2 + L"\\" + std::wstring(105, L'c');
    const std::wstring nested = long3 + L"\\subfolder";
    if (!MakeDirectory(root) || !MakeDirectory(long1) ||
        !MakeDirectory(long2) || !MakeDirectory(long3) || !MakeDirectory(nested))
        return std::puts("FAIL: create long Find fixture"), 1;

    const std::wstring nameA = L"東京_😀.txt";
    const std::wstring nameB = L"大阪_😀.txt";
    const std::wstring nameC = std::wstring(251, L'z') + L".txt";
    const char utf8[] = "unique needle in UTF-8";
    const wchar_t utf16[] = L"unique needle in UTF-16";
    const std::wstring fileA = long3 + L"\\" + nameA;
    const std::wstring fileB = nested + L"\\" + nameB;
    const std::wstring fileC = long3 + L"\\" + nameC;
    if (!WriteFixture(fileA, utf8, sizeof(utf8) - 1) ||
        !WriteFixture(fileB, utf16, sizeof(utf16) - sizeof(wchar_t)) ||
        !WriteFixture(fileC, "other", 5))
        return std::puts("FAIL: write Unicode Find fixtures"), 1;

    // Arrange: source root is beyond MAX_PATH, with UTF-16 names that may
    // collapse to a single CP_ACP alias; no ANSI conversion is allowed.
    Salamander::UnicodeFindOptions options;
    options.root = long3;
    options.masks = L"*.txt";
    options.includeSubdirectories = true;
    std::vector<Salamander::UnicodeFindHit> hits;
    DWORD error = ERROR_SUCCESS;
    const auto collect = [&](const Salamander::UnicodeFindHit& hit) {
        hits.push_back(hit);
        return true;
    };

    // Act / Assert: preserve both exact original W identities and a 255-unit
    // component, including a nested directory under a long parent.
    if (!Salamander::SearchUnicodeDirectory(options, collect, nullptr, error) ||
        hits.size() != 3 || error != ERROR_SUCCESS)
        return std::puts("FAIL: full Unicode long-path search"), 1;
    bool foundA = false, foundB = false, foundC = false;
    for (const auto& hit : hits)
    {
        foundA |= hit.name == nameA && hit.directory == long3;
        foundB |= hit.name == nameB && hit.directory == nested;
        foundC |= hit.name == nameC && hit.name.size() == 255;
    }
    if (!foundA || !foundB || !foundC)
        return std::puts("FAIL: Unicode result identity or 255-unit name"), 1;

    // A single 32K parent may otherwise be duplicated into thousands of
    // result allocations. Refuse an undersized identity budget explicitly.
    options.maximumResultUtf16Units = 1;
    hits.clear();
    if (Salamander::SearchUnicodeDirectory(options, collect, nullptr, error) ||
        error != ERROR_MORE_DATA || !hits.empty())
        return std::puts("FAIL: W result memory cap"), 1;
    options.maximumResultUtf16Units = 8 * 1024 * 1024;

    options.includeSubdirectories = false;
    hits.clear();
    if (!Salamander::SearchUnicodeDirectory(options, collect, nullptr, error) ||
        hits.size() != 2)
        return std::puts("FAIL: non-recursive Unicode search"), 1;

    // Arrange / Act / Assert: masks are case-insensitive by default and
    // exclusion masks must not accidentally enumerate colliding aliases.
    options.masks = L"*.TXT|*😀*";
    hits.clear();
    if (!Salamander::SearchUnicodeDirectory(options, collect, nullptr, error) ||
        hits.size() != 1 || hits[0].name != nameC)
        return std::puts("FAIL: Unicode include/exclude masks"), 1;
    options.masks = L"*.txt";

    // Cross-buffer UTF-8/UTF-16 search: exercise both encodings independently.
    // Arrange: the first byte of a multibyte UTF-8 character is the final
    // byte of the first 64 KiB block; the rest arrives in the second block.
    const std::wstring boundaryName = L"boundary_東京.txt";
    const std::wstring boundaryFile = long3 + L"\\" + boundaryName;
    std::string boundaryPayload(65535, 'x');
    boundaryPayload += "\xE6\x9D\xB1\xE4\xBA\xAC"; // UTF-8 for 東京.
    if (!WriteFixture(boundaryFile, boundaryPayload.data(),
                      static_cast<DWORD>(boundaryPayload.size())))
        return std::puts("FAIL: prepare cross-buffer UTF-8 fixture"), 1;

    // Act / Assert: only the boundary file contains the requested Unicode text.
    options.content = L"東京";
    hits.clear();
    if (!Salamander::SearchUnicodeDirectory(options, collect, nullptr, error) ||
        error != ERROR_SUCCESS || hits.size() != 1 || hits[0].name != boundaryName)
        return std::puts("FAIL: cross-buffer UTF-8 multibyte search"), 1;

    // Arrange: a UTF-16LE needle starts two bytes before a block boundary.
    // On Windows wchar_t stores one UTF-16 code unit in two bytes.
    static_assert(sizeof(wchar_t) == 2, "UTF-16 fixture requires Win32 wchar_t");
    const std::wstring utf16BoundaryName = L"boundary_utf16_大阪.txt";
    const std::wstring utf16BoundaryFile = long3 + L"\\" + utf16BoundaryName;
    const wchar_t utf16BoundaryText[] = L"unique needle across chunks";
    const auto* utf16Bytes =
        reinterpret_cast<const unsigned char*>(utf16BoundaryText);
    std::vector<unsigned char> utf16BoundaryPayload(65534, 'x');
    utf16BoundaryPayload.insert(utf16BoundaryPayload.end(), utf16Bytes,
        utf16Bytes + sizeof(utf16BoundaryText) - sizeof(wchar_t));
    if (!WriteFixture(utf16BoundaryFile, utf16BoundaryPayload.data(),
                      static_cast<DWORD>(utf16BoundaryPayload.size())))
        return std::puts("FAIL: prepare cross-buffer UTF-16LE fixture"), 1;

    // Act / Assert: the existing UTF-8 file and the new UTF-16LE file match.
    // The original UTF-16 file is nested and recursion remains disabled.
    options.content = L"unique needle";
    hits.clear();
    if (!Salamander::SearchUnicodeDirectory(options, collect, nullptr, error) ||
        error != ERROR_SUCCESS || hits.size() != 2)
        return std::puts("FAIL: cross-buffer UTF-16LE result count"), 1;
    bool foundOriginal = false, foundUtf16Boundary = false;
    for (const auto& hit : hits)
    {
        foundOriginal |= hit.name == nameA;
        foundUtf16Boundary |= hit.name == utf16BoundaryName;
    }
    if (!foundOriginal || !foundUtf16Boundary)
        return std::puts("FAIL: cross-buffer UTF-16LE result identity"), 1;
    if (!RemoveFixture(boundaryFile, false) ||
        !RemoveFixture(utf16BoundaryFile, false))
        return std::puts("FAIL: cleanup cross-buffer fixtures"), 1;

    options.includeSubdirectories = true;
    options.content = L"unique needle";
    hits.clear();
    if (!Salamander::SearchUnicodeDirectory(options, collect, nullptr, error) ||
        hits.size() != 2 || (hits[0].name != nameA && hits[1].name != nameA) ||
        (hits[0].name != nameB && hits[1].name != nameB))
        return std::puts("FAIL: streamed UTF-8/UTF-16 search"), 1;

    // A cancelled walk must not proceed into any directory or mutate files.
    std::atomic<bool> cancelled{true};
    hits.clear();
    if (Salamander::SearchUnicodeDirectory(options, collect, &cancelled, error) ||
        error != ERROR_CANCELLED || !hits.empty())
        return std::puts("FAIL: cancellation"), 1;

    options.root = L"relative\\unexpected";
    cancelled.store(false);
    hits.clear();
    if (Salamander::SearchUnicodeDirectory(options, collect, &cancelled, error) ||
        error == ERROR_SUCCESS || !hits.empty())
        return std::puts("FAIL: relative path must be rejected"), 1;

    if (!RemoveFixture(fileA, false) || !RemoveFixture(fileB, false) ||
        !RemoveFixture(fileC, false) ||
        !RemoveFixture(nested, true) || !RemoveFixture(long3, true) ||
        !RemoveFixture(long2, true) || !RemoveFixture(long1, true) ||
        !RemoveFixture(root, true))
        return std::puts("FAIL: fixture cleanup"), 1;
    return std::puts("PASS: Unicode Find long-path, UTF-8/UTF-16 content, identities, recursion, cancellation"), 0;
}
