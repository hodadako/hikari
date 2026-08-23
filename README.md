# Lumina

[English](README.md) | [한국어](README.ko.md)

[![Codecov](https://codecov.io/gh/hodadako/lumina/branch/main/graph/badge.svg)](https://codecov.io/gh/hodadako/lumina)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/hodadako/lumina)

**Bring your desktop to life.**

Lumina is a native, open-source live wallpaper and screen saver for macOS.
Import a movie that macOS can play, use it across your connected displays, and
reuse the same content in the Lumina screen saver.

> Lumina 0.3 remains experimental. Portable builds are ad-hoc signed and are
> not Apple-notarized.

## What works

- Live wallpaper across connected displays and Spaces
- Import of common AVFoundation-compatible MP4, MOV, and M4V files
- Fill and Fit scaling, looping playback, and menu bar controls
- Settings for mute, battery pause, launch at login, and library management
- Screen saver installation/update with preview and full-screen playback
- Playback pause and recovery around sleep, screen lock, and display changes
- Optional Lock Screen playback through the Lumina screen saver
- Checksum-verified in-app update checks

## Requirements

- Portable app: macOS 13 Ventura or later
- Development: Xcode 15 or later and
  [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Native Local/Hikari: macOS 15 or macOS 26 and Xcode 16 or later

The full Xcode installation is required for the Xcode schemes and XCTest suite.

## Experimental native Lock Screen disclaimer

The optional native Lock Screen integration is an experimental Hikari target. It
is separate from the supported Lumina Portable release and its in-app updates.
Hikari may be distributed as an ad-hoc, unnotarized release asset. It writes
undocumented macOS wallpaper/Aerial state; macOS 15 may request administrator
authorization, while macOS 26 uses the current user's Aerial store without that
prompt. These formats may change without notice.

Back up the Mac and keep the Restore action available before trying it. Do not
use it on a managed or irreplaceable Mac, and do not run another wallpaper tool
that edits the same store at the same time. While Native Lock is active, macOS
may keep a system-readable playback copy that other local accounts can read.
CI builds and downloadable artifacts do not validate these privileged changes.
See the [Hikari Native Local guide](docs/LOCAL_NATIVE_BUILD.md) for the complete
build, apply, and restore procedure.

## Download the portable app

Download `Lumina-macOS-portable.zip` from the
[latest release](https://github.com/hodadako/lumina/releases/latest), unzip it,
and move `Lumina.app` to Applications.

Portable builds are ad-hoc signed but not Apple-notarized. On first launch,
Control-click `Lumina.app`, choose **Open**, then confirm **Open**. Lumina appears
in the menu bar rather than the Dock.

Verify the download before opening it:

```sh
shasum -a 256 -c Lumina-macOS-portable.zip.sha256
```

## Build

Install XcodeGen and generate the project:

```sh
brew install xcodegen
xcodegen generate
open Lumina.xcodeproj
```

Select the `Lumina` scheme and run it. Lumina appears in the menu bar.

From the command line:

```sh
xcodebuild \
  -project Lumina.xcodeproj \
  -scheme Lumina \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The build includes `Lumina.saver`. Install it from Lumina Settings → Screen
Saver, then select Lumina in macOS System Settings.

For the experimental Native Local Hikari target, build it on the Mac where it
will run, without opening Xcode:

```sh
scripts/build-native-local.sh
```

The script installs `/Applications/Hikari.app`. Hikari uses reviewed macOS 15
and macOS 26 paths only, is released separately from Lumina Portable on
`hikari-vX.Y.Z` tags, and has no in-app updater. On macOS 15, Apply and Restore
require administrator authorization; macOS 26 user Aerial transactions do not.
See [Building Hikari Native Local on Another Mac](docs/LOCAL_NATIVE_BUILD.md)
before applying or restoring a Native Lock transaction.

## Test

With the full Xcode developer tools selected, run:

```sh
swift test
```

Or run the full Xcode test suite:

```sh
xcodebuild \
  -project Lumina.xcodeproj \
  -scheme Lumina \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Project layout

```text
Sources/
├── LuminaApp/          Menu bar app, settings, and wallpaper windows
├── LuminaCore/         Shared models, storage, import, and playback policy
├── LuminaNativeLock/   Native Local transaction and restore engine
├── LuminaNativeTool/   One-shot administrator-authorized operation
└── LuminaScreenSaver/  ScreenSaver.framework bundle
Tests/
├── LuminaCoreTests/
└── LuminaNativeLockTests/
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for lifecycle and storage details and
[PERFORMANCE.md](PERFORMANCE.md) for the performance test plan.

## Current limitations

- Video support follows the AVFoundation capabilities of the current macOS
  release
- The same video is shown on every display; per-display content is not supported
- No playlist, online gallery, or per-display content
- `Fill` can crop the edges; use `Fit` to keep the entire video visible
- Portable builds are ad-hoc signed and not Apple-notarized
- Hikari is a separate ad-hoc, unnotarized artifact with no in-app updater
- Long-duration performance checks require hands-on Instruments testing

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). By participating, you agree to follow
the [Code of Conduct](CODE_OF_CONDUCT.md). Security reports should follow
[SECURITY.md](SECURITY.md).

## License

Lumina is released under the [MIT License](LICENSE).
