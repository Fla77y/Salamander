# PictView replacement with Windows Imaging Component (WIC)

Status: **integrated native WIC viewer, manual multi-frame viewing, in-memory
transformations, export, clipboard copy and thumbnails; legacy feature parity
and real Windows GUI acceptance remain outstanding.** Work is stacked as PR #10
on PR #9. This branch must remain Draft.

## Licensing and rationale

The original PVW32Cnv import library was removed in November 2023
(`src/plugins/pictview/lib/readme.txt`) because its source is unavailable and
distribution would breach the project's GPL licensing obligations. The previous
x64 PictView depended on 32-bit `SalPVEnv.exe` and `PVW32Cnv.dll`; neither
runtime file is included in the user's tested x64 build. Do not restore or
package proprietary converter binaries.

WIC uses the codecs available in Windows. Unrelated formats previously handled
by PVW32 may have no WIC codec and must not be advertised as working.

## Production integration on the stacked branch

- `WicImageDecoder.h/.cpp`: open the original UTF-16 filename, decode the
  **selected frame**, convert to straight-alpha BGRA, bound decoded image to
  256 MiB and return HRESULTs without leaking COM objects.
- `WicBitmapPresenter.h/.cpp`: validate pixel layout and destination,
  composite alpha over white, compute aspect-preserving fit, and draw
  top-down GDI BGRA. The native window caches composited pixels rather
  than allocating on every paint.
- `WicNativeViewer.h/.cpp`: independently owned Win32 viewer in the
  existing Salamander viewer thread. Creates/destroys HWND and COM objects
  on that thread, posts the ready event once, preserves the viewer lock
  contract and registers/unregisters with `ViewerWindowQueue`. Supports
  fit-to-window (0), zoom +/- or mouse wheel, PageUp/PageDown for
  multipage WIC formats; R/Shift+R rotate clockwise/counterclockwise, H/V
  mirror the current in-memory frame, Ctrl+C copies a composited bitmap,
  Ctrl+Shift+S exports a new image; Ctrl+V loads an uncompressed 24/32-bit
  Windows DIB from the clipboard as an unsaved in-memory image; Escape/close exits.
- `pictview.cpp`: `InitViewer` no longer calls `LoadPictViewDll` or
  `PVSetParam`; the existing viewer entry point delegates to
  `RunNativeViewer`. The old PVW32 renderer is **not reached by the
  advertised viewer operation**.
- `WicImageTransforms`: atomic pixel-perfect rotation and mirroring of the
  in-memory, straight-alpha BGRA frame; input files are never changed.
- `WicImageWriter`: independent WIC PNG/BMP/JPEG/TIFF encoder. The Save Copy
  action encodes before creating a destination with CREATE_NEW, protecting
  existing files; JPEG/BMP alpha is flattened over white. This is not
  an in-place overwrite/save function.
- `WicImageClipboard`: validates and creates a top-down CF_DIB bitmap
  for Ctrl+C; Ctrl+V parses supported bottom-up/top-down 24/32-bit BI_RGB
  clipboard data with checked row alignment, size and ownership. Unsupported
  clipboard formats are rejected without changing the current picture.
- `thumbs.cpp`: the plugin thumbnail callback decodes through WIC,
  respects cancellation, reports dimensions and streams composited rows
  to the Salamander thumbnail maker.
- `Connect`: advertises only WIC-oriented file suffixes, rather than
  the old expansive PVW32-format list. Old menu extensions are not
  exposed: they would invoke PVW32 callbacks.
- The VCXPROJ compiles the new viewer for x86/x64 and no longer references
  the unavailable `salpvenv.vcxproj`. Obsolete source may remain in the
  project temporarily for compatibility until safe removal is reviewed.

## Critical compatibility boundary

The existing plug-in SDK supplies **ANSI** filename pointers. The boundary
converts with the active Windows ANSI code page using strict round-trip checks
and rejects unsafe aliases. This is not arbitrary UTF-16 filename support:
nonrepresentable Unicode names and unrestricted extended-length paths need
a separate SDK-compatible design and acceptance tests.

A functioning basic image viewer is not equivalent to the old PictView
product. The following old capabilities are **not migrated**:

- Timed animated GIF playback; multipage WIC images support manual
  frame navigation (PageUp/PageDown), not animation scheduling
- Cropping, selections, additional pixel editing, in-place save/overwrite,
  editable history/undo and the old save-format choices
- Screen capture, TWAIN/WIA, wallpaper, print and batch operations;
  clipboard copy and BI_RGB 24/32-bit paste are implemented, but other
  clipboard formats and image sources still need dedicated support
- Legacy format-specific codecs (RAW, CDR, PSP, etc.) not provided by WIC
- EXIF orientation/color management, metadata UI and legacy PictView menus
- Advanced slideshow/navigation, persistent viewer layout/configuration,
  and long-path support across the ANSI plug-in interface

Do not re-enable the old menu functions or claim those features pass.
Existing user viewer associations may still contain older extensions; actual
format probes and decoder failures must fail without corrupting original data.

## Verification

The decoder's independent MSVC x86/x64 BMP, PNG, alpha and error tests
previously passed on PR #9. PR #10 adds the presenter, ABI path conversion,
and Win32 viewer, image transforms, safe writer and clipboard components,
with native MSVC x86/x64 test jobs. Earlier
runs detected Windows `min/max` macro and ANSI cursor type compiler errors;
follow-up code fixes were committed. **No end-to-end Salamander GUI acceptance
of the new native viewer has been established as of this document update.**

Required release gates before claiming a full integration:

1. Clean x86/x64 Debug and Release plug-in builds with no warnings/errors
   on the **same SHA** as the tests.
2. Real interactive GUI tests for PictView load, image open, redraw,
   resize, zoom, HWND close, lock signaling, repeated open/close and
   thumbnail generation; check multiple file types and malformed files.
3. Explicit functional decisions and tested implementations for the
   unsupported legacy features listed above, including data-integrity
   checks for save/edit operations.
4. Tests on varied locale/code-page and long-path settings, including
   fail-closed handling of names that cannot cross the ANSI SDK.
5. Update packaging to exclude obsolete runtime sidecars, and verify
   non-PictView plug-in load smoke before merging PR #8.

Do not merge PR #9/#10 as universal PictView compatibility based only
on compiler success or decoder/unit regressions.

The frame decoder regression creates a two-page TIFF using WIC, checks
first- and second-page pixels and rejects invalid indices without stale
outputs. Standalone x86/x64 WIC tests have passed for the decoder, geometry,
rotation/mirroring and safe new-file PNG export at commit 7e8aa1c9.
The clipboard DIB tests and complete native plugin builds require fresh
verification on the latest source commit. These unit tests are not a real GUI
acceptance of the in-process PictView plug-in.

The clipboard test now checks strict CF_DIB parsing, bottom-up 24-bit
row reordering, source alpha compositing and malformed-header rejection.
The changed source requires fresh Windows CI and real desktop acceptance.
