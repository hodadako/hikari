# Architecture

Hikari is the only shipped app. The pre-Hikari screen-saver and event-tap
implementation is preserved under `Archive/HikariLegacy` and is not part of
the Hikari Xcode target.

## Hikari app

The `Hikari` scheme builds the menu bar application, `HikariCore`,
`HikariNativeLock`, and the one-shot Native Lock tool. The app runs on macOS
15 or later and uses the Hikari bundle identity
`com.hodadako.Hikari.NativeLocal`.

Hikari owns desktop wallpaper windows only. `WallpaperController` creates one
borderless player per display and keeps those players synchronized across
display, Space, sleep, and lock transitions. It never installs a screen saver
or intercepts the system lock shortcut.

## Shared core

`HikariCore` contains the video importer, content/settings stores, playback
policy, display topology, renderer, and custom icon handling. Internal type
names use Hikari consistently; the stored JSON schema remains backward
readable.

The canonical user container is:

```text
~/Library/Application Support/Hikari/
├── Media/
├── Thumbnails/
├── contents.json
├── settings.json
├── CustomAppIcon.png
└── CustomMenuBarIcon.png
```

## First-launch storage migration

`NativeStorageMigration` runs before Hikari loads its stores. It discovers
the pre-Hikari general and Native Local support roots through a runtime-only
compatibility table and merges every existing source into the canonical root
in priority order. Existing canonical content IDs and files win conflicts; missing records
and referenced media/thumbnails are copied. Conflicting files are copied under
`MigratedPredecessor/` and the merged metadata points to that copy. Settings
and custom icons are copied only when the canonical file is absent.

Native Lock transaction directories and the active marker are copied before
the source root is moved to a recoverable `.archived` sibling. The
migration is idempotent and writes `hikari-storage-migration.json`. An active,
prepared, restoring, or recovery-required journal continues to be visible to
Hikari, so the app can offer Restore and blocks app updates until the journal
is `restored`.

If migration fails, the source directory is not removed or overwritten. Hikari
keeps updates blocked and shows the migration error so the user can recover
the original data first.

## Native Lock transaction

`HikariNativeLock` owns the user-side transaction journal and both supported
backends:

- macOS 15 uses a root-owned idleassets catalog through the embedded one-shot
  `HikariNativeTool`, after explicit administrator authorization.
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
