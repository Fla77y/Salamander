// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/common/legacy_disk_name_safety.h"

#include <cstdio>
#include <vector>

using Salamander::LegacyDiskEntryView;
using Salamander::IsLossyAnsiDiskName;
using Salamander::SelectionContainsLossyDiskName;

namespace
{
int Fail(const char* scenario)
{
    std::fprintf(stderr, "FAIL: %s\n", scenario);
    return 1;
}
}

int main()
{
    // A literal '?' is not permitted in a Win32 disk filename.
    // It is a signal that ANSI conversion may have destroyed identity.
    if (!IsLossyAnsiDiskName("Groesse_??_??.txt") ||
        !IsLossyAnsiDiskName("Größe_??_??.txt") ||
        IsLossyAnsiDiskName("plain.txt") ||
        IsLossyAnsiDiskName("name~1.txt") ||
        IsLossyAnsiDiskName(nullptr))
        return Fail("classify unrepresentable legacy disk names");

    const std::vector<LegacyDiskEntryView> entries = {
        {"..", false},
        {"safe.txt", false},
        {"Größe_??_??.txt", false},
        {"other.txt", false}
    };
    const auto item = [&entries](std::size_t index) { return entries.at(index); };

    // Without explicit selection, only the focused item is actionable.
    if (SelectionContainsLossyDiskName(entries.size(), 0, 1, item) ||
        !SelectionContainsLossyDiskName(entries.size(), 0, 2, item))
        return Fail("check the focus only when nothing is selected");

    // With explicit selection, the focused item is irrelevant. Every
    // selected entry must be checked to prevent partial batch operations.
    auto selected = entries;
    selected[1].selected = true;
    const auto selectedItem = [&selected](std::size_t index) { return selected.at(index); };
    if (SelectionContainsLossyDiskName(selected.size(), 1, 2, selectedItem))
        return Fail("safe selected file must not be blocked by unsafe focus");
    selected[2].selected = true;
    if (!SelectionContainsLossyDiskName(selected.size(), 2, 1, selectedItem))
        return Fail("any lossy name must block a multi-selection operation");

    // Directory entries and ordinary ASCII names remain unaffected.
    selected[2].selected = false;
    if (SelectionContainsLossyDiskName(selected.size(), 1, 1, selectedItem) ||
        SelectionContainsLossyDiskName(0, 0, 0, item) ||
        SelectionContainsLossyDiskName(entries.size(), 0, entries.size(), item))
        return Fail("safe selection and invalid indices must not be misidentified");

    // A Unicode name may be converted through best-fit to ASCII *without*
    // any question mark. The directory identity index must be able to flag
    // that entry explicitly; '?'-only checks are not sufficient.
    selected[1].unsafeIdentity = true;
    if (!SelectionContainsLossyDiskName(selected.size(), 1, 1, selectedItem))
        return Fail("best-fit alias with no question mark must be refused");
    selected[1].unsafeIdentity = false;
    if (SelectionContainsLossyDiskName(selected.size(), 1, 1, selectedItem))
        return Fail("lossless ASCII name must remain safe");

    std::puts("PASS: fail-closed ANSI disk name operation selection, focus and batch semantics");
    return 0;
}
