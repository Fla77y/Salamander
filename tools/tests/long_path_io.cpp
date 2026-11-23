// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Standalone MSVC/Win32 regression test: does NOT require the Salamander UI.
#include "../../src/common/win32_long_path.h"
#include "../../src/common/win32_long_directory.h"
#include "../../src/common/win32_unicode_file_ops.h"
#include "../../src/common/win32_unicode_clipboard_files.h"
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

// Observe which CopyFileExW callback handle refuses metadata queries. This
// diagnostic never cancels copying or changes the production copy callback.
struct CopyHandleProbe
{
    DWORD callbacks = 0;
    bool sourceFailed = false;
    bool destinationFailed = false;
    DWORD sourceError = ERROR_SUCCESS;
    DWORD destinationError = ERROR_SUCCESS;
    DWORD sourceStream = 0;
    DWORD destinationStream = 0;
};

DWORD CALLBACK ProbeCopyHandles(LARGE_INTEGER, LARGE_INTEGER, LARGE_INTEGER, LARGE_INTEGER,
                                DWORD stream, DWORD, HANDLE source, HANDLE destination, LPVOID context)
{
    auto& probe = *static_cast<CopyHandleProbe*>(context);
    ++probe.callbacks;
    BY_HANDLE_FILE_INFORMATION sourceInfo{}, destinationInfo{};
    if (!GetFileInformationByHandle(source, &sourceInfo) && !probe.sourceFailed)
    {
        probe.sourceFailed = true;
        probe.sourceError = GetLastError();
        probe.sourceStream = stream;
    }
    if (!GetFileInformationByHandle(destination, &destinationInfo) && !probe.destinationFailed)
    {
        probe.destinationFailed = true;
        probe.destinationError = GetLastError();
        probe.destinationStream = stream;
    }
    return PROGRESS_CONTINUE;
}
} // namespace

