// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/common/win32_plugin_module_path.h"
#include <algorithm>
#include <cstdio>
#include <string>

namespace
{
bool ModulePath_WhenTruncated_RetriesWithoutLosingUtf16()
{
    // Arrange
    const std::wstring expected = L"C:\\東京\\" + std::wstring(700, L'x') + L"\\😀.exe";
    std::wstring output = L"stale";
    DWORD error = ERROR_SUCCESS;
    unsigned calls = 0;
    const auto query = [&](HMODULE, wchar_t* buffer, DWORD capacity) -> DWORD
    {
        ++calls;
        if (expected.size() >= capacity)
        {
            std::fill_n(buffer, capacity, L'x'); // Truncation need not terminate.
            return capacity;
        }
        std::copy(expected.begin(), expected.end(), buffer);
        buffer[expected.size()] = 0;
        return static_cast<DWORD>(expected.size());
    };
    // Act
    const bool accepted = Salamander::PluginModulePathDetail::ReadModulePath(nullptr, output, error, query);
    // Assert
    return accepted && error == ERROR_SUCCESS && output == expected && calls == 3;
}

bool ModulePath_WhenQueryFails_PreservesErrorAndClearsOutput()
{
    // Arrange
    std::wstring output = L"stale";
    DWORD error = ERROR_SUCCESS;
    const auto query = [](HMODULE, wchar_t*, DWORD) -> DWORD
    {
        SetLastError(ERROR_ACCESS_DENIED);
        return 0;
    };
    // Act
    const bool accepted = Salamander::PluginModulePathDetail::ReadModulePath(nullptr, output, error, query);
    // Assert
    return !accepted && error == ERROR_ACCESS_DENIED && output.empty();
}

bool ModulePath_WhenAlwaysTruncated_StopsAtNamespaceLimit()
{
    // Arrange
    std::wstring output = L"stale";
    DWORD error = ERROR_SUCCESS;
    unsigned calls = 0;
    const auto query = [&](HMODULE, wchar_t*, DWORD capacity) -> DWORD
    {
        ++calls;
        return capacity;
    };
    // Act
    const bool accepted = Salamander::PluginModulePathDetail::ReadModulePath(nullptr, output, error, query);
    // Assert
    return !accepted && error == ERROR_FILENAME_EXCED_RANGE && output.empty() && calls == 8;
}

bool PluginPath_WhenRelative_UsesHostDirectory()
{
    // Arrange
    std::wstring host;
    std::wstring output;
    DWORD error = ERROR_SUCCESS;
    if (!Salamander::TryGetModulePath(nullptr, host, error))
        return false;
    const auto separator = host.find_last_of(L'\\');
    std::wstring expected;
    if (!Salamander::PluginModulePathDetail::MakeLoaderPath(
            host.substr(0, separator + 1) + L"plugins\\7zip\\7zip.spl", expected, error))
        return false;
    // Act
    const bool accepted = Salamander::TryResolvePluginModulePath(nullptr, "7zip\\7zip.spl", output, error);
    // Assert
    return accepted && error == ERROR_SUCCESS && output == expected;
}

bool LoaderPath_WhenUnicodeLongOrUnc_PreservesIdentity()
{
    // Arrange
    const std::wstring path = L"C:\\東京\\" + std::wstring(200, L'a') +
        L"\\" + std::wstring(200, L'b') + L"\\😀.spl";
    std::wstring output;
    DWORD error = ERROR_SUCCESS;
    // Act / Assert
    if (!Salamander::PluginModulePathDetail::MakeLoaderPath(path, output, error) ||
        output != L"\\\\?\\" + path || error != ERROR_SUCCESS)
        return false;
    return Salamander::PluginModulePathDetail::MakeLoaderPath(
               L"\\\\server\\share\\東京\\😀.spl", output, error) &&
           output == L"\\\\?\\UNC\\server\\share\\東京\\😀.spl";
}

bool LoaderPath_WhenExtendedOrAliased_PreservesNamespace()
{
    // Arrange
    std::wstring output = L"\\\\?\\C:\\東京\\trailing.\\😀.spl";
    const std::wstring expected(output);
    DWORD error = ERROR_SUCCESS;
    // Act
    const bool accepted = Salamander::PluginModulePathDetail::MakeLoaderPath(output, output, error);
    // Assert
    return accepted && output == expected && error == ERROR_SUCCESS;
}

bool PluginPath_WhenInvalid_RefusesWithoutUsingWorkingDirectory()
{
    // Arrange
    std::wstring output = L"stale";
    DWORD error = ERROR_SUCCESS;
    // Act / Assert
    if (Salamander::TryResolvePluginModulePath(nullptr, nullptr, output, error) ||
        error != ERROR_INVALID_PARAMETER || !output.empty())
        return false;
    if (Salamander::TryResolvePluginModulePath(nullptr, "C:relative.spl", output, error) ||
        error != ERROR_INVALID_NAME || !output.empty())
        return false;
    return !Salamander::PluginModulePathDetail::MakeLoaderPath(L"relative.spl", output, error) &&
           error == ERROR_INVALID_NAME && output.empty();
}

bool LanguagePath_WhenTraversalRequested_RefusesWithExactError()
{
    // Arrange
    std::wstring output = L"stale";
    DWORD error = ERROR_SUCCESS;
    // Act / Assert
    if (Salamander::TryResolveLanguageModulePath(nullptr, "..\\other.slg", output, error) ||
        error != ERROR_INVALID_NAME || !output.empty())
        return false;
    const std::wstring embeddedNull(L"C:\\safe.spl\0other.spl", 21);
    return !Salamander::PluginModulePathDetail::MakeLoaderPath(embeddedNull, output, error) &&
           error == ERROR_INVALID_NAME && output.empty();
}

bool LanguageName_WhenNotExactlyRepresentable_RefusesAlias()
{
    // Arrange
    std::string encoded;
    DWORD error = ERROR_SUCCESS;
    // Act / Assert
    if (!Salamander::TryEncodeLegacyLanguageName(L"english.slg", encoded, error) ||
        encoded != "english.slg" || error != ERROR_SUCCESS)
        return false;
    const wchar_t* const original = L"東京-😀.slg";
    if (!Salamander::TryEncodeLegacyLanguageName(original, encoded, error))
        return encoded.empty() && (error == ERROR_NO_UNICODE_TRANSLATION || error == ERROR_FILENAME_EXCED_RANGE);
    std::wstring roundTrip;
    return Salamander::PluginModulePathDetail::DecodeLegacyName(encoded.c_str(), roundTrip, error) &&
           roundTrip == original;
}

bool ModulePresence_WhenFailureIsNotMissing_PreservesConfiguration()
{
    // Arrange
    const DWORD uncertainErrors[] = {ERROR_ACCESS_DENIED, ERROR_BAD_NETPATH,
        ERROR_NOT_READY, ERROR_INVALID_NAME, ERROR_FILENAME_EXCED_RANGE, ERROR_BAD_PATHNAME};
    // Act / Assert: none authorizes removing plugin configuration.
    for (DWORD error : uncertainErrors)
    {
        if (Salamander::ClassifyPluginModulePresence(INVALID_FILE_ATTRIBUTES, error) !=
            Salamander::PluginModulePresence::Unknown)
            return false;
    }
    DWORD error = ERROR_SUCCESS;
    return Salamander::ProbePluginModulePresence(nullptr, "C:relative.spl", error) ==
               Salamander::PluginModulePresence::Unknown && error == ERROR_INVALID_NAME;
}

bool ModuleSuffix_WhenCaseDiffersOrSuffixIsLong_MatchesExactSuffixOnly()
{
    // Arrange
    DWORD error = ERROR_SUCCESS;
    const std::string name = std::string(200, 'x') + "\\" + std::string(100, 'y') + "\\probe.spl";
    // Act / Assert
    return Salamander::PluginModulePathHasSuffix(nullptr, "7zip\\7zip.spl", "7ZIP\\7ZIP.SPL", error) &&
        error == ERROR_SUCCESS &&
        Salamander::PluginModulePathHasSuffix(nullptr, name.c_str(), "probe.spl", error) &&
        !Salamander::PluginModulePathHasSuffix(nullptr, name.c_str(), "other.spl", error) &&
        error == ERROR_SUCCESS &&
        Salamander::PluginModulePathHasSuffix(nullptr, "probe.spl", "", error);
}

struct ModuleFixture
{
    std::vector<std::wstring> directories;
    std::wstring file;
    bool ownsFile = false;
    HMODULE module = nullptr;

