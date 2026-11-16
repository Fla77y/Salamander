// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_long_directory.h"

#include <windows.h>
#include <atomic>
#include <cstdint>
#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace Salamander
{
// This API never passes filesystem identities through CP_ACP.
// The caller owns cancellation and consumes each result synchronously.
struct UnicodeFindOptions
{
    std::wstring root;
    std::wstring masks = L"*";
    std::wstring content;
    bool includeSubdirectories = true;
    bool includeDirectories = false;
    bool caseSensitiveNames = false;
    std::size_t maximumResults = 100000;
};

struct UnicodeFindHit
{
    std::wstring directory;
    std::wstring name;
    DWORD attributes = 0;
    std::uint64_t size = 0;
    FILETIME lastWrite = {};

    std::wstring FullPath() const
    {
        return directory + (directory.back() == L'\\' ? L"" : L"\\") + name;
    }
};

using UnicodeFindSink = std::function<bool(const UnicodeFindHit&)>;

// Match Win32-style * and ? with UTF-16 strings. Wildcard matching compares
// complete UTF-16 code units and cannot turn an ACP best-fit alias into a hit.
inline bool UnicodeFindWildcardMatch(const wchar_t* pattern,
                                     const wchar_t* value,
                                     bool caseSensitive)
{
    if (pattern == nullptr || value == nullptr)
        return false;
    const wchar_t* lastStar = nullptr;
    const wchar_t* lastMatch = nullptr;
    while (*value)
    {
        if (*pattern == L'*')
        {
            lastStar = pattern++;
            lastMatch = value;
        }
        else if (*pattern == L'?' ||
                 (*pattern && CompareStringOrdinal(pattern, 1, value, 1,
                     caseSensitive ? FALSE : TRUE) == CSTR_EQUAL))
        {
            ++pattern;
            ++value;
        }
        else if (lastStar)
        {
            pattern = lastStar + 1;
            value = ++lastMatch;
        }
        else
            return false;
    }
    while (*pattern == L'*')
        ++pattern;
    return *pattern == 0;
}

// Supports semicolon-separated include masks, with optional exclusion masks
// after a single '|', as in the legacy Find masks field.
inline bool UnicodeFindMatchesMasks(const std::wstring& masks,
                                    const std::wstring& filename,
                                    bool caseSensitive)
{
    const std::size_t pipe = masks.find(L'|');
    const auto matchesAny = [&](std::size_t first, std::size_t last) {
        for (std::size_t start = first; start < last;)
        {
            std::size_t end = masks.find(L';', start);
            if (end == std::wstring::npos || end > last)
                end = last;
            const std::size_t beginTrimmed = masks.find_first_not_of(L" \t", start);
            if (beginTrimmed != std::wstring::npos && beginTrimmed < end)
            {
                const std::size_t endTrimmed = masks.find_last_not_of(L" \t", end - 1);
                const std::wstring mask = masks.substr(beginTrimmed, endTrimmed - beginTrimmed + 1);
                if (mask == L"*.*" ||
                    UnicodeFindWildcardMatch(mask.c_str(), filename.c_str(), caseSensitive))
                    return true;
            }
            start = end + 1;
        }
        return false;
    };
    const std::size_t includeEnd = pipe == std::wstring::npos ? masks.size() : pipe;
    const bool include = includeEnd == 0 || matchesAny(0, includeEnd);
    return include &&
        (pipe == std::wstring::npos || !matchesAny(pipe + 1, masks.size()));
}

// Prepare a nonempty UTF-16 literal for a bytewise streaming content search.
// The search accepts UTF-8 and UTF-16LE text, including matches spanning
// read blocks. A future text-decoder extension may support additional encodings.
inline bool PrepareUnicodeFindNeedles(const std::wstring& value,
                                      std::vector<unsigned char>& utf8,
                                      std::vector<unsigned char>& utf16)
{
    utf8.clear();
    utf16.clear();
    if (value.empty())
        return true;
    const int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        value.c_str(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (bytes <= 0)
        return false;
    utf8.resize(static_cast<std::size_t>(bytes));
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(),
                           static_cast<int>(value.size()),
                           reinterpret_cast<char*>(utf8.data()), bytes,
                           nullptr, nullptr) != bytes)
        return false;
    utf16.reserve(value.size() * 2);
    for (wchar_t unit : value)
    {
        const auto number = static_cast<std::uint16_t>(unit);
        utf16.push_back(static_cast<unsigned char>(number & 0xff));
        utf16.push_back(static_cast<unsigned char>(number >> 8));
    }
    return true;
}

inline bool ContainsUnicodeFindNeedle(const std::vector<unsigned char>& buffer,
                                      const std::vector<unsigned char>& needle)
{
    if (needle.empty())
        return true;
    if (buffer.size() < needle.size())
        return false;
    for (std::size_t i = 0; i + needle.size() <= buffer.size(); ++i)
    {
        bool equal = true;
        for (std::size_t j = 0; j < needle.size(); ++j)
        {
            if (buffer[i + j] != needle[j])
            {
                equal = false;
                break;
            }
        }
        if (equal)
            return true;
    }
    return false;
}

