// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
// Native WIC decoder acceptance for every extension advertised by PictView.
// Embedded GIF/ICO inputs are independent of Windows' WIC encoders.

#include "../../src/plugins/pictview/WicImageDecoder.h"

#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <array>
#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <string>
#include <vector>

namespace
{
using Microsoft::WRL::ComPtr;

// Independent, valid 1x1 opaque-red fixtures.
constexpr std::array<unsigned char, 43> kGif = {
    0x47, 0x49, 0x46, 0x38, 0x37, 0x61, 0x01, 0x00,
    0x01, 0x00, 0x81, 0x00, 0x00, 0xFF, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x01, 0x00, 0x00, 0x08, 0x04, 0x00, 0x01, 0x04,
    0x04, 0x00, 0x3B
};

// Two independently encoded 1x1 GIF frames: red followed by green.
// Both palettes and the 80/120 ms frame delays are in the source image.
constexpr std::array<unsigned char, 107> kAnimatedGif = {
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00,
    0x01, 0x00, 0x81, 0x00, 0x00, 0xFF, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x21, 0xFF, 0x0B, 0x4E, 0x45, 0x54, 0x53,
    0x43, 0x41, 0x50, 0x45, 0x32, 0x2E, 0x30, 0x03,
    0x01, 0x00, 0x00, 0x00, 0x21, 0xF9, 0x04, 0x08,
    0x08, 0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00,
    0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x08, 0x04,
    0x00, 0x01, 0x04, 0x04, 0x00, 0x21, 0xF9, 0x04,
    0x08, 0x0C, 0x00, 0x00, 0x00, 0x2C, 0x00, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x81, 0x00,
    0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x08, 0x04, 0x00, 0x01, 0x04,
    0x04, 0x00, 0x3B
};

constexpr std::array<unsigned char, 70> kIcon = {
    0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x01, 0x01,
    0x00, 0x00, 0x01, 0x00, 0x20, 0x00, 0x30, 0x00,
    0x00, 0x00, 0x16, 0x00, 0x00, 0x00, 0x28, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x20, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00
};

struct TestFixture
{
    std::wstring root;
    std::vector<std::wstring> files;
    std::vector<std::wstring> directories;

    ~TestFixture()
    {
        for (const auto& file : files)
            DeleteFileW(file.c_str());
        for (auto it = directories.rbegin(); it != directories.rend(); ++it)
            RemoveDirectoryW(it->c_str());
    }

    bool Initialize()
    {
        wchar_t temp[MAX_PATH + 1]{};
        const DWORD length = GetTempPathW(MAX_PATH + 1, temp);
        if (length == 0 || length > MAX_PATH)
            return false;
        wchar_t unique[MAX_PATH + 1]{};
        if (GetTempFileNameW(temp, L"pvf", 0, unique) == 0)
            return false;
        root = unique;
        if (!DeleteFileW(unique))
            return false;
        if (!CreateDirectoryW(root.c_str(), nullptr))
            return false;
        directories.push_back(root);
        return true;
    }

    // Call Win32 with an extended absolute path, never an ANSI alias.
    bool CreateLongDirectory(std::wstring& result)
    {
        result = LR"(\\?\)" + root;
        for (int index = 0; index < 4; ++index)
        {
            result += L"\\depth-" + std::to_wstring(index) +
                      L"-" + std::wstring(62, L'x');
            if (!CreateDirectoryW(result.c_str(), nullptr))
                return false;
            directories.push_back(result);
        }
        return result.size() > MAX_PATH;
    }
};

// Verify that WIC decoding is read-only even for non-ACP names and extended
// paths. All fixtures are test-owned and at most 1 MiB.
bool ReadFixtureBytes(const std::wstring& path, std::vector<unsigned char>& bytes)
{
    HANDLE handle = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                                nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (handle == INVALID_HANDLE_VALUE)
        return false;

    LARGE_INTEGER size{};
    const bool validSize = GetFileSizeEx(handle, &size) &&
                           size.QuadPart > 0 && size.QuadPart <= 1024 * 1024;
    bool validRead = false;
    if (validSize)
    {
        bytes.resize(static_cast<std::size_t>(size.QuadPart));
        DWORD received = 0;
        validRead = ReadFile(handle, bytes.data(),
                             static_cast<DWORD>(bytes.size()), &received, nullptr) &&
                    received == bytes.size();
    }
    const bool closed = CloseHandle(handle) != FALSE;
    return validSize && validRead && closed;
}

HRESULT WriteBytes(const std::wstring& path, const unsigned char* data,
                   std::size_t length)
{
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return HRESULT_FROM_WIN32(GetLastError());
    DWORD written = 0;
    const bool writtenCompletely =
        WriteFile(file, data, static_cast<DWORD>(length),
                  &written, nullptr) != FALSE && written == length;
    const DWORD writeError = writtenCompletely ? ERROR_SUCCESS : GetLastError();
    const bool closed = CloseHandle(file) != FALSE;
    const DWORD closeError = closed ? ERROR_SUCCESS : GetLastError();
    if (!writtenCompletely)
        return HRESULT_FROM_WIN32(writeError == ERROR_SUCCESS ? ERROR_WRITE_FAULT : writeError);
    return closed ? S_OK : HRESULT_FROM_WIN32(closeError);
}

// Make a real 1x1 red image using Windows' encoder for the requested
// container. PictView's production decoder is the independent code under test.
HRESULT EncodeRedImage(const std::wstring& path, const GUID& container)
{
    ComPtr<IWICImagingFactory> factory;
    HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(factory.GetAddressOf()));
    if (FAILED(hr)) return hr;

