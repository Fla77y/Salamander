// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "WicNativeViewer.h"
#include "WicBitmapPresenter.h"
#include "WicImageDecoder.h"
#include "WicImageTransforms.h"
#include "WicImageWriter.h"

#include <commdlg.h>
#pragma comment(lib, "comdlg32.lib")

#include <algorithm>
#include <climits>
#include <cstring>
#include <new>
#include <string>
#include <utility>

namespace pictview::wic
{
namespace
{
constexpr wchar_t kViewerClass[] = L"OpenSalamander.PictView.WIC";
constexpr int kMinimumZoom = 25;
constexpr int kMaximumZoom = 400;

struct WindowState
{
    DecodedImage image;
    std::vector<std::uint8_t> opaque;
    std::wstring path;
    UINT frame = 0;
    UINT frameCount = 0;
    bool fit = true;
    int zoom = 100;
    HANDLE closedEvent = nullptr; // caller owns this handle
    void (*onClose)(HWND) = nullptr;
    bool registeredWithHost = false;
};

// Decode a frame transactionally. On failure the displayed frame is retained.
bool LoadFrame(WindowState& state, UINT index)
{
    DecodedImage next;
    UINT frameCount = 0;
    if (FAILED(DecodeFrame(state.path.c_str(), index, next, &frameCount)))
        return false;
    std::vector<std::uint8_t> opaque;
    if (FAILED(PrepareOpaqueBgra(next, opaque)))
        return false;
    state.image = std::move(next);
    state.opaque = std::move(opaque);
    state.frame = index;
    state.frameCount = frameCount;
    return true;
}

// Changes only the current in-memory frame. On failure, the displayed image
// and compositor pixels remain unchanged; the source file is never modified.
bool TransformFrame(WindowState& state, ImageTransform operation) noexcept
{
    try
    {
        DecodedImage transformed = state.image;
        if (FAILED(TransformImage(transformed, operation)))
            return false;
        std::vector<std::uint8_t> opaque;
        if (FAILED(PrepareOpaqueBgra(transformed, opaque)))
            return false;
        state.image = std::move(transformed);
        state.opaque = std::move(opaque);
        return true;
    }
    catch (...)
    {
        return false;
    }
}

// Save Copy is deliberately non-destructive: existing paths are rejected by
// CREATE_NEW in SaveNewImage, regardless of races or dialog behavior.
void SaveCopy(HWND hwnd, const WindowState& state) noexcept
{
    try
    {
        std::vector<wchar_t> path(32768, L'\0');
        static constexpr wchar_t filters[] =
            L"PNG (*.png)\0*.png\0"
            L"JPEG (*.jpg)\0*.jpg;*.jpeg\0"
            L"Bitmap (*.bmp)\0*.bmp\0"
            L"TIFF (*.tif)\0*.tif;*.tiff\0\0";

        OPENFILENAMEW dialog{};
        dialog.lStructSize = sizeof(dialog);
        dialog.hwndOwner = hwnd;
        dialog.lpstrFilter = filters;
        dialog.nFilterIndex = 1;
        dialog.lpstrFile = path.data();
        dialog.nMaxFile = static_cast<DWORD>(path.size());
        dialog.lpstrDefExt = L"png";
        dialog.lpstrTitle = L"Save a copy (existing files will not be replaced)";
        dialog.Flags = OFN_EXPLORER | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
        if (!GetSaveFileNameW(&dialog))
            return;

        ImageFileFormat format = ImageFileFormat::Png;
        switch (dialog.nFilterIndex)
        {
        case 1: format = ImageFileFormat::Png; break;
        case 2: format = ImageFileFormat::Jpeg; break;
        case 3: format = ImageFileFormat::Bmp; break;
        case 4: format = ImageFileFormat::Tiff; break;
        default: return;
        }

        const HRESULT hr = SaveNewImage(path.data(), state.image, format);
        if (FAILED(hr))
        {
            const bool exists =
                hr == HRESULT_FROM_WIN32(ERROR_FILE_EXISTS) ||
                hr == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS);
            MessageBoxW(hwnd,
                exists ? L"The destination already exists. Choose a new file name."
                       : L"Image export failed. The source file was not modified.",
                L"PictView", MB_OK | MB_ICONERROR);
        }
    }
    catch (...)
    {
        MessageBoxW(hwnd, L"Image export failed. The source file was not modified.",
                    L"PictView", MB_OK | MB_ICONERROR);
    }
}

// Draws a decoded image without retaining any GDI resources between paints.
void Paint(WindowState& state, HWND hwnd)
{
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(hwnd, &paint);
    if (!dc)
        return;

    RECT client{};
    GetClientRect(hwnd, &client);
    FillRect(dc, &client, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));

