# Architecture

Hikari is the only shipped app. The old Lumina screen-saver and event-tap
implementation is preserved under `Archive/LuminaLegacy` and is not part of
the Hikari Xcode target.

## Hikari app

The `Hikari` scheme builds the menu bar application, `LuminaCore`,
`LuminaNativeLock`, and the one-shot Native Lock tool. The app runs on macOS
15 or later and uses the existing Hikari bundle identity
`com.hodadako.Lumina.NativeLocal` so installed Hikari builds can update in
place.

Hikari owns desktop wallpaper windows only. `WallpaperController` creates one
borderless player per display and keeps those players synchronized across
display, Space, sleep, and lock transitions. It never installs a screen saver
or intercepts the system lock shortcut.

## Shared core

`LuminaCore` contains the video importer, content/settings stores, playback
policy, display topology, renderer, and custom icon handling. Internal type
names remain compatible with existing SwiftPM clients and stored data.

The canonical user container is:

```text
~/Library/Application Support/Lumina/
├── Media/
├── Thumbnails/
├── contents.json
├── settings.json
├── CustomAppIcon.png
└── CustomMenuBarIcon.png
```

## First-launch storage migration

`NativeStorageMigration` runs before Hikari loads its stores. It merges the
former:

```text
~/Library/Application Support/LuminaNative/
```

into the canonical root. Existing canonical content IDs and files win
conflicts; missing legacy records and referenced media/thumbnails are copied.
Conflicting files are copied under `MigratedLuminaNative/` and the merged
metadata points to that copy. Settings and custom icons are copied only when
the canonical file is absent.

Native Lock transaction directories and the active marker are copied before
the old root is moved to a recoverable `LuminaNative.archived` path. The
migration is idempotent and writes `hikari-storage-migration.json`. An active,
prepared, restoring, or recovery-required journal continues to be visible to
Hikari, so the app can offer Restore and blocks app updates until the journal
is `restored`.

If migration fails, the old directory is not removed or overwritten. Hikari
keeps updates blocked and shows the migration error so the user can recover
the original data first.

## Native Lock transaction

`LuminaNativeLock` owns the user-side transaction journal and both supported
backends:

- macOS 15 uses a root-owned idleassets catalog through the embedded one-shot
  `LuminaNativeTool`, after explicit administrator authorization.
- macOS 26 uses the current user's Aerial manifest and media store without a
  root catalog write.

The user store stages media, preview, request, journal, and the original
wallpaper index before system writes. The journal phases are:

```text
prepared → systemApplied → active → restoring → restored
                         └──────────────→ recoveryRequired
```

Restore verifies hashes and selectively preserves external wallpaper changes.
Hikari never runs a persistent privileged helper. Periodic maintenance is
user-level only and does not repeat root operations.

## Updates and releases

`ReleaseUpdateService` reads the latest normal `vX.Y.Z` GitHub release and
requires these exact assets:

```text
Hikari-macOS-portable.zip
Hikari-macOS-portable.zip.sha256
```

`AppUpdateInstaller` verifies the checksum, extracts `Hikari.app`, checks its
bundle identifier, display name, executable, version, and ad-hoc code
signature, then stages the replacement. Updates are disabled while Native
Lock or storage migration requires recovery.

CI runs Hikari tests on macOS 15/26 ARM64 and Intel runners. Release coverage
uploads each result to Codecov with a runner flag. Only normal `vX.Y.Z` tags
run the package and GitHub release jobs; there is no separate Hikari tag
channel.
