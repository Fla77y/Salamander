// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "WicImageDecoder.h"

#include <windows.h>
#include <cstdint>
#include <cstddef>
#include <vector>

namespace pictview::wic
{
// Build a self-contained, top-down, opaque CF_DIB image.
// Straight alpha is composited over white (CF_DIB has no portable alpha).
// Output is empty on failure and never retains external pointers.
HRESULT PrepareClipboardDib(const DecodedImage& image,
                            std::vector<std::uint8_t>& dib) noexcept;

// Transfer the prepared DIB to the Windows clipboard. HWND must belong
// to the current UI thread. Caller retains ownership of the source image.
// Accept only uncompressed 24/32-bit Windows DIBs. Supports bottom-up
// and top-down data with word-aligned rows. Decoded alpha is opaque.
// On any failure, output is reset and no pointer to clipboard data is retained.
HRESULT ParseClipboardDib(const void* data, std::size_t size,
                          DecodedImage& output) noexcept;

// Read and copy the current CF_DIB from the OS clipboard into caller-owned pixels.
HRESULT PasteImageFromClipboard(HWND owner, DecodedImage& output) noexcept;

HRESULT CopyImageToClipboard(HWND owner, const DecodedImage& image) noexcept;
} // namespace pictview::wic
