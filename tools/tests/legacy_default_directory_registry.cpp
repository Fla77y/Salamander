// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Uses only its own disposable HKCU subkey, never the user's Salamander configuration.
#include "../../src/common/legacy_default_directory_registry.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace
{
int Fail(const char* test)
{
    std::fprintf(stderr, "FAIL: legacy default-directory registry: %s\n", test);
    return 1;
}

class TestRegistryKey
{
public:
    explicit TestRegistryKey(const std::string& path) : path_(path), key_(nullptr)
    {
        if (RegCreateKeyExA(HKEY_CURRENT_USER, path_.c_str(), 0, nullptr,
                            REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS,
                            nullptr, &key_, nullptr) != ERROR_SUCCESS)
            key_ = nullptr;
    }

    ~TestRegistryKey()
    {
        if (key_ != nullptr)
            RegCloseKey(key_);
        RegDeleteKeyA(HKEY_CURRENT_USER, path_.c_str());
    }

    TestRegistryKey(const TestRegistryKey&) = delete;
    TestRegistryKey& operator=(const TestRegistryKey&) = delete;

    HKEY Get() const { return key_; }

private:
    std::string path_;
    HKEY key_;
};

bool Put(HKEY key, const char* name, const std::string& value,
         DWORD type = REG_SZ, bool terminate = true)
{
    const DWORD size = static_cast<DWORD>(value.size() + (terminate ? 1 : 0));
    return RegSetValueExA(key, name, 0, type,
                          reinterpret_cast<const BYTE*>(value.c_str()), size) == ERROR_SUCCESS;
}

bool Retained(HKEY key, const char* name, const std::string& original)
{
    DWORD type = REG_NONE;
    DWORD size = 0;
    if (RegQueryValueExA(key, name, nullptr, &type, nullptr, &size) != ERROR_SUCCESS ||
        type != REG_SZ || static_cast<std::size_t>(size) != original.size() + 1)
        return false;

    std::vector<BYTE> stored(size);
    if (RegQueryValueExA(key, name, nullptr, &type, stored.data(), &size) != ERROR_SUCCESS)
        return false;
    return std::memcmp(stored.data(), original.c_str(), size) == 0;
}
} // namespace

int main()
{
    const std::string keyPath = "Software\\OpenSalamanderDefaultDirTest-" +
                                std::to_string(GetCurrentProcessId());
    TestRegistryKey registry(keyPath);
    if (registry.Get() == nullptr)
        return Fail("create disposable HKCU key");

    char directory[MAX_PATH] = "C:\\";
    if (Salamander::ReadLegacyDefaultDirectory(
            registry.Get(), 'C', directory) != Salamander::LegacyDefaultDirectoryStatus::Missing ||
        std::strcmp(directory, "C:\\") != 0)
        return Fail("missing drive retains fallback");

    if (!Put(registry.Get(), "C", "C:\\short\\folder") ||
        Salamander::ReadLegacyDefaultDirectory(
            registry.Get(), 'C', directory) != Salamander::LegacyDefaultDirectoryStatus::Loaded ||
        std::strcmp(directory, "C:\\short\\folder") != 0)
        return Fail("normal drive path loads exactly");

    // 259 bytes of path + terminator is the largest legacy buffer entry.
    const std::string boundary = "C:\\" + std::string(250, 'x') + "\\" + std::string(5, 'y');
    if (boundary.size() + 1 != static_cast<std::size_t>(MAX_PATH) || !Put(registry.Get(), "C", boundary) ||
        Salamander::ReadLegacyDefaultDirectory(
            registry.Get(), 'C', directory) != Salamander::LegacyDefaultDirectoryStatus::Loaded ||
        std::strcmp(directory, boundary.c_str()) != 0)
        return Fail("MAX_PATH-sized value loads without truncation");

    // The original 234 startup failure is reproduced by an oversized value.
    const std::string longPath = "D:\\" + std::string(340, 'q');
    char fallback[MAX_PATH] = "D:\\";
    if (!Put(registry.Get(), "D", longPath) ||
        Salamander::ReadLegacyDefaultDirectory(
            registry.Get(), 'D', fallback) != Salamander::LegacyDefaultDirectoryStatus::Preserve ||
        std::strcmp(fallback, "D:\\") != 0 ||
        !Retained(registry.Get(), "D", longPath))
        return Fail("oversized value preserved without buffer modification");

    if (!Put(registry.Get(), "E", "E:\\not-a-string", REG_BINARY) ||
        Salamander::ReadLegacyDefaultDirectory(
            registry.Get(), 'E', fallback) != Salamander::LegacyDefaultDirectoryStatus::Preserve)
        return Fail("wrong type refused");

    if (!Put(registry.Get(), "F", "F:\\missing-terminator", REG_SZ, false) ||
        Salamander::ReadLegacyDefaultDirectory(
            registry.Get(), 'F', fallback) != Salamander::LegacyDefaultDirectoryStatus::Preserve)
        return Fail("unterminated value refused");

    if (!Put(registry.Get(), "G", "H:\\wrong-drive") ||
        Salamander::ReadLegacyDefaultDirectory(
            registry.Get(), 'G', fallback) != Salamander::LegacyDefaultDirectoryStatus::Preserve)
        return Fail("wrong-drive path refused");

    if (std::strcmp(fallback, "D:\\") != 0)
        return Fail("refusals leave destination unchanged");

    std::puts("PASS: real HKCU registry reads accept short paths and preserve oversized or malformed values");
    return 0;
}
