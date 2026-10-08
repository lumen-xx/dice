# dice

A small native Mac app for image conversion, compression, resizing and metadata inspection. Built in Swift with SwiftUI, AppKit and ImageIO.

![Compact image view](docs/image.png)

## v0.1 preview

- Finder-first utility: right-click an image → Quick Actions → Edit with Dice. No window opens on app launch; no menu-bar dashboard.
- A compact 500 × 390 native blurred window, with the image as its surface and controls in the top-right corner. Finder can open multiple images; a compact top-right picker switches between them.
- Batch JPEG, PNG, HEIC and WebP conversion. Native encoders are checked on the current Mac.
- Quality control for lossy output and optional lossless WebP.
- Resize by longest edge, percentage or a bounding box, preserving proportions without upscaling.
- Remove personal metadata by default. Metadata-only mode uses ExifTool without recompressing pixels, retaining colour profiles and orientation.
- Compact summary: dimensions, size, format, camera, capture time and presence of GPS tags.
- Extensive ExifTool tag viewer: search tags/values, filter by group, select a tag to read its full value, copy values or all tags, and export JSON.
- Apply settings to preview the processed image, or process and save a copy with the down-arrow button. Originals are preserved. Metadata replaces the image in the same window; the back arrow returns to it.
- Last-used processing settings persist locally.
- Serial background processing, bounded previews and no idle polling. Stop finishes the current image, then stops the batch.

### Try it

Download the Apple-silicon ZIP from the repository's Releases page and extract it outside a cloud-synced folder. Use Open With → Dice, or install the Finder Quick Action from the development checkout. This preview is locally ad-hoc signed, **not Developer ID signed or notarized**; distribution signing remains to be configured. Dice targets macOS 14 or newer, but this preview has been tested only on the development Mac. Intel builds have not been produced.

The app bundles ExifTool and WebP tools. No Homebrew installation is needed to run it. It currently relies on `/usr/bin/perl`, supplied by the supported macOS system; compatibility across clean macOS installations still needs validation. No network requests, accounts or server connection are used.

### Build

Requires Apple Command Line Tools (Swift 5.9+), Python 3, and local Homebrew installations of **ExifTool 13.50** and **WebP 1.6.0**. These are the development-preview pins; the packaging script rejects different versions instead of silently changing the shipped tools. A source-download build for pinned dependencies is future work.

```sh
swift build -c release
python3 scripts/package.py
python3 scripts/install-quick-action.py
```

Enable **Edit with Dice** in System Settings → General → Login Items & Extensions → Finder, if macOS leaves the new Quick Action disabled. It is already installed and enabled on the development Mac. The action is image-only and lives at `~/Library/Services/Edit with Dice.workflow`; removing that workflow uninstalls the action. The installer refuses to overwrite an existing action.

The ZIP is written to `build/Dice-v0.1.0-apple-silicon.zip`. The signed application is `build/Dice.app` (also recorded in `build/app-path.txt`). Build outside cloud-synced folders, which can attach Finder metadata that breaks signing. The packaging script enforces an installed size below 40,000,000 bytes.

Screenshots: [image view](docs/image.png), [metadata view](docs/metadata.png). See [validation details](docs/VALIDATION.md).

### Run processing checks

After packaging:

```sh
DICE_TOOLS="$(cat build/app-path.txt)/Contents/Resources/Tools" swift run -c release DiceChecks
```

The standalone runner needs no XCTest installation. Checks exercise resize validation and aspect ratio, original preservation, real JPEG compression, ExifTool inspection/stripping, pixel equality after metadata-only stripping, EXIF orientation, bundled WebP encoding, metadata preservation and filename collisions. Generated fixtures contain no personal data.

## Current limits

- PNG uses native lossless re-encoding, not a dedicated PNG optimiser; it can become larger.
- Converted files can grow. Dice reports actual input/output sizes and never promises savings.
- Animated and multi-image files are rejected by conversion to prevent silently discarding frames. Metadata-only removal is limited to JPEG, PNG, HEIC and WebP. TIFF metadata-only stripping is rejected because a blanket ExifTool deletion can leave personal TIFF tags; convert TIFF to a supported output instead.
- JPEG transparency is flattened onto white. Converted HDR/gain-map images are not preserved as HDR in this preview.
- RAW development, SVG/PDF rasterisation, AVIF export, target-file-size compression, side-by-side before/after comparison, login-item settings and per-file overrides are not implemented.
- The metadata viewer displays textual ExifTool output. Embedded binary blobs are described rather than decoded or exported. File-system properties are shown for inspection; metadata stripping does not anonymise filenames or file-system attributes.
- No persistent processing history. Session results are removed on a normal quit. A crash can leave temporary results behind.
- Output files are generated in a temporary session directory; use Save or drag a result out before quitting.

## Resource goals

First packaged preview: approximately **21.1 MB installed / 6.6 MB zipped**, including bundled metadata and WebP tools. An initial visible-window idle sample was **0.0% CPU and about 119 MiB resident memory** on the development Mac; this is a snapshot, not a benchmark or guarantee. No repeating timers or watchers run at idle. Memory profiling and hidden-window measurements are still needed.

## Dependencies

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `vendor/licenses/`. Dice's original source has no open-source license assigned yet. Third-party components retain their respective licenses.
