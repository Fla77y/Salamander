// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#include "WicImageTransforms.h"

#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace pictview::wic
{
HRESULT TransformImage(DecodedImage& image, ImageTransform transform) noexcept
{
    switch (transform)
    {
    case ImageTransform::RotateClockwise:
    case ImageTransform::RotateCounterclockwise:
    case ImageTransform::FlipHorizontal:
    case ImageTransform::FlipVertical:
        break;
    default:
        return E_INVALIDARG;
    }

    constexpr std::uint64_t kMaxBytes = 256ULL * 1024 * 1024;
    const std::uint64_t sourceStride = static_cast<std::uint64_t>(image.width) * 4;
    const std::uint64_t bytes = sourceStride * image.height;
    if (!image.width || !image.height ||
        sourceStride > (std::numeric_limits<UINT>::max)() ||
        image.stride != sourceStride ||
        bytes > kMaxBytes || image.bgra.size() != bytes)
        return E_INVALIDARG;

    const bool rotation = transform == ImageTransform::RotateClockwise ||
                          transform == ImageTransform::RotateCounterclockwise;
    const UINT destWidth = rotation ? image.height : image.width;
    const UINT destHeight = rotation ? image.width : image.height;
    const std::uint64_t destStride = static_cast<std::uint64_t>(destWidth) * 4;
    if (destStride > (std::numeric_limits<UINT>::max)())
        return E_INVALIDARG;

    try
    {
        std::vector<std::uint8_t> next(static_cast<std::size_t>(bytes));
        for (UINT y = 0; y < image.height; ++y)
        {
            for (UINT x = 0; x < image.width; ++x)
            {
                UINT dx = 0;
                UINT dy = 0;
                switch (transform)
                {
                case ImageTransform::RotateClockwise:
                    dx = image.height - 1 - y;
                    dy = x;
                    break;
                case ImageTransform::RotateCounterclockwise:
                    dx = y;
                    dy = image.width - 1 - x;
                    break;
                case ImageTransform::FlipHorizontal:
                    dx = image.width - 1 - x;
                    dy = y;
                    break;
                case ImageTransform::FlipVertical:
                    dx = x;
                    dy = image.height - 1 - y;
                    break;
                }
                const std::size_t source = static_cast<std::size_t>(y) * image.stride +
                                           static_cast<std::size_t>(x) * 4;
                const std::size_t target = static_cast<std::size_t>(dy) *
                                           static_cast<std::size_t>(destStride) +
                                           static_cast<std::size_t>(dx) * 4;
                std::memcpy(next.data() + target, image.bgra.data() + source, 4);
            }
        }

        image.width = destWidth;
        image.height = destHeight;
        image.stride = static_cast<UINT>(destStride);
        image.bgra.swap(next);
        return S_OK;
    }
    catch (const std::bad_alloc&)
    {
        return E_OUTOFMEMORY;
    }
    catch (...)
    {
        return E_FAIL;
    }
}
} // namespace pictview::wic
