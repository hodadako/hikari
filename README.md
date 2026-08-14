# Lumina

[English](README.md) | [한국어](README.ko.md)

**Bring your desktop to life.**

Lumina is a native, open-source live wallpaper and screen saver for macOS. Import
a movie that AVFoundation can play—including common MP4, MOV, and M4V files—use
it across every connected display, and reuse the same content in the Lumina
screen saver.

> Lumina 0.3 remains an experimental project. Portable builds are ad-hoc signed
> and are not Apple-notarized.

## What works

- AVFoundation-playable movie validation, managed copying, metadata extraction,
  duplicate detection, and thumbnail generation while preserving the source
  container extension
- Low-overhead looping playback with `AVQueuePlayer` and `AVPlayerLooper`
- Borderless wallpaper windows across all Spaces and connected displays
- Independent synchronized playback sessions on every connected display; Lumina
  never changes the macOS desktop wallpaper or menu bar
- Fill and Fit scaling
- Menu bar playback and content controls
- Native settings for mute, battery pause, launch at login, and library management
- Pause and recovery around sleep, screen lock, screen saver, and display changes
- Explicit screen saver installation/update and Lock Screen opt-in with exact
  restoration of the user's previous delay
- A separate `.saver` bundle with preview and full-screen playback
- Optional Lock Screen playback through the Lumina screen saver after 1 minute
- Immediate Lumina Lock action with an optional ^ + Command + Q override
- Blue, Pink, Purple, and user-imported app icons applied to Finder, Spotlight,
  and the app switcher
- Independent built-in or user-imported menu bar icons
- Latest-release checks with checksum-verified in-app updates
- Shared atomic JSON storage in `~/Library/Application Support/Lumina`

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

The full Xcode install is required for the Xcode schemes and XCTest suite. Native
Local additionally needs a toolchain with the macOS 15 SDK (Xcode 16 or matching
Apple Command Line Tools). Its source-only script can be compiled with Command
Line Tools, but that environment cannot run this repository's XCTest targets.

## Experimental native Lock Screen disclaimer

Any experimental integration that places custom video in the native macOS Lock
Screen is **source-only and intended for local builds**. It is not part of the
supported portable release or in-app update path. This work may request
administrator authorization and may modify undocumented macOS wallpaper/aerial
state. Those formats can change without notice and a failed operation can leave
the user's wallpaper configuration requiring repair.

The transaction staging directory is user-only. While Native Lock is active,
however, macOS system services require a root-owned, system-readable playback
copy; another local account on the same Mac may be able to read that copy. The
explicit Restore action removes the verified system copy.

Build and inspect the source locally before enabling this experiment. Keep a
verified backup and recovery path, do not use it on a managed or irreplaceable
Mac, and do not run another tool that edits the same system wallpaper/aerial
store at the same time. GitHub Actions will continue to build and test Lumina,
but a successful CI run or downloadable artifact does **not** validate or
endorse privileged changes on a user's Mac. The normal live wallpaper and
ScreenSaver.framework features remain separate from this experiment. The
The `LuminaNative` scheme is therefore deliberately local-only: it uses a one-shot
bundled tool after an explicit administrator prompt, creates user and root-owned
backups and transaction journals before activation, verifies the result, and
exposes an explicit restore action. It installs no daemon or persistent
privileged helper.

## Download the portable app

Download `Lumina-macOS-portable.zip` from the
[latest release](https://github.com/hodadako/lumina/releases/latest), unzip it,
and move `Lumina.app` to Applications.

Portable builds are ad-hoc signed but not Apple-notarized. On first launch,
Control-click `Lumina.app`, choose **Open**, then confirm **Open**. Lumina appears
in the menu bar rather than the Dock.

Each release includes `Lumina-macOS-portable.zip.sha256`. Verify the download
before opening it:

```sh
shasum -a 256 -c Lumina-macOS-portable.zip.sha256
```

Tagged release builds upload the same ZIP and checksum as release assets.

## Build

```sh
brew install xcodegen
xcodegen generate
open Lumina.xcodeproj
```

Select the `Lumina` scheme and run it. Lumina is an agent app, so it appears in
the menu bar rather than the Dock.

From the command line:

```sh
xcodegen generate
xcodebuild \
  -project Lumina.xcodeproj \
  -scheme Lumina \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The Xcode build embeds `Lumina.saver` in the app. Open Lumina Settings →
Screen Saver → Install Screen Saver, then select Lumina in System Settings.

To inspect the separate local-only target on macOS 15, select the
`LuminaNative` scheme. It builds `Hikari.app` with bundle ID
`com.hodadako.Lumina.NativeLocal`, uses
`~/Library/Application Support/LuminaNative`, supports `Control-Command-Q`
through the macOS-owned system lock path, and disables automatic updates. The
standard Lumina target retains its optional event-tap shortcut override. Native
Local has its own compile/test-only GitHub Actions workflow; it is never packaged
or uploaded as a release artifact.

For a local ad-hoc build without opening Xcode, run:

```sh
scripts/build-native-local.sh
```

The script installs the ad-hoc signed app as `/Applications/Hikari.app`, registers
it with Launch Services and Spotlight, and prints that path. You can then find
and launch `Hikari` from Spotlight. Import
the video first, then use Settings → Native Lock → Apply Selected Video. Apply
and Restore each request macOS administrator authorization. Native Lock system
writes are schema-gated to macOS 15; other major versions remain read-only until
their wallpaper format is reviewed.

For local apply/restore diagnostics, stream the transaction and one-shot tool
events in another Terminal window:

```sh
log stream --level info \
  --predicate 'subsystem == "com.hodadako.Lumina.NativeLocal"'
```

## Test

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
├── LuminaApp/          Menu bar UI, settings, wallpaper windows, system state
├── LuminaCore/         Models, stores, importer, policy, AVFoundation renderer
├── LuminaNativeLock/   Local transaction, backup, apply, and restore engine
├── LuminaNativeTool/   One-shot administrator-authorized system operation
└── LuminaScreenSaver/  Separate ScreenSaver.framework bundle
Tests/
├── LuminaCoreTests/
└── LuminaNativeLockTests/
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for lifecycle and storage details and
[PERFORMANCE.md](PERFORMANCE.md) for the performance test plan.

## Current limitations

- Video container and codec support follows the AVFoundation capabilities of the
  current macOS release; common MP4, MOV, and M4V files are accepted
- The same video is shown on every display using one independent player per
  display; per-display content is not supported
- No playlist, online gallery, or per-display content
- Portable distribution is ad-hoc signed and not Apple-notarized; Native Local
  is source-only and is never a downloadable binary artifact
- The PRD's long-duration performance gates require hands-on Instruments testing

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). By participating, you agree to follow
the [Code of Conduct](CODE_OF_CONDUCT.md). Security reports should follow
[SECURITY.md](SECURITY.md).

## License

Lumina is released under the [MIT License](LICENSE).
