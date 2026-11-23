// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_long_path.h"

#include <windows.h>
#include <algorithm>
#include <new>
#include <string>
#include <vector>

namespace Salamander
{
namespace PluginModulePathDetail
{
// Query has GetModuleFileNameW's contract. The injectable query permits exact
// truncation/error boundary tests without changing a real process image path.
template <typename Query>
bool ReadModulePath(HMODULE module, std::wstring& output, DWORD& error, Query query)
{
    output.clear();
    constexpr std::size_t maximumCapacity = 32768;
    std::vector<wchar_t> buffer(MAX_PATH);
    for (;;)
    {
        const DWORD length = query(module, buffer.data(), static_cast<DWORD>(buffer.size()));
        if (length == 0)
        {
            error = GetLastError();
            return false;
        }
        if (length < buffer.size())
        {
            output.assign(buffer.data(), length);
            error = ERROR_SUCCESS;
            return true;
        }
        if (buffer.size() == maximumCapacity)
        {
            error = ERROR_FILENAME_EXCED_RANGE;
            return false;
        }
        const std::size_t next = buffer.size() * 2;
        buffer.resize(next < maximumCapacity ? next : maximumCapacity);
    }
}

inline bool DecodeLegacyName(const char* name, std::wstring& output, DWORD& error)
{
    output.clear();
    if (name == nullptr || *name == 0)
    {
        error = ERROR_INVALID_PARAMETER;
        return false;
    }
    const int size = MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS, name, -1, nullptr, 0);
    if (size == 0)
    {
        error = GetLastError();
        return false;
    }
    output.resize(static_cast<std::size_t>(size));
    if (MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS, name, -1, &output[0], size) != size)
    {
        error = GetLastError();
        output.clear();
        return false;
    }
    output.pop_back();
    return true;
}

inline bool IsAbsolute(const std::wstring& path)
{
    return (path.size() >= 3 && path[1] == L':' && path[2] == L'\\') ||
           (path.size() >= 2 && path[0] == L'\\' && path[1] == L'\\');
}

// Inputs are already absolute. Resolve normal Win32 dot segments without
// involving the process working directory. Extended paths retain their exact
// namespace semantics and are validated without GetFullPathName normalization.
inline bool MakeLoaderPath(const std::wstring& input, std::wstring& output, DWORD& error)
{
    const std::wstring path(input);
    output.clear();
    if (path.empty() || path.find(L'\0') != std::wstring::npos)
    {
        error = ERROR_INVALID_NAME;
        return false;
    }
    if (path.compare(0, 4, L"\\\\?\\") == 0)
    {
        const std::wstring plain = path.compare(0, 8, L"\\\\?\\UNC\\") == 0
            ? L"\\\\" + path.substr(8) : path.substr(4);
        return TryMakeExtendedLengthPath(plain.c_str(), output, error);
    }
    if (!IsAbsolute(path))
    {
        error = ERROR_INVALID_NAME;
        return false;
    }
    const DWORD capacity = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (capacity == 0)
    {
        error = GetLastError();
        return false;
    }
    if (capacity > 32768)
    {
        error = ERROR_FILENAME_EXCED_RANGE;
        return false;
    }
    std::vector<wchar_t> normalized(capacity);
    const DWORD length = GetFullPathNameW(path.c_str(), capacity, normalized.data(), nullptr);
    if (length == 0)
    {
        error = GetLastError();
        return false;
    }
    if (length >= capacity)
    {
        error = ERROR_FILENAME_EXCED_RANGE;
        return false;
    }
    return TryMakeExtendedLengthPath(normalized.data(), output, error);
}
} // namespace PluginModulePathDetail

inline bool TryGetModulePath(HMODULE module, std::wstring& output, DWORD& error)
{
    return PluginModulePathDetail::ReadModulePath(module, output, error, ::GetModuleFileNameW);
}

// Module-relative resources use the actual loaded module's W directory, never
// an ACP reconstruction. Absolute paths keep their existing explicit location.
inline bool TryResolveModuleRelativePath(HMODULE module, const std::wstring& input,
                                         std::wstring& output, DWORD& error)
{
    const std::wstring name(input);
    if (PluginModulePathDetail::IsAbsolute(name))
        return PluginModulePathDetail::MakeLoaderPath(name, output, error);
    output.clear();
    if (name.empty() || name[0] == L'\\' || name.find(L':') != std::wstring::npos)
    {
        error = ERROR_INVALID_NAME;
        return false;
    }
    std::wstring modulePath;
    if (!TryGetModulePath(module, modulePath, error))
        return false;
    const std::size_t separator = modulePath.find_last_of(L'\\');
    if (separator == std::wstring::npos)
    {
        error = ERROR_INVALID_NAME;
        return false;
    }
    return PluginModulePathDetail::MakeLoaderPath(
        modulePath.substr(0, separator + 1) + name, output, error);
}

