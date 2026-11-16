// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
// Deterministic pixel geometry tests for WIC viewer editing.

#include "../../src/plugins/pictview/WicImageTransforms.h"

#include <array>
#include <cstdio>
#include <utility>
#include <vector>

using pictview::wic::DecodedImage;
using pictview::wic::ImageTransform;
using pictview::wic::TransformImage;

namespace
{
DecodedImage MakeFixture()
{
    // 2 x 3 top-down image; blue component identifies each pixel.
    DecodedImage image;
    image.width = 2;
    image.height = 3;
    image.stride = 8;
    image.bgra = {
        1, 0, 0, 255, 2, 0, 0, 255,
        3, 0, 0, 255, 4, 0, 0, 255,
        5, 0, 0, 255, 6, 0, 0, 128,
    };
    return image;
}

bool Check(const char* scenario, ImageTransform transform,
           UINT width, UINT height, const std::vector<std::uint8_t>& blue)
{
    DecodedImage image = MakeFixture();
    const HRESULT hr = TransformImage(image, transform);
    bool ok = hr == S_OK && image.width == width && image.height == height &&
              image.stride == width * 4 && image.bgra.size() == blue.size() * 4;
    if (ok)
    {
        for (std::size_t i = 0; i < blue.size(); ++i)
        {
            if (image.bgra[i * 4] != blue[i] ||
                image.bgra[i * 4 + 1] != 0 ||
                image.bgra[i * 4 + 2] != 0 ||
                image.bgra[i * 4 + 3] != (blue[i] == 6 ? 128 : 255))
            {
                ok = false;
                break;
            }
        }
    }
    if (!ok)
        std::fprintf(stderr, "FAIL: %s\n", scenario);
    return ok;
}
}

int main()
{
    bool ok = Check("rotate clockwise", ImageTransform::RotateClockwise,
                    3, 2, {5, 3, 1, 6, 4, 2});
    ok &= Check("rotate counterclockwise", ImageTransform::RotateCounterclockwise,
                3, 2, {2, 4, 6, 1, 3, 5});
    ok &= Check("mirror horizontally", ImageTransform::FlipHorizontal,
                2, 3, {2, 1, 4, 3, 6, 5});
    ok &= Check("mirror vertically", ImageTransform::FlipVertical,
                2, 3, {5, 6, 3, 4, 1, 2});

    // Failure must not corrupt an already loaded document.
    DecodedImage invalid = MakeFixture();
    invalid.stride = 7;
    const auto before = invalid.bgra;
    const HRESULT failed = TransformImage(invalid, ImageTransform::RotateClockwise);
    ok &= failed == E_INVALIDARG && invalid.width == 2 &&
          invalid.height == 3 && invalid.stride == 7 && invalid.bgra == before;

    invalid = MakeFixture();
    const HRESULT unknown = TransformImage(invalid, static_cast<ImageTransform>(77));
    ok &= unknown == E_INVALIDARG && invalid.bgra == before;

    if (ok)
        std::puts("PASS: WIC image rotation, mirroring, alpha and atomic failure");
    return ok ? 0 : 1;
}
