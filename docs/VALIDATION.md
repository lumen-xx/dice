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