    RECT destination = client;
    if (!state.fit)
    {
        const std::int64_t w = static_cast<std::int64_t>(state.image.width) * state.zoom / 100;
        const std::int64_t h = static_cast<std::int64_t>(state.image.height) * state.zoom / 100;
        if (w > 0 && h > 0 && w <= INT_MAX && h <= INT_MAX)
        {
            const std::int64_t cw = static_cast<std::int64_t>(client.right) - client.left;
            const std::int64_t ch = static_cast<std::int64_t>(client.bottom) - client.top;
            const std::int64_t x = (cw - w) / 2;
            const std::int64_t y = (ch - h) / 2;
            if (x >= INT_MIN && x + w <= INT_MAX && y >= INT_MIN && y + h <= INT_MAX)
            {
                destination = {static_cast<LONG>(x), static_cast<LONG>(y),
                               static_cast<LONG>(x + w), static_cast<LONG>(y + h)};
            }
            else
                FitImage(state.image.width, state.image.height, client, destination);
        }
        else
            FitImage(state.image.width, state.image.height, client, destination);
    }
    else
        FitImage(state.image.width, state.image.height, client, destination);

    PaintOpaqueBgraAt(dc, destination, state.image.width,
                      state.image.height, state.image.stride, state.opaque);
    EndPaint(hwnd, &paint);
}

// The HWND has a stack-owned state whose lifetime ends only after DestroyWindow.
LRESULT CALLBACK ViewerProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    auto* state = reinterpret_cast<WindowState*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(create->lpCreateParams));
        return TRUE;
    }

    switch (message)
    {
    case WM_ERASEBKGND:
        return 1; // WM_PAINT fills the background before blitting
    case WM_PAINT:
        if (state)
        {
            Paint(*state, hwnd);
            return 0;
        }
        break;
    case WM_SIZE:
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    case WM_MOUSEWHEEL:
        if (state)
        {
            state->fit = false;
            state->zoom = std::clamp(state->zoom +
                (GET_WHEEL_DELTA_WPARAM(wParam) > 0 ? 25 : -25),
                kMinimumZoom, kMaximumZoom);
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        }
        break;
    case WM_KEYDOWN:
        if (state)
        {
            switch (wParam)
            {
            case VK_ESCAPE:
                DestroyWindow(hwnd);
                return 0;
            case VK_ADD:
            case VK_OEM_PLUS:
                state->fit = false;
                state->zoom = (std::min)(kMaximumZoom, state->zoom + 25);
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            case VK_SUBTRACT:
            case VK_OEM_MINUS:
                state->fit = false;
                state->zoom = (std::max)(kMinimumZoom, state->zoom - 25);
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            case VK_NEXT:
            case VK_PRIOR:
            {
                const UINT next = wParam == VK_NEXT ? state->frame + 1 :
                                  (state->frame > 0 ? state->frame - 1 : state->frame);
                if (next < state->frameCount && next != state->frame &&
                    LoadFrame(*state, next))
                {
                    InvalidateRect(hwnd, nullptr, FALSE);
                }
                return 0;
            }
            case 'S':
                if (GetKeyState(VK_CONTROL) < 0 && GetKeyState(VK_SHIFT) < 0)
                {
                    SaveCopy(hwnd, *state);
                    return 0;
                }
                break;
            case 'R':
                if (TransformFrame(*state,
                                   GetKeyState(VK_SHIFT) < 0 ?
                                       ImageTransform::RotateCounterclockwise :
                                       ImageTransform::RotateClockwise))
                    InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            case 'H':
                if (TransformFrame(*state, ImageTransform::FlipHorizontal))
                    InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            case 'V':
                if (TransformFrame(*state, ImageTransform::FlipVertical))
                    InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            case '0':
                state->fit = true;
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            }
        }
        break;
    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    case WM_NCDESTROY:
        if (state)
        {
            if (state->registeredWithHost && state->onClose)
                state->onClose(hwnd);
            if (state->closedEvent)
                SetEvent(state->closedEvent);
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        }
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

// Register once per plugin instance; concurrent viewers may observe an already
// registered class, which is not a failure.
bool RegisterViewer(HINSTANCE instance)
{
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.hInstance = instance;
    wc.lpszClassName = kViewerClass;
    wc.lpfnWndProc = ViewerProc;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    return RegisterClassExW(&wc) != 0 ||
           GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}
} // namespace

