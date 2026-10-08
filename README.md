# Dice

A small native Mac app to convert, resize and compress images, and to inspect and remove metadata. Everything stays on your Mac.

macOS 14+ · Apple silicon

## Install

1. [Download Dice](https://github.com/lumen-xx/dice-releases/releases), unzip and move **Dice.app** to **Applications**.
2. Open it. If macOS blocks it, go to **System Settings → Privacy & Security → Open Anyway**.

Dice is not notarized yet.

## Use

Drop images, PDFs or SVGs on the window, or right-click them in Finder → **Edit with Dice**. Adjust the settings (sliders icon), then press ▶. Results are saved beside the originals, in a default folder, or over the originals (moved to the Trash) if you choose **Replace originals**.

![Image editor](docs/image.png)
![Metadata viewer](docs/metadata.png)

## Build

Needs Swift 5.9+, Python 3, Cargo, and Homebrew `exiftool` 13.50 and `webp` 1.6.0.

```sh
cargo install resvg --version 0.48.1 --locked --root build/vendor/resvg
python3 scripts/package.py --dev   # Dice Dev.app: no Finder service, safe for testing
python3 scripts/package.py         # release app + ZIP in build/
```

Checks: `DICE_TOOLS="$(cat build/app-path.txt)/Contents/Resources/Tools" swift run DiceChecks`

More: [style guide](docs/STYLE_GUIDE.md) · [validation](docs/VALIDATION.md) · [updates](docs/UPDATES.md) · [third-party notices](THIRD_PARTY_NOTICES.md)
