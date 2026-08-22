# Building Hikari Native Local on Another Mac

Hikari Native Local is an experimental source build and can also be published as
a separate ad-hoc release asset. It is not part of the Lumina portable download
and it does not receive in-app updates. Until the first Hikari tag is released,
build it on the Mac where it will run when possible; a copied ad-hoc build may
trigger Gatekeeper warnings. Hikari
uses the macOS-owned lock shortcut and does not enable Lumina's optional global
event-tap shortcut, so this Native Local path does not require Accessibility or
Input Monitoring permission.

Native Lock modifies undocumented macOS-managed video-selection data. macOS 15
requires explicit administrator authorization; macOS 26 uses the current user's
Aerial store without administrator authorization. Back up the Mac first, keep the Restore
action available, and do not run another program that edits the same macOS
video-selection store at the same time. If the known Backdrop wallpaper
renderer is running, Hikari stops that renderer during Native Lock apply; its
manifest and media records are preserved.

## Supported systems

- The Hikari app requires macOS 15 or macOS 26 for Native Lock work. Its macOS
  15 and macOS 26 storage paths differ; other major versions are intentionally
  blocked from Native Lock writes until their format is reviewed.
- **macOS 15** uses the privileged legacy system catalog at
  `/Library/Application Support/com.apple.idleassetsd/Customer/entries.json`.
  Each Apply and Restore requires administrator authorization via a one-shot
  helper tool (`lumina-native-tool`).
- **macOS 26** uses the current user's Aerial catalog at
  `~/Library/Application Support/com.apple.wallpaper/aerials/`. No
  administrator authorization is required, but Apple's Aerial catalog must
  have been initialized first (see Prerequisites below).
- Native Lock never fabricates Apple's manifest. It uses Apple's existing
  initialized manifest as the baseline for transactional modification and
  rollback.
- The direct build script needs a Swift toolchain with the macOS 15 SDK or
  newer. A full Xcode installation is required for Xcode builds and tests.
- Hikari is built from source and can be published through separate ad-hoc
  release assets. Until a Hikari tag is released, the normal Lumina portable
  release is a separate app and does not include Native Lock.

## Prerequisites for macOS 26 Native Lock

On macOS 26, Native Lock writes to Apple's per-user Aerial catalog. This
catalog is created by macOS only after the user downloads or selects an Apple
Aerial wallpaper. If the catalog has never been initialized, Hikari reports:

> Initialize Apple Aerial wallpapers first

To initialize the catalog:

1. Open **System Settings → Wallpaper**.
2. Select any **Aerial** wallpaper and wait for it to download.
3. Return to Hikari's **Lock Screen** tab. The safety status should now show
   **Ready to apply locally**.

Do not attempt to create or edit the Aerial catalog manually. Hikari requires
Apple's existing initialized manifest as the baseline for its transaction.

Hikari targets only an Apple-materialized Lock Screen `Linked` choice and never
uses your `Desktop` or `Idle` value as a fallback. On first launch with a
selected video, Hikari can automatically initialize the same `Linked` topology
using an already-downloaded local Apple Aerial asset, snapshot the original
`Index.plist`, and apply the selected Hikari video in one transaction. If the
Apple manifest has no usable local Aerial asset or the current Space/display
topology cannot be read, Hikari stops before writing the manifest and explains
the missing prerequisite. Restore remains available for the whole transaction.

If Backdrop was used previously, its `BackdropWallpaper` helper may still be
running and can write the old Aerial choice back immediately after Hikari's
write. Hikari terminates only that helper before applying; it does not remove
Backdrop's catalog entries or media. Other wallpaper tools must still be
closed while the transaction runs.

After rebuilding Hikari from source, always relaunch the app before applying
or restoring a Native Lock transaction. The build script terminates any running
Hikari process before installing the new bundle so the old executable cannot
read files from the newly replaced bundle.

## 1. Prepare the Mac

