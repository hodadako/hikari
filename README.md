# Hikari

A macOS menu bar app that turns your videos into live wallpapers for your desktop and Lock Screen.

**[Download Hikari for macOS](https://github.com/hodadako/hikari/releases/latest)** · [한국어](README.ko.md)

## Install and play

1. Download `Hikari-macOS-portable.zip` from the latest release and unzip it.
2. Move `Hikari.app` to Applications and open it.
3. Open Hikari from the menu bar and choose **Change Content → Import Video…**. On macOS 26 and 27, choosing a video can also update the Lock Screen.

Release builds are ad-hoc signed and have no Apple notarization. If macOS shows a first-launch warning, see [Apple’s guide to opening downloaded apps](https://support.apple.com/en-us/102445).

<details>
<summary>Check the download or install with an AI assistant</summary>

To check the download, save the ZIP and its `.sha256` file in the same folder. From that folder, run:

```sh
shasum -a 256 -c Hikari-macOS-portable.zip.sha256
```

To use an AI assistant, copy this prompt:

```text
Install Hikari from its latest GitHub release on this Mac. Ask me before selecting a video. On macOS 26 or 27, explain that selecting a video can also apply it to the macOS Lock Screen, and get my approval before proceeding.
```

</details>

## What you can do

- Loop one video across your displays and Spaces.
- Pause or switch videos from the menu bar. In Settings, choose **Fill** or **Fit**, mute playback, or pause while on battery.
- Find videos with search and favorites, edit their display names, and customize the app and menu bar icons.

## macOS support

| macOS | Macs | Native Lock Screen |
| --- | --- | --- |
| 15 Sequoia | Apple Silicon and Intel | Apply or restore the wallpaper in **Settings → General**. macOS asks for administrator approval. |
| 26 Tahoe | Apple Silicon and Intel | Selecting a video can update the Lock Screen automatically. New conversions require a compatible hardware HEVC encoder. |
| 27 Golden Gate | Apple Silicon | Selecting a video can update the Lock Screen automatically after Hikari checks the wallpaper store. New conversions require a compatible hardware HEVC encoder. |

Native Lock changes macOS-managed wallpaper settings. Back up your Mac before using it and select **Restore Previous Wallpaper** before a major macOS upgrade. On macOS 15, other accounts on the Mac may be able to read the Lock Screen copy while it is active.

Repeated-lock behavior still needs more testing on physical Macs. [Native Lock investigation](docs/NATIVE_LOCK_BLACK_SCREEN.md)

## Development

<details>
<summary>Build and test from source</summary>

Install Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Generate the project, then build or test the **Hikari** scheme in Xcode:

```sh
xcodegen generate
open Hikari.xcodeproj
```

Run `swift test` for the package tests.

</details>

[Release notes](https://github.com/hodadako/hikari/releases) · [Architecture](ARCHITECTURE.md) · [Verification history](docs/VERSION_ISSUES.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [MIT License](LICENSE)
