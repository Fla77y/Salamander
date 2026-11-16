// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
// Native Windows acceptance for the replacement PictView image decoder.

#include "../../src/plugins/pictview/WicImageDecoder.h"

#include <windows.h>

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstdint>
#include <string>

namespace
{
constexpr std::array<unsigned char, 62> kTwoPixelBmp = {
    0x42, 0x4D, 62, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, // BITMAPFILEHEADER
    40, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 1, 0, 24, 0, // BITMAPINFOHEADER
    0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 255, 0, 255, 0, 0, 0 // red and green BGR; 2-byte row padding
};
static_assert(kTwoPixelBmp.size() == 62, "invalid BMP fixture");

// A complete 1x1 RGBA PNG: R=0x80, G=0x40, B=0x20, A=0x7f.
// This catches accidental conversion to premultiplied BGRA.
constexpr std::array<unsigned char, 70> kAlphaPng = {
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x68, 0x70, 0x50, 0xA8,
    0x07, 0x00, 0x03, 0x84, 0x01, 0x60, 0xAC, 0x37,
    0x4B, 0x3A, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
    0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
};


bool Check(bool condition, const char* scenario)
{
    if (!condition)
        std::fprintf(stderr, "FAIL: %s\n", scenario);
    return condition;
}

bool WriteBytes(const std::wstring& path, const unsigned char* data, DWORD size)
{
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return false;

    DWORD written = 0;
    const bool success = WriteFile(file, data, size, &written, nullptr) != FALSE &&
                         written == size;
    CloseHandle(file);
    return success;
}

bool Tests()
{
    wchar_t tempPath[MAX_PATH + 1] = {};
    if (!Check(GetTempPathW(MAX_PATH + 1, tempPath) > 0,
               "temporary directory available"))
        return false;

    wchar_t uniquePath[MAX_PATH + 1] = {};
    if (!Check(GetTempFileNameW(tempPath, L"pwi", 0, uniquePath) != 0,
               "unique fixture path available"))
        return false;

    const std::wstring folder(uniquePath);
    DeleteFileW(uniquePath);
    if (!Check(CreateDirectoryW(folder.c_str(), nullptr) != FALSE,
               "fixture directory created"))
        return false;

    // Arrange
    const std::wstring imagePath = folder + L"\\Grün-\u6F22\u5B57.bmp";
    const std::wstring alphaPath = folder + L"\\alpha-\u6F22\u5B57.png";
    const std::wstring corruptPath = folder + L"\\corrupt.bmp";
    pictview::wic::DecodedImage result;

    bool ok = WriteBytes(imagePath, kTwoPixelBmp.data(),
                         static_cast<DWORD>(kTwoPixelBmp.size()));
    if (ok)
    {
        // Act
        const HRESULT hr = pictview::wic::DecodeFirstFrame(imagePath.c_str(), result);

        // Assert: output pixels must be lossless BGRA in top-down row order.
        const std::array<std::uint8_t, 8> expected =
            {0, 0, 255, 255, 0, 255, 0, 255};
        ok = Check(SUCCEEDED(hr), "WIC BMP decode succeeds with Unicode filename") &&
             Check(result.width == 2 && result.height == 1 && result.stride == 8,
                   "WIC returns correct dimensions and stride") &&
             Check(result.bgra.size() == expected.size() &&
                   std::equal(result.bgra.begin(), result.bgra.end(), expected.begin()),
                   "WIC preserves exact BGRA pixels");
    }

    if (ok)
    {
        // Arrange: a PNG with partial transparency and Unicode filename.
        ok = WriteBytes(alphaPath, kAlphaPng.data(),
                        static_cast<DWORD>(kAlphaPng.size()));
        if (ok)
        {
            // Act
            const HRESULT hr = pictview::wic::DecodeFirstFrame(alphaPath.c_str(), result);

            // Assert
            const std::array<std::uint8_t, 4> expected = {0x20, 0x40, 0x80, 0x7F};
            ok = Check(SUCCEEDED(hr), "WIC PNG decode succeeds") &&
                 Check(result.width == 1 && result.height == 1 &&
                       result.stride == 4, "PNG dimensions and stride correct") &&
                 Check(result.bgra.size() == expected.size() &&
                       std::equal(result.bgra.begin(), result.bgra.end(), expected.begin()),
                       "PNG preserves straight-alpha BGRA");
        }
    }

    if (ok)
    {
        // Arrange: invalid argument must not leak the previous decoded pixels.
        // Act
        const HRESULT hr = pictview::wic::DecodeFirstFrame(nullptr, result);
        // Assert
        ok = Check(hr == E_INVALIDARG, "null filename is rejected") &&
             Check(result.bgra.empty() && result.width == 0,
                   "invalid argument leaves an empty result");
    }

    if (ok)
    {
        // Arrange / Act / Assert: missing file does not retain old pixels.
        const HRESULT hr = pictview::wic::DecodeFirstFrame(
            (folder + L"\\absent.bmp").c_str(), result);
        ok = Check(FAILED(hr), "missing image is rejected") &&
             Check(result.bgra.empty() && result.height == 0,
                   "missing file preserves empty output");
    }

    if (ok)
    {
        // Arrange / Act / Assert: corrupt data cannot become an image.
        const unsigned char junk[] = {0x42, 0x4D, 0x00, 0x00};
        if (!WriteBytes(corruptPath, junk, sizeof(junk)))
            ok = false;
        else
        {
            const HRESULT hr = pictview::wic::DecodeFirstFrame(corruptPath.c_str(), result);
            ok = Check(FAILED(hr), "truncated BMP is rejected") &&
                 Check(result.bgra.empty(), "truncated BMP has no output pixels");
        }
    }

    if (ok)
    {
        // Arrange / Act / Assert: an empty path is invalid.
        const HRESULT hr = pictview::wic::DecodeFirstFrame(L"", result);
        ok = Check(hr == E_INVALIDARG, "empty filename rejected");
    }

    DeleteFileW(imagePath.c_str());
    DeleteFileW(alphaPath.c_str());
    DeleteFileW(corruptPath.c_str());
    RemoveDirectoryW(folder.c_str());
    return ok;
}
} // namespace

int main()
{
    // The decoding contract makes COM ownership explicit; caller initializes
    // the apartment, allowing this to be used in the existing viewer thread.
    const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (!Check(SUCCEEDED(init), "COM apartment initialized"))
        return 1;

    const bool success = Tests();
    CoUninitialize();

    if (success)
        std::puts("PASS: WIC Unicode BMP decode, BGRA pixels and fail-closed errors");
    return success ? 0 : 1;
}
