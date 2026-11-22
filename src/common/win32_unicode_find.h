// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_long_directory.h"

#include <windows.h>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <functional>
#include <optional>
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
    std::optional<std::uint64_t> minimumFileSize;
    std::optional<std::uint64_t> maximumFileSize;
    std::optional<unsigned int> earliestModifiedDate;
    std::optional<unsigned int> latestModifiedDate;
    DWORD attributesMask = 0;
    DWORD attributesValue = 0;
    std::size_t maximumResults = 100000;
    // Bound memory used by retained W identities in addition to hit count.
    // In a 32K directory, each result may otherwise repeat 64 KiB of text.
    std::size_t maximumResultUtf16Units = 8 * 1024 * 1024;
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

// Dates use a numeric YYYYMMDD key so comparisons ignore the time of day.
inline unsigned int UnicodeFindDateKey(const SYSTEMTIME& date)
{
    return date.wYear * 10000U + date.wMonth * 100U + date.wDay;
}

inline bool UnicodeFindLocalTime(DYNAMIC_TIME_ZONE_INFORMATION& timeZone,
                                 const SYSTEMTIME& utc, SYSTEMTIME& local)
{
    // The application still targets Windows 7 in its build settings. Use the
    // dynamic-rule conversion on newer systems without a mandatory import.
    using ConvertTime = BOOL(WINAPI*)(const DYNAMIC_TIME_ZONE_INFORMATION*,
                                    const SYSTEMTIME*, SYSTEMTIME*);
    static const auto convert = reinterpret_cast<ConvertTime>(reinterpret_cast<void*>(
        GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "SystemTimeToTzSpecificLocalTimeEx")));
    if (convert)
        return convert(&timeZone, &utc, &local) != FALSE;

    TIME_ZONE_INFORMATION rules{};
    return GetTimeZoneInformationForYear(utc.wYear, &timeZone, &rules) &&
        SystemTimeToTzSpecificLocalTime(&rules, &utc, &local);
}

inline bool ParseUnicodeFindDate(const std::wstring& text, std::optional<unsigned int>& date)
{
    if (text.empty())
    {
        date.reset();
        return true;
    }
    if (text.size() != 10 || text[4] != L'-' || text[7] != L'-')
        return false;

    SYSTEMTIME parts{};
    WORD* field = &parts.wYear;
    for (std::size_t index = 0; index < text.size(); ++index)
    {
        if (index == 4)
            field = &parts.wMonth;
        else if (index == 7)
            field = &parts.wDay;
        else
        {
            const wchar_t digit = text[index];
            if (digit < L'0' || digit > L'9')
                return false;
            *field = static_cast<WORD>(*field * 10 + (digit - L'0'));
        }
    }
    FILETIME validation;
    if (!SystemTimeToFileTime(&parts, &validation))
        return false;
    date = UnicodeFindDateKey(parts);
    return true;
}

inline int UnicodeFindCharacterLength(const wchar_t* text)
{
    return IS_HIGH_SURROGATE(text[0]) && IS_LOW_SURROGATE(text[1]) ? 2 : 1;
}

// Match * and ? against the original UTF-16 name. A valid surrogate pair
// occupies one wildcard position; an isolated unit still compares literally.
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
        const int valueLength = UnicodeFindCharacterLength(value);
        const int patternLength = UnicodeFindCharacterLength(pattern);
        if (*pattern == L'*')
        {
            lastStar = pattern++;
            lastMatch = value;
        }
        else if (*pattern == L'?' ||
                 (*pattern && CompareStringOrdinal(pattern, patternLength, value, valueLength,
                     caseSensitive ? FALSE : TRUE) == CSTR_EQUAL))
        {
            pattern += patternLength;
            value += valueLength;
        }
        else if (lastStar)
        {
            pattern = lastStar + 1;
            lastMatch += UnicodeFindCharacterLength(lastMatch);
            value = lastMatch;
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

struct UnicodeFindNeedles
{
    std::vector<unsigned char> utf8;
    std::vector<unsigned char> utf16le;
    std::vector<unsigned char> utf16be;
};

// Prepare the byte sequences for a literal match across read blocks.
inline bool PrepareUnicodeFindNeedles(const std::wstring& value,
                                      UnicodeFindNeedles& needles)
{
    needles = {};
    if (value.empty())
        return true;
    const int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        value.c_str(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (bytes <= 0)
        return false;
    needles.utf8.resize(static_cast<std::size_t>(bytes));
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(),
                           static_cast<int>(value.size()),
                           reinterpret_cast<char*>(needles.utf8.data()), bytes,
                           nullptr, nullptr) != bytes)
        return false;
    needles.utf16le.reserve(value.size() * 2);
    needles.utf16be.reserve(value.size() * 2);
    for (wchar_t unit : value)
    {
        const auto number = static_cast<std::uint16_t>(unit);
        const auto low = static_cast<unsigned char>(number & 0xff);
        const auto high = static_cast<unsigned char>(number >> 8);
        needles.utf16le.push_back(low);
        needles.utf16le.push_back(high);
        needles.utf16be.push_back(high);
        needles.utf16be.push_back(low);
    }
    return true;
}

inline bool ContainsUnicodeFindNeedle(const std::vector<unsigned char>& buffer,
                                      const std::vector<unsigned char>& needle,
                                      std::size_t start, std::size_t stride)
{
    for (std::size_t i = start; i + needle.size() <= buffer.size(); i += stride)
    {
        if (std::memcmp(buffer.data() + i, needle.data(), needle.size()) == 0)
            return true;
    }
    return false;
}

