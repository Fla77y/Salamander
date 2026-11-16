// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "WicImageDecoder.h"

#include <wincodec.h>
#include <wrl/client.h>

#include <cstdint>
#include <limits>
#include <new>
#include <utility>

namespace pictview::wic
{
namespace
{
constexpr std::uint64_t kBytesPerPixel = 4;
constexpr std::uint64_t kMaximumDecodedBytes = 256ULL * 1024 * 1024;

HRESULT Decode(const wchar_t* path, DecodedImage& image)
{
    Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
    HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(factory.GetAddressOf()));
    if (FAILED(hr))
        return hr;

    Microsoft::WRL::ComPtr<IWICBitmapDecoder> decoder;
    hr = factory->CreateDecoderFromFilename(path, nullptr, GENERIC_READ,
                                            WICDecodeMetadataCacheOnDemand,
                                            decoder.GetAddressOf());
    if (FAILED(hr))
        return hr;

    Microsoft::WRL::ComPtr<IWICBitmapFrameDecode> frame;
    hr = decoder->GetFrame(0, frame.GetAddressOf());
    if (FAILED(hr))
        return hr;

    UINT width = 0;
    UINT height = 0;
    hr = frame->GetSize(&width, &height);
    if (FAILED(hr))
        return hr;
    if (width == 0 || height == 0)
        return HRESULT_FROM_WIN32(ERROR_INVALID_DATA);

    // WIC CopyPixels uses UINT for both stride and byte count. Calculate
    // with 64 bits first; do not trust image dimensions or file metadata.
    const std::uint64_t stride = static_cast<std::uint64_t>(width) * kBytesPerPixel;
    const std::uint64_t bytes = stride * height;
    if (stride > (std::numeric_limits<UINT>::max)() ||
        bytes > kMaximumDecodedBytes ||
        bytes > (std::numeric_limits<UINT>::max)())
        return HRESULT_FROM_WIN32(ERROR_FILE_TOO_LARGE);

    Microsoft::WRL::ComPtr<IWICFormatConverter> converter;
    hr = factory->CreateFormatConverter(converter.GetAddressOf());
    if (FAILED(hr))
        return hr;

    // BGRA (not PBGRA) preserves straight alpha for later viewer operations.
    hr = converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA,
                               WICBitmapDitherTypeNone, nullptr, 0.0,
                               WICBitmapPaletteTypeCustom);
    if (FAILED(hr))
        return hr;

    DecodedImage decoded;
    decoded.width = width;
    decoded.height = height;
    decoded.stride = static_cast<UINT>(stride);
    decoded.bgra.resize(static_cast<std::size_t>(bytes));

    hr = converter->CopyPixels(nullptr, decoded.stride,
                               static_cast<UINT>(bytes), decoded.bgra.data());
    if (FAILED(hr))
        return hr;

    image = std::move(decoded);
    return S_OK;
}
} // namespace

HRESULT DecodeFirstFrame(const wchar_t* path, DecodedImage& output) noexcept
{
    output = {};
    if (path == nullptr || *path == L'\0')
        return E_INVALIDARG;

    try
    {
        return Decode(path, output);
    }
    catch (const std::bad_alloc&)
    {
        output = {};
        return E_OUTOFMEMORY;
    }
    catch (...)
    {
        output = {};
        return E_FAIL;
    }
}
} // namespace pictview::wic
