# v0.1 validation — 2026-10-08

The release build compiles and its application bundle passes `codesign --verify --deep --strict` with an ad-hoc signature. This is not a notarized distribution build.

All 10 standalone engine checks pass: aspect-ratio resize and original preservation; bounds validation/no upscaling; real JPEG quality compression; metadata inspection and pixel-preserving JPEG stripping; orientation transform before stripping; bundled WebP encoding; metadata preservation; HEIC plus lossless/same-format WebP; rejection of unsupported metadata-only stripping; collision-safe filenames.

The native interface was opened with a generated 512 × 512 Dice icon containing demo Artist/Description tags. Verified the image surface, metadata in the same window, search filtering, back navigation, processing through Apply, and removal of the demo descriptive tags from the processed output. The output was 16 KB versus the 17 KB source; this example is not a general compression benchmark.

The image-only Finder Quick Action is installed at `~/Library/Services/Edit with Dice.workflow`, enabled in Finder extensions, and visibly listed in Finder's image context menu under Quick Actions. The installed workflow was executed successfully with the sample image; it opens the compact editor. File-opening uses the AppKit application lifecycle, with SwiftUI confined to view rendering.

The compact final build is about 21.1 MB installed and 6.6 MB zipped. Runtime memory still needs systematic profiling; there is no zero-memory claim. A dormant earlier native-launch sample showed 0.0% CPU and roughly 72 MiB resident memory; a visible earlier UI sample showed roughly 119 MiB. These are separate snapshots, not a before/after benchmark. Conversion helpers are on demand, with no background polling.

Clean-system testing on macOS 14+, Developer ID signing/notarization, Intel packaging and further memory profiling remain outstanding. System Perl availability is a supported-runtime dependency to validate.
