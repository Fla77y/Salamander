// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/common/win32_worker_copy_io.h"
#include <objbase.h>
#include <cassert>
#include <cstdio>
#include <thread>
#include <cstdlib>
#ifdef _DEBUG
#include <crtdbg.h>
#endif

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ole32.lib")

namespace Io = Salamander::WorkerCopyIo;

namespace
{
std::wstring Extended(const std::wstring& path)
{
    std::wstring result;
    DWORD error;
    assert(Salamander::TryMakeExtendedLengthPath(path.c_str(), result, error));
    return result;
}

Salamander::Utf16DiskPath Owned(const std::wstring& path)
{
    Salamander::Utf16DiskPath result;
    Salamander::Utf16PathError error;
    assert(Salamander::Utf16DiskPath::TryCreateAbsolute(std::u16string(path.begin(), path.end()), result, error));
    return result;
}

struct Fixture
{
    std::vector<std::wstring> Directories;
    std::wstring Source, Target;
    Salamander::WorkerCopyPathStore Store;
    Salamander::WorkerCopyPaths* Paths;

    Fixture()
    {
        wchar_t module[32768];
        const DWORD length = GetModuleFileNameW(nullptr, module, _countof(module));
        assert(length > 0 && length < _countof(module));
        std::wstring root(module, length);
        root.resize(root.find_last_of(L'\\') + 1);
        GUID id;
        assert(SUCCEEDED(CoCreateGuid(&id)));
        wchar_t text[40];
        assert(StringFromGUID2(id, text, _countof(text)) > 0);
        root += L"worker-copy-" + std::wstring(text);
        for (int level = 0; level < 4; ++level)
        {
            assert(CreateDirectoryW(Extended(root).c_str(), nullptr));
            Directories.push_back(root);
            if (level != 3)
                root += L"\\東京_😀_" + std::wstring(80, L'a');
        }
        Source = root + L"\\元_😀.bin";
        Target = root + L"\\先_😀.bin";
        assert(Source.size() > MAX_PATH);
        HANDLE source = CreateFileW(Extended(Source).c_str(), GENERIC_WRITE, 0, nullptr,
            CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
        assert(source != INVALID_HANDLE_VALUE);
        DWORD written;
        assert(WriteFile(source, "data", 4, &written, nullptr) && written == 4);
        assert(CloseHandle(source));
        DWORD error;
        Paths = Store.Add(Owned(Source), Owned(Target), error);
        assert(Paths != nullptr);
    }

    ~Fixture()
    {
        DeleteFileW(Extended(Target).c_str());
        DeleteFileW(Extended(Source).c_str());
        for (auto directory = Directories.rbegin(); directory != Directories.rend(); ++directory)
            assert(RemoveDirectoryW(Extended(*directory).c_str()));
    }
};

bool MakeFixtureHardLink(const Fixture& fixture)
{
    const BOOL created = CreateHardLinkW(Extended(fixture.Target).c_str(), Extended(fixture.Source).c_str(), nullptr);
    const DWORD error = created ? ERROR_SUCCESS : GetLastError();
    if (!created)
        std::fprintf(stderr, "Hard-link fixture setup failed: Win32 %lu\n", error);
    return created != FALSE;
}

void Io_WhenTokensAreBound_UsesOriginalWidePathsAndMetadata()
{
    // Arrange
    Fixture fixture;
    Io::Scope scope(fixture.Paths);
    const char* sourceName = fixture.Paths->SourceToken.c_str();
    const char* targetName = fixture.Paths->TargetToken.c_str();
    HANDLE source = Io::OpenRaw(sourceName, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_EXISTING, 0, nullptr);
    assert(source != INVALID_HANDLE_VALUE && fixture.Paths->HasSourceIdentity);
    // Act
    HANDLE target = Io::OpenRaw(targetName, GENERIC_WRITE, 0, nullptr, CREATE_NEW, 0, nullptr);
    assert(target != INVALID_HANDLE_VALUE);
    char bytes[4];
    DWORD count;
    assert(ReadFile(source, bytes, sizeof(bytes), &count, nullptr) && count == sizeof(bytes));
    assert(WriteFile(target, bytes, sizeof(bytes), &count, nullptr) && count == sizeof(bytes));
    assert(Io::SetAttributes(targetName, FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_ARCHIVE));
    // Assert: metadata probes must also work while our target is open exclusively.
    assert((Io::Attributes(targetName) & FILE_ATTRIBUTE_HIDDEN) != 0);
    assert(CloseHandle(target) && CloseHandle(source));
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    PACL dacl = nullptr;
    assert(Io::GetSecurity(const_cast<char*>(sourceName), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
        nullptr, nullptr, &dacl, nullptr, &descriptor) == ERROR_SUCCESS);
    assert(Io::SetSecurity(const_cast<char*>(targetName), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
        nullptr, nullptr, dacl, nullptr) == ERROR_SUCCESS);
    LocalFree(descriptor);
}

void Io_WhenCreatingAnAlternateStream_RefusesToReplaceExistingData()
{
    // Arrange
    Fixture fixture;
    Io::Scope scope(fixture.Paths);
    const auto streamPath = Extended(fixture.Source) + L":識別_😀:$DATA";

    // Act: create a stream on a file whose main stream already exists.
    HANDLE stream = Io::CreateNewAlternateStream(streamPath.c_str());
    assert(stream != INVALID_HANDLE_VALUE);
    DWORD count;
    assert(WriteFile(stream, "ads", 3, &count, nullptr) && count == 3);
    assert(CloseHandle(stream));

    // Assert: a second create fails without changing the existing stream.
    assert(Io::CreateNewAlternateStream(streamPath.c_str()) == INVALID_HANDLE_VALUE);
    assert(GetLastError() == ERROR_FILE_EXISTS);
    stream = CreateFileW(streamPath.c_str(), GENERIC_READ, FILE_SHARE_READ,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    assert(stream != INVALID_HANDLE_VALUE);
    char bytes[3];
    assert(ReadFile(stream, bytes, sizeof(bytes), &count, nullptr) && count == sizeof(bytes));
    assert(memcmp(bytes, "ads", sizeof(bytes)) == 0);
    assert(CloseHandle(stream));
}

void Io_WhenUnknownOrSourceMutation_RefusesWithoutChangingFiles()
{
    // Arrange
    Fixture fixture;
    Io::Scope scope(fixture.Paths);
    // Act / Assert
    assert(Io::OpenRaw("unknown", GENERIC_READ, 0, nullptr, OPEN_EXISTING, 0, nullptr) == INVALID_HANDLE_VALUE);
    assert(GetLastError() == ERROR_INVALID_NAME);
    assert(Io::OpenRaw(fixture.Paths->SourceToken.c_str(), GENERIC_WRITE, 0,
        nullptr, CREATE_ALWAYS, 0, nullptr) == INVALID_HANDLE_VALUE);
    assert(GetLastError() == ERROR_ACCESS_DENIED);
    assert(!Io::Delete(fixture.Paths->SourceToken.c_str()) && GetLastError() == ERROR_ACCESS_DENIED);
    assert(GetFileAttributesW(Extended(fixture.Source).c_str()) != INVALID_FILE_ATTRIBUTES);
    std::thread other([] { assert(Io::Current == nullptr); });
    other.join();
    {
        Io::Scope nested(nullptr);
        assert(Io::Current == nullptr);
    }
    assert(Io::Current == fixture.Paths);
}

void Io_WhenTargetIsSourceHardLink_NeverTruncatesOrChangesSource()
{
    // Arrange
    Fixture fixture;
    Io::Scope scope(fixture.Paths);
    assert(MakeFixtureHardLink(fixture));
    HANDLE source = Io::OpenRaw(fixture.Paths->SourceToken.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
    assert(source != INVALID_HANDLE_VALUE);
    const DWORD attributes = Io::Attributes(fixture.Paths->SourceToken.c_str());
    // Act / Assert
    assert(Io::OpenRaw(fixture.Paths->TargetToken.c_str(), GENERIC_WRITE, 0, nullptr,
        CREATE_ALWAYS, 0, nullptr) == INVALID_HANDLE_VALUE);
    assert(GetLastError() == ERROR_INVALID_PARAMETER);
    assert(!Io::SetAttributes(fixture.Paths->TargetToken.c_str(), FILE_ATTRIBUTE_READONLY));
    assert(!Io::Delete(fixture.Paths->TargetToken.c_str()));
    assert(Io::Attributes(fixture.Paths->SourceToken.c_str()) == attributes);
    LARGE_INTEGER size;
    assert(GetFileSizeEx(source, &size) && size.QuadPart == 4);
    assert(CloseHandle(source));
}

void Io_WhenSourceReplacedBetweenRetries_RejectsDifferentFileId()
{
    // Arrange
    Fixture fixture;
    Io::Scope scope(fixture.Paths);
    const char* token = fixture.Paths->SourceToken.c_str();
    // Keep the old identity alive before opening it without delete sharing.
    assert(MakeFixtureHardLink(fixture));
    HANDLE source = Io::OpenRaw(token, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_EXISTING, 0, nullptr);
    assert(source != INVALID_HANDLE_VALUE);
    assert(CloseHandle(source));
    assert(DeleteFileW(Extended(fixture.Source).c_str()));
    HANDLE replacement = CreateFileW(Extended(fixture.Source).c_str(), GENERIC_WRITE, 0, nullptr,
        CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    assert(replacement != INVALID_HANDLE_VALUE && CloseHandle(replacement));
    // Act / Assert
    assert(Io::OpenRaw(token, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_EXISTING, 0, nullptr) == INVALID_HANDLE_VALUE);
    assert(GetLastError() == ERROR_FILE_INVALID);
}
} // namespace

int main()
{
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
    _set_error_mode(_OUT_TO_STDERR);
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
#ifdef _DEBUG
    _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
#endif
    Io_WhenTokensAreBound_UsesOriginalWidePathsAndMetadata();
    Io_WhenCreatingAnAlternateStream_RefusesToReplaceExistingData();
    Io_WhenUnknownOrSourceMutation_RefusesWithoutChangingFiles();
    Io_WhenTargetIsSourceHardLink_NeverTruncatesOrChangesSource();
    Io_WhenSourceReplacedBetweenRetries_RejectsDifferentFileId();
    return std::puts("PASS: scoped W worker I/O, metadata, hard-link safety, source identity and thread isolation"), 0;
}
