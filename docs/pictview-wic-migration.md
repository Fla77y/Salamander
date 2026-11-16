# PictView replacement with Windows Imaging Component (WIC)

Status: **integrated first-frame native viewer + thumbnails; feature parity and
real Windows GUI acceptance remain outstanding.** Work is stacked as PR #10
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
  multipage WIC formats, and Escape/close.
- `pictview.cpp`: `InitViewer` no longer calls `LoadPictViewDll` or
  `PVSetParam`; the existing viewer entry point delegates to
  `RunNativeViewer`. The old PVW32 renderer is **not reached by the
  advertised viewer operation**.
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
- Image rotation, mirroring, cropping, pixel editing and image save/export
- Clipboard/capture, TWAIN/WIA, wallpaper, print and batch operations
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
and Win32 viewer components, with native MSVC x86/x64 test jobs. Earlier
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

The subsequent frame decoder regression also creates a two-page TIFF using
WIC, then checks distinct first- and second-page pixels and rejects invalid
indices without exposing stale image buffers. Its first real CI execution
is still required before claiming multi-page behavior verified.