    ~ModuleFixture()
    {
        if (module != nullptr)
            FreeLibrary(module);
        if (ownsFile)
            DeleteFileW(file.c_str());
        for (auto it = directories.rbegin(); it != directories.rend(); ++it)
            RemoveDirectoryW(it->c_str());
    }

    bool AddDirectory(const std::wstring& plain)
    {
        std::wstring extended;
        DWORD error = ERROR_SUCCESS;
        if (!Salamander::PluginModulePathDetail::MakeLoaderPath(plain, extended, error) ||
            !CreateDirectoryW(extended.c_str(), nullptr))
            return false;
        directories.push_back(extended);
        return true;
    }
};

bool LoadedModule_WhenUnderLongUnicodeDirectory_ResolvesOwnLanguageDirectory()
{
    // Arrange: a private PE copy beside this test executable. Mapping an EXE
    // with LoadLibrary does not run it or call plugin initialization code.
    std::wstring ownPath;
    DWORD error = ERROR_SUCCESS;
    if (!Salamander::TryGetModulePath(nullptr, ownPath, error))
        return false;
    ModuleFixture fixture;
    std::wstring directory = ownPath.substr(0, ownPath.find_last_of(L'\\') + 1) +
        L"module-fixture-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
    if (!fixture.AddDirectory(directory))
        return false;
    for (int i = 0; i < 3; ++i)
    {
        directory += L"\\東京-😀-" + std::wstring(70, L'x');
        if (!fixture.AddDirectory(directory))
            return false;
    }
    if (directory.size() <= MAX_PATH ||
        !Salamander::PluginModulePathDetail::MakeLoaderPath(
            directory + L"\\probe.spl", fixture.file, error) ||
        !CopyFileW(ownPath.c_str(), fixture.file.c_str(), TRUE))
        return false;
    fixture.ownsFile = true;
    // Act: use the real Windows loader and real growing module-name query.
    fixture.module = LoadLibraryW(fixture.file.c_str());
    std::wstring modulePath, languagePath;
    if (fixture.module == nullptr || !Salamander::TryGetModulePath(fixture.module, modulePath, error))
        return false;
    // Assert: resource lookup follows the loaded module, not the host or CWD.
    if (Salamander::ProbePluginModulePath(fixture.file, error) !=
        Salamander::PluginModulePresence::Present || error != ERROR_SUCCESS)
        return false;
    if (Salamander::ProbePluginModulePath(fixture.directories.back() + L"\\missing.spl", error) !=
        Salamander::PluginModulePresence::Missing || error != ERROR_FILE_NOT_FOUND)
        return false;
    return modulePath == fixture.file &&
           Salamander::TryResolveLanguageModulePath(fixture.module, "english.slg", languagePath, error) &&
           languagePath == fixture.directories.back() + L"\\lang\\english.slg";
}
}

