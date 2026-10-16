# v0.2.5 background removal — 2026-10-16

All 51 standalone checks pass, one of them new. On a synthetic red ball with a shadow on a pale table, Remove background (Vision's foreground instance mask, on device) leaves the corners fully transparent and the ball's centre opaque red; a JPEG with "Same as original" is saved as PNG to keep the transparency, while an explicit JPEG is flattened onto the fill colour; a 1:1 crop resized to 100 px as WebP stays transparent around the ball; Resize only still processes an image already within the size; a plain grey image fails with "couldn't find a subject" and writes nothing. Each part was confirmed to fail with its code reverted (mask not applied, JPEG kept as JPEG, resize-only skipping).

The mask is applied to the decoded pixels in their own colour space (or half-float for HDR), so colours aren't re-rendered. "Keep the original when it's smaller" never applies to a cut-out. Animations are not cut out.

Native review of Dice Dev with Remove background on, using the macOS user picture Parrot.heic (512 × 512): Start saved `parrot-dice.heic` with alpha, 36% fully transparent and 61% fully opaque, and composited over a checkerboard the parrot's head and beak are cleanly cut out. The Adjust menu shows Remove background under Crop and the row reads "No background" when it's on. Not checked: photos with several subjects, and very large images (Vision runs at the decode size, up to the output size).

---

# v0.2.4 colour and metadata — 2026-10-16

All 50 standalone checks pass, five of them new. File names: `{name}-dice` by default; `{n}` pads to the batch size (`003` of 120, at least two digits), `{date}` is today as `yyyy-MM-dd`; slashes and colons are dropped, an empty pattern falls back to the original name, a leading dot is not allowed to hide the file, and PDF pages keep their page suffix. Convert to sRGB turns a Display P3 image into sRGB with P3's pure green clipped to sRGB green, and leaves an sRGB image unchanged with no note. HDR, on synthetic ISO gain-map photos (half SDR grey, half four times SDR white): an HDR JPEG with Artist, GPS and City saved as HEIC keeps its gain map and its metadata; with Remove location it keeps the gain map and Artist and loses GPS and City; rotated and resized to 16 × 32 it stays HDR as JPEG, HEIC and AVIF; as PNG it is SDR with a note; with Keep HDR off, or Convert to sRGB on, it is SDR. Metadata-only removal keeps the gain map of HDR JPEG, HEIC and AVIF files. Location-only removal clears EXIF and XMP GPS and IPTC/XMP place names while keeping Artist, both in place and when converting. The JPEG HDR removal, HDR decoding, location removal and sRGB checks were confirmed to fail with their change reverted.

Two bugs in earlier versions, found while probing ExifTool 13.50 against ImageIO's gain-map files: Dice decoded HDR photos to their SDR base, so every conversion silently lost HDR; and metadata-only removal (`-all=`) deleted the MPF trailer and APP2 block that hold a JPEG's gain map. HDR JPEGs now have their metadata removed group by group, and if a gain map still goes missing the file is left unchanged with an error. ExifTool adding a new metadata item to an ImageIO gain-map HEIC or AVIF also dropped the gain map, so HDR output takes its metadata from ImageIO instead (EXIF, GPS and XMP; maker notes are not carried). The check for that guard still passes with the guard removed, because ImageIO had already written the items and ExifTool only updated them; the guard is kept for files where ExifTool would add an item.

Not tested with a real camera HDR photo (iPhone HEICs carry Apple's own gain map, which ImageIO reads the same way): all HDR checks use synthetic ISO gain-map files. HDR handling needs macOS 15; on macOS 14 photos are treated as SDR, as before.

Native review of Dice Dev on a 64 × 32 HDR JPEG: the info line reads "JPEG HDR"; Image settings shows Adjust ("As is") and a Metadata picker (Keep, Remove location, Remove personal); the Adjust menu adds Convert to sRGB and a checked Keep HDR. Start saved `sunset-hdr-dice.jpg` with its gain map. Not checked natively: the File name field in App settings and migration of an existing suffix (a saved "-dice" suffix becomes `{name}-dice`).

---

# v0.2.3 size and shape — 2026-10-16

All 45 standalone checks pass, four of them new. Planning: Width and Height modes keep the aspect ratio; a raster image never grows unless Allow enlarging is on (then 800 × 600 at width 1600 gives 1600 × 1200, and percentages up to 1000% are allowed; above 100% without it is an error); Fill and crop gives exactly 1080 × 1080 from 2000 × 1200 and stays 900 × 900 from 1600 × 900 without enlarging; rotation by 90° swaps width and height before sizing; a 1:1 or 16:9 crop is centred; outputs over 32768 px are refused. Pixels: on a red-left, blue-right image, clockwise rotation puts red on top, anticlockwise at the bottom, 180° and horizontal flip put blue on the left, rotate-then-flip-vertical puts red at the bottom, and a 1:1 crop keeps the centre. A rotated JPEG in the same format and size is not replaced by the original when "Keep the original when it's smaller" applies. @1x–@3x sets are a folder of `photo@3x.png` (the planned size), `photo@2x.png` and `photo.png`, also with Fill and crop. PDF pages render at 200 × 120 by default (144 dpi), 417 × 250 at 300 dpi and 100 × 60 at 72 dpi. A rotated GIF animation keeps its frames at the turned size. The rotation direction, scale-set fill and keep-original checks were confirmed to fail with the code reverted; the keep-original check first passed with the guard removed, because the optimised PNG was already smaller, and now uses a low-quality JPEG re-encoded at 100%.

Rotation and flips reset with each new batch, like Metadata only; the crop, enlarging, scale-set and PDF resolution settings are remembered. Crop is centred; there is no interactive crop.

Native review of Dice Dev: Image settings gains one row, Shape, whose label summarises what is on ("1:1, @1–3x", or "As is"); its menu holds Rotate and Crop submenus, the two flips, Allow enlarging and Also save @2x and @1x, plus PDF resolution when the batch has a PDF. Start on a 400 × 300 JPEG with 1:1 and the scale set wrote a `first-dice` folder of 300², 200² and 100² images beside it. Not checked natively: Width, Height and Fill and crop fields, rotation in the app, and the PDF resolution submenu.

---

# v0.2.2 formats — 2026-10-16

All 41 standalone checks pass, six of them new. SVGZ renders like SVG; an Illustrator file saved with PDF compatibility opens as its PDF pages; an Illustrator file without it and an EPS file each fail with an explanation instead of a generic error. ICO output holds 16–256 px (ImageIO writes at most six images, so 64 px is left out) and ICNS 16–512 px for a 600 px image (ICNS has no 64 px slot); a 300 × 200 image is padded to a square, not stretched, and a 10 px image becomes a single 16 px icon. PDF output is one page the size of the image; combining a one-page and a two-page PDF gives three pages with their own sizes. A three-frame GIF saved as APNG, animated WebP (bundled img2webp 1.6.0), HEIC sequence and GIF keeps three frames at the resized width, with the middle frame's colour intact. Metadata-only removal works in place for TIFF, GIF and AVIF; DNG is enabled too but untested, with no DNG sample. The animation, SVGZ and AVIF checks were confirmed to fail with their change reverted.

The checks found a bug in earlier versions: ImageIO's AVIF encoder fails at quality 1.0, so AVIF output at 100% quality gave "Could not write the converted image". AVIF quality now tops out at 0.99.

Three existing checks were updated for intended changes: metadata-only rejection now uses BMP (TIFF is supported), "Same as original" for an ICO now writes an ICO, and an animated GIF saved as PNG needs Keep animations off to give a folder of frames.

JPEG XL output was not added. Homebrew's cjxl 0.12 needs libjxl, OpenEXR, Imath, highway, brotli and lcms2, about 6.5 MB more, which puts the app over its 40 MB budget, and it needs a newer libpng than the one bundled for cwebp.

Native review of Dice Dev with two JPEGs and PDF as the default format: Image settings shows PDF, Quality and "Combine into one PDF"; Start wrote `Combined-dice.pdf` beside the first image with pages of 400 × 300 and 300 × 500 points. The installed app is 35.2 MB. Not checked natively: animated output, ICO/ICNS and SVGZ in the app (covered by the engine checks only).

---

# v0.2.1 compression — 2026-10-16

All 35 standalone checks pass, three of them new. Target file size: a 800 × 600 noise image fits 150 KB at full size; at 12 KB the image shrinks until it fits; with about 50 KB of kept XMP the result still fits; PNG output ignores the target with a note. PNG optimisation with the bundled oxipng 10.2.1 is smaller with identical decoded pixels. Keep the original when it's smaller: a quality-30% JPEG re-encoded at 100% keeps the original's bytes, with GPS and Artist removed when metadata removal is on; the setting off, or another format, keeps the re-encoded file. Each new check was confirmed to fail with its feature disabled.

The metadata-retry check first passed with the retry disabled. That exposed a bug: `Engine.fileSize` read URL resource values, which are cached, so a rewritten file reported its old size. It now reads the size from disk.

`Engine.swift` is split into `Types.swift` (formats and options), `Engine.swift` (inspection, conversion, saving) and `Encoders.swift` (flattening, encoders, optimisation).

Native review of Dice Dev: the Quality label is a menu that switches the same row to a target size in KB; PNG input hides Quality and shows Optimise PNG. Not checked visually: the "Keep the original when it's smaller" switch in App settings, which is further down the scrolling settings view.

---

# v0.2.0 Aurora style — 2026-10-16

Visual change only; no processing code changed and all 32 checks still pass. Orange is gone: `DiceStyle` defines the Aurora palette (mint `#34E5B8`, cyan `#2BC4F2`, indigo `#5E6BFF`, violet `#A65CFF`). Indigo is the single accent, also used for the Start play glyph; gradients are used only for the drop glow, the progress ring, the empty-state die and the app icon.

Native review of Dice Dev in dark and forced-light appearance (`-NSRequiresAquaSystemAppearance YES`) verified the empty-state aurora die, the indigo Start play glyph, indigo selection in the batch list, indigo checkbox, slider and picker tints in Image settings, and the aurora progress ring at 7 of 30 during a 30-image run. The README screenshots were retaken with the new icon. Image settings over a green photo was unreadable with indigo picker values; pickers now use primary text and dark appearance uses a lighter indigo, rechecked over the same image in dark and light. Not checked visually: the drop glow during a real drag, the menu bar drop target's highlight,.

---

# v0.1.28 bug fixes — 2026-10-16

All 32 standalone checks pass, including ten new ones, one per fixed bug: BMP output with metadata kept; multi-size icons as one image; the WebP temporary file never replacing another result; SVG and PDF rendering above their intrinsic size; "Same as original" fallbacks and when Quality applies; session-only choices resetting; PDF pages reusing file metadata (ExifTool unreachable for page 2); folder expansion with hidden files and a limit; the bundled-tool timeout; and wide-gamut flattening. Five engine checks were confirmed to fail with the old code put back (BMP, icons, WebP temporary, vector size, flattening).

Native review of Dice Dev verified the Edit menu (Undo, Redo, Cut, Copy, Paste, Select All), opening a folder as its three images including one in a subfolder, an ICO shown as a single 64 × 64 image (its largest size), and Command-V adding a pasted image to the batch. Not exercised natively: pasting text into search fields, saving a pasted image to Downloads, trashing every page of a PDF from one page, and the "nothing was saved" alert after a resize-only run that skips everything.

---

# v0.1.9 settings correction — 2026-10-08

Native review verified two separate views: Command-comma opens App settings inside Dice with export defaults and update controls only; the sliders opens an anchored Image settings popover containing conversion, resize, quality and metadata controls. Command-comma from the open popover dismisses it and opens App settings. The release build and deep strict signature verification pass. No processing changes were made; the 20 processing checks from 0.1.8 remain applicable.

---

# v0.1.8 validation — 2026-10-08

The release build compiles, passes deep strict bundle signature verification, and stays below 40 MB: approximately 31.5 MB installed / 10.1 MB zipped. The bundled resvg 0.48.1 renderer runs only on demand; dependency license texts are shipped.

All 20 standalone checks pass. New coverage exercises SVG alpha, JPEG flattening and viewBox sizing; PDF page extraction, rotation and full-page raster scaling; GIF/BMP/TIFF/AVIF round trips; GIF/TIFF frame extraction; resolution-only downsizing with metadata retained and smaller inputs skipped; automatic saving beside originals or to a configured folder without overwriting; and preview budget/eviction/page isolation. RAW support uses the available macOS decoders and was not checked against a camera-file corpus. AVIF encoding is confirmed on this Mac and remains dependent on macOS encoder availability.

Native review verified SVG/PDF imports, separately named PDF pages, correct second-page rendering, instant cached paging without a loader, and automatic saving through Start. Resolution-only resize saved two PDF pages at 500 × 333 and skipped the 300 × 200 SVG. Command-comma opens Settings inside the Dice window, with Back; it was also checked from metadata before the final move into the window. Native horizontal/vertical/diagonal cursor rectangles and edge-drag handling compile; the cursor's exact appearance could not be confirmed with the available cropped native screenshot controls.

Native app settings review verified folder selection, independent default-format and folder switches, the automatic-update switch, and preference persistence after quitting/reopening the isolated review build. Automatic-check scheduling is wired to Sparkle but its delayed network check was not timed in this review.

A generated 2400 × 1600 JPEG, displayed at a 1200-pixel longest edge, averaged 73.265 ms per decode over 8 decodes versus approximately 0.0002 ms per cached retrieval over 1000 lookups. This measures engine/cache work, not full UI latency. The cache enforces a 32 MiB pixel-data budget; batch thumbnails and the active view are additional memory. Imports reuse the OCR-sized decode for previews and create the thumbnail from it instead of decoding each input twice. Metadata is reused during paging. Reprocessing has a new preview generation to avoid reusing stale result pixels.

A visible three-entry review session after processing sampled 0.0% CPU and about 149 MiB resident memory. This is one idle snapshot, not a benchmark or zero-resource claim. Larger batches may evict previews and decode them again, showing their thumbnail while loading. Closing the session clears cached previews. Previous signed public update validation is recorded below.

---

# v0.1.7 validation — 2026-10-08

Release build and deep strict bundle signature verification pass. Size: 26.23 MB installed / 7.80 MB zipped. All 11 processing/search checks pass.

Fresh native development launch imports the generated image promptly after moving the AppKit run loop out of the Swift main-actor entry job. Native checks verified header/search spacing, trailing per-row copy controls, metadata details in the bottom-left footer, and the batch count aligned with paging. Clicking Copy ImageSize placed `512x512` on the clipboard. README screenshots use generated demo content only.

Public GitHub updates installed both 0.1.6 and 0.1.7. For 0.1.7, native download/ready-to-install UI was checked; after session protection and close, the installed bundle became 0.1.7/build 8, passed deep strict signature verification and reopened to the drop surface. The public GitHub update completed: `/Applications/Dice.app` changed from 0.1.5/build 6 to 0.1.6/build 7, and the running app reopened with an image. The earlier local signed installation/relaunch test is recorded below.

---

# v0.1.6 updater validation — 2026-10-08

Sparkle 2.10.0 is pinned in SwiftPM and bundled with its license. The packaged app passes deep, strict signature verification and remains below the 40 MB budget: approximately 26.2 MB installed / 7.8 MB zipped. All 11 processing/search checks pass.

The signed archive and signed feed verify against the Dice Keychain key. Modified archive and feed fixtures are rejected. Reusing an already-published build is rejected by the publisher. Public assets and feeds are hosted separately from the private source repository; no access token is packaged.

A native local update test installed build 6 over build 5 and relaunched at the original app path. Server logs confirmed feed/archive requests; the installed Info.plist changed to 0.1.5/build 6, and the subsequent check reported that version up to date. The public release feed and archive are published; GitHub’s raw feed can lag while its CDN refreshes.

Checks are manual by default. The updater postpones relaunch if image processing/import or unsaved processed copies remain. The unsaved-results branch was subsequently exercised during the public 0.1.7 update: relaunch was held until the result was backed up and the editor closed. Initial browser-download Gatekeeper approval and cross-machine compatibility remain to be validated; update signatures do not notarize Dice itself.

---

# v0.1.4 validation — 2026-10-08

The release build compiles and the installed bundle passes deep, strict signature verification. A native preview showed the full 620 × 460 borderless surface, a custom left-side close capsule matching the right toolbar, and no native traffic lights. The drag overlay now shares the complete content/window bounds; there is no title-bar strip outside it.

The custom close button was exercised: the development process switched to accessory activation (Dock hidden), and reopening restored the editor. Minimize/fullscreen overrides remain in place; Command-W also invokes the custom close action. A held Finder drag was not visually checked in this update.

---

# v0.1.3 validation — 2026-10-08

The release build compiles. The native metadata preview was checked with a generated image: grouped flat rows, unboxed header, larger search field, filtering to two Artist tags, and inline full-value expansion. Copy/export actions remain available from the header and row context menu. Search fields in metadata and batch views use 36-point height and 13-point system text.

The installed application passes deep, strict code-signature verification. Processing code is unchanged in this interface update; the prior 11 processing/search checks are recorded below.

---

# v0.1.2 validation — 2026-10-08

The release build compiles. An isolated copy of the packaged app launched to the empty drop surface with no file picker. Clicking Choose images explicitly opened the picker; Cancel returned to the editor. The check used a separate application identifier to leave the active Dice session intact.

The new full-window aurora border is scoped to the accepted drag-over state, with its timeline limited to that state's lifetime. Reduce Motion pauses the gradient and disables the hover transition. The actual drag-hover appearance has not been verified through a held Finder drag.

---

# v0.1.1 validation — 2026-10-08

The release build compiles and the installed `/Applications/Dice.app` passes deep, strict code-signature verification. It is ad-hoc signed, not notarized.

All 11 standalone checks pass, including a new search check covering filenames, diacritics, metadata names/values, dimensions, recognized-text input and multi-term matching across fields.

Native interface checks verified Applications launch/reopen, shared image/metadata/batch navigation, searchable batch selection and removal without deleting originals. Generated fixtures demonstrated actual OCR search for “Lantern” and metadata search for “Artist Atlas”. Native close was exercised; the installed process switched from regular (Dock visible) to accessory (Dock hidden), and reopening restored the editor. Minimize and fullscreen are disabled at the window level.

The default window is 620 × 460 points, with a 520 × 420 minimum. Typography, accent and control sizing are centralized in `Sources/Dice/Style.swift`, with the interface guide documenting their use. The title bar is transparent and the content fills it; native traffic lights occupy the left and Start applies the current settings from the right toolbar.

The package is approximately 21.3 MB installed and 6.7 MB zipped. The Finder Quick Action targets the installed Applications copy. No systematic memory benchmark or clean-system compatibility check was performed for this update.

---

# v0.1 validation — 2026-10-08

The release build compiles and its application bundle passes `codesign --verify --deep --strict` with an ad-hoc signature. This is not a notarized distribution build.

All 10 standalone engine checks pass: aspect-ratio resize and original preservation; bounds validation/no upscaling; real JPEG quality compression; metadata inspection and pixel-preserving JPEG stripping; orientation transform before stripping; bundled WebP encoding; metadata preservation; HEIC plus lossless/same-format WebP; rejection of unsupported metadata-only stripping; collision-safe filenames.

The native interface was opened with a generated 512 × 512 Dice icon containing demo Artist/Description tags. Verified the image surface, metadata in the same window, search filtering, back navigation, processing through Apply, and removal of the demo descriptive tags from the processed output. The output was 16 KB versus the 17 KB source; this example is not a general compression benchmark.

The image-only Finder Quick Action is installed at `~/Library/Services/Edit with Dice.workflow`, enabled in Finder extensions, and visibly listed in Finder's image context menu under Quick Actions. The installed workflow was executed successfully with the sample image; it opens the compact editor. File-opening uses the AppKit application lifecycle, with SwiftUI confined to view rendering.

The compact final build is about 21.1 MB installed and 6.6 MB zipped. Runtime memory still needs systematic profiling; there is no zero-memory claim. A dormant earlier native-launch sample showed 0.0% CPU and roughly 72 MiB resident memory; a visible earlier UI sample showed roughly 119 MiB. These are separate snapshots, not a before/after benchmark. Conversion helpers are on demand, with no background polling.

Clean-system testing on macOS 14+, Developer ID signing/notarization, Intel packaging and further memory profiling remain outstanding. System Perl availability is a supported-runtime dependency to validate.
