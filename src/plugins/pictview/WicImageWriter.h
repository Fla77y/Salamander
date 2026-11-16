// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "WicImageDecoder.h"
#include <string>

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
// Ensure that the destination has a suffix matching the selected encoder.
// Adds a default suffix only when none exists, and rejects mismatches.
// Does not modify a mismatched input path.
bool PrepareExportPath(std::wstring& path, ImageFileFormat format) noexcept;

HRESULT SaveNewImage(const wchar_t* path, const DecodedImage& image,
                     ImageFileFormat format) noexcept;
} // namespace pictview::wic
