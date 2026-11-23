// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <windows.h>
#include <uxtheme.h>
#include <algorithm>
#include <memory>
#include <new>
#include <string>

namespace Salamander
{
namespace Utf16StaticTextDetail
{
inline const wchar_t* PropertyName() { return L"OpenSalamander.OwnedUtf16StaticText.v1"; }

struct TextData
{
    WNDPROC Previous = nullptr;
    bool PreviousUnicode = false;
    std::wstring Text;
};

inline LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
{
    auto* data = static_cast<TextData*>(GetPropW(window, PropertyName()));
    if (data == nullptr)
        return DefWindowProcW(window, message, wParam, lParam);
    if (message == WM_GETTEXTLENGTH)
        return static_cast<LRESULT>(data->Text.size());
    if (message == WM_GETTEXT)
    {
        if (wParam == 0 || lParam == 0)
            return 0;
        const std::size_t length = (std::min)(static_cast<std::size_t>(wParam - 1), data->Text.size());
        auto* output = reinterpret_cast<wchar_t*>(lParam);
        std::copy_n(data->Text.data(), length, output);
        output[length] = 0;
        return static_cast<LRESULT>(length);
    }
    if (message == WM_SETTEXT)
    {
        try
        {
            const std::wstring text(lParam == 0 ? L"" : reinterpret_cast<const wchar_t*>(lParam));
            data->Text = text;
            // Preserve the real Unicode caption for cross-process accessibility
            // as well as our WM_GETTEXT implementation and painting.
            DefWindowProcW(window, message, wParam, reinterpret_cast<LPARAM>(data->Text.c_str()));
            InvalidateRect(window, nullptr, FALSE);
            return TRUE;
        }
        catch (const std::bad_alloc&)
        {
            SetLastError(ERROR_NOT_ENOUGH_MEMORY);
            return FALSE;
        }
    }
    if (message == WM_PAINT)
    {
        PAINTSTRUCT paint;
        HDC dc = BeginPaint(window, &paint);
        RECT rectangle;
        GetClientRect(window, &rectangle);
        const HWND parent = GetParent(window);
        HBRUSH background = reinterpret_cast<HBRUSH>(SendMessage(parent, WM_CTLCOLORSTATIC,
            reinterpret_cast<WPARAM>(dc), reinterpret_cast<LPARAM>(window)));
        if (background == nullptr)
            background = GetSysColorBrush(COLOR_BTNFACE);
        FillRect(dc, &rectangle, background);
        if (IsAppThemed())
            DrawThemeParentBackground(window, dc, &rectangle);
        const int oldMode = SetBkMode(dc, TRANSPARENT);
        const HFONT font = reinterpret_cast<HFONT>(SendMessage(window, WM_GETFONT, 0, 0));
        HGDIOBJ oldFont = font == nullptr ? nullptr : SelectObject(dc, font);
        if (!IsWindowEnabled(window))
            SetTextColor(dc, GetSysColor(COLOR_GRAYTEXT));
        DrawTextW(dc, data->Text.c_str(), static_cast<int>(data->Text.size()), &rectangle,
            DT_SINGLELINE | DT_TOP | DT_LEFT | DT_NOPREFIX | DT_PATH_ELLIPSIS);
        if (oldFont != nullptr)
            SelectObject(dc, oldFont);
        SetBkMode(dc, oldMode);
        EndPaint(window, &paint);
        return 0;
    }
    const LRESULT result = CallWindowProcW(data->Previous, window, message, wParam, lParam);
    if (message == WM_NCDESTROY)
    {
        RemovePropW(window, PropertyName());
        delete data;
    }
    return result;
}
} // namespace Utf16StaticTextDetail

// Opt-in adaptation of an existing path static, preserving HWND, resource ID,
// font, position and dialog buttons. Only its owning UI thread may call this.
// The original subclass remains responsible for its own object/lifetime.
// Passing nullptr restores the original A/W procedure before legacy SetText.
inline bool SetUtf16StaticText(HWND window, const wchar_t* text)
{
    DWORD owner = 0;
    const DWORD thread = GetWindowThreadProcessId(window, &owner);
    if (thread != GetCurrentThreadId() || owner != GetCurrentProcessId())
    {
        SetLastError(ERROR_ACCESS_DENIED);
        return false;
    }
    auto* data = static_cast<Utf16StaticTextDetail::TextData*>(
        GetPropW(window, Utf16StaticTextDetail::PropertyName()));
    if (text == nullptr)
    {
        if (data != nullptr)
        {
            // A later subclass owns the current chain. Do not orphan its
            // procedure/data; the normal WM_NCDESTROY chain still frees ours.
            if (reinterpret_cast<WNDPROC>(GetWindowLongPtrW(window, GWLP_WNDPROC)) !=
                Utf16StaticTextDetail::WindowProc)
            {
                SetLastError(ERROR_BUSY);
                return false;
            }
            SetLastError(ERROR_SUCCESS);
            const LONG_PTR previous = data->PreviousUnicode
                ? SetWindowLongPtrW(window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(data->Previous))
                : SetWindowLongPtrA(window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(data->Previous));
            if (previous == 0 && GetLastError() != ERROR_SUCCESS)
                return false;
            RemovePropW(window, Utf16StaticTextDetail::PropertyName());
            delete data;
        }
        return true;
    }
    try
    {
        if (data == nullptr)
        {
            std::unique_ptr<Utf16StaticTextDetail::TextData> fresh(new Utf16StaticTextDetail::TextData);
            fresh->Text = text;
            fresh->PreviousUnicode = IsWindowUnicode(window) != FALSE;
            if (!SetPropW(window, Utf16StaticTextDetail::PropertyName(), fresh.get()))
                return false;
            SetLastError(ERROR_SUCCESS);
            fresh->Previous = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(window, GWLP_WNDPROC,
                reinterpret_cast<LONG_PTR>(Utf16StaticTextDetail::WindowProc)));
            if (fresh->Previous == nullptr)
            {
                const DWORD error = GetLastError();
                RemovePropW(window, Utf16StaticTextDetail::PropertyName());
                SetLastError(error);
                return false;
            }
            data = fresh.release();
        }
        return SendMessageW(window, WM_SETTEXT, 0, reinterpret_cast<LPARAM>(text)) != FALSE;
    }
    catch (const std::bad_alloc&)
    {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return false;
    }
}
} // namespace Salamander
