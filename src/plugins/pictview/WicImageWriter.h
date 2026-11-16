// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "WicImageDecoder.h"

namespace pictview::wic
{
enum class ImageFileFormat
{
    Png,
    Bmp,
    Jpeg,
    Tiff,
};

// Saves an in-memory image to a NEW file. Existing files are never replaced.
// The input is not modified. A failed encoding never opens the destination;
// failed writes attempt to remove only their own newly-created destination.
// COM must be initialized by the caller.
HRESULT SaveNewImage(const wchar_t* path, const DecodedImage& image,
                     ImageFileFormat format) noexcept;
} // namespace pictview::wic
