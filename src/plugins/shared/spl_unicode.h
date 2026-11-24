// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <windows.h>

// Optional, independent extension of SDK 103. No legacy vtable or layout is
// extended. A plugin implementing this contract exports the exact undecorated
// name SalamanderPluginQueryUnicodeViewer (use a .def file on x86 as well).
// Older hosts ignore the export; older plugins need not export it.
struct CSalamanderPluginViewerData;

namespace SalamanderSdk
{
constexpr DWORD UnicodeViewerVersion1 = 1;
constexpr char UnicodeViewerExportName[] = "SalamanderPluginQueryUnicodeViewer";

#pragma pack(push, 4)
struct UnicodeViewerV1
{
    DWORD Size;
    DWORD Version;
    // name: exact, null-terminated UTF-16 identity, valid for the call.
    // No ACP conversion or MAX_PATH truncation is permitted. The callee must
    // copy the name if it outlives the call. Window, lock and enumeration
    // semantics are those of spl_view.h; caller owns the table storage.
    // Optional diagnostic on FALSE: SetLastError may carry a raw Win32
    // error or HRESULT. It is advisory only; zero or an absent diagnostic
    // must not change viewer selection or the meaning of the BOOL result.
    BOOL (WINAPI* CanViewFileW)(const WCHAR* name);
    BOOL (WINAPI* ViewFileW)(const WCHAR* name, int left, int top,
                             int width, int height, UINT showCmd,
                             BOOL alwaysOnTop, BOOL returnLock, HANDLE* lock,
                             BOOL* lockOwner, CSalamanderPluginViewerData* viewerData,
                             int enumFilesSourceUID, int enumFilesCurrentIndex);
};
#pragma pack(pop)

// Query must not write beyond capacity. Return FALSE for unsupported versions.
// On success set Size to sizeof(UnicodeViewerV1), Version to the requested
// version and both callbacks. The host calls only while the module is loaded.
using QueryUnicodeViewer = BOOL (WINAPI*)(DWORD version, DWORD capacity,
                                          UnicodeViewerV1* output);

inline bool NegotiateUnicodeViewerV1(QueryUnicodeViewer query, UnicodeViewerV1& output)
{
    output = {};
    if (!query)
        return false;
    UnicodeViewerV1 candidate{};
    if (!query(UnicodeViewerVersion1, static_cast<DWORD>(sizeof(candidate)), &candidate) ||
        candidate.Size != sizeof(candidate) ||
        candidate.Version != UnicodeViewerVersion1 ||
        !candidate.CanViewFileW || !candidate.ViewFileW)
        return false;
    output = candidate;
    return true;
}
} // namespace SalamanderSdk
