// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "win32_unicode_find.h"
#include "win32_unicode_file_ops.h"
#include "win32_unicode_rename_dialog.h"
#include "win32_unicode_recycle.h"
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>

#include <atomic>
#include <cwchar>
#include <functional>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace Salamander
{
// Modeless UTF-16 search window for physical disk panels. The existing Find
// dialog remains available for its advanced legacy criteria; it is not
// modified to accept paths its ANSI result model cannot safely represent.
class UnicodeFindWindow
{
    enum ControlId
    {
        Root = 5101,
        Masks,
        Content,
        Target,
        Recurse,
        IncludeDirs,
        Find,
        Cancel,
        CopyPath,
        OpenFile,
        CopyResult,
        MoveResult,
        RenameResult,
        RecycleResult,
        Advanced,
        Close,
        Results,
        Status
    };
    static constexpr UINT WM_FIND_UPDATE = WM_APP + 191;

    HWND window_ = nullptr;
    HWND root_ = nullptr;
    HWND masks_ = nullptr;
    HWND content_ = nullptr;
    HWND target_ = nullptr;
    HWND recurse_ = nullptr;
    HWND includeDirs_ = nullptr;
    HWND results_ = nullptr;
    HWND status_ = nullptr;
    std::wstring initialRoot_;
    std::function<void(const std::wstring&)> legacyFind_;
    std::thread worker_;
    std::mutex queueMutex_;
    std::vector<UnicodeFindHit> pending_;
    std::vector<UnicodeFindHit> displayed_;
    std::atomic<bool> cancellation_{false};
    std::atomic<bool> running_{false};
    bool finished_ = false;
    DWORD searchError_ = ERROR_SUCCESS;
    bool searchSucceeded_ = false;
    bool ownedByWindow_ = false;

    static std::wstring ReadText(HWND edit)
    {
        const int size = GetWindowTextLengthW(edit);
        if (size < 0 || size >= 32767)
            return {};
        std::wstring result(static_cast<std::size_t>(size) + 1, L'\0');
        const int copied = GetWindowTextW(edit, &result[0], size + 1);
        result.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0);
        return result;
    }

    static HWND Child(HWND parent, const wchar_t* cls, const wchar_t* text,
                      DWORD style, int id, DWORD extendedStyle = 0)
    {
        HWND child = CreateWindowExW(extendedStyle, cls, text,
                                     WS_CHILD | WS_VISIBLE | style,
                                     0, 0, 0, 0, parent,
                                     reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
                                     GetModuleHandleW(nullptr), nullptr);
        if (child)
            SendMessageW(child, WM_SETFONT,
                         reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
        return child;
    }

    void Initialize(HWND window)
    {
        window_ = window;
        INITCOMMONCONTROLSEX icc{sizeof(icc), ICC_LISTVIEW_CLASSES};
        InitCommonControlsEx(&icc);
        Child(window, L"STATIC", L"Look in:", 0, 0);
        root_ = Child(window, L"EDIT", initialRoot_.c_str(),
                      WS_TABSTOP | ES_AUTOHSCROLL, Root, WS_EX_CLIENTEDGE);
        SendMessageW(root_, EM_LIMITTEXT, 32766, 0);
        Child(window, L"STATIC", L"Named:", 0, 0);
        masks_ = Child(window, L"EDIT", L"*",
                       WS_TABSTOP | ES_AUTOHSCROLL, Masks, WS_EX_CLIENTEDGE);
        Child(window, L"STATIC", L"Containing (UTF-8/UTF-16LE):", 0, 0);
        content_ = Child(window, L"EDIT", L"",
                         WS_TABSTOP | ES_AUTOHSCROLL, Content, WS_EX_CLIENTEDGE);
        Child(window, L"STATIC", L"Destination (full path):", 0, 0);
        target_ = Child(window, L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL,
                        Target, WS_EX_CLIENTEDGE);
        SendMessageW(target_, EM_LIMITTEXT, 32766, 0);
        recurse_ = Child(window, L"BUTTON", L"Include subdirectories",
                         BS_AUTOCHECKBOX | WS_TABSTOP, Recurse);
        SendMessageW(recurse_, BM_SETCHECK, BST_CHECKED, 0);
        includeDirs_ = Child(window, L"BUTTON", L"Include matching directories",
                             BS_AUTOCHECKBOX | WS_TABSTOP, IncludeDirs);
        SendMessageW(includeDirs_, BM_SETCHECK, BST_CHECKED, 0);
        Child(window, L"BUTTON", L"Find now", BS_PUSHBUTTON | WS_TABSTOP, Find);
        Child(window, L"BUTTON", L"Cancel", BS_PUSHBUTTON | WS_TABSTOP, Cancel);
        Child(window, L"BUTTON", L"Copy full path", BS_PUSHBUTTON | WS_TABSTOP, CopyPath);
        Child(window, L"BUTTON", L"Open", BS_PUSHBUTTON | WS_TABSTOP, OpenFile);
        Child(window, L"BUTTON", L"Copy file to destination",
              BS_PUSHBUTTON | WS_TABSTOP, CopyResult);
        Child(window, L"BUTTON", L"Move file to destination",
              BS_PUSHBUTTON | WS_TABSTOP, MoveResult);
        Child(window, L"BUTTON", L"Rename", BS_PUSHBUTTON | WS_TABSTOP, RenameResult);
        Child(window, L"BUTTON", L"Recycle", BS_PUSHBUTTON | WS_TABSTOP, RecycleResult);
        Child(window, L"BUTTON", L"Advanced (legacy)", BS_PUSHBUTTON | WS_TABSTOP, Advanced);
        Child(window, L"BUTTON", L"Close", BS_PUSHBUTTON | WS_TABSTOP, Close);
        results_ = Child(window, WC_LISTVIEWW, L"",
                          LVS_REPORT | LVS_SHOWSELALWAYS | WS_TABSTOP,
                          Results, WS_EX_CLIENTEDGE);
        SendMessageW(results_, LVM_SETEXTENDEDLISTVIEWSTYLE,
                     LVS_EX_FULLROWSELECT, LVS_EX_FULLROWSELECT);
        SendMessageW(results_, LVM_SETUNICODEFORMAT, TRUE, 0);
        const struct { const wchar_t* label; int width; } columns[] = {
            {L"Filename", 270}, {L"Directory (UTF-16)", 540}, {L"Size (bytes)", 110}
        };
        for (int index = 0; index != 3; ++index)
        {
            LVCOLUMNW column{};
            column.mask = LVCF_FMT | LVCF_TEXT | LVCF_WIDTH;
            column.fmt = LVCFMT_LEFT;
            column.pszText = const_cast<LPWSTR>(columns[index].label);
            column.cx = columns[index].width;
            SendMessageW(results_, LVM_INSERTCOLUMNW, index,
                         reinterpret_cast<LPARAM>(&column));
        }
        status_ = Child(window, L"STATIC",
                        L"Search preserves complete Unicode names and long paths.",
                        0, Status);
        Layout();
    }

    HWND GetControl(int id) const { return GetDlgItem(window_, id); }

    void Layout()
    {
        RECT r{};
        GetClientRect(window_, &r);
        const int width = r.right - r.left;
        const int height = r.bottom - r.top;
        const int inset = 12;
        const int contentWidth = width - 2 * inset;
        const int labelWidth = 175;
        const int editX = inset + labelWidth;
        const int editWidth = contentWidth - labelWidth;
        // Three rows of search controls plus a status line. The listview
        // takes all remaining space and never overlaps the command buttons.
        MoveWindow(root_, editX, 12, editWidth, 24, TRUE);
        // The label windows need distinct identities: static id 0 is used
        // by more than one, so enumerate siblings in creation order below.
        HWND label = GetWindow(window_, GW_CHILD);
        // Controls are in reverse creation order; place all static labels
        // through their expected preceding edit sibling instead.
        for (HWND child = label; child; child = GetWindow(child, GW_HWNDNEXT))
        {
            if (child == status_)
                continue;
            if (GetDlgCtrlID(child) != 0)
                continue;
            wchar_t caption[96]{};
            GetWindowTextW(child, caption, 96);
            int y = 12;
            if (wcscmp(caption, L"Named:") == 0) y = 44;
            else if (wcsncmp(caption, L"Containing", 10) == 0) y = 76;
            else if (wcsncmp(caption, L"Destination", 11) == 0) y = 108;
            MoveWindow(child, inset, y, labelWidth, 24, TRUE);
        }
        MoveWindow(masks_, editX, 44, editWidth, 24, TRUE);
        MoveWindow(content_, editX, 76, editWidth, 24, TRUE);
        MoveWindow(target_, editX, 108, editWidth, 24, TRUE);
        MoveWindow(recurse_, inset, 141, 195, 26, TRUE);
        MoveWindow(includeDirs_, 222, 141, 235, 26, TRUE);

        const int yButtons = 172;
        const struct { int id; int w; } buttons[] = {
            {Find, 92}, {Cancel, 75}, {CopyPath, 112},
            {OpenFile, 72}, {Advanced, 155}, {Close, 72}
        };
        int x = inset;
        for (const auto& b : buttons)
        {
            MoveWindow(GetControl(b.id), x, yButtons, b.w, 27, TRUE);
            x += b.w + 7;
        }
        const struct { int id; int w; } fileButtons[] = {
            {CopyResult, 180}, {MoveResult, 180}, {RenameResult, 100},
            {RecycleResult, 105}
        };
        x = inset;
        for (const auto& b : fileButtons)
        {
            MoveWindow(GetControl(b.id), x, 210, b.w, 27, TRUE);
            x += b.w + 7;
        }
        const int listTop = 251;
        const int statusHeight = 27;
        MoveWindow(results_, inset, listTop, contentWidth,
                   height > listTop + statusHeight + inset ?
                   height - listTop - statusHeight - inset : 30, TRUE);
        MoveWindow(status_, inset, height - statusHeight - 4, contentWidth,
                   statusHeight, TRUE);
    }

    void Append(const UnicodeFindHit& hit)
    {
        const int index = static_cast<int>(displayed_.size());
        displayed_.push_back(hit);
        LVITEMW row{};
        row.mask = LVIF_TEXT;
        row.iItem = index;
        row.iSubItem = 0;
        row.pszText = const_cast<LPWSTR>(displayed_.back().name.c_str());
        if (SendMessageW(results_, LVM_INSERTITEMW, 0,
                         reinterpret_cast<LPARAM>(&row)) == -1)
            return;
        row.iSubItem = 1;
        row.pszText = const_cast<LPWSTR>(displayed_.back().directory.c_str());
        SendMessageW(results_, LVM_SETITEMTEXTW, index,
                     reinterpret_cast<LPARAM>(&row));
        wchar_t bytes[40]{};
        swprintf_s(bytes, L"%llu",
                   static_cast<unsigned long long>(displayed_.back().size));
        row.iSubItem = 2;
        row.pszText = bytes;
        SendMessageW(results_, LVM_SETITEMTEXTW, index,
                     reinterpret_cast<LPARAM>(&row));
    }

    void ConsumeResults()
    {
        std::vector<UnicodeFindHit> batch;
        bool done = false;
        bool succeeded = false;
        DWORD error = ERROR_SUCCESS;
        {
            std::lock_guard<std::mutex> lock(queueMutex_);
            batch.swap(pending_);
            done = finished_;
            succeeded = searchSucceeded_;
            error = searchError_;
        }
        for (const auto& hit : batch)
            Append(hit);
        if (done)
        {
            if (worker_.joinable())
                worker_.join();
            running_.store(false);
            wchar_t message[240]{};
            if (succeeded)
                swprintf_s(message, L"Completed: %llu Unicode results.",
                           static_cast<unsigned long long>(displayed_.size()));
            else if (error == ERROR_CANCELLED)
                swprintf_s(message, L"Search cancelled: %llu results displayed.",
                           static_cast<unsigned long long>(displayed_.size()));
            else
                swprintf_s(message, L"Search incomplete (Win32 error %lu). "
                           L"%llu results displayed.", error,
                           static_cast<unsigned long long>(displayed_.size()));
            SetWindowTextW(status_, message);
        }
        else
        {
            wchar_t message[110]{};
            swprintf_s(message, L"Searching... %llu results",
                       static_cast<unsigned long long>(displayed_.size()));
            SetWindowTextW(status_, message);
        }
    }

    void Start()
    {
        if (running_.load())
            return;
        if (worker_.joinable())
            worker_.join();
        UnicodeFindOptions options;
        options.root = ReadText(root_);
        options.masks = ReadText(masks_);
        options.content = ReadText(content_);
        options.includeSubdirectories =
            SendMessageW(recurse_, BM_GETCHECK, 0, 0) == BST_CHECKED;
        options.includeDirectories =
            SendMessageW(includeDirs_, BM_GETCHECK, 0, 0) == BST_CHECKED;
        options.maximumResults = 25000; // explicit cap, never silent truncation
        std::wstring validated;
        DWORD error = ERROR_SUCCESS;
        if (!TryMakeExtendedLengthPath(options.root.c_str(), validated, error))
        {
            SetWindowTextW(status_, L"Invalid or too-long absolute search root.");
            return;
        }
        SendMessageW(results_, LVM_DELETEALLITEMS, 0, 0);
        displayed_.clear();
        {
            std::lock_guard<std::mutex> lock(queueMutex_);
            pending_.clear();
            finished_ = false;
            searchError_ = ERROR_SUCCESS;
        }
        cancellation_.store(false);
        running_.store(true);
        SetWindowTextW(status_, L"Searching...");
        try
        {
            worker_ = std::thread([this, options] {
                DWORD searchError = ERROR_SUCCESS;
                const bool success = SearchUnicodeDirectory(options,
                    [this](const UnicodeFindHit& hit) {
                        bool notify = false;
                        {
                            std::lock_guard<std::mutex> lock(queueMutex_);
                            pending_.push_back(hit);
                            notify = pending_.size() >= 64;
                        }
                        if (notify)
                            PostMessageW(window_, WM_FIND_UPDATE, 0, 0);
                        return !cancellation_.load();
                    }, &cancellation_, searchError);
                {
                    std::lock_guard<std::mutex> lock(queueMutex_);
                    searchSucceeded_ = success;
                    searchError_ = searchError;
                    finished_ = true;
                }
                PostMessageW(window_, WM_FIND_UPDATE, 0, 0);
            });
        }
        catch (...)
        {
            running_.store(false);
            SetWindowTextW(status_, L"Unable to start the search worker.");
        }
    }

    int SelectedIndex() const
    {
        return static_cast<int>(SendMessageW(results_, LVM_GETNEXTITEM, -1, LVNI_SELECTED));
    }

    // Convert the exact result path into the immutable validated W-operation
    // model, never through a legacy ANSI alias.
    static bool OwnPath(const std::wstring& text, Utf16DiskPath& owned)
    {
        static_assert(sizeof(wchar_t) == sizeof(char16_t),
                      "Find result operations require Windows UTF-16");
        Utf16PathError error = Utf16PathError::None;
        return Utf16DiskPath::TryCreateAbsolute(
            std::u16string(text.begin(), text.end()), owned, error);
    }

    bool OriginalResultUnchanged(const UnicodeFindHit& hit)
    {
        std::wstring extended;
        DWORD error = ERROR_SUCCESS;
        if (!TryMakeExtendedLengthPath(hit.FullPath().c_str(), extended, error))
            return false;
        WIN32_FILE_ATTRIBUTE_DATA actual{};
        if (!GetFileAttributesExW(extended.c_str(), GetFileExInfoStandard, &actual))
            return false;
        const std::uint64_t size =
            (static_cast<std::uint64_t>(actual.nFileSizeHigh) << 32) |
            actual.nFileSizeLow;
        return actual.dwFileAttributes == hit.attributes &&
               ((hit.attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
                (size == hit.size &&
                 CompareFileTime(&actual.ftLastWriteTime, &hit.lastWrite) == 0));
    }

    void RunFileAction(int command)
    {
        const int index = SelectedIndex();
        if (index < 0 || static_cast<std::size_t>(index) >= displayed_.size())
            return;
        const UnicodeFindHit hit = displayed_[index];
        if (!OriginalResultUnchanged(hit))
        {
            SetWindowTextW(status_, L"The result has changed since the search. "
                            L"Search again before performing a file action.");
            return;
        }

        const bool isDirectory =
            (hit.attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        Utf16DiskPath source;
        if (!OwnPath(hit.FullPath(), source))
        {
            SetWindowTextW(status_, L"Result path is not valid for a file operation.");
            return;
        }
        if (command == RecycleResult)
        {
            // Existing IFileOperation adapter is deliberately limited to
            // short local files. Never silently turn a recycle into deletion.
            HRESULT hresult = E_FAIL;
            if (!isDirectory && TryRecycleUnicodeFile(source, window_, hresult))
            {
                SendMessageW(results_, LVM_DELETEITEM, index, 0);
                displayed_.erase(displayed_.begin() + index);
                SetWindowTextW(status_, L"File moved to the Recycle Bin.");
            }
            else
                SetWindowTextW(status_, L"Recycle unsupported or refused. "
                                L"No permanent delete was attempted.");
            return;
        }

        std::wstring destination;
        if (command == RenameResult)
        {
            std::wstring newName;
            if (!TryPromptUnicodeRename(window_, hit.name, isDirectory, false, newName))
                return;
            destination = hit.directory +
                (hit.directory.back() == L'\\' ? L"" : L"\\") + newName;
        }
        else
            destination = ReadText(target_);
        Utf16DiskPath target;
        if (!OwnPath(destination, target))
        {
            SetWindowTextW(status_, L"Enter a valid absolute Unicode destination path.");
            return;
        }
        if (isDirectory && command == CopyResult)
        {
            SetWindowTextW(status_, L"Recursive directory copy is not supported "
                            L"by this safe single-file operation.");
            return;
        }
        DWORD error = ERROR_SUCCESS;
        bool succeeded = false;
        if (command == CopyResult)
            succeeded = TryCopyUnicodeFileNoOverwrite(source, target, error);
        else if (isDirectory)
            succeeded = TryMoveUnicodeDirectoryNoOverwrite(source, target, error);
        else
            succeeded = TryMoveUnicodeFileNoOverwrite(source, target, error);
        if (!succeeded)
        {
            wchar_t message[110]{};
            swprintf_s(message, L"File action rejected (Win32 %lu). "
                       L"No overwrite fallback was attempted.", error);
            SetWindowTextW(status_, message);
            return;
        }
        if (command != CopyResult)
        {
            SendMessageW(results_, LVM_DELETEITEM, index, 0);
            displayed_.erase(displayed_.begin() + index);
        }
        SetWindowTextW(status_, L"Unicode file action completed. "
                        L"No existing destination was overwritten.");
    }

    void CopySelectedPath()
    {
        const int index = SelectedIndex();
        if (index < 0 || static_cast<std::size_t>(index) >= displayed_.size())
            return;
        const std::wstring path = displayed_[index].FullPath();
        if (!OpenClipboard(window_))
            return;
        if (EmptyClipboard())
        {
            const SIZE_T bytes = (path.size() + 1) * sizeof(wchar_t);
            HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
            if (memory)
            {
                void* destination = GlobalLock(memory);
                if (destination)
                {
                    memcpy(destination, path.c_str(), bytes);
                    GlobalUnlock(memory);
                    if (SetClipboardData(CF_UNICODETEXT, memory))
                        memory = nullptr;
                }
                if (memory)
                    GlobalFree(memory);
            }
        }
        CloseClipboard();
    }

    void OpenSelected()
    {
        const int index = SelectedIndex();
        if (index < 0 || static_cast<std::size_t>(index) >= displayed_.size())
            return;
        const std::wstring file = displayed_[index].FullPath();
        // Shell extensions are not guaranteed to accept extended-length
        // paths even though filesystem Win32 W APIs can. Refuse rather
        // than passing a truncated identity or an ANSI best-fit alias.
        if (file.size() >= MAX_PATH)
        {
            MessageBoxW(window_, L"Windows shell associations may not support "
                        L"this long path. Use Copy full path instead.",
                        L"Unicode Find", MB_OK | MB_ICONINFORMATION);
            return;
        }
        const HINSTANCE result = ShellExecuteW(window_, L"open", file.c_str(),
                                               nullptr, nullptr, SW_SHOWNORMAL);
        if (reinterpret_cast<INT_PTR>(result) <= 32)
            MessageBoxW(window_, L"Windows could not open this file.",
                        L"Unicode Find", MB_OK | MB_ICONWARNING);
    }

    void OpenLegacy()
    {
        if (!legacyFind_)
            return;
        const std::wstring root = ReadText(root_);
        if (root.size() >= MAX_PATH)
        {
            MessageBoxW(window_, L"The legacy advanced Find interface cannot "
                        L"represent the current root. Shorten the path or use "
                        L"this Unicode search.",
                        L"Unicode Find", MB_OK | MB_ICONINFORMATION);
            return;
        }
        legacyFind_(root);
    }

    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message,
                                             WPARAM wParam, LPARAM lParam)
    {
        UnicodeFindWindow* state = reinterpret_cast<UnicodeFindWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE)
        {
            auto* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
            state = static_cast<UnicodeFindWindow*>(create->lpCreateParams);
            SetWindowLongPtrW(window, GWLP_USERDATA,
                              reinterpret_cast<LONG_PTR>(state));
            return TRUE;
        }
        if (!state)
            return DefWindowProcW(window, message, wParam, lParam);
        switch (message)
        {
        case WM_CREATE:
            state->Initialize(window);
            return 0;
        case WM_SIZE:
            state->Layout();
            return 0;
        case WM_FIND_UPDATE:
            state->ConsumeResults();
            return 0;
        case WM_NOTIFY:
            if (reinterpret_cast<NMHDR*>(lParam)->idFrom == Results &&
                reinterpret_cast<NMHDR*>(lParam)->code == NM_DBLCLK)
                state->OpenSelected();
            return 0;
        case WM_COMMAND:
            if (HIWORD(wParam) == BN_CLICKED)
            {
                switch (LOWORD(wParam))
                {
                case Find: state->Start(); break;
                case Cancel: state->cancellation_.store(true); break;
                case CopyPath: state->CopySelectedPath(); break;
                case OpenFile: state->OpenSelected(); break;
                case CopyResult:
                case MoveResult:
                case RenameResult:
                case RecycleResult: state->RunFileAction(LOWORD(wParam)); break;
                case Advanced: state->OpenLegacy(); break;
                case Close: DestroyWindow(window); break;
                }
            }
            return 0;
        case WM_CLOSE:
            DestroyWindow(window);
            return 0;
        case WM_NCDESTROY:
            state->cancellation_.store(true);
            if (state->worker_.joinable())
                state->worker_.join();
            SetWindowLongPtrW(window, GWLP_USERDATA, 0);
            // Failed window creation is still owned by Open(); otherwise
            // WM_NCDESTROY is the sole owner of the state.
            if (state->ownedByWindow_)
                delete state;
            return DefWindowProcW(window, message, wParam, lParam);
        }
        return DefWindowProcW(window, message, wParam, lParam);
    }

public:
    UnicodeFindWindow(std::wstring initialRoot,
                      std::function<void(const std::wstring&)> legacyFind)
        : initialRoot_(std::move(initialRoot)),
          legacyFind_(std::move(legacyFind))
    {
    }

    // Opens a modeless Unicode result window. Lifetime is owned by HWND and
    // terminated only after the background search worker has been cancelled.
    static bool Open(HWND owner, const std::wstring& initialRoot,
                     std::function<void(const std::wstring&)> legacyFind)
    {
        const wchar_t* cls = L"OpenSalUnicodeFindWindow";
        WNDCLASSEXW info{};
        info.cbSize = sizeof(info);
        info.lpfnWndProc = &WindowProcedure;
        info.hInstance = GetModuleHandleW(nullptr);
        info.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        info.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
        info.lpszClassName = cls;
        if (!RegisterClassExW(&info) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
            return false;

        UnicodeFindWindow* state = new (std::nothrow)
            UnicodeFindWindow(initialRoot, std::move(legacyFind));
        if (!state)
            return false;
        HWND window = CreateWindowExW(WS_EX_APPWINDOW, cls,
            L"Open Salamander — Unicode Find (UTF-16 / long paths)",
            WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
            CW_USEDEFAULT, CW_USEDEFAULT, 1100, 780,
            owner, nullptr, GetModuleHandleW(nullptr), state);
        if (!window)
        {
            delete state;
            return false;
        }
        state->ownedByWindow_ = true;
        ShowWindow(window, SW_SHOW);
        UpdateWindow(window);
        return true;
    }
};
} // namespace Salamander
