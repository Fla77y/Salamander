// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <windows.h>
#include <cstdint>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace Salamander
{
namespace UnicodeRenameDialogDetail
{
constexpr WORD EditControlId = 4101;

// DLGTEMPLATE and DLGITEMTEMPLATE require DWORD-aligned records. DWORD
// storage keeps the alignment explicit without a resource or ANSI dialog.
class DialogTemplate
{
public:
    DialogTemplate() : storage_(256, 0) {}

    template <class T>
    void Add(const T& value)
    {
        const std::size_t next = used_ + sizeof(value);
        if (next > storage_.size() * sizeof(DWORD))
        {
            valid_ = false;
            return;
        }
        std::memcpy(reinterpret_cast<unsigned char*>(storage_.data()) + used_,
                    &value, sizeof(value));
        used_ = next;
    }

    void AddString(const wchar_t* value)
    {
        do
        {
            Add(*value);
        } while (*value++ != L'\0');
    }

    void Align()
    {
        used_ = (used_ + 3u) & ~std::size_t(3u);
    }

    bool Valid() const { return valid_; }
    const DLGTEMPLATE* Data() const
    {
        return reinterpret_cast<const DLGTEMPLATE*>(storage_.data());
    }

private:
    std::vector<DWORD> storage_;
    std::size_t used_ = 0;
    bool valid_ = true;
};

inline void AddControl(DialogTemplate& result, DWORD style, WORD id,
                       short x, short y, short width, short height,
                       WORD classAtom, const wchar_t* caption)
{
    result.Align();
    DLGITEMTEMPLATE control = {};
    control.style = WS_CHILD | WS_VISIBLE | style;
    control.x = x;
    control.y = y;
    control.cx = width;
    control.cy = height;
    control.id = id;
    result.Add(control);
    result.Add(static_cast<WORD>(0xFFFF));
    result.Add(classAtom);
    result.AddString(caption);
    result.Add(static_cast<WORD>(0)); // no creation data
}

inline DialogTemplate BuildTemplate()
{
    DialogTemplate result;
    DLGTEMPLATE header = {};
    header.style = WS_POPUP | WS_CAPTION | WS_SYSMENU |
                   DS_MODALFRAME | DS_CENTER;
    header.cdit = 4;
    header.cx = 248;
    header.cy = 76;
    result.Add(header);
    result.Add(static_cast<WORD>(0)); // menu: default
    result.Add(static_cast<WORD>(0)); // dialog window class
    result.AddString(L"Rename Unicode item");
    AddControl(result, 0, 4100, 8, 8, 228, 12, 0x0082, L"New file name:");
    AddControl(result, WS_BORDER | WS_TABSTOP | ES_AUTOHSCROLL,
               EditControlId, 8, 24, 230, 14, 0x0081, L"");
    AddControl(result, WS_TABSTOP | BS_DEFPUSHBUTTON,
               IDOK, 120, 50, 54, 16, 0x0080, L"OK");
    AddControl(result, WS_TABSTOP | BS_PUSHBUTTON,
               IDCANCEL, 184, 50, 54, 16, 0x0080, L"Cancel");
    return result;
}

struct State
{
    std::wstring name;
    bool selectAll = false;
    bool isDirectory = false;
};

inline INT_PTR CALLBACK DialogProc(HWND dialog, UINT message,
                                   WPARAM wParam, LPARAM lParam)
{
    if (message == WM_INITDIALOG)
    {
        auto* state = reinterpret_cast<State*>(lParam);
        SetWindowLongPtrW(dialog, DWLP_USER, reinterpret_cast<LONG_PTR>(state));
        SetDlgItemTextW(dialog, EditControlId, state->name.c_str());
        SendDlgItemMessageW(dialog, EditControlId, EM_LIMITTEXT, 255, 0);

        std::size_t selectionEnd = state->name.size();
        if (!state->selectAll && !state->isDirectory)
        {
            const std::size_t dot = state->name.rfind(L'.');
            if (dot != std::wstring::npos && dot > 0)
                selectionEnd = dot;
        }
        SendDlgItemMessageW(dialog, EditControlId, EM_SETSEL,
                            0, static_cast<LPARAM>(selectionEnd));
        SetFocus(GetDlgItem(dialog, EditControlId));
        return FALSE;
    }
    if (message != WM_COMMAND)
        return FALSE;

    const WORD command = LOWORD(wParam);
    if (command == IDCANCEL)
    {
        EndDialog(dialog, IDCANCEL);
        return TRUE;
    }
    if (command != IDOK)
        return FALSE;

    auto* state = reinterpret_cast<State*>(GetWindowLongPtrW(dialog, DWLP_USER));
    if (state == nullptr)
        return TRUE;

    const int length = GetWindowTextLengthW(GetDlgItem(dialog, EditControlId));
    if (length <= 0 || length > 255)
    {
        MessageBoxW(dialog, L"Enter a filename with 1 to 255 UTF-16 units.",
                    L"Invalid filename", MB_OK | MB_ICONWARNING);
        return TRUE;
    }
    std::vector<wchar_t> name(static_cast<std::size_t>(length) + 1u, L'\0');
    if (GetDlgItemTextW(dialog, EditControlId, name.data(),
                        static_cast<int>(name.size())) == 0)
        return TRUE;

    state->name.assign(name.data());
    EndDialog(dialog, IDOK);
    return TRUE;
}
} // namespace UnicodeRenameDialogDetail

// Provides a native UTF-16 text field instead of the legacy ANSI
// CCopyMoveDialog. The caller validates filename semantics and may retry.
inline bool TryPromptUnicodeRename(HWND parent, const std::wstring& currentName,
                                   bool isDirectory, bool selectAll,
                                   std::wstring& requestedName)
{
    requestedName.clear();
    UnicodeRenameDialogDetail::State state{currentName, selectAll, isDirectory};
    const auto data = UnicodeRenameDialogDetail::BuildTemplate();
    if (!data.Valid())
        return false;
    const INT_PTR result = DialogBoxIndirectParamW(
        GetModuleHandleW(nullptr), data.Data(), parent,
        UnicodeRenameDialogDetail::DialogProc,
        reinterpret_cast<LPARAM>(&state));
    if (result != IDOK)
        return false;
    requestedName = std::move(state.name);
    return true;
}
} // namespace Salamander
