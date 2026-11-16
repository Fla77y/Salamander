// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/plugins/pictview/WicImageWriter.h"
#include "../../src/plugins/pictview/WicImageDecoder.h"

#include <windows.h>
#include <array>
#include <cstdio>
#include <string>

namespace
{
bool Check(bool condition, const char* message)
{
    if (!condition)
        std::fprintf(stderr, "FAIL: %s\n", message);
    return condition;
}

bool Tests()
{
    wchar_t directory[MAX_PATH + 1] = {};
    DWORD n = GetTempPathW(MAX_PATH + 1, directory);
    if (!Check(n != 0 && n <= MAX_PATH, "temporary path available"))
        return false;
    wchar_t unique[MAX_PATH + 1] = {};
    if (!Check(GetTempFileNameW(directory, L"wrt", 0, unique) != 0,
               "unique export fixture directory"))
        return false;

    DeleteFileW(unique);
    if (!Check(CreateDirectoryW(unique, nullptr) != FALSE,
               "isolated export directory"))
        return false;

    const std::wstring output = std::wstring(unique) + L"\\save-漢字.png";
    pictview::wic::DecodedImage source;
    source.width = 2;
    source.height = 1;
    source.stride = 8;
    source.bgra = {0x11, 0x22, 0x33, 0x7f,
                   0x44, 0x55, 0x66, 0xff};
    bool ok = Check(SUCCEEDED(pictview::wic::SaveNewImage(
                         output.c_str(), source, pictview::wic::ImageFileFormat::Png)),
                    "save first PNG under Unicode path");

    if (ok)
    {
        pictview::wic::DecodedImage decoded;
        ok = Check(SUCCEEDED(pictview::wic::DecodeFirstFrame(output.c_str(), decoded)),
                   "read PNG written by WIC encoder") &&
             Check(decoded.width == source.width && decoded.height == source.height &&
                   decoded.bgra == source.bgra, "exact BGRA and alpha round trip");

        source.bgra[0] = 0xee;
        const HRESULT collision = pictview::wic::SaveNewImage(
            output.c_str(), source, pictview::wic::ImageFileFormat::Png);
        ok &= Check(collision == HRESULT_FROM_WIN32(ERROR_FILE_EXISTS) ||
                    collision == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS),
                    "existing output cannot be overwritten");
        pictview::wic::DecodedImage preserved;
        ok &= Check(SUCCEEDED(pictview::wic::DecodeFirstFrame(output.c_str(), preserved)) &&
                    preserved.bgra[0] == 0x11,
                    "conflicting export preserves original bytes");
    }
    // The selected encoder and the displayed suffix must never disagree.
    std::wstring path = L"C:\\Images\\photo";
    ok &= Check(pictview::wic::PrepareExportPath(
                    path, pictview::wic::ImageFileFormat::Jpeg) &&
                path == L"C:\\Images\\photo.jpg",
                "JPEG selection appends JPEG suffix");
    path = L"C:\\Images\\photo.png";
    ok &= Check(!pictview::wic::PrepareExportPath(
                    path, pictview::wic::ImageFileFormat::Jpeg) &&
                path == L"C:\\Images\\photo.png",
                "JPEG selection refuses existing PNG suffix");
    path = L"C:\\Images.with.dot\\photo";
    ok &= Check(pictview::wic::PrepareExportPath(
                    path, pictview::wic::ImageFileFormat::Tiff) &&
                path == L"C:\\Images.with.dot\\photo.tif",
                "directory dots are not treated as file extensions");
    path = L"C:\\Images\\photo.JPEG";
    ok &= Check(pictview::wic::PrepareExportPath(
                    path, pictview::wic::ImageFileFormat::Jpeg) &&
                path == L"C:\\Images\\photo.JPEG",
                "case-insensitive matching preserves explicit suffix");

    pictview::wic::DecodedImage invalid = source;
    invalid.stride = 7;
    const std::wstring rejected = std::wstring(unique) + L"\\invalid.png";
    ok &= Check(pictview::wic::SaveNewImage(
                    rejected.c_str(), invalid, pictview::wic::ImageFileFormat::Png)
                    == E_INVALIDARG,
                "invalid stride rejected");
    ok &= Check(GetFileAttributesW(rejected.c_str()) == INVALID_FILE_ATTRIBUTES,
                "invalid export leaves no artifact");

    DeleteFileW(output.c_str());
    RemoveDirectoryW(unique);
    return ok;
}
}

int main()
{
    const HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (!Check(SUCCEEDED(hr), "COM initialized"))
        return 1;
    const bool success = Tests();
    CoUninitialize();
    if (success)
        std::puts("PASS: Unicode WIC export, lossless PNG, collision refusal");
    return success ? 0 : 1;
}