Install full Xcode 16 or later, launch it once, and accept its license. If the
active developer directory still points at Command Line Tools, select Xcode:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license
xcodebuild -version
```

`sudo xcodebuild -license` is interactive: read and accept the license in the
Terminal prompt. Do not use this command on a managed Mac without permission.

Install Git. Homebrew and XcodeGen are optional for the direct build script,
but XcodeGen is required when generating the Xcode project:

```sh
brew install xcodegen
```

## 2. Get the source

```sh
git clone https://github.com/hodadako/lumina.git
cd lumina
git status --short
```

Review the source and the documents in `docs/` before enabling Native Lock.
An empty `git status --short` confirms that the checkout has no local changes.

## 3. Build and install Hikari

The direct script builds, ad-hoc signs, verifies, installs, and registers
Hikari with Launch Services and Spotlight:

```sh
scripts/build-native-local.sh
codesign --verify --deep --strict /Applications/Hikari.app
open -a Hikari
```

The default destination is `/Applications/Hikari.app`. If the current user
cannot write to `/Applications`, install to that user's Applications folder
instead:

```sh
mkdir -p "$HOME/Applications"
LUMINA_NATIVE_INSTALL_DIRECTORY="$HOME/Applications" \
  scripts/build-native-local.sh
open "$HOME/Applications/Hikari.app"
```

The app is an agent app, so it appears in the menu bar rather than the Dock.
After the script completes, Spotlight should find `Hikari`; the direct `open`
command above also works while Spotlight finishes indexing.

### Hikari ad-hoc release assets

Pushing a `hikari-vX.Y.Z` tag runs the Hikari Release workflow. After macOS 15
and macOS 26 compile/test gates pass, it publishes
`Hikari-macOS-native-vX.Y.Z.zip` and its SHA-256 checksum in a separate GitHub
Release. The asset keeps the current ad-hoc, unnotarized signing structure and
is separate from the normal Lumina release. Verify the checksum and
`codesign --verify --deep --strict` before opening it. Hikari has no in-app
updater and does not include Lumina's optional global event-tap shortcut.

## 4. Optional Xcode build and test

Use this path when changing code or validating the local toolchain. It builds
and tests but does not activate Native Lock or modify macOS settings.

```sh
xcodegen generate
xcodebuild \
  -project Lumina.xcodeproj \
  -scheme LuminaNative \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project Lumina.xcodeproj \
  -scheme LuminaNative \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 5. Use Native Lock cautiously

1. Launch Hikari and import a video in **General**.
2. Open **Lock Screen** and apply the selected video only after reading the
   safety status.
3. macOS 15 asks for administrator authorization for each Apply and Restore.
   macOS 26 user Aerial transactions use the current user's store without an
   administrator prompt.
4. Test lock → unlock → next lock before relying on it.
5. Use **Restore** before a macOS major upgrade, before deleting Hikari, or
   whenever an experiment is finished.

Keep Hikari running while a Native Lock transaction is active so it can monitor
the user-level mapping and recover it when needed. Do not attempt to edit its
transaction files manually.

## Troubleshooting

| Symptom | Safe action |
| --- | --- |
| `xcodebuild` says the license is not accepted | Run `sudo xcodebuild -license` and complete the interactive prompt. |
| Tools resolve to `/Library/Developer/CommandLineTools` | Select full Xcode with `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`. |
| The install step cannot write to `/Applications` | Use `LUMINA_NATIVE_INSTALL_DIRECTORY="$HOME/Applications"` as shown above. |
| Spotlight does not show Hikari yet | Run `open /Applications/Hikari.app`, or use the matching `$HOME/Applications` path, then allow indexing to finish. |
| Hikari reports Native Lock writes are unavailable | Confirm the Mac is on macOS 15 or 26. Do not bypass the operating-system safety gate. |
| Hikari reports "Initialize Apple Aerial wallpapers first" (macOS 26) | Open System Settings → Wallpaper, select an Apple Aerial wallpaper, wait for it to download, then return to Hikari. |
| Hikari reports "Aerial wallpaper store is not recognized" (macOS 26) | The Aerial manifest exists but has an unexpected schema. Do not modify it manually; file a bug with the transaction details. |
| macOS 26 shows `Clear Failed Preparation` | An older build was rejected before it wrote any system or user mapping. This button clears only that exact hash-free failure; then apply the selected video again from Lock Screen. |
| A legacy transaction cannot be restored on macOS 26 | If it has an applied system or user mapping, run Hikari on macOS 15 to Restore it. Do not delete the journal or wallpaper files manually. |
| After rebuilding, Hikari still behaves like the old version | The build script now terminates the old Hikari before installing. If the issue persists, quit Hikari manually and rerun the build script. |
| An Apply or lock-screen test looks wrong | Stop testing, use Restore, and preserve the transaction/error details before trying another change. |

For diagnostics during Apply or Restore, use:

```sh
log stream --level info \
  --predicate 'subsystem == "com.hodadako.Lumina.NativeLocal"'
```
