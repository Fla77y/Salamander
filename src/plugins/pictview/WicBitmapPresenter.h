// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "WicImageDecoder.h"

#include <windows.h>
#include <cstdint>
#include <vector>

namespace pictview::wic
{
// Composite straight-alpha BGRA over an opaque white background for GDI SRCCOPY.
// On failure the destination is empty. The source image is never modified.
HRESULT PrepareOpaqueBgra(const DecodedImage& image,
                          std::vector<std::uint8_t>& opaque) noexcept;

// Determine centered, aspect-preserving fit. Dimensions are pixel counts.
bool FitImage(UINT width, UINT height, const RECT& client, RECT& target) noexcept;

// Draw already composited opaque BGRA without allocating in WM_PAINT.
HRESULT PaintOpaqueBgraAt(HDC dc, const RECT& destination, UINT width,
                          UINT height, UINT stride,
                          const std::vector<std::uint8_t>& opaque) noexcept;

// Draw a decoded first frame with GDI. Caller owns the HDC and its lifetime.
// Neither the input pixels nor the device context state is retained.
HRESULT PaintImage(HDC dc, const RECT& client, const DecodedImage& image) noexcept;

// Draw at an already validated destination (the HDC may clip it).
HRESULT PaintImageAt(HDC dc, const RECT& destination, const DecodedImage& image) noexcept;
} // namespace pictview::wic
