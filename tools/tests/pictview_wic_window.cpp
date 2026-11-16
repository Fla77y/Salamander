// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
// Opt-in local desktop smoke. Exercises the real native viewer HWND, not the
// Salamander plug-in manager or its legacy process-wide SDK registration.

#include "../../src/plugins/pictview/WicNativeViewer.h"

#include <windows.h>
#include <array>
#include <atomic>
#include <cstdio>
#include <string>
#include <thread>

namespace
{
std::atomic<HWND> opened{nullptr};
std::atomic<int> closed{0};

void OnOpen(HWND window)
{
    opened.store(window);
}

void OnClose(HWND window)
{
    if (window == opened.load())
        ++closed;
}

bool CreateBmpFixture(std::string& path)
{
    char temp[MAX_PATH + 1] = {};
    if (!GetTempPathA(MAX_PATH + 1, temp))
        return false;
    char temporary[MAX_PATH + 1] = {};
    if (!GetTempFileNameA(temp, "pwi", 0, temporary))
        return false;
    DeleteFileA(temporary);
    path = std::string(temporary) + ".bmp";

    constexpr std::array<unsigned char, 62> data = {
        0x42,0x4D,62,0,0,0,0,0,0,0,54,0,0,0,
        40,0,0,0,2,0,0,0,1,0,0,0,1,0,24,0,
        0,0,0,0,8,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,255,0,255,0,0,0
    };
    static_assert(data.size() == 62);
    HANDLE file = CreateFileA(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return false;
    DWORD written = 0;
    const bool ok = WriteFile(file, data.data(), static_cast<DWORD>(data.size()),
                              &written, nullptr) && written == data.size();
    CloseHandle(file);
    return ok;
}
} // namespace

int main()
{
    // Arrange: a disposable image and the same synchronization objects that
    // the Salamander viewer interface supplies to its viewer thread.
    std::string path;
    if (!CreateBmpFixture(path))
    {
        std::fputs("FAIL: could not create BMP fixture\n", stderr);
        return 1;
    }
    HANDLE ready = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!ready)
    {
        DeleteFileA(path.c_str());
        return 1;
    }
    HANDLE lock = nullptr;
    BOOL lockOwner = FALSE;
    BOOL created = FALSE;
    std::atomic<unsigned> viewerResult{UINT_MAX};

    // Act: start the real viewer, wait for its thread-ready notification,
    // exercise key routes, then close the window through its message queue.
    std::thread viewer([&] {
        viewerResult.store(pictview::wic::RunNativeViewer(
            path.c_str(), GetModuleHandleW(nullptr),
            CW_USEDEFAULT, CW_USEDEFAULT, 640, 480,
            SW_SHOWNORMAL, FALSE, TRUE, &lock, &lockOwner, ready, &created,
            OnOpen, OnClose));
    });
    const DWORD startup = WaitForSingleObject(ready, 15000);
    const HWND window = opened.load();
    const bool started = startup == WAIT_OBJECT_0 && created && lockOwner &&
                         lock != nullptr && window && IsWindow(window);
    if (started)
    {
        PostMessageW(window, WM_KEYDOWN, 'R', 0);
        PostMessageW(window, WM_KEYDOWN, 'H', 0);
        PostMessageW(window, WM_KEYDOWN, 'V', 0);
        PostMessageW(window, WM_KEYDOWN, '0', 0);
        PostMessageW(window, WM_CLOSE, 0, 0);
    }
    else if (window)
        PostMessageW(window, WM_CLOSE, 0, 0);

    const DWORD released = lock ? WaitForSingleObject(lock, 15000) : WAIT_FAILED;
    if (viewer.joinable())
        viewer.join();

    // Assert: the window opens, closes, notifies host and releases its lock.
    const bool pass = started && released == WAIT_OBJECT_0 &&
                      closed.load() == 1 && viewerResult.load() == 0;
    if (!pass)
        std::fprintf(stderr,
            "FAIL: WIC HWND contract (started=%d, lock=%lu, closed=%d, result=%u)\n",
            started ? 1 : 0, static_cast<unsigned long>(released),
            closed.load(), viewerResult.load());
    if (lock)
        CloseHandle(lock);
    CloseHandle(ready);
    DeleteFileA(path.c_str());
    if (pass)
        std::puts("PASS: WIC viewer HWND, input, close and Salamander lock contract");
    return pass ? 0 : 1;
}