// Scan without mapping untrusted file sizes into the process address space.
// On I/O errors return false: skipped unreadable files must not masquerade
// as a complete, successful "no results" search.
inline bool UnicodeFindFileContains(const std::wstring& absoluteFile,
                                    const UnicodeFindNeedles& needles,
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

    const std::size_t longestNeedle = needles.utf8.size() > needles.utf16le.size() ?
        needles.utf8.size() : needles.utf16le.size();
    const std::size_t overlap = longestNeedle - 1;
    std::vector<unsigned char> buffer;
    buffer.reserve(65536 + overlap);
    enum class Encoding { Unknown, Utf8, Utf16LE, Utf16BE };
    Encoding encoding = Encoding::Unknown;
    bool firstBlock = true;
    bool bufferStartsOnOddByte = false;
    std::size_t prefixRemaining = 0;
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
        if (firstBlock)
        {
            firstBlock = false;
            if (buffer.size() >= 3 && buffer[0] == 0xef && buffer[1] == 0xbb && buffer[2] == 0xbf)
            {
                encoding = Encoding::Utf8;
                prefixRemaining = 3;
            }
            else if (buffer.size() >= 2 && buffer[0] == 0xff && buffer[1] == 0xfe)
            {
                encoding = Encoding::Utf16LE;
                prefixRemaining = 2;
            }
            else if (buffer.size() >= 2 && buffer[0] == 0xfe && buffer[1] == 0xff)
            {
                encoding = Encoding::Utf16BE;
                prefixRemaining = 2;
            }
        }
        const std::size_t utf16Start = prefixRemaining +
            ((prefixRemaining + static_cast<std::size_t>(bufferStartsOnOddByte)) % 2);
        if (((encoding == Encoding::Unknown || encoding == Encoding::Utf8) &&
             ContainsUnicodeFindNeedle(buffer, needles.utf8, prefixRemaining, 1)) ||
            ((encoding == Encoding::Unknown || encoding == Encoding::Utf16LE) &&
             ContainsUnicodeFindNeedle(buffer, needles.utf16le, utf16Start, 2)) ||
            ((encoding == Encoding::Unknown || encoding == Encoding::Utf16BE) &&
             ContainsUnicodeFindNeedle(buffer, needles.utf16be, utf16Start, 2)))
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
        {
            const auto discarded = buffer.size() - overlap;
            bufferStartsOnOddByte = bufferStartsOnOddByte != (discarded % 2 != 0);
            prefixRemaining = discarded >= prefixRemaining ? 0 : prefixRemaining - discarded;
            buffer.erase(buffer.begin(), buffer.begin() + static_cast<std::ptrdiff_t>(discarded));
        }
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
    if (!sink || options.root.empty() || options.maximumResults == 0 ||
        (options.minimumFileSize && options.maximumFileSize &&
         *options.minimumFileSize > *options.maximumFileSize) ||
        (options.earliestModifiedDate && options.latestModifiedDate &&
         *options.earliestModifiedDate > *options.latestModifiedDate))
        return false;

    const bool filterModifiedDate = options.earliestModifiedDate || options.latestModifiedDate;
    DYNAMIC_TIME_ZONE_INFORMATION timeZone{};
    if (filterModifiedDate && GetDynamicTimeZoneInformation(&timeZone) == TIME_ZONE_ID_INVALID)
    {
        error = GetLastError();
        return false;
    }

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

    UnicodeFindNeedles needles;
    if (!PrepareUnicodeFindNeedles(options.content, needles))
    {
        error = ERROR_NO_UNICODE_TRANSLATION;
        return false;
    }

    std::vector<std::wstring> remaining;
    remaining.push_back(options.root);
    std::size_t found = 0;
    std::size_t resultUnits = 0;
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
                (entry.attributes & options.attributesMask) !=
                    (options.attributesValue & options.attributesMask) ||
                !UnicodeFindMatchesMasks(options.masks, entry.name,
                                         options.caseSensitiveNames))
                continue;
            if ((isDirectory && (options.minimumFileSize || options.maximumFileSize)) ||
                (options.minimumFileSize && entry.size < *options.minimumFileSize) ||
                (options.maximumFileSize && entry.size > *options.maximumFileSize))
                continue;
            if (filterModifiedDate)
            {
                SYSTEMTIME utc{}, local{};
                if (!FileTimeToSystemTime(&entry.lastWrite, &utc) ||
                    !UnicodeFindLocalTime(timeZone, utc, local))
                {
                    error = GetLastError();
                    return false;
                }
                const unsigned int modifiedDate = UnicodeFindDateKey(local);
                if ((options.earliestModifiedDate && modifiedDate < *options.earliestModifiedDate) ||
                    (options.latestModifiedDate && modifiedDate > *options.latestModifiedDate))
                    continue;
            }
            if (!options.content.empty())
            {
                if (isDirectory || isReparse)
                    continue;
                bool contains = false;
                if (!UnicodeFindFileContains(child, needles, cancel, contains, error))
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
            const std::size_t nextUnits = hit.directory.size() + hit.name.size();
            if (nextUnits > options.maximumResultUtf16Units ||
                resultUnits > options.maximumResultUtf16Units - nextUnits)
            {
                error = ERROR_MORE_DATA;
                return false;
            }
            resultUnits += nextUnits;
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