int main()
{
    if (!ModulePath_WhenTruncated_RetriesWithoutLosingUtf16() ||
        !ModulePath_WhenQueryFails_PreservesErrorAndClearsOutput() ||
        !ModulePath_WhenAlwaysTruncated_StopsAtNamespaceLimit() ||
        !PluginPath_WhenRelative_UsesHostDirectory() ||
        !LoaderPath_WhenUnicodeLongOrUnc_PreservesIdentity() ||
        !LoaderPath_WhenExtendedOrAliased_PreservesNamespace() ||
        !PluginPath_WhenInvalid_RefusesWithoutUsingWorkingDirectory() ||
        !LanguagePath_WhenTraversalRequested_RefusesWithExactError() ||
        !LanguageName_WhenNotExactlyRepresentable_RefusesAlias() ||
        !ModulePresence_WhenFailureIsNotMissing_PreservesConfiguration() ||
        !ModuleSuffix_WhenCaseDiffersOrSuffixIsLong_MatchesExactSuffixOnly() ||
        !LoadedModule_WhenUnderLongUnicodeDirectory_ResolvesOwnLanguageDirectory())
        return std::puts("FAIL: dynamic UTF-16 plugin module path contract"), 1;
    return std::puts("PASS: dynamic W module paths, truncation, errors, UNC, namespace and plugin resolution"), 0;
}
