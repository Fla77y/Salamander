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

// Optional menu extension, independent of both SDK 103 and UnicodeViewerV1.
// The plugin must only advertise commands that can consume the complete W
// selection without subsequently retrieving filenames through the legacy ABI.
constexpr DWORD UnicodeMenuVersion1 = 1;
constexpr char UnicodeMenuExportName[] = "SalamanderPluginQueryUnicodeMenu";

#pragma pack(push, 4)
struct UnicodeMenuItemV1
{
    const WCHAR* Name; // exact leaf name, not an ACP alias
    BOOL IsDirectory;
};

struct UnicodeMenuSelectionV1
{
    DWORD Size;
    const WCHAR* Root; // exact absolute disk directory, no MAX_PATH limit
    DWORD Count;
    const UnicodeMenuItemV1* Items;
};

struct UnicodeMenuV1
{
    DWORD Size;
    DWORD Version;
    BOOL (WINAPI* CanExecuteMenuItemW)(int id);
    // Return value has the same selection-clearing semantics as the legacy
    // ExecuteMenuItem. Root, Items and every Name are borrowed for this
    // synchronous call only. Copy all needed values before starting a thread.
    // The plugin owns filesystem validation and user-visible error handling.
    // No exceptions or ownership of allocations may cross the ABI.
    BOOL (WINAPI* ExecuteMenuItemW)(HWND parent, int id, DWORD eventMask,
                                   const UnicodeMenuSelectionV1* selection);
};
#pragma pack(pop)

using QueryUnicodeMenu = BOOL (WINAPI*)(DWORD version, DWORD capacity,
                                        UnicodeMenuV1* output);

inline bool NegotiateUnicodeMenuV1(QueryUnicodeMenu query, UnicodeMenuV1& output)
{
    output = {};
    if (!query)
        return false;
    UnicodeMenuV1 candidate{};
    if (!query(UnicodeMenuVersion1, static_cast<DWORD>(sizeof(candidate)), &candidate) ||
        candidate.Size != sizeof(candidate) ||
        candidate.Version != UnicodeMenuVersion1 ||
        !candidate.CanExecuteMenuItemW || !candidate.ExecuteMenuItemW)
        return false;
    output = candidate;
    return true;
}
} // namespace SalamanderSdk
