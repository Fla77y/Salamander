// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Standalone MSVC/Win32 regression test: does NOT require the Salamander UI.
#include "../../src/common/win32_long_path.h"
#include "../../src/common/win32_long_directory.h"
#include "../../src/common/win32_unicode_file_ops.h"
#include "../../src/common/win32_unicode_panel_name.h"

#include <windows.h>

#include <cstdio>
#include <cstring>
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

bool OwnPath(const std::wstring& input, Salamander::Utf16DiskPath& output)
{
    // Win32 wchar_t is 16 bits; this preserves even supplementary characters
    // as their original surrogate pair, not via the system ANSI code page.
    static_assert(sizeof(wchar_t) == sizeof(char16_t), "Win32 UTF-16 required");
    const std::u16string utf16(input.begin(), input.end());
    Salamander::Utf16PathError error = Salamander::Utf16PathError::InvalidInput;
    return Salamander::Utf16DiskPath::TryCreateAbsolute(utf16, output, error) &&
           error == Salamander::Utf16PathError::None;
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

    // The legacy ANSI facade must preserve long ASCII paths without
    // truncating, and must reject relative paths and null pointers.
    std::string longAnsiPath = "C:\\";
    longAnsiPath.append(300, 'a');
    DWORD ansiError = ERROR_SUCCESS;
    if (!Salamander::TryMakeExtendedLengthPathFromAnsi(longAnsiPath.c_str(), result, ansiError) ||
        ansiError != ERROR_SUCCESS ||
        result != L"\\\\?\\C:\\" + std::wstring(300, L'a'))
        return Fail("legacy ANSI-to-wide long path conversion");
    if (Salamander::TryMakeExtendedLengthPathFromAnsi("relative\\name.txt", result, ansiError) ||
        ansiError != ERROR_INVALID_NAME || !result.empty())
        return Fail("legacy ANSI adapter must reject relative path");
    if (Salamander::TryMakeExtendedLengthPathFromAnsi(nullptr, result, ansiError) ||
        ansiError != ERROR_INVALID_PARAMETER || !result.empty())
        return Fail("legacy ANSI adapter must reject null path");

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

    // Two distinct filesystem names may collapse to the same CP_ACP alias.
    // A future panel representation must not conflate their identities.
    const std::wstring distinctName = current + L"\\Größe_大阪_😀.txt";
    std::wstring extendedDistinct;
    if (!Convert(distinctName, extendedDistinct))
        return Fail("prepare collision-resistant Unicode name");
    HANDLE distinctFile = CreateFileW(extendedDistinct.c_str(), GENERIC_WRITE, 0,
                                      nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (distinctFile == INVALID_HANDLE_VALUE)
        return Fail("create second distinct Unicode name");
    const char distinctPayload[] = "other-identity";
    DWORD distinctWritten = 0;
    const bool distinctWriteOk = WriteFile(distinctFile, distinctPayload,
                                           sizeof(distinctPayload), &distinctWritten, nullptr) &&
                                 distinctWritten == sizeof(distinctPayload);
    CloseHandle(distinctFile);
    if (!distinctWriteOk)
        return Fail("write second distinct Unicode name");

    // Maximum-length single filename (255 UTF-16 code units) beneath a
    // long path. This must remain distinct from the total path limit.
    const std::wstring maxName = L"東京" + std::wstring(249, L'a') + L".txt";
    if (maxName.size() != 255)
        return Fail("test filename length");
    const std::wstring maxFilename = current + L"\\" + maxName;
    std::wstring extendedMaxFile;
    if (!Convert(maxFilename, extendedMaxFile))
        return Fail("prepare max-length Unicode filename");
    HANDLE maxFile = CreateFileW(extendedMaxFile.c_str(), GENERIC_WRITE, 0, nullptr,
                                 CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (maxFile == INVALID_HANDLE_VALUE)
        return Fail("create 255-unit Unicode filename on long path");
    CloseHandle(maxFile);

    // Arrange: the disk panel uses an ACP search-pattern adapter. Its
    // current input can be represented in ACP, but exceeds MAX_PATH.
    // Act: enumerate it through the real panel FindFirst adapter.
    std::string longPanelPattern;
    const std::wstring longWidePattern = current + L"\\*";
    const int patternBytes = WideCharToMultiByte(
        CP_ACP, WC_NO_BEST_FIT_CHARS, longWidePattern.c_str(), -1,
        nullptr, 0, nullptr, nullptr);
    if (patternBytes <= 0)
        return Fail("encode long panel search pattern");
    longPanelPattern.resize(static_cast<std::size_t>(patternBytes), '\0');
    BOOL usedDefault = FALSE;
    if (WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS,
                            longWidePattern.c_str(), -1,
                            &longPanelPattern[0], patternBytes,
                            nullptr, &usedDefault) != patternBytes || usedDefault)
        return Fail("long panel search pattern must not narrow lossy Unicode");
    longPanelPattern.pop_back();
    if (longPanelPattern.size() <= MAX_PATH)
        return Fail("panel search pattern must exceed MAX_PATH");
    WIN32_FIND_DATAA panelAnsiData = {};
    WIN32_FIND_DATAW panelWideData = {};
    HANDLE panelFind = Salamander::FindFirstUnicodePanelFile(
        longPanelPattern.c_str(), panelAnsiData, panelWideData);
    // Assert: the adapter must use a W extended-length search internally.
    if (panelFind == INVALID_HANDLE_VALUE)
        return Fail("W-backed panel enumeration of a long directory");
    const bool panelNamePreserved =
        std::wstring(panelWideData.cFileName) == L"Größe_東京_😀.txt";
    FindClose(panelFind);
    if (!panelNamePreserved)
        return Fail("W-backed panel long directory preserves Unicode row identity");

    // Directory enumeration must preserve the exact UTF-16 filename. This
    // is needed before replacing Salamander's ANSI CFileData.Name flow.
    std::vector<Salamander::LongDirectoryEntry> entries;
    DWORD enumError = ERROR_SUCCESS;
    if (!Salamander::TryEnumerateLongDirectory(current.c_str(), entries, enumError) ||
        enumError != ERROR_SUCCESS || entries.size() != 3)
        return Fail("Unicode long directory enumeration");
    bool foundUnicode = false;
    bool foundDistinctUnicode = false;
    bool foundMaxName = false;
    for (const auto& entry : entries)
    {
        if ((entry.attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
            return Fail("unexpected directory in fixture");
        foundUnicode |= entry.name == L"Größe_東京_😀.txt";
        foundDistinctUnicode |= entry.name == L"Größe_大阪_😀.txt";
        foundMaxName |= entry.name == maxName;
    }
    if (!foundUnicode || !foundDistinctUnicode || !foundMaxName)
        return Fail("directory enumeration must preserve distinct UTF-16 identities");

    // Arrange: the legacy panel stores CP_ACP bytes, which may conflate
    // multiple distinct Unicode names. Derive the actual Windows alias.
    const auto ansiAlias = [](const wchar_t* input) -> std::string {
        const int count = WideCharToMultiByte(CP_ACP, 0, input, -1,
                                               nullptr, 0, nullptr, nullptr);
        if (count == 0)
            return {};
        std::string bytes(static_cast<std::size_t>(count), '\0');
        if (WideCharToMultiByte(CP_ACP, 0, input, -1, &bytes[0], count,
                                nullptr, nullptr) != count)
            return {};
        bytes.pop_back();
        return bytes;
    };
    const std::string tokyoAlias = ansiAlias(L"Größe_東京_😀.txt");
    const std::string osakaAlias = ansiAlias(L"Größe_大阪_😀.txt");
    if (tokyoAlias.empty() || osakaAlias.empty())
        return Fail("derive legacy aliases for Unicode panel names");

    // Act: resolve a currently focused legacy name through original
    // FindFirstFileW entries rather than returning the lossy ANSI bytes.
    std::wstring resolvedName;
    DWORD resolveError = ERROR_SUCCESS;
    const auto resolved = Salamander::ResolveUnicodePanelFileName(
        current.c_str(), tokyoAlias.c_str(), resolvedName, resolveError);
    // Assert: only a unique name is safe. On CP_ACP alias collisions
    // ambiguous input must fail closed rather than choosing a wrong file.
    if (tokyoAlias == osakaAlias)
    {
        if (resolved != Salamander::UnicodePanelNameResult::Ambiguous ||
            !resolvedName.empty())
            return Fail("reject Unicode filename identity collision");
    }
    else if (resolved != Salamander::UnicodePanelNameResult::Unique ||
             resolvedName != L"Größe_東京_😀.txt")
        return Fail("recover exact Unicode filename from unique ACP alias");

    // Arrange / Act / Assert: the panel must build its Unicode index once
    // per directory listing, not enumerate the directory for every paint.
    Salamander::UnicodePanelNameCache panelNames;
    if (!panelNames.Load(current.c_str(), resolveError))
        return Fail("build Unicode panel filename index");
    std::wstring cachedName = L"stale";
    const bool cacheFound = panelNames.TryGet(tokyoAlias.c_str(), cachedName);
    if (tokyoAlias == osakaAlias)
    {
        if (cacheFound || !cachedName.empty())
            return Fail("indexed Unicode aliases must remain ambiguous");
    }
    else if (!cacheFound || cachedName != L"Größe_東京_😀.txt")
        return Fail("indexed Unicode alias must resolve exact name");
    // The operation gate must refuse an ambiguous identity and ANY lossy
    // conversion, including best-fit mappings that contain no '?'.
    // Unicode round-trip equality is the required invariant.
    if (!Salamander::IsExactAnsiName("plain.txt", L"plain.txt") ||
        Salamander::IsExactAnsiName("plain.txt", L"other.txt") ||
        Salamander::IsExactAnsiName("Größe_??_??.txt", L"Größe_東京_😀.txt"))
        return Fail("exact ANSI round-trip detection independent of '?'");
    const bool unambiguous = tokyoAlias != osakaAlias;
    const bool tokyoIsLossless = Salamander::IsExactAnsiName(
        tokyoAlias.c_str(), L"Größe_東京_😀.txt");
    if (panelNames.IsUnsafeAnsiName(tokyoAlias.c_str()) !=
        (!unambiguous || !tokyoIsLossless) ||
        !panelNames.IsUnsafeAnsiName("not-in-the-directory.xyz"))
        return Fail("unknown, ambiguous and lossy identities must be unsafe");
    std::wstring restored = L"stale";
    if (panelNames.TryGetLossy(tokyoAlias.c_str(), restored) !=
            (unambiguous && !tokyoIsLossless) ||
        (unambiguous && !tokyoIsLossless &&
         restored != L"Größe_東京_😀.txt"))
        return Fail("only unique lossy names can be displayed in wide text");

    // Exercise an actual best-fit ACP alias with no '?' if the machine's
    // Windows codepage provides one. UTF-8 ACP configurations legitimately
    // have no such mapping and skip only this optional fixture.
    const wchar_t bestFitCandidates[] = {
        0xFF21, 0xFF41, 0x2010, 0x2011, 0x2013, 0x2014,
        0x2212, 0x2018, 0x2019, 0x2460, 0x2160
    };
    std::wstring bestFitName;
    std::string bestFitAlias;
    for (const wchar_t candidate : bestFitCandidates)
    {
        std::wstring candidateName = std::wstring(L"bestfit_") +
                                     candidate + L".txt";
        const std::string converted = ansiAlias(candidateName.c_str());
        if (!converted.empty() && converted.find('?') == std::string::npos &&
            !Salamander::IsExactAnsiName(converted.c_str(), candidateName.c_str()))
        {
            bestFitName = std::move(candidateName);
            bestFitAlias = converted;
            break;
        }
    }
    if (!bestFitName.empty())
    {
        const std::wstring bestFitFile = current + L"\\" + bestFitName;
        std::wstring bestFitExtended;
        if (!Convert(bestFitFile, bestFitExtended))
            return Fail("prepare best-fit filename fixture");
        HANDLE bestFitHandle = CreateFileW(bestFitExtended.c_str(), GENERIC_WRITE,
                                           0, nullptr, CREATE_NEW,
                                           FILE_ATTRIBUTE_NORMAL, nullptr);
        if (bestFitHandle == INVALID_HANDLE_VALUE)
            return Fail("create best-fit non-question-mark Unicode filename");
        CloseHandle(bestFitHandle);

        if (!panelNames.Load(current.c_str(), resolveError) ||
            !panelNames.IsUnsafeAnsiName(bestFitAlias.c_str()))
            return Fail("best-fit Unicode name must not reach the ANSI action engine");
        std::wstring restoredBestFit;
        if (!panelNames.TryGetLossy(bestFitAlias.c_str(), restoredBestFit) ||
            restoredBestFit != bestFitName)
            return Fail("best-fit Unicode filename must be recoverable for GUI display");
        if (!DeleteFileW(bestFitExtended.c_str()))
            return Fail("remove best-fit filename fixture");
    }
    else
        std::puts("SKIP: ACP has no candidate non-question-mark best-fit mapping");

    panelNames.Clear();
    cachedName = L"stale";
    if (panelNames.TryGet(tokyoAlias.c_str(), cachedName) || !cachedName.empty())
        return Fail("panel name index must invalidate on refresh");

    resolvedName = L"stale";
    if (Salamander::ResolveUnicodePanelFileName(
            current.c_str(), "not-in-the-directory.xyz",
            resolvedName, resolveError) != Salamander::UnicodePanelNameResult::NotFound ||
        !resolvedName.empty())
        return Fail("missing name must not return stale Unicode identity");

    // Arrange: typed path is the new non-ANSI integration boundary.
    Salamander::Utf16DiskPath unicodeDirectory;
    if (!OwnPath(current, unicodeDirectory))
        return Fail("arrange owned UTF-16 directory path");
    std::vector<Salamander::LongDirectoryEntry> typedEntries;
    // Act / Assert: enumerate the same names without converting via char*.
    if (!Salamander::TryEnumerateLongDirectory(unicodeDirectory, typedEntries, enumError) ||
        enumError != ERROR_SUCCESS || typedEntries.size() != entries.size())
        return Fail("typed directory enumeration");
    bool typedUnicodeName = false;
    for (const auto& entry : typedEntries)
        typedUnicodeName |= entry.name == L"Größe_東京_😀.txt";
    if (!typedUnicodeName)
        return Fail("typed enumeration retains exact supplementary UTF-16 name");
    bool typedDistinctName = false;
    for (const auto& entry : typedEntries)
        typedDistinctName |= entry.name == L"Größe_大阪_😀.txt";
    if (!typedDistinctName)
        return Fail("typed enumeration retains both distinct Unicode names");

    // Arrange / Act / Assert: default invalid path cannot reach Win32 API.
    Salamander::Utf16DiskPath missingDirectory;
    if (Salamander::TryEnumerateLongDirectory(missingDirectory, typedEntries, enumError) ||
        enumError != ERROR_INVALID_PARAMETER || !typedEntries.empty())
        return Fail("typed enumeration rejects uninitialized path");

    // Arrange: preserve the original Unicode filename and payload in the
    // source and keep all destinations inside the temporary fixture.
    Salamander::Utf16DiskPath unicodeSource;
    Salamander::Utf16DiskPath unicodeCopy;
    Salamander::Utf16DiskPath unicodeMoved;
    const std::wstring copyPath = current + L"\\copy_東京_😀.txt";
    const std::wstring movedPath = current + L"\\moved_東京_😀.txt";
    if (!OwnPath(filename, unicodeSource) ||
        !OwnPath(copyPath, unicodeCopy) ||
        !OwnPath(movedPath, unicodeMoved))
        return Fail("arrange lossless Unicode source and targets");

    // Act / Assert: copy must not change source bytes or overwrite a target.
    DWORD operationError = ERROR_SUCCESS;
    if (!Salamander::TryCopyUnicodeFileNoOverwrite(unicodeSource, unicodeCopy, operationError) ||
        operationError != ERROR_SUCCESS)
        return Fail("copy Unicode long filename");
    if (Salamander::TryCopyUnicodeFileNoOverwrite(unicodeSource, unicodeCopy, operationError) ||
        operationError != ERROR_FILE_EXISTS)
        return Fail("refuse to overwrite existing Unicode destination");
    std::wstring extendedCopy;
    std::wstring extendedMoved;
    if (!Convert(copyPath, extendedCopy) || !Convert(movedPath, extendedMoved))
        return Fail("prepare Unicode copy and move verification");
    HANDLE copiedFile = CreateFileW(extendedCopy.c_str(), GENERIC_READ, FILE_SHARE_READ,
                                    nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (copiedFile == INVALID_HANDLE_VALUE)
        return Fail("reopen Unicode copy");
    char copiedPayload[sizeof(payload)] = {};
    DWORD copiedBytes = 0;
    const bool copiedOk = ReadFile(copiedFile, copiedPayload, sizeof(copiedPayload),
                                   &copiedBytes, nullptr) &&
        copiedBytes == sizeof(payload) &&
        std::string(copiedPayload, copiedBytes) == std::string(payload, sizeof(payload));
    CloseHandle(copiedFile);
    if (!copiedOk)
        return Fail("Unicode copy retained exact bytes");

    // The F2 GUI rename uses the same no-overwrite W helper. A destination
    // with different contents must be preserved, as must the source.
    const std::wstring collisionPath = current + L"\\protected_rename_東京_😀.txt";
    std::wstring extendedCollision;
    Salamander::Utf16DiskPath protectedTarget;
    if (!Convert(collisionPath, extendedCollision) ||
        !OwnPath(collisionPath, protectedTarget))
        return Fail("prepare non-overwriting Unicode F2 rename target");
    HANDLE protectedFile = CreateFileW(
        extendedCollision.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (protectedFile == INVALID_HANDLE_VALUE)
        return Fail("create protected Unicode F2 destination");
    const char marker[] = "MUST-NOT-BE-OVERWRITTEN";
    DWORD markerWritten = 0;
    const bool markerOk = WriteFile(protectedFile, marker,
        static_cast<DWORD>(sizeof(marker)), &markerWritten, nullptr) &&
        markerWritten == sizeof(marker);
    CloseHandle(protectedFile);
    if (!markerOk)
        return Fail("write Unicode rename collision marker");
    if (Salamander::TryMoveUnicodeFileNoOverwrite(
            unicodeSource, protectedTarget, operationError) ||
        GetFileAttributesW(result.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("Unicode F2 rename must refuse an existing destination");
    HANDLE preserved = CreateFileW(extendedCollision.c_str(),
        GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (preserved == INVALID_HANDLE_VALUE)
        return Fail("reopen protected Unicode rename target");
    char checkMarker[sizeof(marker)] = {};
    DWORD markerRead = 0;
    const bool contentsSafe =
        ReadFile(preserved, checkMarker, sizeof(checkMarker), &markerRead, nullptr) &&
        markerRead == sizeof(marker) &&
        std::memcmp(checkMarker, marker, sizeof(marker)) == 0;
    CloseHandle(preserved);
    if (!contentsSafe || !DeleteFileW(extendedCollision.c_str()))
        return Fail("Unicode F2 collision preserves destination contents");

    // Act / Assert: move then delete only the disposable copy, not source.
    if (!Salamander::TryMoveUnicodeFileNoOverwrite(unicodeCopy, unicodeMoved, operationError) ||
        operationError != ERROR_SUCCESS ||
        GetFileAttributesW(extendedCopy.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(extendedMoved.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("move Unicode long filename without source duplication");
    if (!Salamander::TryDeleteUnicodeFile(unicodeMoved, operationError) ||
        operationError != ERROR_SUCCESS ||
        GetFileAttributesW(extendedMoved.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(result.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("delete only chosen Unicode file and retain original");

    std::vector<Salamander::LongDirectoryEntry> invalidEntries;
    if (Salamander::TryEnumerateLongDirectory(L"relative\\directory", invalidEntries, enumError) ||
        enumError != ERROR_INVALID_NAME || !invalidEntries.empty())
        return Fail("relative directory enumeration must be rejected");

    // Exercise the exact file-open helper used by SAFE_FILE, including the
    // second open that read/write error retries must perform.
    std::wstring legacyFilename = current + L"\\legacy-long-file.txt";
    std::wstring extendedLegacyFile;
    if (!Convert(legacyFilename, extendedLegacyFile))
        return Fail("prepare legacy-open filename");
    const int ansiLength = WideCharToMultiByte(CP_ACP, 0, legacyFilename.c_str(),
                                              -1, nullptr, 0, nullptr, nullptr);
    if (ansiLength < 2)
        return Fail("encode test path for legacy ANSI adapter");
    std::string legacyAnsi(static_cast<std::size_t>(ansiLength), '\0');
    if (WideCharToMultiByte(CP_ACP, 0, legacyFilename.c_str(), -1,
                            &legacyAnsi[0], ansiLength, nullptr, nullptr) != ansiLength)
        return Fail("encode legacy ANSI test path");
    legacyAnsi.pop_back();
    if (legacyAnsi.size() < MAX_PATH)
        return Fail("legacy opening fixture is not a long path");

    HANDLE legacyHandle = Salamander::OpenFileWithLegacyPath(
        legacyAnsi.c_str(), GENERIC_WRITE, FILE_SHARE_READ, CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL);
    if (legacyHandle == INVALID_HANDLE_VALUE)
        return Fail("legacy SAFE_FILE long path initial CreateFileW");
    DWORD legacyWritten = 0;
    const char legacyPayload[] = "retry-path";
    const bool legacyWriteOk = WriteFile(
        legacyHandle, legacyPayload, sizeof(legacyPayload), &legacyWritten, nullptr) &&
        legacyWritten == sizeof(legacyPayload);
    CloseHandle(legacyHandle);
    if (!legacyWriteOk)
        return Fail("write via long legacy path");

    // The retry path must not repeat CREATE_ALWAYS, or earlier bytes vanish.
    legacyHandle = Salamander::ReopenExistingFileWithLegacyPath(
        legacyAnsi.c_str(), GENERIC_READ, FILE_SHARE_READ, FILE_ATTRIBUTE_NORMAL);
    if (legacyHandle == INVALID_HANDLE_VALUE)
        return Fail("legacy SAFE_FILE long path reopen");
    char legacyRead[sizeof(legacyPayload)] = {};
    DWORD legacyBytesRead = 0;
    const bool legacyReadOk = ReadFile(
        legacyHandle, legacyRead, sizeof(legacyRead), &legacyBytesRead, nullptr) &&
        legacyBytesRead == sizeof(legacyPayload) &&
        std::string(legacyRead, legacyBytesRead) ==
            std::string(legacyPayload, sizeof(legacyPayload));
    CloseHandle(legacyHandle);
    if (!legacyReadOk)
        return Fail("read back through long legacy path");
    if (!DeleteFileW(extendedLegacyFile.c_str()))
        return Fail("delete legacy long-path fixture");
    legacyHandle = Salamander::ReopenExistingFileWithLegacyPath(
        legacyAnsi.c_str(), GENERIC_READ, FILE_SHARE_READ, FILE_ATTRIBUTE_NORMAL);
    if (legacyHandle != INVALID_HANDLE_VALUE)
    {
        CloseHandle(legacyHandle);
        return Fail("retry must not recreate a deleted file");
    }

    // Deleting the explicitly selected Unicode source must never delete
    // the second name whose ANSI replacement could look identical.
    HANDLE unaffectedFile = CreateFileW(extendedDistinct.c_str(), GENERIC_READ,
        FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (unaffectedFile == INVALID_HANDLE_VALUE)
        return Fail("distinct Unicode source survived copy/move/delete");
    char unaffectedData[sizeof(distinctPayload)] = {};
    DWORD unaffectedBytes = 0;
    const bool unaffectedOk = ReadFile(unaffectedFile, unaffectedData,
                                       sizeof(unaffectedData), &unaffectedBytes, nullptr) &&
                               unaffectedBytes == sizeof(distinctPayload) &&
                               std::string(unaffectedData, unaffectedBytes) ==
                                   std::string(distinctPayload, sizeof(distinctPayload));
    CloseHandle(unaffectedFile);
    if (!unaffectedOk)
        return Fail("distinct Unicode source retained bytes");

    if (!DeleteFileW(extendedDistinct.c_str()))
        return Fail("DeleteFileW distinct Unicode filename");
    if (!DeleteFileW(extendedMaxFile.c_str()))
        return Fail("DeleteFileW maximum filename");
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
