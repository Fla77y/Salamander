# Replace the PictView image engine with Windows Imaging Component

Status: **first native decoder slice implemented, viewer migration NOT complete**
Base: `main` at `17d1d0e611f31a8370d666a1a7a540210e65ecd8`
Independent of draft PR #8 (`feature/unicode-plugin-recycle-integration`).

## Why this is required

`src/plugins/pictview/lib/readme.txt` (November 2023) explicitly records
removal of `PVW32Cnv.lib`: its source is unavailable, incompatible with the
project's GPL distribution obligations. On x64, PictView currently uses
`PICTVIEW_DLL_IN_SEPARATE_PROCESS` to start the 32-bit `SalPVEnv.exe`,
which in turn needs `PVW32Cnv.dll`. The user's 16 November 2026
Release x64 build contains `pictview.spl` but neither of these runtime
dependencies, so the Plugin Manager's global **Test All** reported a
PictView loading error.

Do not restore unlicensed proprietary binaries or fabricate missing
converter interfaces. WIC is a Windows-provided native codec API; support
for additional image formats depends on codecs installed on the host.

## Migration boundary

The legacy `CPVW32DLL` table is used across `render1.cpp`,
`render2.cpp`, `thumbs.cpp`, `saveas.cpp`, `PixelAccess.cpp`, and
`pictview.cpp`. It includes significantly more than decoding:
rendering and stretching, editing, histograms, color models, animation,
save formats, thumbnails, printer output, clipboard and TWAIN/WIA.
A single WIC decoder cannot be substituted for this table without
silently losing functionality or risking invalid image handles.

The new `WicImageDecoder` is intentionally independent of this
legacy interface. The production PictView project compiles and links
it, but **PictView still calls the old library during initialization**.
Consequently, this branch does NOT yet fix the Plugin Manager PictView
load failure. The replacement must proceed behind a new viewer/renderer
integration, rather than by leaving unsupported legacy callbacks as
successful no-ops.

## Implemented: owned BGRA decode kernel

`src/plugins/pictview/WicImageDecoder.h/.cpp`:

- Calls the operating system's WIC codec through
  `IWICImagingFactory`, `IWICBitmapDecoder`,
  `IWICBitmapFrameDecode`, and `IWICFormatConverter`.
- Opens an original UTF-16 file path (no ACP conversion), returning
  top-down, **straight-alpha 32-bit BGRA** pixels with dimensions/stride.
- Decodes **only the first frame** and does not claim animated playback.
- Requires COM initialized on the calling thread; owns/relinquishes
  all local COM interfaces via smart pointers.
- Limits the decoded pixel buffer to **256 MiB**, uses checked
  calculations before allocating, and resets outputs on all failures.
- Returns HRESULTs for absent, corrupt, invalid or unsupported input,
  never replacing original files or generating output files.

## Acceptance tests

`tools/tests/pictview_wic_decode.cpp` creates isolated BMP and PNG
fixtures with Unicode filenames on Windows, verifies exact BGRA pixels
and PNG straight-alpha preservation, then rejects missing files,
truncated image data, null and empty paths.
Its temporary resources are removed after completion.

A dedicated `pr-pictview-wic.yml` workflow uses the actual MSVC
compiler and OS WIC codecs on **x64 and x86**, with warning-as-error.
The first standalone x64 and x86 WIC decoder tests passed with MSVC
on the initial BMP-only commit. A follow-up PNG straight-alpha fixture
has been added and requires a fresh run. The legacy PictView project
build and real viewer integration are separate gates.

## Next tasks (not implemented by this slice)

1. Add a **WIC-native viewer rendering path** using the existing
   PictView window and GDI/Direct2D; verify exact pixels, scaling,
   alpha blending and resource disposal in real GUI tests.
2. Route basic open/view operations through that path and remove the
   unconditional `LoadPictViewDll`/SalPVEnv dependency for supported
   WIC formats. Preserve the Salamander plug-in ABI.
3. Implement isolated WIC metadata/thumbnails, multi-frame behavior
   and format-specific save operations with explicit capability checks.
   Disable unsupported commands visibly rather than pretending to
   reproduce proprietary engine capabilities.
4. Exercise Unicode filenames, extended-length paths, malformed images,
   large dimensions, frame selection and repeated open/close on a
   Windows desktop, including Release and Debug.
5. After verified feature coverage, remove obsolete PVW32/SalPVEnv
   build projects and update package validation/plug-in smoke tests.

The unrar plug-in is a separate feature with its own archive/codec
requirements; it is not modified by this image migration.
