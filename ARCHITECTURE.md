# Architecture

Lumina is split into a shared core, two app variants, a screen saver, and an
isolated Native Lock transaction module and one-shot privileged tool. Unit-test
targets mirror the shared core and Native Lock module.

## LuminaCore

The static core framework owns data and playback primitives shared by the app
and screen saver:

- `SharedContainer` resolves a caller-selected Application Support directory;
  the standard default is `~/Library/Application Support/Lumina`.
- `SettingsStore` and `ContentStore` write atomic, human-readable JSON.
- `VideoImporter` accepts movie containers recognized by macOS, verifies actual
  AVFoundation playback and a video track, calculates SHA-256 hashes to reject
  duplicates, preserves the source container extension, extracts metadata, and
  creates bounded thumbnails.
- `VideoRenderer` owns one queue player and looper and releases them explicitly.
- `PlaybackPolicy` combines independent pause reasons without losing user intent.
- `InterprocessSignal` coordinates the app and screen saver.

The framework is linked statically so an installed `Lumina.saver` does not
depend on a framework inside `Lumina.app`.

## Lumina app

`AppModel` is the main-actor composition root. It loads stores, owns the renderer,
observes system state, and reconciles state changes through `PlaybackPolicy`.

`WallpaperController` creates one non-interactive desktop-level window and one
player session per `NSScreen`. Display changes reconcile stable display IDs;
wake rebuilds the whole window set to replace stale WindowServer surfaces.

The menu bar and settings UI use SwiftUI system controls. The app has `LSUIElement`
enabled and does not appear in the Dock.

## Lumina Native Local app

The `LuminaNative` scheme compiles the shared app UI with the
`LUMINA_NATIVE_LOCAL` condition. It has a separate bundle ID
(`com.hodadako.Lumina.NativeLocal`), product name, and
`~/Library/Application Support/LuminaNative` storage. It does not embed the
screen saver or perform automatic updates. It supports `Control-Command-Q` via
the macOS-owned system lock path instead of installing a competing event tap;
the standard target retains its optional event-tap shortcut override.

`LuminaNativeLock` owns both sides of a native transaction. The user side stages
hashed MOV/JPEG files, snapshots the complete wallpaper `Index.plist`, writes a
phase journal, updates every existing display/Space choice, and can selectively
restore only Lumina-owned mappings if an external change occurred. Before each
user-store write, the app stops the current `WallpaperAgent`; after launchd
restarts it, the app polls the persisted mapping before reporting success.

`LuminaNativeTool` is embedded only in the Native Local app. Each apply or
restore is a one-shot `do shell script ... with administrator privileges`
operation with fixed arguments, not an installed daemon. It accepts only a
local user ID and transaction UUID, verifies ownership and hashes, pins writes
to the reviewed macOS 15 manifest schema, and maintains a root-only backup and
phase journal. Restore uses the exact original manifest when unchanged, or
removes only Lumina-owned entries when another process changed it meanwhile.

## Lumina screen saver

`LuminaScreenSaverView` is a separate ScreenSaver.framework bundle and process.
It reads settings and content as a consumer, creates its own player only while
animation is active, and releases the player, item, looper, and layer reference
when animation stops.

The saver posts distributed start/stop notifications. The app treats those as
independent pause reasons and revalidates policy after wake, unlock, and display
changes.

## Storage

```text
~/Library/Application Support/Lumina/
├── settings.json
├── contents.json
├── Media/<uuid>.<source-movie-extension>
└── Thumbnails/<uuid>.jpg
```

Native Local uses the same layout under a separate `LuminaNative/` root and adds:

```text
~/Library/Application Support/LuminaNative/
├── NativeLockTransactions/<transaction-uuid>/
│   ├── Index.original.plist
│   ├── request.json
│   ├── journal.json
│   ├── media.mov
│   └── preview.jpg
└── native-lock-active.json

/Library/Application Support/com.hodadako.LuminaNative/
├── active.json
└── Transactions/<transaction-uuid>/
    ├── entries.original.json
    └── system-journal.json
```

Imported media is copied into this directory so playback does not depend on
security-scoped access to the original file. Deletion only affects Lumina's
managed copy.

## State invariants

- User pause is never cleared by unlock or wake.
- Missing content never starts playback.
- Any active system pause reason stops playback.
- Display rebuilds replace, rather than append to, wallpaper windows.
- Stopping a renderer disables looping and removes all player items.
- Native Local system mutation remains disabled outside the explicitly reviewed
  macOS major-version and manifest-schema allowlist.
- A Native Lock transaction is not active until the system journal, user
  journal, and post-restart wallpaper mapping agree on one transaction/asset ID.
