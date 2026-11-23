// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "utf16_disk_path.h"

#include <string>
#include <string_view>
#include <utility>

namespace Salamander
{
// Owns the true UTF-16 identity of one legacy Find result. The ANSI display
// fields in CFoundFilesData are not an authoritative filesystem identity;
// callers must obtain this from W enumeration, never by decoding a lossy
// code-page alias. This value type does not perform I/O or ANSI conversion.
class LegacyFindUtf16Identity
{
public:
    // Inputs may refer to output's fields. Publish only after validation and
    // ownership of both components; validation failure clears the old identity.
    static bool TryCreate(std::u16string_view directory,
                          std::u16string_view filename,
                          LegacyFindUtf16Identity& output,
                          Utf16PathError& error)
    {
        Utf16DiskPath root;
        Utf16DiskPath complete;
        Utf16FileName leaf;
        if (!Utf16DiskPath::TryCreateAbsolute(directory, root, error) ||
            !Utf16FileName::TryCreate(filename, leaf, error) ||
            !root.TryAppend(leaf, complete, error))
        {
            output = LegacyFindUtf16Identity();
            return false;
        }
        LegacyFindUtf16Identity validated;
        validated.directory_.assign(directory);
        validated.name_.assign(filename);
        output = std::move(validated);
        return true;
    }

    bool IsValid() const noexcept { return !directory_.empty(); }
    const std::u16string& Directory() const noexcept { return directory_; }
    const std::u16string& Name() const noexcept { return name_; }

    std::u16string FullPath() const
    {
        if (!IsValid())
            return {};
        std::u16string result(directory_);
        if (result.back() != u'\\')
            result.push_back(u'\\');
        result.append(name_);
        return result;
    }

private:
    std::u16string directory_;
    std::u16string name_;
};
} // namespace Salamander
