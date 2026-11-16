// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#include "WicImageClipboard.h"
#include "WicBitmapPresenter.h"

#include <climits>
#include <cstdint>
#include <limits>
#include <cstring>
#include <limits>
#include <new>
#include <utility>

namespace pictview::wic
{
HRESULT PrepareClipboardDib(const DecodedImage& image,
                            std::vector<std::uint8_t>& dib) noexcept
{
    dib.clear();
    if (!image.width || !image.height || image.width > INT_MAX ||
        image.height > INT_MAX)
        return E_INVALIDARG;
    std::vector<std::uint8_t> opaque;
    const HRESULT hr = PrepareOpaqueBgra(image, opaque);
    if (FAILED(hr))
        return hr;

    if (opaque.size() > (std::numeric_limits<DWORD>::max)() ||
        opaque.size() > (std::numeric_limits<std::size_t>::max)() -
                          sizeof(BITMAPINFOHEADER))
        return E_INVALIDARG;

    try
    {
        std::vector<std::uint8_t> result(sizeof(BITMAPINFOHEADER) + opaque.size());
        BITMAPINFOHEADER header{};
        header.biSize = sizeof(header);
        header.biWidth = static_cast<LONG>(image.width);
        header.biHeight = -static_cast<LONG>(image.height);
        header.biPlanes = 1;
        header.biBitCount = 32;
        header.biCompression = BI_RGB;
        header.biSizeImage = static_cast<DWORD>(opaque.size());

        std::memcpy(result.data(), &header, sizeof(header));
        std::memcpy(result.data() + sizeof(header), opaque.data(), opaque.size());
        dib.swap(result);
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

HRESULT ParseClipboardDib(const void* data, std::size_t size,
                          DecodedImage& output) noexcept
{
    output = {};
    if (!data || size < sizeof(BITMAPINFOHEADER))
        return E_INVALIDARG;

    BITMAPINFOHEADER header{};
    std::memcpy(&header, data, sizeof(header));
    if (header.biSize < sizeof(BITMAPINFOHEADER) ||
        header.biSize > size || header.biWidth <= 0 ||
        header.biHeight == 0 || header.biHeight == INT_MIN ||
        header.biPlanes != 1 || header.biCompression != BI_RGB ||
        (header.biBitCount != 24 && header.biBitCount != 32))
        return E_INVALIDARG;

    const std::uint64_t width = static_cast<UINT>(header.biWidth);
    const UINT height = static_cast<UINT>(
        header.biHeight < 0 ? -header.biHeight : header.biHeight);
    constexpr std::uint64_t kLimit = 256ULL * 1024 * 1024;
    const std::uint64_t bits = static_cast<std::uint64_t>(header.biBitCount);
    const std::uint64_t inputStride = ((width * bits + 31) / 32) * 4;
    const std::uint64_t outputStride = width * 4;
    const std::uint64_t inputBytes = inputStride * height;
    const std::uint64_t outputBytes = outputStride * height;
    if (!width || !height || outputStride > (std::numeric_limits<UINT>::max)() ||
        inputBytes > kLimit || outputBytes > kLimit ||
        inputBytes > size - header.biSize)
        return E_INVALIDARG;

    const auto* pixels = static_cast<const std::uint8_t*>(data) + header.biSize;
    try
    {
        DecodedImage next;
        next.width = static_cast<UINT>(width);
        next.height = height;
        next.stride = static_cast<UINT>(outputStride);
        next.bgra.resize(static_cast<std::size_t>(outputBytes));
        for (UINT y = 0; y < height; ++y)
        {
            const UINT srcY = header.biHeight < 0 ? y : (height - 1 - y);
            const std::uint8_t* src = pixels + static_cast<std::size_t>(srcY * inputStride);
            std::uint8_t* dst = next.bgra.data() +
                                static_cast<std::size_t>(y * outputStride);
            for (UINT x = 0; x < next.width; ++x)
            {
                const std::size_t in = static_cast<std::size_t>(x) * (bits / 8);
                const std::size_t out = static_cast<std::size_t>(x) * 4;
                dst[out + 0] = src[in + 0];
                dst[out + 1] = src[in + 1];
                dst[out + 2] = src[in + 2];
                dst[out + 3] = 255; // BI_RGB does not define meaningful alpha
            }
        }
        output = std::move(next);
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

HRESULT PasteImageFromClipboard(HWND owner, DecodedImage& output) noexcept
{
    output = {};
    if (!owner || !IsWindow(owner))
        return E_INVALIDARG;
    if (!OpenClipboard(owner))
    {
        const DWORD error = GetLastError();
        return HRESULT_FROM_WIN32(error ? error : ERROR_BUSY);
    }

    HRESULT result = HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
    HANDLE handle = GetClipboardData(CF_DIB);
    if (handle)
    {
        const SIZE_T size = GlobalSize(handle);
        const void* data = GlobalLock(handle);
        if (data)
        {
            result = ParseClipboardDib(data, size, output);
            GlobalUnlock(handle);
        }
        else
        {
            const DWORD error = GetLastError();
            result = HRESULT_FROM_WIN32(error ? error : ERROR_INVALID_DATA);
        }
    }
    CloseClipboard();
    return result;
}

HRESULT CopyImageToClipboard(HWND owner, const DecodedImage& image) noexcept
{
    if (!owner || !IsWindow(owner))
        return E_INVALIDARG;

    std::vector<std::uint8_t> dib;
    const HRESULT hr = PrepareClipboardDib(image, dib);
    if (FAILED(hr))
        return hr;

    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, dib.size());
    if (!memory)
        return E_OUTOFMEMORY;
    void* ptr = GlobalLock(memory);
    if (!ptr)
    {
        const DWORD error = GetLastError();
        GlobalFree(memory);
        return HRESULT_FROM_WIN32(error ? error : ERROR_NOT_ENOUGH_MEMORY);
    }
    std::memcpy(ptr, dib.data(), dib.size());
    GlobalUnlock(memory);

    if (!OpenClipboard(owner))
    {
        const DWORD error = GetLastError();
        GlobalFree(memory);
        return HRESULT_FROM_WIN32(error ? error : ERROR_BUSY);
    }

    HRESULT result = S_OK;
    if (!EmptyClipboard())
    {
        const DWORD error = GetLastError();
        result = HRESULT_FROM_WIN32(error ? error : ERROR_GEN_FAILURE);
    }
    else if (SetClipboardData(CF_DIB, memory))
    {
        // Windows now owns the HGLOBAL.
        memory = nullptr;
    }
    else
    {
        const DWORD error = GetLastError();
        result = HRESULT_FROM_WIN32(error ? error : ERROR_GEN_FAILURE);
    }
    CloseClipboard();
    if (memory)
        GlobalFree(memory);
    return result;
}
} // namespace pictview::wic
