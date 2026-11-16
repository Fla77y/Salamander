// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/plugins/pictview/WicNativeViewer.h"

#include <cstdio>
#include <string>

int main()
{
    std::wstring wide;
    bool ok = pictview::wic::ConvertSdkPath("C:\\Images\\plain.bmp", wide) &&
              wide == L"C:\\Images\\plain.bmp";
    if (!ok)
        std::fputs("FAIL: round-trip ASCII Win32 SDK path\n", stderr);

    wide.assign(L"stale data");
    ok &= !pictview::wic::ConvertSdkPath(nullptr, wide) && wide.empty();
    if (!wide.empty())
        std::fputs("FAIL: null path must clear destination\n", stderr);

    wide.assign(L"stale data");
    ok &= !pictview::wic::ConvertSdkPath("", wide) && wide.empty();
    if (!wide.empty())
        std::fputs("FAIL: empty path must clear destination\n", stderr);

    std::string excessive(32761, 'x');
    wide.assign(L"stale data");
    ok &= !pictview::wic::ConvertSdkPath(excessive.c_str(), wide) && wide.empty();
    if (!wide.empty())
        std::fputs("FAIL: overlimit path must be rejected without truncation\n", stderr);

    if (ok)
        std::puts("PASS: lossless SDK path boundary and fail-closed validation");
    return ok ? 0 : 1;
}
