# Architecture

Lumina is split into three native macOS targets.

## LuminaCore

The static core framework owns data and playback primitives shared by the app
and screen saver:

- `SharedContainer` resolves `~/Library/Application Support/Lumina`.
- `SettingsStore` and `ContentStore` write atomic, human-readable JSON.
- `VideoImporter` validates MP4 assets, calculates SHA-256 hashes to reject
  duplicates, copies media, extracts metadata, and creates bounded thumbnails.
- `VideoRenderer` owns one queue player and looper and releases them explicitly.
- `PlaybackPolicy` combines independent pause reasons without losing user intent.
- `InterprocessSignal` coordinates the app and screen saver.

The framework is linked statically so an installed `Lumina.saver` does not
depend on a framework inside `Lumina.app`.

## Lumina app

`AppModel` is the main-actor composition root. It loads stores, owns the renderer,
observes system state, and reconciles state changes through `PlaybackPolicy`.

`WallpaperController` creates one non-interactive desktop-level window per
`NSScreen`. All windows use the shared player. Display changes rebuild the whole
window set, preventing stale windows from accumulating.

The menu bar and settings UI use SwiftUI system controls. The app has `LSUIElement`
enabled and does not appear in the Dock.

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
├── Media/<uuid>.mp4
└── Thumbnails/<uuid>.jpg
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