// Scan without mapping untrusted file sizes into the process address space.
// On I/O errors return false: skipped unreadable files must not masquerade
// as a complete, successful "no results" search.
inline bool UnicodeFindFileContains(const std::wstring& absoluteFile,
                                    const std::vector<unsigned char>& utf8,
                                    const std::vector<unsigned char>& utf16,
                                    std::atomic<bool>* cancel,
                                    bool& matched, DWORD& error)
{
    matched = false;
    std::wstring extended;
    if (!TryMakeExtendedLengthPath(absoluteFile.c_str(), extended, error))
        return false;

    HANDLE file = CreateFileW(extended.c_str(), GENERIC_READ, FILE_SHARE_READ |
        FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        error = GetLastError();
        return false;
    }
    struct FileGuard { HANDLE handle; ~FileGuard() { CloseHandle(handle); } } guard{file};

    const std::size_t overlap = (utf8.size() > utf16.size() ? utf8.size() : utf16.size()) - 1;
    std::vector<unsigned char> buffer;
    buffer.reserve(65536 + overlap);
    for (;;)
    {
        if (cancel && cancel->load())
        {
            error = ERROR_CANCELLED;
            return false;
        }
        const std::size_t oldSize = buffer.size();
        buffer.resize(oldSize + 65536);
        DWORD read = 0;
        const BOOL success = ReadFile(file, buffer.data() + oldSize, 65536, &read, nullptr);
        if (!success)
        {
            error = GetLastError();
            return false;
        }
        buffer.resize(oldSize + read);
        if (ContainsUnicodeFindNeedle(buffer, utf8) ||
            ContainsUnicodeFindNeedle(buffer, utf16))
        {
            matched = true;
            error = ERROR_SUCCESS;
            return true;
        }
        if (read == 0)
        {
            error = ERROR_SUCCESS;
            return true;
        }
        if (buffer.size() > overlap)
            buffer.erase(buffer.begin(), buffer.end() - static_cast<std::ptrdiff_t>(overlap));
    }
}

// Enumerate original UTF-16 names, preserving the full absolute directory.
// Never follow directory reparse points: recursive junction cycles are unsafe.
// A sink returning false cancels the operation. Results are not partially
// sorted or silently truncated. No file is modified by this operation.
inline bool SearchUnicodeDirectory(const UnicodeFindOptions& options,
                                   const UnicodeFindSink& sink,
                                   std::atomic<bool>* cancel,
                                   DWORD& error)
{
    error = ERROR_INVALID_PARAMETER;
    if (!sink || options.root.empty() || options.maximumResults == 0)
        return false;

    std::wstring rootExtended;
    if (!TryMakeExtendedLengthPath(options.root.c_str(), rootExtended, error))
        return false;
    const DWORD attributes = GetFileAttributesW(rootExtended.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        error = GetLastError();
        return false;
    }
    if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
    {
        error = ERROR_DIRECTORY;
        return false;
    }

    std::vector<unsigned char> utf8;
    std::vector<unsigned char> utf16;
    if (!PrepareUnicodeFindNeedles(options.content, utf8, utf16))
    {
        error = ERROR_NO_UNICODE_TRANSLATION;
        return false;
    }

    std::vector<std::wstring> remaining;
    remaining.push_back(options.root);
    std::size_t found = 0;
    while (!remaining.empty())
    {
        if (cancel && cancel->load())
        {
            error = ERROR_CANCELLED;
            return false;
        }
        const std::wstring directory = std::move(remaining.back());
        remaining.pop_back();
        std::vector<LongDirectoryEntry> entries;
        if (!TryEnumerateLongDirectory(directory.c_str(), entries, error))
            return false;

        for (const auto& entry : entries)
        {
            if (cancel && cancel->load())
            {
                error = ERROR_CANCELLED;
                return false;
            }
            const bool isDirectory = (entry.attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
            const bool isReparse = (entry.attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
            const std::wstring child = directory +
                (directory.back() == L'\\' ? L"" : L"\\") + entry.name;
            std::wstring extendedChild;
            DWORD childError = ERROR_SUCCESS;
            if (!TryMakeExtendedLengthPath(child.c_str(), extendedChild, childError))
            {
                // Logically inaccessible children must not abort enumeration of
                // accessible siblings, but the caller must know it was partial.
                error = childError;
                return false;
            }
            if (isDirectory && !isReparse && options.includeSubdirectories)
                remaining.push_back(child);

            if ((isDirectory && !options.includeDirectories) ||
                !UnicodeFindMatchesMasks(options.masks, entry.name,
                                         options.caseSensitiveNames))
                continue;
            if (!options.content.empty())
            {
                if (isDirectory || isReparse)
                    continue;
                bool contains = false;
                if (!UnicodeFindFileContains(child, utf8, utf16, cancel, contains, error))
                    return false;
                if (!contains)
                    continue;
            }
            UnicodeFindHit hit;
            hit.directory = directory;
            hit.name = entry.name;
            hit.attributes = entry.attributes;
            hit.size = entry.size;
            hit.lastWrite = entry.lastWrite;
            if (!sink(hit))
            {
                error = ERROR_CANCELLED;
                return false;
            }
            if (++found >= options.maximumResults)
            {
                error = ERROR_MORE_DATA;
                return false;
            }
        }
    }
    error = ERROR_SUCCESS;
    return true;
}
} // namespace Salamander
