// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include <utility>

namespace Salamander
{
// This model is independent of the legacy CFileData / plugin ABI.
// Use UTF-16 code units explicitly, including on platforms where wchar_t
// is not 16 bits. No implicit conversion through the process ANSI code page.
enum class Utf16PathError
{
    None,
    InvalidInput,
    InvalidUtf16,
    InvalidComponent,
    ComponentTooLong,
    PathTooLong
};

namespace Utf16DiskDetail
{
inline bool IsValidUtf16(std::u16string_view input) noexcept
{
    for (std::size_t i = 0; i < input.size(); ++i)
    {
        const char16_t code = input[i];
        if (code >= 0xD800 && code <= 0xDBFF)
        {
            if (++i == input.size() || input[i] < 0xDC00 || input[i] > 0xDFFF)
                return false;
        }
        else if (code >= 0xDC00 && code <= 0xDFFF)
        {
            return false;
        }
    }
    return true;
}

inline char16_t AsciiUpper(char16_t code) noexcept
{
    return code >= u'a' && code <= u'z' ? static_cast<char16_t>(code - 32) : code;
}

inline bool IsReservedDeviceName(std::u16string_view name) noexcept
{
    // Windows reserves these names even when followed by an extension.
    const std::size_t dot = name.find(u'.');
    const std::u16string_view stem = name.substr(0, dot);
    if (stem.size() == 3)
    {
        const char16_t a = AsciiUpper(stem[0]);
        const char16_t b = AsciiUpper(stem[1]);
        const char16_t c = AsciiUpper(stem[2]);
        return (a == u'C' && b == u'O' && c == u'N') ||
               (a == u'P' && b == u'R' && c == u'N') ||
               (a == u'A' && b == u'U' && c == u'X') ||
               (a == u'N' && b == u'U' && c == u'L');
    }
    if (stem.size() == 4)
    {
        const char16_t a = AsciiUpper(stem[0]);
        const char16_t b = AsciiUpper(stem[1]);
        const char16_t c = AsciiUpper(stem[2]);
        return ((a == u'C' && b == u'O' && c == u'M') ||
                (a == u'L' && b == u'P' && c == u'T')) &&
               stem[3] >= u'1' && stem[3] <= u'9';
    }
    return false;
}

inline Utf16PathError ValidateComponent(std::u16string_view value) noexcept
{
    if (value.empty() || value == u"." || value == u"..")
        return Utf16PathError::InvalidComponent;
    if (value.size() > 255)
        return Utf16PathError::ComponentTooLong;
    if (!IsValidUtf16(value))
        return Utf16PathError::InvalidUtf16;
    if (value.back() == u'.' || value.back() == u' ' ||
        IsReservedDeviceName(value))
        return Utf16PathError::InvalidComponent;

    for (const char16_t code : value)
    {
        if (code < 0x20 || code == u'<' || code == u'>' ||
            code == u':' || code == u'"' || code == u'/' ||
            code == u'\\' || code == u'|' || code == u'?' || code == u'*')
            return Utf16PathError::InvalidComponent;
    }
    return Utf16PathError::None;
}
} // namespace Utf16DiskDetail

// A single, validated filesystem filename. It never performs ANSI conversion.
class Utf16FileName
{
public:
    static bool TryCreate(std::u16string_view input,
                          Utf16FileName& output,
                          Utf16PathError& error)
    {
        output.value_.clear();
        error = Utf16DiskDetail::ValidateComponent(input);
        if (error != Utf16PathError::None)
            return false;
        output.value_.assign(input);
        return true;
    }

    const std::u16string& Value() const noexcept { return value_; }

private:
    std::u16string value_;
};

// An owned, absolute drive or UNC path with dynamically sized UTF-16 storage.
// The model intentionally does not normalize dot segments or change case.
// This is a foundation only: the legacy Salamander panels still use ANSI.
class Utf16DiskPath
{
public:
    static bool TryCreateAbsolute(std::u16string_view input,
                                  Utf16DiskPath& output,
                                  Utf16PathError& error)
    {
        output.value_.clear();
        error = Utf16PathError::InvalidInput;

        std::size_t componentStart = 0;
        std::size_t prefixExtra = 0;
        if (input.size() >= 3 &&
            ((input[0] >= u'A' && input[0] <= u'Z') ||
             (input[0] >= u'a' && input[0] <= u'z')) &&
            input[1] == u':' && input[2] == u'\\')
        {
            componentStart = 3;
            prefixExtra = 4;
        }
        else if (input.size() >= 5 &&
                 input[0] == u'\\' && input[1] == u'\\' &&
                 input[2] != u'?' && input[2] != u'.' && input[2] != u'\\')
        {
            const std::size_t serverEnd = input.find(u'\\', 2);
            if (serverEnd == std::u16string_view::npos)
                return false;
            error = Utf16DiskDetail::ValidateComponent(input.substr(2, serverEnd - 2));
            if (error != Utf16PathError::None)
                return false;

            const std::size_t shareStart = serverEnd + 1;
            const std::size_t shareEnd = input.find(u'\\', shareStart);
            error = Utf16DiskDetail::ValidateComponent(
                input.substr(shareStart, shareEnd - shareStart));
            if (error != Utf16PathError::None)
                return false;

            componentStart = shareEnd == std::u16string_view::npos
                                 ? input.size() : shareEnd + 1;
            prefixExtra = 6;
        }
        else
        {
            return false;
        }

        // Win32 extended-length paths are limited to 32767 UTF-16 units
        // INCLUDING their prefix and terminator.
        if (input.size() >= 32767 - prefixExtra)
        {
            error = Utf16PathError::PathTooLong;
            return false;
        }

        while (componentStart < input.size())
        {
            const std::size_t end = input.find(u'\\', componentStart);
            const std::size_t count =
                (end == std::u16string_view::npos ? input.size() : end) -
                componentStart;
            error = Utf16DiskDetail::ValidateComponent(
                input.substr(componentStart, count));
            if (error != Utf16PathError::None)
                return false;
            if (end == std::u16string_view::npos || end == input.size() - 1)
                break;
            componentStart = end + 1;
        }

        error = Utf16PathError::None;
        output.value_.assign(input);
        return true;
    }

    bool TryAppend(const Utf16FileName& name,
                   Utf16DiskPath& output,
                   Utf16PathError& error) const
    {
        if (value_.empty() || name.Value().empty())
        {
            output.value_.clear();
            error = Utf16PathError::InvalidInput;
            return false;
        }
        std::u16string combined(value_);
        if (combined.back() != u'\\')
            combined.push_back(u'\\');
        combined.append(name.Value());
        return TryCreateAbsolute(combined, output, error);
    }

    const std::u16string& Value() const noexcept { return value_; }

private:
    std::u16string value_;
};
} // namespace Salamander
