# Lumina

**Bring your desktop to life.**

Lumina is a native, open-source live wallpaper and screen saver for macOS. Import
one MP4, use it across every connected display, and reuse the same content in the
Lumina screen saver.

> Lumina 0.1 is an early MVP. It is ready for development and hands-on testing,
> but is not yet a signed or notarized release.

## What works

- MP4 validation, managed copying, metadata extraction, duplicate detection, and
  thumbnail generation
- Low-overhead looping playback with `AVQueuePlayer` and `AVPlayerLooper`
- Borderless wallpaper windows across all Spaces and connected displays
- Fill and Fit scaling
- Menu bar playback and content controls
- Native settings for mute, battery pause, launch at login, and library management
- Pause and recovery around sleep, screen lock, screen saver, and display changes
- A separate `.saver` bundle with preview and full-screen playback
- Shared atomic JSON storage in `~/Library/Application Support/Lumina`

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

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
└── LuminaScreenSaver/  Separate ScreenSaver.framework bundle
Tests/
└── LuminaCoreTests/
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for lifecycle and storage details and
[PERFORMANCE.md](PERFORMANCE.md) for the performance test plan.

## Current limitations

- MP4 only
- The same video is shown on every display
- No playlist, online gallery, or per-display content
- Distribution is not yet code-signed, notarized, or packaged as a release
- The PRD's long-duration performance gates require hands-on Instruments testing

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). By participating, you agree to follow
the [Code of Conduct](CODE_OF_CONDUCT.md). Security reports should follow
[SECURITY.md](SECURITY.md).

## License

Lumina is released under the [MIT License](LICENSE).