    BYTE pixel[4] = {0, 0, 255, 0}; // 24bpp BGR with DWORD-aligned row
    ComPtr<IWICBitmap> source;
    hr = factory->CreateBitmapFromMemory(1, 1, GUID_WICPixelFormat24bppBGR,
                                         4, 4, pixel, source.GetAddressOf());
    if (FAILED(hr)) return hr;

    ComPtr<IWICStream> stream;
    hr = factory->CreateStream(stream.GetAddressOf());
    if (FAILED(hr)) return hr;
    hr = stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE);
    if (FAILED(hr)) return hr;

    ComPtr<IWICBitmapEncoder> encoder;
    hr = factory->CreateEncoder(container, nullptr, encoder.GetAddressOf());
    if (FAILED(hr)) return hr;
    hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
    if (FAILED(hr)) return hr;

    ComPtr<IWICBitmapFrameEncode> frame;
    ComPtr<IPropertyBag2> properties;
    hr = encoder->CreateNewFrame(frame.GetAddressOf(), properties.GetAddressOf());
    if (FAILED(hr)) return hr;
    hr = frame->Initialize(properties.Get());
    if (FAILED(hr)) return hr;
    hr = frame->SetSize(1, 1);
    if (FAILED(hr)) return hr;
    WICPixelFormatGUID pixelFormat = GUID_WICPixelFormat24bppBGR;
    hr = frame->SetPixelFormat(&pixelFormat);
    if (FAILED(hr)) return hr;
    hr = frame->WriteSource(source.Get(), nullptr);
    if (FAILED(hr)) return hr;
    hr = frame->Commit();
    if (FAILED(hr)) return hr;
    return encoder->Commit();
}

struct FormatCase
{
    const wchar_t* extension;
    const GUID* encoder;
    const unsigned char* embedded;
    std::size_t embeddedSize;
};

// Mirror both PictView AddViewer and SetThumbnailLoader registrations.
// JPEG XR (WMP) requires the corresponding Windows WIC codec.
const FormatCase kFormats[] = {
    {L"bmp", &GUID_ContainerFormatBmp, nullptr, 0},
    {L"dib", &GUID_ContainerFormatBmp, nullptr, 0},
    {L"png", &GUID_ContainerFormatPng, nullptr, 0},
    {L"jpg", &GUID_ContainerFormatJpeg, nullptr, 0},
    {L"jpeg", &GUID_ContainerFormatJpeg, nullptr, 0},
    {L"jpe", &GUID_ContainerFormatJpeg, nullptr, 0},
    {L"gif", nullptr, kGif.data(), kGif.size()},
    {L"tif", &GUID_ContainerFormatTiff, nullptr, 0},
    {L"tiff", &GUID_ContainerFormatTiff, nullptr, 0},
    {L"ico", nullptr, kIcon.data(), kIcon.size()},
    {L"jxr", &GUID_ContainerFormatWmp, nullptr, 0},
    {L"wdp", &GUID_ContainerFormatWmp, nullptr, 0},
    {L"hdp", &GUID_ContainerFormatWmp, nullptr, 0},
};

