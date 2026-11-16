// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
// Regression contracts for the WIC -> GDI presentation boundary.

#include "../../src/plugins/pictview/WicBitmapPresenter.h"

#include <algorithm>
#include <array>
#include <cstdio>
#include <vector>

namespace
{
bool Check(bool condition, const char* reason)
{
    if (!condition)
        std::fprintf(stderr, "FAIL: %s\n", reason);
    return condition;
}
} // namespace

int main()
{
    using pictview::wic::DecodedImage;
    using pictview::wic::PrepareOpaqueBgra;
    using pictview::wic::FitImage;

    // Arrange: straight-alpha red 50% over white, and opaque green.
    DecodedImage image;
    image.width = 2;
    image.height = 1;
    image.stride = 8;
    image.bgra = {0, 0, 255, 128, 0, 255, 0, 255};
    std::vector<std::uint8_t> pixels;

    // Act
    const HRESULT hr = PrepareOpaqueBgra(image, pixels);

    // Assert: GDI SRCCOPY receives fully composited, non-transparent BGRA.
    const std::array<std::uint8_t, 8> expected =
        {127, 127, 255, 255, 0, 255, 0, 255};
    bool ok = Check(hr == S_OK, "compose straight alpha") &&
              Check(std::equal(pixels.begin(), pixels.end(), expected.begin(), expected.end()),
                    "exact opaque pixel bytes");

    // Arrange: inconsistent buffer length must never be read.
    image.bgra.pop_back();
    // Act
    const HRESULT invalid = PrepareOpaqueBgra(image, pixels);
    // Assert
    ok &= Check(invalid == E_INVALIDARG && pixels.empty(),
                "malformed bitmap rejected without stale pixels");

    // Arrange: preserve aspect ratio in a 100 x 100 client.
    RECT client = {0, 0, 100, 100};
    RECT target = {};
    // Act
    const bool fitted = FitImage(200, 100, client, target);
    // Assert
    ok &= Check(fitted && target.left == 0 && target.top == 25 &&
                target.right == 100 && target.bottom == 75,
                "landscape centered without distortion");

    // Arrange / Act / Assert: invalid geometry is rejected.
    ok &= Check(!FitImage(0, 100, client, target), "zero image width refused");
    ok &= Check(!FitImage(200, 100, RECT{0, 0, 0, 100}, target),
                "empty client refused");

    if (ok)
        std::puts("PASS: WIC GDI composition, geometry and validation");
    return ok ? 0 : 1;
}
