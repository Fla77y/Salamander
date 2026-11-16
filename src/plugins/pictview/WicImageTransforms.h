// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "WicImageDecoder.h"

namespace pictview::wic
{
enum class ImageTransform
{
    RotateClockwise,
    RotateCounterclockwise,
    FlipHorizontal,
    FlipVertical,
};

// The input is updated only on success. Pixels remain straight-alpha BGRA.
// Rejects inconsistent dimensions, stride, size and unknown transforms.
HRESULT TransformImage(DecodedImage& image, ImageTransform transform) noexcept;
} // namespace pictview::wic