// A rejected read must clear output from the preceding successful decode.
// This includes an explicitly reset frame count for callers reusing it.
bool TestInvalidFrameDoesNotReturnPixels(const std::wstring& path)
{
    pictview::wic::DecodedImage image;
    UINT frameCount = 0;
    HRESULT hr = pictview::wic::DecodeFrame(path.c_str(), 0, image, &frameCount);
    if (FAILED(hr) || frameCount != 1 || image.bgra.empty())
    {
        std::fprintf(stderr, "FAIL: prepare out-of-range WIC frame regression\n");
        return false;
    }

    // Act / Assert: all test images have exactly one frame.
    frameCount = 99;
    hr = pictview::wic::DecodeFrame(path.c_str(), 1, image, &frameCount);
    if (SUCCEEDED(hr) || frameCount != 0 || image.width != 0 ||
        image.height != 0 || image.stride != 0 || !image.bgra.empty())
    {
        std::fprintf(stderr, "FAIL: out-of-range WIC frame retains pixels or frame count\n");
        return false;
    }
    return true;
}

// Reuse the same DecodedImage after a successful decode to detect stale
// pixel exposure across all common invalid input paths.
bool VerifyInvalidDecode(const std::wstring& valid, const wchar_t* invalid,
                         const char* scenario)
{
    pictview::wic::DecodedImage image;
    UINT frameCount = 0;
    HRESULT hr = pictview::wic::DecodeFrame(valid.c_str(), 0, image, &frameCount);
    if (FAILED(hr) || image.bgra.empty())
    {
        std::fprintf(stderr, "FAIL: prepare invalid WIC decoding regression\n");
        return false;
    }

    frameCount = 99;
    hr = pictview::wic::DecodeFrame(invalid, 0, image, &frameCount);
    if (SUCCEEDED(hr) || frameCount != 0 || image.width != 0 ||
        image.height != 0 || image.stride != 0 || !image.bgra.empty())
    {
        std::fprintf(stderr, "FAIL: %s did not fail closed\n", scenario);
        return false;
    }
    return true;
}

// The production WIC decode API guarantees empty results for invalid files.
bool TestDecodeFailuresAreAtomic(TestFixture& fixture)
{
    const std::wstring valid = fixture.root + L"\\valid-failure-reference.png";
    fixture.files.push_back(valid);
    if (FAILED(EncodeRedImage(valid, GUID_ContainerFormatPng)))
    {
        std::fprintf(stderr, "FAIL: create reference WIC image\n");
        return false;
    }

    const std::wstring corrupt = fixture.root + L"\\truncated-image.png";
    fixture.files.push_back(corrupt);
    const unsigned char truncated[] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
    if (FAILED(WriteBytes(corrupt, truncated, sizeof(truncated))))
    {
        std::fprintf(stderr, "FAIL: create truncated WIC image\n");
        return false;
    }

    const std::wstring missing = fixture.root + L"\\not-present.png";
    return VerifyInvalidDecode(valid, nullptr, "invalid WIC filename: null") &&
           VerifyInvalidDecode(valid, L"", "invalid WIC filename: empty") &&
           VerifyInvalidDecode(valid, missing.c_str(), "missing WIC image") &&
           VerifyInvalidDecode(valid, corrupt.c_str(), "truncated WIC image");
}

// A real two-frame GIF must expose both frames through the production
// decoder, not just report an image for a .gif file extension.
bool TestAnimatedGifFrameNavigation(TestFixture& fixture)
{
    // Arrange
    const std::wstring path = fixture.root + L"\\Animation-東京-😀.gif";
    fixture.files.push_back(path);
    if (FAILED(WriteBytes(path, kAnimatedGif.data(), kAnimatedGif.size())))
        return false;
    std::vector<unsigned char> before, after;
    if (!ReadFixtureBytes(path, before))
        return false;

    // Act: decode both frames in sequence into the same output object.
    pictview::wic::DecodedImage image;
    UINT count = 0;
    const HRESULT red = pictview::wic::DecodeFrame(path.c_str(), 0, image, &count);

    // Assert
    const bool first = SUCCEEDED(red) && count == 2 && image.width == 1 &&
                       image.height == 1 && image.bgra.size() == 4 &&
                       image.bgra[0] == 0 && image.bgra[1] == 0 &&
                       image.bgra[2] == 255 && image.bgra[3] == 255;
    const HRESULT green = pictview::wic::DecodeFrame(path.c_str(), 1, image, &count);
    const bool second = SUCCEEDED(green) && count == 2 &&
                        image.bgra.size() == 4 && image.bgra[0] == 0 &&
                        image.bgra[1] == 255 && image.bgra[2] == 0 &&
                        image.bgra[3] == 255;
    if (!first || !second)
        std::fprintf(stderr, "FAIL: second animated GIF frame has green pixels\n");
    return first && second && ReadFixtureBytes(path, after) && before == after &&
           TestInvalidFrameDoesNotReturnPixels(path);
}

