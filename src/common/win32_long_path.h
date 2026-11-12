// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <windows.h>
#include <string>

namespace Salamander
{
// Temporary implementation used to verify that the behavior test fails.
inline bool TryMakeExtendedLengthPath(const wchar_t*, std::wstring& result, DWORD& error)
{
    result.clear();
    error = ERROR_INVALID_NAME;
    return false;
}
} // namespace Salamander
