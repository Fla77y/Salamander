// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#include "WicImageClipboard.h"
#include "WicBitmapPresenter.h"

#include <climits>
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
