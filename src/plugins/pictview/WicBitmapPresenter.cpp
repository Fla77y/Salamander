// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "WicBitmapPresenter.h"

#include <algorithm>
#include <limits>
#include <new>
#include <utility>

namespace pictview::wic
{
HRESULT PrepareOpaqueBgra(const DecodedImage& image,
                          std::vector<std::uint8_t>& opaque) noexcept
{
    opaque.clear();
    const std::uint64_t stride = static_cast<std::uint64_t>(image.width) * 4;
    const std::uint64_t bytes = stride * image.height;
    if (!image.width || !image.height || stride > (std::numeric_limits<UINT>::max)() ||
        image.stride != stride || bytes > 256ULL * 1024 * 1024 ||
        image.bgra.size() != bytes)
        return E_INVALIDARG;

    try
    {
        std::vector<std::uint8_t> result(image.bgra);
        for (std::size_t i = 0; i < result.size(); i += 4)
        {
            const unsigned alpha = result[i + 3];
            for (unsigned channel = 0; channel < 3; ++channel)
                result[i + channel] = static_cast<std::uint8_t>(
                    (static_cast<unsigned>(result[i + channel]) * alpha +
                     255U * (255U - alpha)) / 255U);
            result[i + 3] = 255;
        }
        opaque = std::move(result);
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

bool FitImage(UINT width, UINT height, const RECT& client, RECT& target) noexcept
{
    target = {};
    const std::int64_t cw = static_cast<std::int64_t>(client.right) - client.left;
    const std::int64_t ch = static_cast<std::int64_t>(client.bottom) - client.top;
    if (!width || !height || cw <= 0 || ch <= 0)
        return false;

    std::int64_t dw = cw;
    std::int64_t dh = ch;
    if (cw * height <= ch * width)
        dh = std::max<std::int64_t>(1, cw * height / width);
    else
        dw = std::max<std::int64_t>(1, ch * width / height);
    const std::int64_t left = static_cast<std::int64_t>(client.left) + (cw - dw) / 2;
    const std::int64_t top = static_cast<std::int64_t>(client.top) + (ch - dh) / 2;
    if (left < INT_MIN || top < INT_MIN ||
        left + dw > INT_MAX || top + dh > INT_MAX)
        return false;
    target = {static_cast<LONG>(left), static_cast<LONG>(top),
              static_cast<LONG>(left + dw), static_cast<LONG>(top + dh)};
    return true;
}

HRESULT PaintImage(HDC dc, const RECT& client, const DecodedImage& image) noexcept
{
    if (!dc)
        return E_INVALIDARG;

    RECT dest{};
    if (!FitImage(image.width, image.height, client, dest))
        return E_INVALIDARG;
    std::vector<std::uint8_t> pixels;
    const HRESULT hr = PrepareOpaqueBgra(image, pixels);
    if (FAILED(hr))
        return hr;

    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = static_cast<LONG>(image.width);
    if (image.width > static_cast<UINT>(INT_MAX) ||
        image.height > static_cast<UINT>(INT_MAX))
        return E_INVALIDARG;
    info.bmiHeader.biHeight = -static_cast<LONG>(image.height);
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    const int previousMode = SetStretchBltMode(dc, HALFTONE);
    if (!previousMode)
        return HRESULT_FROM_WIN32(GetLastError());
    const int ret = StretchDIBits(dc, dest.left, dest.top,
                                  dest.right - dest.left, dest.bottom - dest.top,
                                  0, 0, static_cast<int>(image.width),
                                  static_cast<int>(image.height), pixels.data(),
                                  &info, DIB_RGB_COLORS, SRCCOPY);
    SetStretchBltMode(dc, previousMode);
    return ret == GDI_ERROR ? HRESULT_FROM_WIN32(GetLastError()) : S_OK;
}
} // namespace pictview::wic
