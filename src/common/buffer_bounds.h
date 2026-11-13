// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>

namespace Salamander
{
// The appended code unit and the trailing NUL must both fit.
// This checks capacity only; callers are responsible for valid string contents.
constexpr bool CanAppendNullTerminatedCharacter(std::size_t length, std::size_t capacity) noexcept
{
    return capacity != 0 && length < capacity - 1;
}
} // namespace Salamander