int main()
{
    std::string legacyProjection;
    const std::wstring unicodeNavigation = L"C:\\folder_\u6771\u4EAC_\U0001F600";
    const bool exactNavigation = Salamander::TryMakeExactAnsiPanelPath(unicodeNavigation, legacyProjection);
    if (GetACP() == CP_UTF8 ? (!exactNavigation ||
                             !Salamander::IsExactAnsiName(legacyProjection.c_str(), unicodeNavigation.c_str()))
                           : (exactNavigation || !legacyProjection.empty()))
        return Fail("panel navigation permits only an exact Windows code page projection");

    // Arrange: the caller may request in-place path expansion.
    std::wstring aliasedPath = L"C:\\東京\\😀.txt";
    DWORD aliasError = ERROR_SUCCESS;
    // Act / Assert: retaining the input precedes clearing the destination.
    if (!Salamander::TryMakeExtendedLengthPath(aliasedPath.c_str(), aliasedPath, aliasError) ||
        aliasError != ERROR_SUCCESS || aliasedPath != L"\\\\?\\C:\\東京\\😀.txt")
        return Fail("in-place extended Unicode path expansion must retain its input");

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

    // Arrange / Act / Assert: exact namespace boundaries for the real Win32
    // conversion helper. These checks are purely syntactic; Windows' actual
    // achievable on-disk path limit can be lower than the namespace limit.
    const auto makeBoundaryPath = [](std::wstring path, std::size_t length) {
        while (path.size() < length)
        {
            if (path.back() != L'\\')
                path.push_back(L'\\');
            const std::size_t remaining = length - path.size();
            path.append(remaining > 200 ? 200 : remaining, L'x');
        }
        return path;
    };
    const auto maxDrive = makeBoundaryPath(L"C:\\", 32762);
    const auto maxUnc = makeBoundaryPath(L"\\\\server\\share", 32760);
    const auto invalidDrive = makeBoundaryPath(L"C:\\", 32763);
    const auto invalidUnc = makeBoundaryPath(L"\\\\server\\share", 32761);
    if (!Convert(maxDrive, result) || result.size() != 32766 ||
        !Convert(maxUnc, result) || result.size() != 32766 ||
        !Reject(invalidDrive, ERROR_FILENAME_EXCED_RANGE) ||
        !Reject(invalidUnc, ERROR_FILENAME_EXCED_RANGE))
        return Fail("Win32 32767-unit drive and UNC namespace boundary");

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

    const auto nativeDirectory = current + L"\\\u6771\u4EAC_\U0001F600";
    const auto nativeFile = nativeDirectory + L"\\\u0141\U0001F642.txt";
    std::wstring nativeDirectoryExtended, nativeFileExtended;
    if (!Convert(nativeDirectory, nativeDirectoryExtended) ||
        !Convert(nativeFile, nativeFileExtended) ||
        !CreateDirectoryW(nativeDirectoryExtended.c_str(), nullptr))
        return Fail("create the native Unicode panel directory");
    std::wstring watchPath;
    if (!Salamander::TryMakeUnicodeDirectoryWatchPath(nativeDirectory, watchPath, error) ||
        watchPath != nativeDirectoryExtended)
        return Fail("prepare the complete Unicode notification path");
    HANDLE watcher = FindFirstChangeNotificationW(watchPath.c_str(), FALSE, FILE_NOTIFY_CHANGE_FILE_NAME);
    if (watcher == INVALID_HANDLE_VALUE)
        return Fail("monitor the native Unicode panel directory past MAX_PATH");
    HANDLE nativeFixture = CreateFileW(nativeFileExtended.c_str(), GENERIC_WRITE, 0,
                                       nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (nativeFixture == INVALID_HANDLE_VALUE)
        return Fail("create the native Unicode panel file");
    CloseHandle(nativeFixture);
    const DWORD watched = WaitForSingleObject(watcher, 5000);
    FindCloseChangeNotification(watcher);
    if (watched != WAIT_OBJECT_0)
        return Fail("long-path directory monitoring reports a change");
    WIN32_FIND_DATAA legacyRow{};
    WIN32_FIND_DATAW nativeRow{};
    HANDLE listing = Salamander::FindFirstUnicodePanelFile(nativeDirectory + L"\\", legacyRow, nativeRow);
    if (listing == INVALID_HANDLE_VALUE)
        return Fail("list the native Unicode panel directory past MAX_PATH");
    bool foundNativeName = false;
    do
    {
        if (wcscmp(nativeRow.cFileName, L"\u0141\U0001F642.txt") == 0)
            foundNativeName = true;
    } while (Salamander::FindNextUnicodePanelFile(listing, legacyRow, nativeRow));
    FindClose(listing);
    if (!foundNativeName || !DeleteFileW(nativeFileExtended.c_str()) ||
        !RemoveDirectoryW(nativeDirectoryExtended.c_str()))
        return Fail("native panel listing preserves Unicode in both directory and file name");

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
    DWORD filesystemFlags = 0;
    const bool hasNamedStreams = GetVolumeInformationByHandleW(distinctFile, nullptr, 0, nullptr,
        nullptr, &filesystemFlags, nullptr, 0) && (filesystemFlags & FILE_NAMED_STREAMS);
    CloseHandle(distinctFile);
    if (!distinctWriteOk)
        return Fail("write second distinct Unicode name");

    const wchar_t streamSuffix[] = L":opensal-clipboard";
    const char streamPayload[] = "clipboard named stream";
    if (hasNamedStreams)
    {
        HANDLE stream = CreateFileW((result + streamSuffix).c_str(), GENERIC_WRITE, 0, nullptr,
                                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (stream == INVALID_HANDLE_VALUE)
            return Fail("create a named stream on the clipboard source");
        const bool wroteStream = WriteFile(stream, streamPayload, sizeof(streamPayload), &written, nullptr) &&
            written == sizeof(streamPayload);
        CloseHandle(stream);
        if (!wroteStream)
            return Fail("write the clipboard named-stream fixture");
    }

    const auto notificationPath = current + L"\\\u00C4nderung";
    const auto notificationPanel = current + L"\\\u00E4nderung";
    if (current.size() <= MAX_PATH ||
        !Salamander::UnicodePanelPathAffected(notificationPath, notificationPanel + L"\\", false) ||
        !Salamander::UnicodePanelPathAffected(notificationPath, notificationPanel + L"\\child", true) ||
        !Salamander::UnicodePanelPathAffected(notificationPath + L"\\child", notificationPanel, false) ||
        Salamander::UnicodePanelPathAffected(notificationPath, notificationPanel + L"-sibling", true) ||
        Salamander::UnicodePanelPathAffected(notificationPath, notificationPanel + L"\\child", false))
        return Fail("change notifications compare complete Unicode path components");

    // A clipboard snapshot can mix ordinary absolute and extended paths.
    DROPFILES drop{};
    drop.pFiles = sizeof(drop);
    drop.fWide = TRUE;
    std::wstring dropNames = result;
    dropNames.push_back(L'\0');
    dropNames += distinctName;
    dropNames.append(2, L'\0');
    std::vector<unsigned char> dropBytes(sizeof(drop) + dropNames.size() * sizeof(wchar_t));
    std::memcpy(dropBytes.data(), &drop, sizeof(drop));
    std::memcpy(dropBytes.data() + sizeof(drop), dropNames.data(), dropNames.size() * sizeof(wchar_t));
    std::vector<Salamander::Utf16DiskPath> pastedFiles;
    if (Salamander::TryReadUnicodeClipboardFiles(dropBytes.data(), dropBytes.size() - sizeof(wchar_t),
                                                  pastedFiles, error) || !pastedFiles.empty())
        return Fail("incomplete clipboard file list must be rejected atomically");
    if (!Salamander::TryReadUnicodeClipboardFiles(dropBytes.data(), dropBytes.size(), pastedFiles, error) ||
        pastedFiles.size() != 2 || pastedFiles[0].Value() != std::u16string(filename.begin(), filename.end()))
        return Fail("clipboard snapshot preserves the exact source paths");
    std::vector<unsigned char> published;
    std::vector<Salamander::Utf16DiskPath> publishedPaths;
    if (!Salamander::TryEncodeUnicodeFileDrop(pastedFiles, published) ||
        !Salamander::TryReadUnicodeClipboardFiles(published.data(), published.size(), publishedPaths, error) ||
        publishedPaths.size() != pastedFiles.size() ||
        publishedPaths[0].Value() != pastedFiles[0].Value() ||
        publishedPaths[1].Value() != pastedFiles[1].Value())
        return Fail("published file drop round-trips both exact paths");

    const auto pastePath = current + L"\\paste-target";
    std::wstring extendedPaste;
    Salamander::Utf16DiskPath pasteTarget;
    if (!Convert(pastePath, extendedPaste) || !CreateDirectoryW(extendedPaste.c_str(), nullptr) ||
        !OwnPath(pastePath, pasteTarget))
        return Fail("create long clipboard copy target");
    // CopyFileExW chooses access rights for the callback handles. A separate
    // disposable copy exposes those rights without changing the production
    // identity-verification callback or its fail-closed behavior.
    CopyHandleProbe handleProbe;
    const auto probePath = extendedPaste + L"\\copy-handle-metadata-probe.tmp";
    const BOOL probeCopied = CopyFileExW(result.c_str(), probePath.c_str(),
        ProbeCopyHandles, &handleProbe, nullptr, COPY_FILE_FAIL_IF_EXISTS);
    const DWORD probeCopyError = probeCopied ? ERROR_SUCCESS : GetLastError();
    if (probeCopied && !DeleteFileW(probePath.c_str()))
        return Fail("remove disposable CopyFileExW metadata probe");
    if (!probeCopied || handleProbe.callbacks == 0)
    {
        std::fprintf(stderr, "FAIL: CopyFileExW handle probe (copyError=%lu, callbacks=%lu)\n",
                     probeCopyError, handleProbe.callbacks);
        return 1;
    }

    std::size_t copied = 0;
    // Arrange / Assert: unsupported ambiguous drop effects must not trigger
    // an actual transfer or obscure its error when the copy below fails.
    if (Salamander::UnicodeClipboardTransferEffect(DROPEFFECT_COPY | DROPEFFECT_MOVE) != DROPEFFECT_NONE ||
        Salamander::UnicodeClipboardTransferEffect(DROPEFFECT_MOVE | DROPEFFECT_SCROLL) != DROPEFFECT_MOVE)
        return Fail("Unicode clipboard drop effect validation");

    // Act: copy both files, including the source's alternate data stream.
    const bool transferSucceeded = Salamander::TryTransferUnicodeClipboardFiles(
        pastedFiles, pasteTarget, DROPEFFECT_COPY, copied, error);
    const DWORD nativeError = GetLastError();

    // Assert: report the API's explicit error and partial progress, not just
    // a potentially stale thread-local GetLastError value.
    if (!transferSucceeded || copied != 2)
    {
        std::fprintf(stderr,
                     "FAIL: copy both Unicode clipboard files into a long directory "
                     "(transferSucceeded=%d, operationError=%lu, copied=%zu/2, GetLastError=%lu)\n",
                     transferSucceeded ? 1 : 0, error, copied, nativeError);
        std::fprintf(stderr,
                     "DIAGNOSTIC: CopyFileExW callback metadata "
                     "(callbacks=%lu, sourceDenied=%d, sourceError=%lu, sourceStream=%lu, "
                     "destinationDenied=%d, destinationError=%lu, destinationStream=%lu)\n",
                     handleProbe.callbacks, handleProbe.sourceFailed ? 1 : 0,
                     handleProbe.sourceError, handleProbe.sourceStream,
                     handleProbe.destinationFailed ? 1 : 0,
                     handleProbe.destinationError, handleProbe.destinationStream);
        return 1;
    }

    const auto firstCopy = extendedPaste + filename.substr(filename.find_last_of(L'\\'));
    const auto secondCopy = extendedPaste + distinctName.substr(distinctName.find_last_of(L'\\'));
    if (hasNamedStreams)
    {
        HANDLE stream = CreateFileW((firstCopy + streamSuffix).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                                    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (stream == INVALID_HANDLE_VALUE)
            return Fail("open the copied named stream");
        char streamContents[sizeof(streamPayload)] = {};
        const bool copiedStream = ReadFile(stream, streamContents, sizeof(streamContents), &read, nullptr) &&
            read == sizeof(streamContents) && std::memcmp(streamContents, streamPayload, sizeof(streamContents)) == 0;
        CloseHandle(stream);
        if (!copiedStream)
            return Fail("source identity check must preserve named streams");
    }
    HANDLE clipboardCopyHandle = CreateFileW(firstCopy.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (clipboardCopyHandle == INVALID_HANDLE_VALUE)
        return Fail("open clipboard copy by its exact Unicode name");
    const bool copiedExactly = ReadFile(clipboardCopyHandle, actual, sizeof(actual), &read, nullptr) &&
        read == sizeof(payload) && std::memcmp(actual, payload, sizeof(payload)) == 0;
    CloseHandle(clipboardCopyHandle);
    if (!copiedExactly || !DeleteFileW(firstCopy.c_str()) ||
        Salamander::TryTransferUnicodeClipboardFiles(pastedFiles, pasteTarget, DROPEFFECT_COPY, copied, error) ||
        copied != 0 || error != ERROR_FILE_EXISTS ||
        GetFileAttributesW(firstCopy.c_str()) != INVALID_FILE_ATTRIBUTES)
        return Fail("clipboard copy preserves bytes and checks all collisions before writing");
    if (Salamander::TryTransferUnicodeClipboardFiles(pastedFiles, pasteTarget, DROPEFFECT_MOVE, copied, error) ||
        copied != 0 || error != ERROR_FILE_EXISTS ||
        GetFileAttributesW(result.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(extendedDistinct.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(firstCopy.c_str()) != INVALID_FILE_ATTRIBUTES)
        return Fail("multi-file cut detects a later collision before moving any source");
    const std::vector<Salamander::Utf16DiskPath> secondFileOnly{pastedFiles[1]};
    if (Salamander::TryTransferUnicodeClipboardFiles(secondFileOnly, pasteTarget, DROPEFFECT_MOVE, copied, error) ||
        copied != 0 || error != ERROR_FILE_EXISTS || GetFileAttributesW(extendedDistinct.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("cut must preserve the source on collision");

    BY_HANDLE_FILE_INFORMATION copySourceInfo{};
    HANDLE copySourceHandle = Salamander::OpenUnicodeClipboardSource(
        result, DROPEFFECT_COPY, copySourceInfo, error);
    if (copySourceHandle == INVALID_HANDLE_VALUE)
        return Fail("open and hold the expected clipboard copy source");
    Salamander::Utf16DiskPath wrongCopyTarget;
    const bool refusesDifferentSource = OwnPath(pastePath + L"\\wrong-source.txt", wrongCopyTarget) &&
        !Salamander::TryCopyUnicodeFileNoOverwrite(pastedFiles[1], wrongCopyTarget, error, &copySourceInfo) &&
        error == ERROR_FILE_INVALID;
    CloseHandle(copySourceHandle);
    WIN32_FIND_DATAW unexpectedStaging{};
    HANDLE staging = FindFirstFileW((extendedPaste + L"\\.opensal-copy-*.tmp").c_str(), &unexpectedStaging);
    if (staging != INVALID_HANDLE_VALUE)
        FindClose(staging);
    if (!refusesDifferentSource || staging != INVALID_HANDLE_VALUE ||
        GetFileAttributesW((extendedPaste + L"\\wrong-source.txt").c_str()) != INVALID_FILE_ATTRIBUTES)
        return Fail("a different opened source must not publish a copy or leave a staging file");

    const auto stagingPath = extendedPaste + L"\\staging-identity.tmp";
    const auto originalStagingPath = extendedPaste + L"\\original-staging.tmp";
    const auto unpublishedPath = extendedPaste + L"\\unpublished.txt";
    if (!CopyFileW(result.c_str(), stagingPath.c_str(), TRUE))
        return Fail("create a verified staging file");
    HANDLE stagingFile = CreateFileW(stagingPath.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ, nullptr,
                                     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (stagingFile == INVALID_HANDLE_VALUE)
        return Fail("read the verified staging file identity");
    BY_HANDLE_FILE_INFORMATION stagingIdentity{};
    const bool readStagingIdentity = GetFileInformationByHandle(stagingFile, &stagingIdentity) != FALSE;
    CloseHandle(stagingFile);
    if (!readStagingIdentity || !MoveFileW(stagingPath.c_str(), originalStagingPath.c_str()) ||
        !CopyFileW(extendedDistinct.c_str(), stagingPath.c_str(), TRUE))
        return Fail("substitute a different file at the staging path");
    if (Salamander::UnicodeFileOperationsDetail::PublishVerifiedCopy(stagingPath, unpublishedPath, stagingIdentity, error) ||
        error != ERROR_FILE_INVALID || GetFileAttributesW(stagingPath.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(unpublishedPath.c_str()) != INVALID_FILE_ATTRIBUTES ||
        !DeleteFileW(stagingPath.c_str()))
        return Fail("replacement staging file must neither be published nor removed");

    if (!SetFileAttributesW(originalStagingPath.c_str(), FILE_ATTRIBUTE_READONLY))
        return Fail("make the owned staging file read-only");
    if (Salamander::UnicodeFileOperationsDetail::PublishVerifiedCopy(originalStagingPath, secondCopy, stagingIdentity, error) ||
        GetFileAttributesW(originalStagingPath.c_str()) != INVALID_FILE_ATTRIBUTES)
        return Fail("late destination collision cleans up only the verified read-only staging file");

    BY_HANDLE_FILE_INFORMATION cutSourceInfo{};
    HANDLE cutSourceHandle = Salamander::OpenUnicodeClipboardSource(
        result, DROPEFFECT_MOVE, cutSourceInfo, error);
    if (cutSourceHandle == INVALID_HANDLE_VALUE)
        return Fail("hold the exact cut source open across validation and rename");
    const bool pathRenameBlocked = !MoveFileW(result.c_str(), firstCopy.c_str());
    Salamander::Utf16DiskPath occupiedTarget;
    const bool rejectsLateCollision = OwnPath(pastePath + distinctName.substr(distinctName.find_last_of(L'\\')), occupiedTarget) &&
        !Salamander::RenameUnicodeClipboardSource(cutSourceHandle, occupiedTarget, error);
    CloseHandle(cutSourceHandle);
    HANDLE occupiedFile = CreateFileW(secondCopy.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                                     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (occupiedFile == INVALID_HANDLE_VALUE)
        return Fail("open the late-collision target by its original name");
    char retainedPayload[sizeof(distinctPayload)] = {};
    const bool retainsTarget = ReadFile(occupiedFile, retainedPayload, sizeof(retainedPayload), &read, nullptr) &&
        read == sizeof(retainedPayload) && std::memcmp(retainedPayload, distinctPayload, sizeof(retainedPayload)) == 0;
    CloseHandle(occupiedFile);
    if (!pathRenameBlocked || !rejectsLateCollision ||
        !retainsTarget || GetFileAttributesW(result.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("cut source cannot be renamed by path while held, and handle rename preserves a late collision");

    const std::vector<Salamander::Utf16DiskPath> firstFileOnly{pastedFiles[0]};
    if (!Salamander::TryTransferUnicodeClipboardFiles(firstFileOnly, pasteTarget, DROPEFFECT_MOVE, copied, error) ||
        copied != 1 || GetFileAttributesW(result.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(firstCopy.c_str()) == INVALID_FILE_ATTRIBUTES ||
        !MoveFileW(firstCopy.c_str(), result.c_str()))
        return Fail("move one cut file atomically to a long Unicode destination");

    if (!DeleteFileW(secondCopy.c_str()) ||
        !Salamander::TryTransferUnicodeClipboardFiles(pastedFiles, pasteTarget, DROPEFFECT_MOVE, copied, error) ||
        copied != 2 || GetFileAttributesW(result.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(extendedDistinct.c_str()) != INVALID_FILE_ATTRIBUTES ||
        !MoveFileW(firstCopy.c_str(), result.c_str()) ||
        !MoveFileW(secondCopy.c_str(), extendedDistinct.c_str()) ||
        !CopyFileW(extendedDistinct.c_str(), secondCopy.c_str(), TRUE))
        return Fail("move both cut files and restore the test fixtures");

    const auto emptySourcePath = current + L"\\empty_\U0001F600.txt";
    const auto emptyTargetPath = extendedPaste + L"\\empty_\U0001F600.txt";
    std::wstring emptySourceExtended;
    Salamander::Utf16DiskPath emptyOwned;
    if (!Convert(emptySourcePath, emptySourceExtended) || !OwnPath(emptySourcePath, emptyOwned))
        return Fail("prepare an empty Unicode clipboard source");
    HANDLE emptyFile = CreateFileW(emptySourceExtended.c_str(), GENERIC_WRITE, 0, nullptr,
                                   CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (emptyFile == INVALID_HANDLE_VALUE)
        return Fail("create the empty Unicode clipboard source");
    CloseHandle(emptyFile);
    if (!Salamander::TryTransferUnicodeClipboardFiles({emptyOwned}, pasteTarget, DROPEFFECT_COPY, copied, error) ||
        copied != 1 || !DeleteFileW(emptyTargetPath.c_str()))
        return Fail("prove source identity even when copying an empty file");
    Salamander::Utf16DiskPath crossVolumeTarget;
    BY_HANDLE_FILE_INFORMATION crossVolumeSourceInfo{};
    if (!OwnPath(pastePath + L"\\empty_\U0001F600.txt", crossVolumeTarget))
        return Fail("prepare copy-then-delete destination");
    HANDLE guardedSource = Salamander::OpenUnicodeClipboardSource(
        emptySourceExtended, DROPEFFECT_COPY, crossVolumeSourceInfo, error, true);
    if (guardedSource == INVALID_HANDLE_VALUE)
        return Fail("hold source against writers during copy-then-delete");
    const bool movedByCopy = Salamander::MoveUnicodeClipboardFileByCopy(
        emptyOwned, crossVolumeTarget, crossVolumeSourceInfo, error);
    CloseHandle(guardedSource);
    if (!movedByCopy || GetFileAttributesW(emptySourceExtended.c_str()) != INVALID_FILE_ATTRIBUTES ||
        !DeleteFileW(emptyTargetPath.c_str()))
        return Fail("verified copy-then-delete preserves an empty file and removes only its source");
    if (!CopyFileW(result.c_str(), emptySourceExtended.c_str(), TRUE) ||
        !SetFileAttributesW(emptySourceExtended.c_str(), FILE_ATTRIBUTE_READONLY))
        return Fail("prepare a source whose deletion must fail");
    guardedSource = Salamander::OpenUnicodeClipboardSource(
        emptySourceExtended, DROPEFFECT_COPY, crossVolumeSourceInfo, error, true);
    if (guardedSource == INVALID_HANDLE_VALUE)
        return Fail("hold read-only move source");
    const bool unexpectedlyRemoved = Salamander::MoveUnicodeClipboardFileByCopy(
        emptyOwned, crossVolumeTarget, crossVolumeSourceInfo, error);
    CloseHandle(guardedSource);
    if (unexpectedlyRemoved || error != ERROR_ACCESS_DENIED ||
        GetFileAttributesW(emptySourceExtended.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(emptyTargetPath.c_str()) == INVALID_FILE_ATTRIBUTES ||
        !SetFileAttributesW(emptyTargetPath.c_str(), FILE_ATTRIBUTE_NORMAL) || !DeleteFileW(emptyTargetPath.c_str()) ||
        !SetFileAttributesW(emptySourceExtended.c_str(), FILE_ATTRIBUTE_NORMAL) || !DeleteFileW(emptySourceExtended.c_str()))
        return Fail("failed source removal keeps both the original and the verified copy");

    wchar_t otherVolume[MAX_PATH];
    const DWORD otherLength = GetEnvironmentVariableW(L"OPENSAL_TEST_OTHER_VOLUME", otherVolume, MAX_PATH);
    if (otherLength)
    {
        if (otherLength >= MAX_PATH || otherLength < 3 || otherVolume[1] != L':' || otherVolume[2] != L'\\')
            return Fail("second-volume fixture must be in a supplied local directory");
        const std::wstring otherRoot = std::wstring(otherVolume) + L"\\OpenSal-VolumeMove-" +
            std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
        Salamander::Utf16DiskPath otherTarget;
        std::wstring otherRootExtended;
        if (!OwnPath(otherRoot, otherTarget) || !Convert(otherRoot, otherRootExtended) ||
            !CreateDirectoryW(otherRootExtended.c_str(), nullptr) ||
            !CopyFileW(result.c_str(), emptySourceExtended.c_str(), TRUE))
            return Fail("create disposable volume-move fixtures");
        const HANDLE sourceVolumeHandle = CreateFileW(emptySourceExtended.c_str(), FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
        const HANDLE targetVolumeHandle = CreateFileW(otherRootExtended.c_str(), FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
        if (sourceVolumeHandle == INVALID_HANDLE_VALUE || targetVolumeHandle == INVALID_HANDLE_VALUE)
            return Fail("inspect the actual volumes of the move fixtures");
        const auto sourceVolumeName = Salamander::UnicodeClipboardVolumeName(sourceVolumeHandle);
        const auto targetVolumeName = Salamander::UnicodeClipboardVolumeName(targetVolumeHandle);
        CloseHandle(targetVolumeHandle);
        CloseHandle(sourceVolumeHandle);
        if (sourceVolumeName.empty() || targetVolumeName.empty() || sourceVolumeName == targetVolumeName)
            return Fail("test move requires two distinct volume device paths");
        if (!Salamander::TryTransferUnicodeClipboardFiles({emptyOwned}, otherTarget, DROPEFFECT_MOVE, copied, error) ||
            copied != 1 || GetFileAttributesW(emptySourceExtended.c_str()) != INVALID_FILE_ATTRIBUTES)
            return Fail("clipboard move selects copy-then-delete on a different volume");
        const auto transferred = otherRootExtended + L"\\empty_\U0001F600.txt";
        HANDLE moved = CreateFileW(transferred.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                                  OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (moved == INVALID_HANDLE_VALUE)
            return Fail("open exact cross-volume Unicode destination");
        const bool contentMatches = ReadFile(moved, actual, sizeof(actual), &read, nullptr) &&
            read == sizeof(payload) && std::memcmp(actual, payload, sizeof(payload)) == 0;
        CloseHandle(moved);
        if (!contentMatches || !DeleteFileW(transferred.c_str()) || !RemoveDirectoryW(otherRootExtended.c_str()))
            return Fail("verified cross-volume destination and cleanup");
        std::puts("PASS: clipboard move across distinct physical volume identities");
    }

    const std::wstring cutDirectory = current + L"\\cut_\U0001F600";
    const std::wstring movedDirectory = pastePath + L"\\cut_\U0001F600";
    std::wstring cutDirectoryExtended, movedDirectoryExtended;
    Salamander::Utf16DiskPath cutDirectoryOwned;
    if (!Convert(cutDirectory, cutDirectoryExtended) || !Convert(movedDirectory, movedDirectoryExtended) ||
        !OwnPath(cutDirectory, cutDirectoryOwned) || !CreateDirectoryW(cutDirectoryExtended.c_str(), nullptr))
        return Fail("prepare long cut directory");
    const auto cutChild = cutDirectoryExtended + L"\\content.txt";
    const auto movedChild = movedDirectoryExtended + L"\\content.txt";
    if (!CopyFileW(result.c_str(), cutChild.c_str(), TRUE))
        return Fail("prepare content in the long cut directory");
    if (!Salamander::TryTransferUnicodeClipboardFiles({cutDirectoryOwned}, pasteTarget, DROPEFFECT_COPY, copied, error) ||
        copied != 1 || GetFileAttributesW(cutChild.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(movedChild.c_str()) == INVALID_FILE_ATTRIBUTES ||
        !DeleteFileW(movedChild.c_str()) || !RemoveDirectoryW(movedDirectoryExtended.c_str()))
        return Fail("recursively copy a long Unicode directory without modifying its contents");
    if (!Salamander::TryTransferUnicodeClipboardFiles({cutDirectoryOwned}, pasteTarget, DROPEFFECT_MOVE, copied, error) ||
        copied != 1 || GetFileAttributesW(cutDirectoryExtended.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(movedChild.c_str()) == INVALID_FILE_ATTRIBUTES ||
        !DeleteFileW(movedChild.c_str()) || !RemoveDirectoryW(movedDirectoryExtended.c_str()))
        return Fail("move a Unicode directory into a long same-volume destination");

    if (GetFileAttributesW(result.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(extendedDistinct.c_str()) == INVALID_FILE_ATTRIBUTES ||
        !DeleteFileW(secondCopy.c_str()) || !RemoveDirectoryW(extendedPaste.c_str()))
        return Fail("clipboard copy retains both sources and cleans up its test fixture");

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
    if (current.size() <= MAX_PATH)
        return Fail("panel directory must exceed MAX_PATH");
    WIN32_FIND_DATAA panelAnsiData = {};
    WIN32_FIND_DATAW panelWideData = {};
    HANDLE panelFind = Salamander::FindFirstUnicodePanelFile(
        current, panelAnsiData, panelWideData);
    // Assert: the adapter must use a W extended-length search internally.
    if (panelFind == INVALID_HANDLE_VALUE)
        return Fail("W-backed panel enumeration of a long directory");
    bool panelNamePreserved = false;
    bool secondNamePreserved = false;
    bool maximumNamePreserved = false;
    int actualEntries = 0;
    do
    {
        const std::wstring name(panelWideData.cFileName);
        if (name == L"." || name == L"..")
            continue;
        ++actualEntries;
        panelNamePreserved |= name == L"Größe_東京_😀.txt";
        secondNamePreserved |= name == L"Größe_大阪_😀.txt";
        maximumNamePreserved |= name == maxName;
    } while (Salamander::FindNextUnicodePanelFile(
        panelFind, panelAnsiData, panelWideData));
    const DWORD enumerationError = GetLastError();
    FindClose(panelFind);
    if (enumerationError != ERROR_NO_MORE_FILES || actualEntries != 3 ||
        !panelNamePreserved || !secondNamePreserved || !maximumNamePreserved)
        return Fail("W-backed long panel enumeration preserves every Unicode row");

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
    // A missing source must not publish any destination or leave a
    // staging artifact in the parent directory.
    Salamander::Utf16DiskPath missingCopySource, missingCopyTarget;
    const std::wstring missingCopyName = current + L"\\missing-copy-source-東京.txt";
    const std::wstring missingTargetName = current + L"\\missing-copy-target-東京.txt";
    if (!OwnPath(missingCopyName, missingCopySource) ||
        !OwnPath(missingTargetName, missingCopyTarget) ||
        Salamander::TryCopyUnicodeFileNoOverwrite(
            missingCopySource, missingCopyTarget, operationError))
        return Fail("refuse staged copy from missing source");
    std::wstring extendedMissingTarget;
    if (!Convert(missingTargetName, extendedMissingTarget) ||
        GetFileAttributesW(extendedMissingTarget.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetLastError() != ERROR_FILE_NOT_FOUND)
        return Fail("missing-source copy must not publish a target");

    // The staged copy path must never remain visible after either success
    // or a rejected overwrite. Validate the real destination directory.
    std::vector<Salamander::LongDirectoryEntry> postCopy;
    DWORD postCopyError = ERROR_SUCCESS;
    if (!Salamander::TryEnumerateLongDirectory(current.c_str(), postCopy,
                                               postCopyError))
        return Fail("enumerate staged-copy destination");
    for (const auto& candidate : postCopy)
    {
        if (candidate.name.compare(0, 14, L".opensal-copy-") == 0)
            return Fail("staged Unicode copy left a temporary artifact");
    }

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

    // Act / Assert: move the exact, originally opened Unicode file by its
    // verified Win32 handle, not a replaceable pathname.
    BY_HANDLE_FILE_INFORMATION originalCopyIdentity{};
    if (!Salamander::TryReadUnicodeRegularFileIdentity(
            unicodeCopy, originalCopyIdentity, operationError))
        return Fail("capture pre-dialog Unicode F6 file identity");
    if (!Salamander::TryMoveUnicodeFileNoOverwrite(
            unicodeCopy, unicodeMoved, operationError, &originalCopyIdentity) ||
        operationError != ERROR_SUCCESS ||
        GetFileAttributesW(extendedCopy.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(extendedMoved.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("move Unicode long filename without source duplication");
    if (!Salamander::TryDeleteUnicodeFile(unicodeMoved, operationError) ||
        operationError != ERROR_SUCCESS ||
        GetFileAttributesW(extendedMoved.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(result.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("delete only chosen Unicode file and retain original");

    // Arrange: a genuine nested directory tree in the disposable >MAX_PATH
    // fixture. Move is a same-volume atomic directory rename: contents,
    // subdirectories and Unicode identity must remain unchanged.
    const std::wstring originalTree = current + L"\\tree_東京_😀";
    const std::wstring movedTree = current + L"\\tree_moved_東京_😀";
    const std::wstring blockedTree = current + L"\\tree_blocked_東京_😀";
    const std::wstring originalChild = originalTree + L"\\nested";
    const std::wstring originalLeaf = originalChild + L"\\payload_日本.txt";
    const std::wstring movedLeaf = movedTree + L"\\nested\\payload_日本.txt";
    std::wstring originalTreeExtended, movedTreeExtended, blockedTreeExtended;
    std::wstring originalChildExtended, originalLeafExtended, movedLeafExtended;
    Salamander::Utf16DiskPath ownedTree, ownedMovedTree, ownedBlockedTree;
    if (!Convert(originalTree, originalTreeExtended) ||
        !Convert(movedTree, movedTreeExtended) ||
        !Convert(blockedTree, blockedTreeExtended) ||
        !Convert(originalChild, originalChildExtended) ||
        !Convert(originalLeaf, originalLeafExtended) ||
        !Convert(movedLeaf, movedLeafExtended) ||
        !OwnPath(originalTree, ownedTree) ||
        !OwnPath(movedTree, ownedMovedTree) ||
        !OwnPath(blockedTree, ownedBlockedTree))
        return Fail("prepare Unicode directory move fixture");
    if (!CreateDirectoryW(originalTreeExtended.c_str(), nullptr) ||
        !CreateDirectoryW(originalChildExtended.c_str(), nullptr) ||
        !CreateDirectoryW(blockedTreeExtended.c_str(), nullptr))
        return Fail("create Unicode directory move fixture");

    HANDLE leaf = CreateFileW(originalLeafExtended.c_str(), GENERIC_WRITE, 0,
                             nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (leaf == INVALID_HANDLE_VALUE)
        return Fail("create Unicode nested tree payload");
    const char treeBytes[] = "NESTED-TREE-ORIGINAL-BYTES";
    DWORD treeWritten = 0;
    const bool wroteTree = WriteFile(leaf, treeBytes, sizeof(treeBytes),
                                     &treeWritten, nullptr) &&
                           treeWritten == sizeof(treeBytes);
    CloseHandle(leaf);
    if (!wroteTree)
        return Fail("write Unicode nested tree payload");

    // Act / Assert: a collision must not modify either tree.
    if (Salamander::TryMoveUnicodeDirectoryNoOverwrite(
            ownedTree, ownedBlockedTree, operationError) ||
        GetFileAttributesW(originalLeafExtended.c_str()) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(blockedTreeExtended.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("directory collision must preserve both trees");

    // Act / Assert: the complete tree moves atomically within one volume.
    if (!Salamander::TryMoveUnicodeDirectoryNoOverwrite(
            ownedTree, ownedMovedTree, operationError) ||
        operationError != ERROR_SUCCESS ||
        GetFileAttributesW(originalTreeExtended.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(movedLeafExtended.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("atomic long Unicode directory move");

    HANDLE movedLeafHandle = CreateFileW(movedLeafExtended.c_str(), GENERIC_READ,
                                        FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (movedLeafHandle == INVALID_HANDLE_VALUE)
        return Fail("read moved Unicode directory payload");
    char readTreeBytes[sizeof(treeBytes)] = {};
    DWORD treeRead = 0;
    const bool contentsUnchanged =
        ReadFile(movedLeafHandle, readTreeBytes, sizeof(readTreeBytes),
                 &treeRead, nullptr) &&
        treeRead == sizeof(treeBytes) &&
        std::memcmp(readTreeBytes, treeBytes, sizeof(treeBytes)) == 0;
    CloseHandle(movedLeafHandle);
    if (!contentsUnchanged)
        return Fail("directory move must preserve nested file bytes");

    const std::wstring movedChildExtended = movedTreeExtended + L"\\nested";
    if (!DeleteFileW(movedLeafExtended.c_str()) ||
        !RemoveDirectoryW(movedChildExtended.c_str()) ||
        !RemoveDirectoryW(movedTreeExtended.c_str()) ||
        !RemoveDirectoryW(blockedTreeExtended.c_str()))
        return Fail("cleanup Unicode directory move fixture");

    // GUI F6 regression: move a nested tree from a >MAX_PATH source into
    // a different, short parent directory on the SAME volume. Moving between
    // different parents is distinct from renaming within one directory.
    const std::wstring crossParentSource = current + L"\\tree-move-cross-parent";
    const std::wstring crossParentChild = crossParentSource + L"\\nested";
    const std::wstring crossParentLeaf = crossParentChild + L"\\payload.bin";
    const std::wstring crossParentTarget = root + L"\\tree-move-cross-parent";
    const std::wstring crossParentTargetChild = crossParentTarget + L"\\nested";
    const std::wstring crossParentTargetLeaf = crossParentTargetChild + L"\\payload.bin";
    std::wstring crossSourceExtended, crossChildExtended, crossLeafExtended;
    std::wstring crossTargetExtended, crossTargetChildExtended, crossTargetLeafExtended;
    Salamander::Utf16DiskPath crossSourceOwned, crossTargetOwned;
    if (!Convert(crossParentSource, crossSourceExtended) ||
        !Convert(crossParentChild, crossChildExtended) ||
        !Convert(crossParentLeaf, crossLeafExtended) ||
        !Convert(crossParentTarget, crossTargetExtended) ||
        !Convert(crossParentTargetChild, crossTargetChildExtended) ||
        !Convert(crossParentTargetLeaf, crossTargetLeafExtended) ||
        !OwnPath(crossParentSource, crossSourceOwned) ||
        !OwnPath(crossParentTarget, crossTargetOwned) ||
        !CreateDirectoryW(crossSourceExtended.c_str(), nullptr) ||
        !CreateDirectoryW(crossChildExtended.c_str(), nullptr))
        return Fail("prepare long source to short parent tree move");

    HANDLE crossLeaf = CreateFileW(crossLeafExtended.c_str(), GENERIC_WRITE,
                                   0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (crossLeaf == INVALID_HANDLE_VALUE)
        return Fail("create nested payload for cross-parent directory move");
    DWORD crossWritten = 0;
    const char crossBytes[] = "cross-parent-tree";
    const bool crossWrote = WriteFile(crossLeaf, crossBytes, sizeof(crossBytes),
                                      &crossWritten, nullptr) &&
                            crossWritten == sizeof(crossBytes);
    CloseHandle(crossLeaf);
    if (!crossWrote)
        return Fail("write cross-parent directory payload");

    if (!Salamander::TryMoveUnicodeDirectoryNoOverwrite(
            crossSourceOwned, crossTargetOwned, operationError) ||
        operationError != ERROR_SUCCESS ||
        GetFileAttributesW(crossSourceExtended.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(crossTargetLeafExtended.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("atomic directory move from long source to short parent");

    HANDLE movedCrossLeaf = CreateFileW(crossTargetLeafExtended.c_str(),
                                       GENERIC_READ, FILE_SHARE_READ, nullptr,
                                       OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (movedCrossLeaf == INVALID_HANDLE_VALUE)
        return Fail("read cross-parent moved directory payload");
    char crossRead[sizeof(crossBytes)] = {};
    DWORD crossBytesRead = 0;
    const bool crossPreserved = ReadFile(movedCrossLeaf, crossRead,
                                        sizeof(crossRead), &crossBytesRead, nullptr) &&
                                crossBytesRead == sizeof(crossBytes) &&
                                memcmp(crossRead, crossBytes, sizeof(crossBytes)) == 0;
    CloseHandle(movedCrossLeaf);
    if (!crossPreserved ||
        !DeleteFileW(crossTargetLeafExtended.c_str()) ||
        !RemoveDirectoryW(crossTargetChildExtended.c_str()) ||
        !RemoveDirectoryW(crossTargetExtended.c_str()))
        return Fail("cross-parent directory move bytes and cleanup");

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

    // Optional *real* cross-volume F6 regression. The caller explicitly
    // provides a disposable directory on a SECOND volume. We never pick
    // arbitrary drives, change volume configuration, or delete its parent.
    // In its absence the scenario stays SKIP, never a claimed PASS.
    WCHAR otherRootBuffer[MAX_PATH]{};
    const DWORD otherRootLength = GetEnvironmentVariableW(
        L"OPENSAL_CROSS_VOLUME_TEST_DIR", otherRootBuffer, _countof(otherRootBuffer));
    if (otherRootLength == 0)
        std::puts("SKIP: cross-volume UTF-16 move requires OPENSAL_CROSS_VOLUME_TEST_DIR");
    else
    {
        if (otherRootLength >= _countof(otherRootBuffer))
            return Fail("cross-volume destination root exceeds test buffer");
        std::wstring otherRoot(otherRootBuffer);
        while (otherRoot.size() > 3 && otherRoot.back() == L'\\')
            otherRoot.pop_back();
        Salamander::Utf16DiskPath otherDirectory;
        std::wstring sourceDirectoryExtended, otherDirectoryExtended;
        if (!OwnPath(otherRoot, otherDirectory) ||
            !Convert(current, sourceDirectoryExtended) ||
            !Convert(otherRoot, otherDirectoryExtended))
            return Fail("validate explicit cross-volume test directories");
        const HANDLE sourceDirectoryHandle = CreateFileW(
            sourceDirectoryExtended.c_str(), FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
        const HANDLE otherDirectoryHandle = CreateFileW(
            otherDirectoryExtended.c_str(), FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
        if (sourceDirectoryHandle == INVALID_HANDLE_VALUE ||
            otherDirectoryHandle == INVALID_HANDLE_VALUE)
        {
            if (sourceDirectoryHandle != INVALID_HANDLE_VALUE) CloseHandle(sourceDirectoryHandle);
            if (otherDirectoryHandle != INVALID_HANDLE_VALUE) CloseHandle(otherDirectoryHandle);
            return Fail("open source and second-volume test directories");
        }
        BY_HANDLE_FILE_INFORMATION otherDirectoryInfo{};
        const bool otherIsPlainDirectory =
            GetFileInformationByHandle(otherDirectoryHandle, &otherDirectoryInfo) &&
            (otherDirectoryInfo.dwFileAttributes &
                (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) == FILE_ATTRIBUTE_DIRECTORY;
        const std::wstring sourceVolume = Salamander::UnicodeClipboardVolumeName(sourceDirectoryHandle);
        const std::wstring otherVolume = Salamander::UnicodeClipboardVolumeName(otherDirectoryHandle);
        CloseHandle(sourceDirectoryHandle);
        CloseHandle(otherDirectoryHandle);
        if (!otherIsPlainDirectory || sourceVolume.empty() || otherVolume.empty() ||
            CompareStringOrdinal(sourceVolume.c_str(), -1, otherVolume.c_str(), -1, TRUE) == CSTR_EQUAL)
            return Fail("test destination must be a real directory on a different volume");

        const std::wstring leafName = L"opensal-crossvolume-" +
            std::to_wstring(GetCurrentProcessId()) + L"-東京_😀.bin";
        const std::wstring crossSourceName = current + L"\\" + leafName;
        const std::wstring crossTargetName = otherRoot + L"\\" + leafName;
        std::wstring crossSourceExtended, crossTargetExtended;
        Salamander::Utf16DiskPath crossSource;
        if (!OwnPath(crossSourceName, crossSource) ||
            !Convert(crossSourceName, crossSourceExtended) ||
            !Convert(crossTargetName, crossTargetExtended) ||
            GetFileAttributesW(crossTargetExtended.c_str()) != INVALID_FILE_ATTRIBUTES)
            return Fail("prepare unique cross-volume Unicode names");

        const char movedPayload[] = "exact cross-volume UTF-16 payload";
        auto writePayload = [&](const std::wstring& path, const char* bytes, DWORD count) -> bool {
            HANDLE h = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                                   CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (h == INVALID_HANDLE_VALUE) return false;
            DWORD written = 0;
            const bool ok = WriteFile(h, bytes, count, &written, nullptr) && written == count;
            CloseHandle(h);
            return ok;
        };
        if (!writePayload(crossSourceExtended, movedPayload, sizeof(movedPayload)))
            return Fail("create source on first volume");
        // Act / Assert: the same W-only clipboard transfer primitive used by
        // the F6 cross-volume fallback must publish exact bytes, then remove
        // the original. No ACP string is involved.
        std::size_t completed = 0;
        if (!Salamander::TryTransferUnicodeClipboardFiles(
                {crossSource}, otherDirectory, DROPEFFECT_MOVE, completed, operationError) ||
            completed != 1 || operationError != ERROR_SUCCESS ||
            GetFileAttributesW(crossSourceExtended.c_str()) != INVALID_FILE_ATTRIBUTES)
            return Fail("cross-volume Unicode move must complete without duplicating source");
        HANDLE moved = CreateFileW(crossTargetExtended.c_str(), GENERIC_READ,
                                   FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                   FILE_ATTRIBUTE_NORMAL, nullptr);
        if (moved == INVALID_HANDLE_VALUE)
            return Fail("open cross-volume Unicode destination");
        char actualBytes[sizeof(movedPayload)]{};
        DWORD bytesRead = 0;
        const bool identical = ReadFile(moved, actualBytes, sizeof(actualBytes),
                                        &bytesRead, nullptr) &&
                               bytesRead == sizeof(movedPayload) &&
                               memcmp(actualBytes, movedPayload, sizeof(movedPayload)) == 0;
        CloseHandle(moved);
        if (!identical || !DeleteFileW(crossTargetExtended.c_str()))
            return Fail("verify moved bytes and clean own target");

        // Two selected Unicode files must move across volumes without
        // accepting an ACP alias or leaving a source copy. The complete
        // preflight also refuses an occupied second target *before* moving
        // the first file.
        const std::wstring multiNameA = L"multi-a-" +
            std::to_wstring(GetCurrentProcessId()) + L"-東京.bin";
        const std::wstring multiNameB = L"multi-b-" +
            std::to_wstring(GetCurrentProcessId()) + L"-大阪.bin";
        const std::wstring multiSourceA = current + L"\\" + multiNameA;
        const std::wstring multiSourceB = current + L"\\" + multiNameB;
        const std::wstring multiTargetA = otherRoot + L"\\" + multiNameA;
        const std::wstring multiTargetB = otherRoot + L"\\" + multiNameB;
        std::wstring sourceAExtended, sourceBExtended;
        std::wstring targetAExtended, targetBExtended;
        Salamander::Utf16DiskPath ownedA, ownedB;
        if (!OwnPath(multiSourceA, ownedA) ||
            !OwnPath(multiSourceB, ownedB) ||
            !Convert(multiSourceA, sourceAExtended) ||
            !Convert(multiSourceB, sourceBExtended) ||
            !Convert(multiTargetA, targetAExtended) ||
            !Convert(multiTargetB, targetBExtended))
            return Fail("prepare independent cross-volume multi-file names");
        const char bytesA[] = "unicode cross-volume A";
        const char bytesB[] = "unicode cross-volume B";
        if (!writePayload(sourceAExtended, bytesA, sizeof(bytesA)) ||
            !writePayload(sourceBExtended, bytesB, sizeof(bytesB)) ||
            !writePayload(targetBExtended, "occupied", sizeof("occupied")))
            return Fail("create explicit multi-file cross-volume fixtures");
        completed = 0;
        if (Salamander::TryTransferUnicodeClipboardFiles(
                {ownedA, ownedB}, otherDirectory, DROPEFFECT_MOVE,
                completed, operationError) ||
            completed != 0 || operationError != ERROR_FILE_EXISTS ||
            GetFileAttributesW(targetAExtended.c_str()) != INVALID_FILE_ATTRIBUTES ||
            GetFileAttributesW(sourceAExtended.c_str()) == INVALID_FILE_ATTRIBUTES ||
            GetFileAttributesW(sourceBExtended.c_str()) == INVALID_FILE_ATTRIBUTES)
            return Fail("multi-file collision must reject entire batch before first move");
        if (!DeleteFileW(targetBExtended.c_str()))
            return Fail("remove only owned collision fixture");
        completed = 0;
        if (!Salamander::TryTransferUnicodeClipboardFiles(
                {ownedA, ownedB}, otherDirectory, DROPEFFECT_MOVE,
                completed, operationError) ||
            completed != 2 || operationError != ERROR_SUCCESS ||
            GetFileAttributesW(sourceAExtended.c_str()) != INVALID_FILE_ATTRIBUTES ||
            GetFileAttributesW(sourceBExtended.c_str()) != INVALID_FILE_ATTRIBUTES)
            return Fail("move both Unicode files between independent volumes");
        const auto verifyAndRemove = [](const std::wstring& path,
                                        const char* expected, DWORD length) -> bool {
            HANDLE handle = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                                        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (handle == INVALID_HANDLE_VALUE)
                return false;
            std::vector<char> actual(length);
            DWORD read = 0;
            const bool valid = ReadFile(handle, actual.data(), length, &read, nullptr) &&
                               read == length && memcmp(actual.data(), expected, length) == 0;
            CloseHandle(handle);
            return valid && DeleteFileW(path.c_str());
        };
        if (!verifyAndRemove(targetAExtended, bytesA, sizeof(bytesA)) ||
            !verifyAndRemove(targetBExtended, bytesB, sizeof(bytesB)))
            return Fail("multi-file cross-volume move preserves both payloads");

        // A pre-existing file with the same Unicode name is never replaced.
        const char occupiedBytes[] = "unrelated destination";
        if (!writePayload(crossSourceExtended, movedPayload, sizeof(movedPayload)) ||
            !writePayload(crossTargetExtended, occupiedBytes, sizeof(occupiedBytes)))
            return Fail("create cross-volume no-overwrite regression");
        completed = 0;
        if (Salamander::TryTransferUnicodeClipboardFiles(
                {crossSource}, otherDirectory, DROPEFFECT_MOVE, completed, operationError) ||
            completed != 0 || operationError != ERROR_FILE_EXISTS ||
            GetFileAttributesW(crossSourceExtended.c_str()) == INVALID_FILE_ATTRIBUTES)
            return Fail("cross-volume Unicode move must reject occupied destination");
        HANDLE occupied = CreateFileW(crossTargetExtended.c_str(), GENERIC_READ,
                                      FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                      FILE_ATTRIBUTE_NORMAL, nullptr);
        if (occupied == INVALID_HANDLE_VALUE)
            return Fail("inspect protected cross-volume destination");
        char preservedBytes[sizeof(occupiedBytes)]{};
        DWORD preservedCount = 0;
        const bool preserved = ReadFile(occupied, preservedBytes, sizeof(preservedBytes),
                                        &preservedCount, nullptr) &&
                               preservedCount == sizeof(occupiedBytes) &&
                               memcmp(preservedBytes, occupiedBytes, sizeof(occupiedBytes)) == 0;
        CloseHandle(occupied);
        if (!preserved || !DeleteFileW(crossSourceExtended.c_str()) ||
            !DeleteFileW(crossTargetExtended.c_str()))
            return Fail("cross-volume no-overwrite must preserve both file identities");
        std::puts("PASS: real two-volume Unicode move, exact bytes and no-overwrite");
    }

    // A delayed F8 confirmation must never delete a different file
    // substituted at the same Unicode path. Verify the opened file identity
    // atomically with the final disposition request.
    const std::wstring deleteProbe = current + L"\\delete-identity-東京.txt";
    const std::wstring movedProbe = current + L"\\delete-original-東京.txt";
    std::wstring deleteProbeExtended, movedProbeExtended;
    Salamander::Utf16DiskPath ownedDeleteProbe;
    if (!OwnPath(deleteProbe, ownedDeleteProbe) ||
        !Convert(deleteProbe, deleteProbeExtended) ||
        !Convert(movedProbe, movedProbeExtended))
        return Fail("prepare Unicode F8 identity fixture");
    HANDLE deleteProbeFile = CreateFileW(
        deleteProbeExtended.c_str(), GENERIC_WRITE | FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (deleteProbeFile == INVALID_HANDLE_VALUE)
        return Fail("create Unicode F8 identity fixture");
    BY_HANDLE_FILE_INFORMATION originalIdentity{};
    const bool originalIdentified =
        GetFileInformationByHandle(deleteProbeFile, &originalIdentity) != FALSE;
    CloseHandle(deleteProbeFile);
    if (!originalIdentified ||
        !MoveFileExW(deleteProbeExtended.c_str(), movedProbeExtended.c_str(), 0))
        return Fail("move original Unicode F8 identity out of the way");
    deleteProbeFile = CreateFileW(
        deleteProbeExtended.c_str(), GENERIC_WRITE, 0,
        nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (deleteProbeFile == INVALID_HANDLE_VALUE)
        return Fail("create unrelated replacement at old Unicode filename");
    CloseHandle(deleteProbeFile);

    if (Salamander::TryDeleteUnicodeFileWithIdentity(
            ownedDeleteProbe, originalIdentity, operationError) ||
        operationError != ERROR_FILE_INVALID ||
        GetFileAttributesW(deleteProbeExtended.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("F8 cannot delete unrelated replacement file at same path");
    if (!DeleteFileW(deleteProbeExtended.c_str()) ||
        !MoveFileExW(movedProbeExtended.c_str(), deleteProbeExtended.c_str(), 0))
        return Fail("restore original Unicode F8 fixture name");
    if (!Salamander::TryDeleteUnicodeFileWithIdentity(
            ownedDeleteProbe, originalIdentity, operationError) ||
        operationError != ERROR_SUCCESS ||
        GetFileAttributesW(deleteProbeExtended.c_str()) != INVALID_FILE_ATTRIBUTES)
        return Fail("F8 deletes original file only after identity revalidation");

    // The background Unicode F6 worker may remove its source only after a
    // complete copied target has the same *file identity* it created. A path
    // replacement with identical bytes and size must still be rejected.
    const std::wstring workerSource = current + L"\\worker-source-東京.bin";
    const std::wstring workerTarget = current + L"\\worker-target-大阪.bin";
    const std::wstring workerAside = current + L"\\worker-aside-識別.bin";
    std::wstring sourceForWorker, targetForWorker, asideForWorker;
    Salamander::Utf16DiskPath ownedWorkerSource, ownedWorkerTarget;
    if (!Convert(workerSource, sourceForWorker) ||
        !Convert(workerTarget, targetForWorker) ||
        !Convert(workerAside, asideForWorker) ||
        !OwnPath(workerSource, ownedWorkerSource) ||
        !OwnPath(workerTarget, ownedWorkerTarget))
        return Fail("create UTF-16 asynchronous move identity paths");
    HANDLE workerInput = CreateFileW(sourceForWorker.c_str(), GENERIC_WRITE,
                                     0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (workerInput == INVALID_HANDLE_VALUE)
        return Fail("create UTF-16 asynchronous move source");
    const char workerPayload[] = "verified Unicode background copy";
    DWORD workerWritten = 0;
    const bool workerWrote = WriteFile(workerInput, workerPayload,
                                       sizeof(workerPayload), &workerWritten, nullptr) &&
                             workerWritten == sizeof(workerPayload);
    CloseHandle(workerInput);
    if (!workerWrote || !CopyFileW(sourceForWorker.c_str(), targetForWorker.c_str(), TRUE))
        return Fail("create completed Unicode worker copy");

    auto readWorkerIdentity = [](const std::wstring& name,
                                 BY_HANDLE_FILE_INFORMATION& identity) -> bool {
        const HANDLE file = CreateFileW(name.c_str(), FILE_READ_ATTRIBUTES,
                                        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                        nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
        if (file == INVALID_HANDLE_VALUE)
            return false;
        const bool read = GetFileInformationByHandle(file, &identity) != FALSE;
        CloseHandle(file);
        return read;
    };
    BY_HANDLE_FILE_INFORMATION expectedWorkerSource{}, expectedWorkerTarget{};
    if (!readWorkerIdentity(sourceForWorker, expectedWorkerSource) ||
        !readWorkerIdentity(targetForWorker, expectedWorkerTarget))
        return Fail("capture both worker file identities");

    // Replace the *target* with a byte-identical file at the same path.
    if (!MoveFileExW(targetForWorker.c_str(), asideForWorker.c_str(), 0) ||
        !CopyFileW(sourceForWorker.c_str(), targetForWorker.c_str(), TRUE))
        return Fail("stage replaced Unicode worker destination");
    if (Salamander::TryCompleteUnicodeMoveAfterCopy(
            ownedWorkerSource, ownedWorkerTarget, expectedWorkerSource,
            expectedWorkerTarget, operationError) ||
        operationError != ERROR_FILE_INVALID ||
        GetFileAttributesW(sourceForWorker.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("worker move must not delete source after target replacement");
    if (!DeleteFileW(targetForWorker.c_str()) ||
        !MoveFileExW(asideForWorker.c_str(), targetForWorker.c_str(), 0))
        return Fail("restore copied target identity");

    // Replace the *source* after copying. Its original identity is now
    // at a different filename, and the replacement must survive.
    if (!MoveFileExW(sourceForWorker.c_str(), asideForWorker.c_str(), 0) ||
        !CopyFileW(targetForWorker.c_str(), sourceForWorker.c_str(), TRUE))
        return Fail("stage replaced Unicode worker source");
    if (Salamander::TryCompleteUnicodeMoveAfterCopy(
            ownedWorkerSource, ownedWorkerTarget, expectedWorkerSource,
            expectedWorkerTarget, operationError) ||
        operationError != ERROR_FILE_INVALID ||
        GetFileAttributesW(sourceForWorker.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("worker move must not delete unrelated source replacement");
    if (!DeleteFileW(sourceForWorker.c_str()) ||
        !MoveFileExW(asideForWorker.c_str(), sourceForWorker.c_str(), 0))
        return Fail("restore original Unicode move source");

    // Same file ID and size are NOT sufficient: another writer may alter
    // bytes in place after the worker completed. The finalizer must compare
    // the actual streams while both handles deny writes.
    HANDLE alteredTarget = CreateFileW(targetForWorker.c_str(), GENERIC_WRITE,
                                       0, nullptr, OPEN_EXISTING,
                                       FILE_ATTRIBUTE_NORMAL, nullptr);
    if (alteredTarget == INVALID_HANDLE_VALUE)
        return Fail("open worker destination for in-place byte corruption test");
    const char corrupted = 'X';
    DWORD alteredCount = 0;
    const bool altered = WriteFile(alteredTarget, &corrupted, 1, &alteredCount, nullptr) &&
                         alteredCount == 1;
    CloseHandle(alteredTarget);
    if (!altered)
        return Fail("corrupt one byte without changing Unicode target identity");
    if (Salamander::TryCompleteUnicodeMoveAfterCopy(
            ownedWorkerSource, ownedWorkerTarget, expectedWorkerSource,
            expectedWorkerTarget, operationError) ||
        operationError != ERROR_CRC ||
        GetFileAttributesW(sourceForWorker.c_str()) == INVALID_FILE_ATTRIBUTES)
        return Fail("worker move must reject same-sized but byte-different destination");
    alteredTarget = CreateFileW(targetForWorker.c_str(), GENERIC_WRITE,
                                0, nullptr, OPEN_EXISTING,
                                FILE_ATTRIBUTE_NORMAL, nullptr);
    if (alteredTarget == INVALID_HANDLE_VALUE)
        return Fail("reopen owned Unicode destination for test restoration");
    alteredCount = 0;
    const char originalByte = workerPayload[0];
    const bool restored = WriteFile(alteredTarget, &originalByte, 1,
                                    &alteredCount, nullptr) && alteredCount == 1;
    CloseHandle(alteredTarget);
    if (!restored)
        return Fail("restore exact Unicode destination bytes before success test");

    // Both identities and all data bytes now match. A successful move
    // removes exactly the original source and retains the target.
    if (!Salamander::TryCompleteUnicodeMoveAfterCopy(
            ownedWorkerSource, ownedWorkerTarget, expectedWorkerSource,
            expectedWorkerTarget, operationError) ||
        operationError != ERROR_SUCCESS ||
        GetFileAttributesW(sourceForWorker.c_str()) != INVALID_FILE_ATTRIBUTES)
        return Fail("worker Unicode move finalizer deletes exact source");
    HANDLE verifiedTarget = CreateFileW(targetForWorker.c_str(), GENERIC_READ,
                                        FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (verifiedTarget == INVALID_HANDLE_VALUE)
        return Fail("open finalized Unicode move copy");
    char workerBytes[sizeof(workerPayload)]{};
    DWORD workerRead = 0;
    const bool workerSameBytes = ReadFile(
        verifiedTarget, workerBytes, sizeof(workerBytes), &workerRead, nullptr) &&
        workerRead == sizeof(workerPayload) &&
        memcmp(workerBytes, workerPayload, sizeof(workerPayload)) == 0;
    CloseHandle(verifiedTarget);
    if (!workerSameBytes || !DeleteFileW(targetForWorker.c_str()))
        return Fail("finalized Unicode background move retained original data");
    std::puts("PASS: cross-volume worker finalizer rejects changed source/target identity and preserves exact bytes");

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
