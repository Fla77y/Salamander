// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <cstring>

namespace Salamander
{
// This is a temporary safety gate for the legacy ANSI disk panel, not a
// replacement for an owned UTF-16 identity. Win32 does not permit a literal
// '?' in a filesystem component. A '?' in the ANSI panel name therefore
// indicates that the original Unicode identity may already be lost.
inline bool IsLossyAnsiDiskName(const char* name) noexcept
{
    return name != nullptr && std::strchr(name, '?') != nullptr;
}

// Legacy Win32 ANSI file operations need a separator plus the source name
// below MAX_PATH. Avoid adding lengths before testing (size_t may overflow).
// The result describes the *full* path, not just a long parent directory or
// a lossy ANSI filename. F5/F6 must use an owned UTF-16 row in this case.
inline bool ExceedsLegacyDiskPathLimit(std::size_t directoryBytes,
                                       std::size_t filenameBytes,
                                       std::size_t maxPath) noexcept
{
    return maxPath == 0 || directoryBytes >= maxPath ||
           filenameBytes >= maxPath - directoryBytes - 1;
}

// F5/F6 write into the opposite panel. A path that fits in the source
// panel may overflow the legacy ANSI destination buffer. The two checks
// share the same overflow-safe boundary calculation.
inline bool ExceedsLegacyTransferPathLimit(std::size_t sourceDirectoryBytes,
                                           std::size_t targetDirectoryBytes,
                                           std::size_t filenameBytes,
                                           std::size_t maxPath) noexcept
{
    return ExceedsLegacyDiskPathLimit(sourceDirectoryBytes, filenameBytes, maxPath) ||
           ExceedsLegacyDiskPathLimit(targetDirectoryBytes, filenameBytes, maxPath);
}

struct LegacyDiskEntryView
{
    const char* name;
    bool selected;
    // True when the panel's UTF-16 identity index cannot prove that
    // the legacy byte name addresses the same file exactly.
    bool unsafeIdentity = false;
};

// Match Salamander's file-action contract: process all selected entries, or
// only the focused item when no explicit selection exists. Call before any
// side effects, so an unsafe batch is refused as a whole.
// The caller must restrict this test to a physical disk panel.
template <typename GetEntry>
bool SelectionContainsLossyDiskName(std::size_t entryCount,
                                    std::size_t selectedCount,
                                    std::size_t focusedIndex,
                                    GetEntry&& getEntry)
{
    if (selectedCount == 0)
    {
        return focusedIndex < entryCount &&
               (getEntry(focusedIndex).unsafeIdentity ||
                IsLossyAnsiDiskName(getEntry(focusedIndex).name));
    }

    for (std::size_t i = 0; i < entryCount; ++i)
    {
        const LegacyDiskEntryView entry = getEntry(i);
        if (entry.selected &&
            (entry.unsafeIdentity || IsLossyAnsiDiskName(entry.name)))
            return true;
    }
    return false;
}
} // namespace Salamander
