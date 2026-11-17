// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/common/win32_utf16_static_text.h"
#include <cassert>
#include <cstdio>
#include <vector>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "uxtheme.lib")

int main()
{
    // Arrange: a real hidden ANSI static, as used by the legacy dialogs.
    HWND control = CreateWindowExA(0, "STATIC", "original", WS_POPUP,
        0, 0, 300, 30, nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
    assert(control != nullptr && !IsWindowUnicode(control));
    const std::wstring expected = L"C:\\東京\\" + std::wstring(600, L'a') + L"\\😀.bin";
    // Act
    assert(Salamander::SetUtf16StaticText(control, expected.c_str()));
    std::vector<wchar_t> result(expected.size() + 2);
    // Assert: actual Win32 messages retain every UTF-16 unit, not ACP aliases.
    assert(IsWindowUnicode(control));
    assert(GetWindowTextLengthW(control) == static_cast<int>(expected.size()));
    assert(GetWindowTextW(control, result.data(), static_cast<int>(result.size())) == static_cast<int>(expected.size()));
    assert(result.data() == expected);
    wchar_t truncatedText[3] = {L'x', L'x', L'x'};
    assert(GetWindowTextW(control, truncatedText, 3) == 2 && truncatedText[2] == 0);
    assert(SetWindowTextW(control, L"日本😀"));
    assert(GetWindowTextW(control, result.data(), static_cast<int>(result.size())) == 4);
    assert(std::wstring(result.data()) == L"日本😀");
    // Act / Assert: restore A semantics and permit repeated attach/destroy.
    assert(Salamander::SetUtf16StaticText(control, nullptr));
    assert(!IsWindowUnicode(control));
    assert(SetWindowTextA(control, "ASCII"));
    assert(Salamander::SetUtf16StaticText(control, L"再表示😀"));
    assert(DestroyWindow(control));
    assert(!Salamander::SetUtf16StaticText(nullptr, L"invalid"));
    assert(GetLastError() == ERROR_ACCESS_DENIED);
    return std::puts("PASS: UTF-16 path static preserves native text, bounded reads, restoration and destruction"), 0;
}
