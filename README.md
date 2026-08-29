# Hikari

[English](README.md) | [한국어](README.ko.md)

[![CI](https://github.com/hodadako/lumina/actions/workflows/ci.yml/badge.svg)](https://github.com/hodadako/lumina/actions/workflows/ci.yml)
[![CodeQL](https://github.com/hodadako/lumina/actions/workflows/codeql.yml/badge.svg)](https://github.com/hodadako/lumina/actions/workflows/codeql.yml)
[![Codecov](https://codecov.io/gh/hodadako/lumina/branch/main/graph/badge.svg)](https://codecov.io/gh/hodadako/lumina)
[![Latest release](https://img.shields.io/github/v/release/hodadako/lumina?display_name=tag&sort=semver&label=latest%20release)](https://github.com/hodadako/lumina/releases/latest)
[![License: MIT](https://img.shields.io/github/license/hodadako/lumina?label=license)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/hodadako/lumina?branch=main&label=last%20commit)](https://github.com/hodadako/lumina/commits/main/)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/hodadako/lumina)

**Bring your desktop to life.**

Hikari is a native live wallpaper app for macOS. Import a video, use it across
your connected displays, and optionally apply the selected video through the
macOS Native Lock Screen path.

> Hikari release builds are ad-hoc signed and are not Apple-notarized.

## What works

- AVFoundation video validation, managed copying, metadata, duplicate checks,
  and thumbnails
- Low-overhead looping playback across connected displays and Spaces
- Fill and Fit scaling, mute, battery pause, launch at login, and library management
- Menu bar playback and content controls
- Native Lock Screen apply and explicit Restore with transaction recovery
- Built-in and custom app/menu bar icons
- Checksum-verified Hikari updates from the normal `vX.Y.Z` release channel

## Requirements

- macOS 15 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

The full Xcode installation is required for the Xcode scheme and XCTest suite.

## Native Lock Screen disclaimer

Native Lock changes undocumented macOS wallpaper/Aerial state. Formats may
change without notice, and a failed operation can require recovery. macOS 15
may request administrator authorization; macOS 26 uses the current user's
Aerial store.

Keep a verified backup and do not use this feature on a managed or irreplaceable
Mac. Hikari creates transaction journals and requires **Restore** before a new
video or app update can proceed when a transaction is unfinished. An active
transaction may create a root-readable playback copy; other local accounts on
the Mac may be able to read it while Native Lock is active.

## Download

Download `Hikari-macOS-portable.zip` from the
[latest release](https://github.com/hodadako/lumina/releases/latest), unzip it,
and move `Hikari.app` to Applications.

The app is ad-hoc signed, not notarized. On first launch, Control-click
`Hikari.app`, choose **Open**, and confirm. Verify the download first:

```sh
shasum -a 256 -c Hikari-macOS-portable.zip.sha256
```

## Storage migration

Hikari keeps the existing `~/Library/Application Support/Lumina` directory as
the canonical library. On first launch it merges missing content, settings,
icons, and Native Lock transactions from the former
`~/Library/Application Support/LuminaNative` directory, then moves the old
directory to a recoverable `.archived` folder. Existing canonical files win
conflicts; no source video is deleted.

## Build

```sh
brew install xcodegen
xcodegen generate
open Hikari.xcodeproj
```

Select the `Hikari` scheme. From the command line:

```sh
xcodebuild \
  -project Hikari.xcodeproj \
  -scheme Hikari \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For a local ad-hoc installation:

```sh
scripts/build-hikari.sh
```

The script builds and installs `/Applications/Hikari.app`. Apply and Restore
are available in Settings → Lock Screen. The script does not install a daemon
or persistent privileged helper.

## Test

```sh
swift test
xcodebuild \
  -project Hikari.xcodeproj \
  -scheme Hikari \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Release

Normal `vX.Y.Z` tags build and publish Hikari only as
`Hikari-macOS-portable.zip` with its SHA-256 checksum. Non-tag builds run
validation and tests; packaging and publishing are tag-only.

## Project layout

```text
Sources/
├── LuminaApp/          Hikari menu bar UI, settings, and wallpaper windows
├── LuminaCore/         Models, stores, importer, policy, and renderer
├── LuminaNativeLock/   Native Lock transaction, backup, apply, and restore
└── LuminaNativeTool/   One-shot administrator-authorized system operation
Archive/LuminaLegacy/   Retired Lumina screen-saver and event-tap sources
Tests/
├── LuminaCoreTests/
└── LuminaNativeLockTests/
```

## Current limitations

- Video support follows the AVFoundation capabilities of the installed macOS
- The same video is shown on every display; per-display content is not supported
- No playlist, online gallery, or per-display content
- Releases are ad-hoc signed and not Apple-notarized
- Native Lock uses undocumented macOS behavior and requires hands-on recovery
  testing on each supported macOS major version

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports should follow
[SECURITY.md](SECURITY.md).

## License

Hikari is released under the [MIT License](LICENSE).
