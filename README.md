# Hikari

[English](README.md) | [한국어](README.ko.md)

<p align="center">
  <a href="https://github.com/hodadako/hikari/actions/workflows/ci.yml"><img src="https://github.com/hodadako/hikari/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/hodadako/hikari/actions/workflows/codeql.yml"><img src="https://github.com/hodadako/hikari/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
  <a href="https://codecov.io/gh/hodadako/hikari"><img src="https://codecov.io/gh/hodadako/hikari/branch/main/graph/badge.svg" alt="Codecov"></a><br>
  <a href="https://github.com/hodadako/hikari/releases/latest"><img src="https://img.shields.io/github/v/release/hodadako/hikari?display_name=tag&amp;sort=semver&amp;label=latest%20release" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/hodadako/hikari?label=license" alt="License: MIT"></a>
  <a href="https://github.com/hodadako/hikari/commits/main/"><img src="https://img.shields.io/github/last-commit/hodadako/hikari?branch=main&amp;label=last%20commit" alt="Last commit"></a><br>
  <a href="https://deepwiki.com/hodadako/hikari"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
</p>

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
- Automatic macOS 26 Native Lock Screen updates when the selected video changes,
  plus transaction recovery and Restore
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
Mac. Hikari creates transaction journals and requires **Restore** before an app
update, or before changing a recovery-required transaction. On macOS 26,
selecting a different video automatically replaces an active Aerial transaction. An active
transaction may create a root-readable playback copy; other local accounts on
the Mac may be able to read it while Native Lock is active.

## Download

Download `Hikari-macOS-portable.zip` from the
[latest release](https://github.com/hodadako/hikari/releases/latest), unzip it,
and move `Hikari.app` to Applications.

The app is ad-hoc signed, not notarized. On first launch, Control-click
`Hikari.app`, choose **Open**, and confirm. Verify the download first:

```sh
shasum -a 256 -c Hikari-macOS-portable.zip.sha256
```

## Storage migration

Hikari uses `~/Library/Application Support/Hikari` as its canonical library.
On first launch it merges missing content, settings, icons, and Native Lock
transactions from a detected pre-Hikari support root, then moves that source
directory to a recoverable `.archived` sibling. Existing canonical files win
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

The script builds and installs `/Applications/Hikari.app`. On macOS 26,
changing the selected video in General automatically updates the Native Lock
Screen Aerial. Restore is shown in General only while a transaction needs
recovery. The script does not install a daemon or persistent privileged helper.

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
├── HikariApp/          Hikari menu bar UI, settings, and wallpaper windows
├── HikariCore/         Models, stores, importer, policy, and renderer
├── HikariNativeLock/   Native Lock transaction, backup, apply, and restore
└── HikariNativeTool/   One-shot administrator-authorized system operation
Archive/HikariLegacy/   Retired Hikari screen-saver and event-tap sources
Tests/
├── HikariCoreTests/
└── HikariNativeLockTests/
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