// DLLName remains the legacy persisted ACP setting. Decode it once and anchor
// relative entries at the host's plugins directory, preserving the plugin ABI.
// This cannot recover characters already lost when an absolute setting was saved.
inline bool TryResolvePluginModulePath(HMODULE host, const char* dllName,
                                       std::wstring& output, DWORD& error)
{
    output.clear();
    std::wstring name;
    if (!PluginModulePathDetail::DecodeLegacyName(dllName, name, error))
        return false;
    if (name.compare(0, 4, L"\\\\?\\") != 0)
        std::replace(name.begin(), name.end(), L'/', L'\\');
    if (!PluginModulePathDetail::IsAbsolute(name))
        name.insert(0, L"plugins\\");
    return TryResolveModuleRelativePath(host, name, output, error);
}

// The legacy setting is a leaf, not a path relative to an arbitrary directory.
inline bool TryResolveLanguageModulePath(HMODULE module, const char* languageName,
                                         std::wstring& output, DWORD& error)
{
    output.clear();
    std::wstring name;
    if (!PluginModulePathDetail::DecodeLegacyName(languageName, name, error))
        return false;
    if (name == L"." || name == L".." || name.find_first_of(L"\\/:*?") != std::wstring::npos)
    {
        error = ERROR_INVALID_NAME;
        return false;
    }
    return TryResolveModuleRelativePath(module, L"lang\\" + name, output, error);
}

enum class PluginModulePresence
{
    Present,
    Missing,
    Unknown
};

// A failed path conversion, explicit network error or access denial is not
// evidence that a plugin was uninstalled. Never delete its configuration then.
inline PluginModulePresence ClassifyPluginModulePresence(DWORD attributes, DWORD error)
{
    if (attributes != INVALID_FILE_ATTRIBUTES)
        return PluginModulePresence::Present;
    return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND
        ? PluginModulePresence::Missing : PluginModulePresence::Unknown;
}

// path must be the fully resolved W identity from the resolver above.
inline PluginModulePresence ProbePluginModulePath(const std::wstring& path, DWORD& error)
{
    const DWORD attributes = GetFileAttributesW(path.c_str());
    error = attributes == INVALID_FILE_ATTRIBUTES ? GetLastError() : ERROR_SUCCESS;
    return ClassifyPluginModulePresence(attributes, error);
}

inline PluginModulePresence ProbePluginModulePresence(HMODULE host, const char* dllName, DWORD& error)
{
    try
    {
        std::wstring path;
        if (!TryResolvePluginModulePath(host, dllName, path, error))
            return PluginModulePresence::Unknown;
        return ProbePluginModulePath(path, error);
    }
    catch (const std::bad_alloc&)
    {
        error = ERROR_NOT_ENOUGH_MEMORY;
        return PluginModulePresence::Unknown;
    }
}

inline bool PluginModulePathHasSuffix(HMODULE host, const char* dllName,
                                      const char* suffix, DWORD& error)
{
    if (suffix == nullptr)
    {
        error = ERROR_INVALID_PARAMETER;
        return false;
    }
    // Preserve the legacy helper's empty-suffix semantics.
    if (*suffix == 0)
    {
        error = ERROR_SUCCESS;
        return true;
    }
    try
    {
        std::wstring path, wideSuffix;
        if (!TryResolvePluginModulePath(host, dllName, path, error) ||
            !PluginModulePathDetail::DecodeLegacyName(suffix, wideSuffix, error))
            return false;
        error = ERROR_SUCCESS;
        return path.size() >= wideSuffix.size() &&
            CompareStringOrdinal(path.data() + path.size() - wideSuffix.size(),
                static_cast<int>(wideSuffix.size()), wideSuffix.data(),
                static_cast<int>(wideSuffix.size()), TRUE) == CSTR_EQUAL;
    }
    catch (const std::bad_alloc&)
    {
        error = ERROR_NOT_ENOUGH_MEMORY;
        return false;
    }
}

// The existing language selector persists ACP leaves into MAX_PATH buffers.
// Refuse unrepresentable names explicitly; never select a best-fit alias.
inline bool TryEncodeLegacyLanguageName(const wchar_t* name, std::string& output, DWORD& error)
{
    output.clear();
    if (name == nullptr || *name == 0)
    {
        error = ERROR_INVALID_PARAMETER;
        return false;
    }
    const int size = WideCharToMultiByte(CP_ACP, 0, name, -1, nullptr, 0, nullptr, nullptr);
    if (size == 0)
    {
        error = GetLastError();
        return false;
    }
    if (size > MAX_PATH)
    {
        error = ERROR_FILENAME_EXCED_RANGE;
        return false;
    }
    output.resize(static_cast<std::size_t>(size));
    if (WideCharToMultiByte(CP_ACP, 0, name, -1, &output[0], size, nullptr, nullptr) != size)
    {
        error = GetLastError();
        output.clear();
        return false;
    }
    output.pop_back();
    std::wstring roundTrip;
    if (!PluginModulePathDetail::DecodeLegacyName(output.c_str(), roundTrip, error) || roundTrip != name)
    {
        output.clear();
        error = ERROR_NO_UNICODE_TRANSLATION;
        return false;
    }
    error = ERROR_SUCCESS;
    return true;
}
} // namespace Salamander
