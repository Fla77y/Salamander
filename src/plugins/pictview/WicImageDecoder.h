// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <windows.h>

#include <cstdint>
#include <vector>

namespace pictview::wic
{
// Top-down, unpremultiplied 32-bit BGRA pixels. Each row contains stride bytes.
// Ownership of the pixels belongs to the caller (no WIC/COM objects escape).
struct DecodedImage
{
    UINT width = 0;
    UINT height = 0;
    UINT stride = 0;
    std::vector<std::uint8_t> bgra;
};

// Decode the first frame using the OS-provided Windows Imaging Component.
// The caller must have initialized COM on the calling thread.
// This is a read-only operation on the original UTF-16 file path.
// On failure, output is reset to an empty image. No exceptions escape.
// An explicit 256 MiB decoded-pixel limit prevents unbounded allocation
// from untrusted images (independent of the compressed file size).
HRESULT DecodeFirstFrame(const wchar_t* path, DecodedImage& output) noexcept;

// Decode a selected frame with the same ownership, size and failure guarantees.
// 'frameCount' receives the total count on success; nullptr is accepted.
HRESULT DecodeFrame(const wchar_t* path, UINT frameIndex, DecodedImage& output,
                    UINT* frameCount = nullptr) noexcept;
} // namespace pictview::wic