bool TestFormat(TestFixture& fixture, const FormatCase& format)
{
    // Arrange
    const std::wstring file = fixture.root + L"\\Bild-\u6771\u4eac-\U0001f600." + format.extension;
    fixture.files.push_back(file);
    const HRESULT encoded = format.embedded
        ? WriteBytes(file, format.embedded, format.embeddedSize)
        : EncodeRedImage(file, *format.encoder);
    if (FAILED(encoded))
    {
        std::fwprintf(stderr, L"FAIL: WIC fixture .%ls encode (HRESULT 0x%08lX)\n",
                      format.extension, static_cast<unsigned long>(encoded));
        return false;
    }

    // Act
    std::vector<unsigned char> before, after;
    if (!ReadFixtureBytes(file, before))
        return false;
    pictview::wic::DecodedImage image;
    UINT frames = 0;
    const HRESULT decoded = pictview::wic::DecodeFrame(file.c_str(), 0, image, &frames);
    const bool sourcePreserved = ReadFixtureBytes(file, after) && before == after;

    // Assert: the advertised extension must produce actual decoded pixels.
    // JPEG and JPEG XR are lossy; only require an opaque red-dominant pixel.
    const bool valid = SUCCEEDED(decoded) && frames >= 1 &&
        image.width == 1 && image.height == 1 &&
        image.stride == 4 && image.bgra.size() == 4 &&
        image.bgra[0] <= 64 && image.bgra[1] <= 64 &&
        image.bgra[2] >= 190 && image.bgra[3] == 255;
    if (!valid)
        std::fwprintf(stderr, L"FAIL: PictView WIC .%ls decode (HRESULT 0x%08lX, frames=%u, pixels=%zu)\n",
                      format.extension, static_cast<unsigned long>(decoded),
                      frames, image.bgra.size());
    if (!sourcePreserved)
        std::fwprintf(stderr, L"FAIL: PictView .%ls decoder modified its source bytes\n",
                      format.extension);
    return valid && sourcePreserved && TestInvalidFrameDoesNotReturnPixels(file);
}

bool TestLongPath(TestFixture& fixture)
{
    // Arrange
    std::wstring longDirectory;
    if (!fixture.CreateLongDirectory(longDirectory))
    {
        std::fprintf(stderr, "FAIL: WIC long-path test directory could not be created\n");
        return false;
    }
    const std::wstring file = longDirectory + L"\\\u6771\u4eac-\U0001f600.png";
    fixture.files.push_back(file);
    const HRESULT encoded = EncodeRedImage(file, GUID_ContainerFormatPng);
    if (FAILED(encoded))
    {
        std::fprintf(stderr, "FAIL: WIC encoded long-path PNG fixture (0x%08lX)\n",
                     static_cast<unsigned long>(encoded));
        return false;
    }

    // Act / Assert
    std::vector<unsigned char> before, after;
    if (!ReadFixtureBytes(file, before))
        return false;
    pictview::wic::DecodedImage image;
    const HRESULT hr = pictview::wic::DecodeFirstFrame(file.c_str(), image);
    const bool valid = SUCCEEDED(hr) && image.width == 1 &&
                       image.height == 1 && image.bgra.size() == 4 &&
                       image.bgra[2] == 255 && image.bgra[3] == 255 &&
                       ReadFixtureBytes(file, after) && before == after;
    if (!valid)
        std::fprintf(stderr, "FAIL: WIC PNG decode from >MAX_PATH UTF-16 path (0x%08lX)\n",
                     static_cast<unsigned long>(hr));
    return valid;
}

bool RunTests()
{
    TestFixture fixture;
    if (!fixture.Initialize())
    {
        std::fprintf(stderr, "FAIL: cannot create isolated PictView format fixture\n");
        return false;
    }
    bool success = true;
    for (const auto& format : kFormats)
        if (!TestFormat(fixture, format))
            success = false;
    if (!TestAnimatedGifFrameNavigation(fixture))
        success = false;
    if (!TestDecodeFailuresAreAtomic(fixture))
        success = false;
    if (!TestLongPath(fixture))
        success = false;
    return success;
}
} // namespace

int main()
{
    const HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr))
    {
        std::fprintf(stderr, "FAIL: PictView format WIC COM initialization (0x%08lX)\n",
                     static_cast<unsigned long>(hr));
        return 1;
    }
    const bool success = RunTests();
    CoUninitialize();
    if (success)
        std::puts("PASS: all 13 advertised PictView WIC extensions decode; Unicode and >MAX_PATH PNG verified");
    return success ? 0 : 1;
}
