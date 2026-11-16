// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <windows.h>
#include <string>

namespace pictview::wic
{
// Convert a legacy plug-in SDK path to UTF-16 without code-page best-fit.
// The original ANSI API cannot represent arbitrary UTF-16 names. Reject
// invalid or non-round-trippable input rather than guessing an alias.
bool ConvertSdkPath(const char* path, std::wstring& output) noexcept;

// Called on the existing Salamander viewer thread. Takes ownership only of
// local COM, HWND, and decoded pixels. Caller owns the synchronization HANDLEs.
// Always signals 'ready' once and never accesses 'created' or 'lockOwner' after
// signaling it. 'onOpen'/'onClose' attach to Salamander's viewer window queue.
void UnregisterNativeViewerClass(HINSTANCE instance) noexcept;

unsigned RunNativeViewer(const char* path, HINSTANCE instance,
                         int left, int top, int width, int height,
                         UINT showCommand, BOOL alwaysOnTop,
                         BOOL returnLock, HANDLE* lock, BOOL* lockOwner,
                         HANDLE ready, BOOL* created,
                         void (*onOpen)(HWND), void (*onClose)(HWND)) noexcept;
} // namespace pictview::wic
