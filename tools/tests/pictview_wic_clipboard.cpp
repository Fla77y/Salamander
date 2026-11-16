// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#include "../../src/plugins/pictview/WicImageClipboard.h"
#include "../../src/plugins/pictview/WicImageDecoder.h"

#include <windows.h>
#include <cstdint>
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
    image.stride = 7;
    pass &= pictview::wic::PrepareClipboardDib(image, dib) == E_INVALIDARG &&
            dib.empty();

    if (!pass)
        std::fputs("FAIL: clipboard DIB layout, alpha or invalid data\n", stderr);
    else
        std::puts("PASS: clipboard DIB exact pixels, top-down layout and validation");
    return pass ? 0 : 1;
}
