// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#include "WicImageWriter.h"
#include "WicBitmapPresenter.h"

#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <cwchar>
#include <limits>
#include <new>
#include <vector>

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")

namespace pictview::wic
{
namespace
{
constexpr std::uint64_t kMaxDecodedBytes = 256ULL * 1024 * 1024;
constexpr std::uint64_t kMaxEncodedBytes = 512ULL * 1024 * 1024;

HRESULT Validate(const wchar_t* path, const DecodedImage& image)
{
    const std::uint64_t stride = static_cast<std::uint64_t>(image.width) * 4;
    const std::uint64_t bytes = stride * image.height;
    if (!path || !*path || !image.width || !image.height ||
        image.width > INT_MAX || image.height > INT_MAX ||
        stride > (std::numeric_limits<UINT>::max)() ||
        image.stride != stride || bytes > kMaxDecodedBytes ||
        image.bgra.size() != bytes)
        return E_INVALIDARG;
    return S_OK;
}

const GUID* GetContainerFormat(ImageFileFormat format) noexcept
{
    switch (format)
    {
    case ImageFileFormat::Png:
        return &GUID_ContainerFormatPng;
    case ImageFileFormat::Bmp:
        return &GUID_ContainerFormatBmp;
    case ImageFileFormat::Jpeg:
        return &GUID_ContainerFormatJpeg;
    case ImageFileFormat::Tiff:
        return &GUID_ContainerFormatTiff;
    }
    return nullptr;
}

HRESULT EncodeImage(const DecodedImage& image, ImageFileFormat format,
                    IStream* output)
{
    using Microsoft::WRL::ComPtr;

    ComPtr<IWICImagingFactory> factory;
    HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(factory.GetAddressOf()));
    if (FAILED(hr))
        return hr;

    const GUID* container = GetContainerFormat(format);
    if (!container)
        return E_INVALIDARG;

    ComPtr<IWICBitmapEncoder> encoder;
    hr = factory->CreateEncoder(*container, nullptr, encoder.GetAddressOf());
    if (FAILED(hr))
        return hr;
    hr = encoder->Initialize(output, WICBitmapEncoderNoCache);
    if (FAILED(hr))
        return hr;

    ComPtr<IWICBitmapFrameEncode> frame;
    ComPtr<IPropertyBag2> properties;
    hr = encoder->CreateNewFrame(frame.GetAddressOf(), properties.GetAddressOf());
    if (FAILED(hr))
        return hr;
    hr = frame->Initialize(properties.Get());
    if (FAILED(hr))
        return hr;
    hr = frame->SetSize(image.width, image.height);
    if (FAILED(hr))
        return hr;

    // JPEG and BMP cannot be assumed to retain alpha, so flatten explicitly.
    const bool hasAlpha = format == ImageFileFormat::Png ||
                          format == ImageFileFormat::Tiff;
    std::vector<std::uint8_t> pixels;
    if (hasAlpha)
        pixels = image.bgra;
    else
    {
        hr = PrepareOpaqueBgra(image, pixels);
        if (FAILED(hr))
            return hr;
    }

    ComPtr<IWICBitmap> bitmap;
    hr = factory->CreateBitmapFromMemory(
        image.width, image.height, GUID_WICPixelFormat32bppBGRA,
        image.stride, static_cast<UINT>(pixels.size()),
        pixels.data(), bitmap.GetAddressOf());
    if (FAILED(hr))
        return hr;

    WICPixelFormatGUID pixelFormat = hasAlpha ?
        GUID_WICPixelFormat32bppBGRA : GUID_WICPixelFormat24bppBGR;
    hr = frame->SetPixelFormat(&pixelFormat);
    if (FAILED(hr))
        return hr;

    ComPtr<IWICFormatConverter> converter;
    hr = factory->CreateFormatConverter(converter.GetAddressOf());
    if (FAILED(hr))
        return hr;
    hr = converter->Initialize(bitmap.Get(), pixelFormat, WICBitmapDitherTypeNone,
                               nullptr, 0.0, WICBitmapPaletteTypeCustom);
    if (FAILED(hr))
        return hr;