bool ConvertSdkPath(const char* path, std::wstring& output) noexcept
{
    output.clear();
    if (!path || !*path)
        return false;
    try
    {
        const std::size_t length = std::strlen(path);
        if (length > 32760)
            return false;
        const int count = MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS,
                                               path, -1, nullptr, 0);
        if (count <= 1)
            return false;

        std::wstring wide(static_cast<std::size_t>(count), L'\0');
        if (MultiByteToWideChar(CP_ACP, MB_ERR_INVALID_CHARS,
                                path, -1, wide.data(), count) != count)
            return false;

        const bool isUtf8Acp = GetACP() == CP_UTF8;
        BOOL usedDefault = FALSE;
        const DWORD flags = isUtf8Acp ? WC_ERR_INVALID_CHARS : WC_NO_BEST_FIT_CHARS;
        const int bytes = WideCharToMultiByte(CP_ACP, flags, wide.c_str(), count,
                                               nullptr, 0, nullptr,
                                               isUtf8Acp ? nullptr : &usedDefault);
        if (bytes <= 0 || usedDefault)
            return false;
        std::string check(static_cast<std::size_t>(bytes), '\0');
        if (WideCharToMultiByte(CP_ACP, flags, wide.c_str(), count,
                                check.data(), bytes, nullptr,
                                isUtf8Acp ? nullptr : &usedDefault) != bytes ||
            usedDefault || check != std::string(path, length + 1))
            return false;

        wide.pop_back(); // remove terminator owned by std::wstring
        output = std::move(wide);
        return true;
    }
    catch (...)
    {
        output.clear();
        return false;
    }
}

unsigned RunNativeViewer(const char* path, HINSTANCE instance,
                         int left, int top, int width, int height,
                         UINT showCommand, BOOL alwaysOnTop,
                         BOOL returnLock, HANDLE* lock, BOOL* lockOwner,
                         HANDLE ready, BOOL* created,
                         void (*onOpen)(HWND), void (*onClose)(HWND)) noexcept
{
    if (!ready || !created)
        return 1;
    *created = FALSE;
    if (returnLock && (!lock || !lockOwner))
    {
        SetEvent(ready);
        return 1;
    }
    if (returnLock)
    {
        *lock = nullptr;
        *lockOwner = FALSE;
    }

    bool notified = false;
    HANDLE localLock = nullptr;
    HWND hwnd = nullptr;
    HRESULT com = E_FAIL;
    auto notify = [&]() {
        if (!notified)
        {
            notified = true;
            SetEvent(ready);
        }
    };

    try
    {
        WindowState state;
        if (!ConvertSdkPath(path, state.path))
        {
            notify();
            return 1;
        }

        com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (FAILED(com) && com != RPC_E_CHANGED_MODE)
        {
            notify();
            return 1;
        }

        if (!LoadFrame(state, 0) || !RegisterViewer(instance))
        {
            if (SUCCEEDED(com))
                CoUninitialize();
            notify();
            return 1;
        }

        if (returnLock)
        {
            localLock = CreateEventW(nullptr, FALSE, FALSE, nullptr);
            if (!localLock)
            {
                if (SUCCEEDED(com))
                    CoUninitialize();
                notify();
                return 1;
            }
            state.closedEvent = localLock;
        }
        state.onClose = onClose;

        hwnd = CreateWindowExW(alwaysOnTop ? WS_EX_TOPMOST : 0,
                               kViewerClass, state.path.c_str(),
                               WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                               left, top, width > 0 ? width : 800,
                               height > 0 ? height : 600,
                               nullptr, nullptr, instance, &state);
        if (!hwnd)
        {
            if (localLock)
                CloseHandle(localLock);
            if (SUCCEEDED(com))
                CoUninitialize();
            notify();
            return 1;
        }

        if (onOpen)
        {
            onOpen(hwnd);
            state.registeredWithHost = true;
        }
        if (returnLock)
        {
            *lock = localLock; // host owns the HANDLE from here
            *lockOwner = TRUE;
        }
        *created = TRUE;
        notify();

        ShowWindow(hwnd, showCommand);
        UpdateWindow(hwnd);
        MSG message{};
        while (GetMessageW(&message, nullptr, 0, 0) > 0)
        {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        if (IsWindow(hwnd))
            DestroyWindow(hwnd);
        if (SUCCEEDED(com))
            CoUninitialize();
        return 0;
    }
    catch (...)
    {
        if (hwnd && IsWindow(hwnd))
            DestroyWindow(hwnd);
        else if (localLock)
            CloseHandle(localLock);
        if (SUCCEEDED(com))
            CoUninitialize();
        notify();
        return 1;
    }
}

void UnregisterNativeViewerClass(HINSTANCE instance) noexcept
{
    UnregisterClassW(kViewerClass, instance);
}
} // namespace pictview::wic
