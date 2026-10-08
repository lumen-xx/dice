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
