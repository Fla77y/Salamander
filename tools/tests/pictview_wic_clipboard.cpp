// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#include "../../src/plugins/pictview/WicImageClipboard.h"
#include "../../src/plugins/pictview/WicImageDecoder.h"

#include <windows.h>
#include <cstdint>
#include <climits>
#include <cstdio>
#include <cstring>
#include <vector>

int main()
{
    pictview::wic::DecodedImage image;
    image.width = 2;
    image.height = 1;
    image.stride = 8;
    image.bgra = {0, 0, 255, 128, 0, 255, 0, 255};
    std::vector<std::uint8_t> dib;
    const HRESULT ok = pictview::wic::PrepareClipboardDib(image, dib);
    bool pass = ok == S_OK && dib.size() == sizeof(BITMAPINFOHEADER) + 8;
    if (pass)
    {
        BITMAPINFOHEADER header{};
        std::memcpy(&header, dib.data(), sizeof(header));
        pass &= header.biSize == sizeof(BITMAPINFOHEADER) &&
                header.biWidth == 2 && header.biHeight == -1 &&
                header.biBitCount == 32 && header.biCompression == BI_RGB &&
                header.biSizeImage == 8;
        const std::vector<std::uint8_t> expected = {127, 127, 255, 255, 0, 255, 0, 255};
        pass &= std::memcmp(dib.data() + sizeof(header), expected.data(), 8) == 0;
    }
    pictview::wic::DecodedImage restored;
    pass &= pictview::wic::ParseClipboardDib(dib.data(), dib.size(), restored) == S_OK &&
            restored.width == 2 && restored.height == 1 &&
            restored.bgra.size() == 8 &&
            restored.bgra[0] == 127 && restored.bgra[2] == 255 &&
            restored.bgra[3] == 255;

    // External clipboard DIBs may be stored bottom-up and in 24-bit BGR.
    std::vector<std::uint8_t> bottomUp(sizeof(BITMAPINFOHEADER) + 16, 0);
    BITMAPINFOHEADER external{};
    external.biSize = sizeof(external);
    external.biWidth = 2;
    external.biHeight = 2;
    external.biPlanes = 1;
    external.biBitCount = 24;
    external.biCompression = BI_RGB;
    std::memcpy(bottomUp.data(), &external, sizeof(external));
    // Bottom row: pixel 3, pixel 4. Top row: pixel 1, pixel 2.
    const std::uint8_t bgr[16] = {
        3, 0, 0, 4, 0, 0, 0, 0,
        1, 0, 0, 2, 0, 0, 0, 0
    };
    std::memcpy(bottomUp.data() + sizeof(external), bgr, sizeof(bgr));
    pass &= pictview::wic::ParseClipboardDib(bottomUp.data(), bottomUp.size(), restored) == S_OK &&
            restored.width == 2 && restored.height == 2 &&
            restored.bgra[0] == 1 && restored.bgra[4] == 2 &&
            restored.bgra[8] == 3 && restored.bgra[12] == 4;

    // Reject malformed header and clear old decoded pixels.
    external.biHeight = INT_MIN;
    std::memcpy(bottomUp.data(), &external, sizeof(external));
    pass &= pictview::wic::ParseClipboardDib(bottomUp.data(), bottomUp.size(), restored) == E_INVALIDARG &&
            restored.bgra.empty() && restored.width == 0;
    pass &= pictview::wic::ParseClipboardDib(bottomUp.data(), 12, restored) == E_INVALIDARG;

    image.stride = 7;
    pass &= pictview::wic::PrepareClipboardDib(image, dib) == E_INVALIDARG &&
            dib.empty();

    if (!pass)
        std::fputs("FAIL: clipboard DIB layout, alpha or invalid data\n", stderr);
    else
        std::puts("PASS: clipboard DIB exact pixels, top-down layout and validation");
    return pass ? 0 : 1;
}