    hr = frame->WriteSource(converter.Get(), nullptr);
    if (FAILED(hr))
        return hr;
    hr = frame->Commit();
    if (FAILED(hr))
        return hr;
    return encoder->Commit();
}

HRESULT WriteNewFile(const wchar_t* path, const std::uint8_t* bytes,
                     std::uint64_t count)
{
    HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, nullptr,
                              CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return HRESULT_FROM_WIN32(GetLastError());

    bool written = true;
    DWORD error = ERROR_SUCCESS;
    std::uint64_t offset = 0;
    while (offset < count)
    {
        const DWORD chunk = static_cast<DWORD>(
            (std::min)(count - offset, 1024ULL * 1024));
        DWORD actual = 0;
        if (!WriteFile(file, bytes + static_cast<std::size_t>(offset),
                       chunk, &actual, nullptr) || actual != chunk)
        {
            written = false;
            error = GetLastError();
            if (error == ERROR_SUCCESS)
                error = ERROR_WRITE_FAULT;
            break;
        }
        offset += chunk;
    }
    if (written && !FlushFileBuffers(file))
    {
        written = false;
        error = GetLastError();
    }
    if (!CloseHandle(file))
    {
        written = false;
        if (error == ERROR_SUCCESS)
            error = GetLastError();
    }
    if (!written)
    {
        // The exclusive CREATE_NEW above proves ownership of this path.
        DeleteFileW(path);
        return HRESULT_FROM_WIN32(error ? error : ERROR_WRITE_FAULT);
    }
    return S_OK;
}

HRESULT Save(const wchar_t* path, const DecodedImage& image,
             ImageFileFormat format)
{
    if (!GetContainerFormat(format))
        return E_INVALIDARG;
    Microsoft::WRL::ComPtr<IStream> stream;
    HRESULT hr = CreateStreamOnHGlobal(nullptr, TRUE, stream.GetAddressOf());
    if (FAILED(hr))
        return hr;
    hr = EncodeImage(image, format, stream.Get());
    if (FAILED(hr))
        return hr;

    STATSTG stat{};
    hr = stream->Stat(&stat, STATFLAG_NONAME);
    if (FAILED(hr))
        return hr;
    const std::uint64_t size = static_cast<std::uint64_t>(stat.cbSize.QuadPart);
    if (!size || size > kMaxEncodedBytes)
        return HRESULT_FROM_WIN32(ERROR_FILE_TOO_LARGE);

    HGLOBAL memory = nullptr;
    hr = GetHGlobalFromStream(stream.Get(), &memory);
    if (FAILED(hr))
        return hr;
    const auto* bytes = static_cast<const std::uint8_t*>(GlobalLock(memory));
    if (!bytes)
        return HRESULT_FROM_WIN32(GetLastError());

    hr = WriteNewFile(path, bytes, size);
    GlobalUnlock(memory);
    return hr;
}
} // namespace

bool PrepareExportPath(std::wstring& path, ImageFileFormat format) noexcept
{
    const wchar_t* expected = nullptr;
    switch (format)
    {
    case ImageFileFormat::Png: expected = L".png"; break;
    case ImageFileFormat::Bmp: expected = L".bmp"; break;
    case ImageFileFormat::Jpeg: expected = L".jpg"; break;
    case ImageFileFormat::Tiff: expected = L".tif"; break;
    default: return false;
    }

    if (path.empty() || path.size() >= 32767 || path.find(L'\0') != std::wstring::npos)
        return false;
    const std::size_t separator = path.find_last_of(L"\\/");
    const std::size_t start = separator == std::wstring::npos ? 0 : separator + 1;
    if (start >= path.size())
        return false;
    const std::size_t dot = path.find_last_of(L'.');
    if (dot != std::wstring::npos && dot >= start)
    {
        const wchar_t* ext = path.c_str() + dot;
        bool valid = CompareStringOrdinal(ext, -1, expected, -1, TRUE) == CSTR_EQUAL;
        if (format == ImageFileFormat::Jpeg)
            valid = valid || CompareStringOrdinal(ext, -1, L".jpeg", -1, TRUE) == CSTR_EQUAL ||
                              CompareStringOrdinal(ext, -1, L".jpe", -1, TRUE) == CSTR_EQUAL;
        if (format == ImageFileFormat::Tiff)
            valid = valid || CompareStringOrdinal(ext, -1, L".tiff", -1, TRUE) == CSTR_EQUAL;
        return valid;
    }

    try
    {
        if (path.size() + std::wcslen(expected) >= 32767)
            return false;
        path.append(expected);
        return true;
    }
    catch (...)
    {
        return false;
    }
}

HRESULT SaveNewImage(const wchar_t* path, const DecodedImage& image,
                     ImageFileFormat format) noexcept
{
    const HRESULT validation = Validate(path, image);
    if (FAILED(validation))
        return validation;
    try
    {
        return Save(path, image, format);
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
