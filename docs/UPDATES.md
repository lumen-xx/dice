# Dice updates

The application menu contains Check for Updates… and Include Preview Releases. Checks are manual by default, with no background checking or automatic installation. Preview releases are enabled by default during v0.1 development; disabling them accepts only stable entries.

Source remains in the private `lumen-xx/dice` repository. Downloads, release notes and the signed appcast live in public `lumen-xx/dice-releases`. The app does not call the authenticated GitHub API or contain a token. Its HTTPS feed points to tagged GitHub release assets, so prereleases work without relying on GitHub’s stable-only latest-download redirect.

Sparkle 2.10.0 verifies Ed25519 update archives before extraction and verifies the signed feed. The feed-signature failure timeout is disabled. Unsigned/tampered archives are rejected. These signatures authenticate Dice updates; they do not replace Developer ID notarization for the initial browser-downloaded installation.

The release key is stored in the login Keychain under Sparkle account `dice`. Only its public key is committed in `updates/config.json`. Keep the Keychain backed up: loss of this private key would prevent issuing trusted updates to existing ad-hoc builds. No key is exported by the normal build or publisher.

## Release steps

1. Increase the version and integer build in `updates/version.json`; select `preview` or `stable`.
2. Build with `python3 scripts/package.py`.
3. Write release notes to a plain text or Markdown file.
4. Prepare and verify the signed assets with `python3 scripts/publish-update.py --notes /absolute/path/notes.md`.
5. Add `--publish` to that command to create a GitHub release and update the feed.

The publisher verifies the configured Keychain key, the packaged version, the existing signed feed, the archive signature and the new feed signature. It preserves prior feed entries, including stable entries while publishing previews. The archive is published before updating the feed; GitHub’s file revision prevents silently overwriting a concurrent feed edit. Reusing a build number is rejected. Published releases are immutable by convention: fix any error with a newer build.

Automatic publishing here means one release command handles signing, upload and feed publication. It is not a hosted GitHub Actions build: building depends on the development Mac’s pinned tools and signing key.

## Installation and development

Existing v0.1.4 and older builds have no updater. Install one updater-enabled release once; browser downloads may still need macOS approval because Dice itself is not Developer ID signed/notarized. Later updates run through Sparkle.

The separate Dice Dev copy uses another bundle identifier and is marked as a development build; it does not install production updates over that identity. Use Dice in Applications to update releases. Rebuild the dev copy from source instead.

If images are being imported or processed, a new manual check is blocked until they finish. If an installation is already ready while images are active or processed copies remain unsaved, relaunch waits: save the copies and close the Dice editor to proceed.
