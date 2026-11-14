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
borderless window and `AVPlayerLayer` surface per display, all fed by one shared
`AVPlayer`. Space recovery prepares a replacement layer inside the existing
window and swaps it only after the first frame is ready, so window geometry does
not change during the Space animation. It never installs a screen saver or
intercepts the system lock shortcut.

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

## Library metadata and conversion controls (unreleased)

Display titles remain in `LiveContent.title` in `contents.json`. Renaming saves
metadata without changing IDs, filenames, preparation cache identities, playback
or Native Lock journals. `HikariSettings` stores `favoriteContentIDs` and
`cancelledNativeLockPreparationIDs`, both defaulting to empty sets when absent in
older settings. Search/favorites-only filters are view state and do not reorder
or modify the underlying library. Menu content choices indicate favorites.

General shows preparation independently of the library filter. Each preparation
operation has an ID so delayed progress callbacks cannot revive finished or
cancelled UI. Progress is based on encoded presentation timestamps, capped below
completion until finalization/preview/cache publication, and throttled to at most
five deliveries per second. `VideoPreparationControl` propagates cancellation
through detached tasks and VideoToolbox callbacks. Both 26's Main10 writer and
27's temporal writer check cancellation during production/backpressure and final
writer waits. The owning preparation operation removes its private staging on
failure or cancellation and checks cancellation before publishing a cache.

Cancellation is separate from Native Lock Restore: it stops private preparation,
not an in-flight wallpaper transaction. Its persisted content ID suppresses both
preparation and auto-apply until explicit Retry. Retry waits for the old worker to
finish cleanup; deleting content cancels its worker. Settings and content writes
are performed before committing favorite/title changes to observable state.
The shared desktop player and transaction engine remain independent of these
controls. macOS 15 has no new conversion workflow.

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
is `restored`. From 0.5.4, the update flow permits downloading and validating a
replacement with a supported unfinished transaction, then restores it before
starting the replacement helper. Failed migration and unreadable or unsupported
transactions still block update preparation.

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

The runtime write policy selects a reviewed backend independently of manifest
validation. Restore and active maintenance require the recorded backend to
match the runtime. A journal without a backend is usable on macOS 15 for
legacy Restore. On macOS 27 the app reads saved journals for display in General
and blocks the update installer while a transaction is unfinished. The lookup
leaves the journal, marker and backups intact. From 0.5.3, macOS 27 uses the
separate userAerials27 backend for Apply, matching-journal Restore and maintenance.
Product enablement is independent of store/schema preflight and does not assert
that every Lock Screen presentation scenario is validated. Desktop video follows
its own playback policy.

### Restore during an app update (0.5.4+)

`AppModel` separates update preparation eligibility from the final replacement
guard. The confirmation dialog discloses automatic Restore, failure/cancellation
behavior, and macOS 15 administrator authorization. `AppUpdateInstaller` first
downloads the archive/checksum, checks SHA-256, extracts the app, verifies its
bundle identity/version/signature and destination writability, and prepares the
helper. Its required `beforeReplacingApp` callback then reloads the journal,
checks runtime/session/migration eligibility, calls the same throwing Restore
path as General, and rechecks that no unfinished transaction or read error
remains. It starts the helper only after the callback returns successfully.
Cancellation is checked before and after that callback.

`isApplyingUpdate` gates Native Lock Apply, auto-apply, Restore/discard buttons,
maintenance and renderer refresh for the entire download/restore/handoff period.
Pending auto-apply and maintenance tasks are cancelled before downloading; an
already running Native Lock operation blocks the update. On failure the app
stays open and resumes eligible maintenance without automatically applying a new
transaction. Journals/backups remain governed by the existing Restore engine;
the updater neither deletes nor rewrites them. A failure after successful Restore
may leave the old app running with the previous wallpaper restored. Selected
content/settings are retained. Normal selected-video auto-apply behavior on a
subsequent launch is unchanged.

The 0.5.1 candidate separates `userAerials27` from 26's shared catalog. Its
`NativeLockGoldenGateActivation` copies the bundled schema-2 catalog to a
transaction-specific user path and journals the original two catalog-selection
preferences and their digest before activation. The shared engine receives the
schema/locations explicitly. Maintenance checks preference ownership and the
owned asset before reconciliation; Restore preserves foreign selections.
New journals record their originating OS before shared writes. Explicit 26 → 27
recovery uses validated backups and a Linked-only merge into the current topology.
The first schema-1 trial failed actual playback despite stable Index choices;
later schema-2 Apply/Restore and file access were observed on one 27.2.1 Mac.
The user explicitly requested an enabled release, so 0.5.3 sets the product flag
`goldenGateNativeLockEnabled` true. Repeated-lock, reboot and physical display
validation remain incomplete. See [the evidence and enablement scope](docs/NATIVE_LOCK_MACOS27.md).

The macOS 27 private video derivative uses `AerialTemporalEncoder`: public
VideoToolbox hierarchical HEVC, compressed-sample MOV writing and bounded
`AerialTemporalSampleGroups` verification before cache publication. Its cache
identity differs from the unchanged 26 Main10 path. The desktop player never
uses this derivative. See [the black-screen investigation](docs/NATIVE_LOCK_BLACK_SCREEN.md).

`NativeLockMaintenanceSchedule` shares the latest unlock's monotonic two-second
deadline between periodic reconciliation and one-shot refresh. An immediate lock
callback cancels stale work; session state is checked again before process control.
A deferred session transition preserves the request without reporting corruption.

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

CI retains the macOS 15/26 ARM64 and Intel matrix. A separate ARM64
`xcode-27` job builds both architectures with the macOS 27 SDK, checks the
macOS 15.0 minimum on the app and helper, and runs the SwiftPM and Xcode tests
on macOS 27. The existing macOS 15/26 matrix exercises its own builds on the
older runtimes. The macOS 15 release job still produces the portable ZIP and
checksum, and the four matrix results retain their Codecov flags. The 27 job adds its own
`macos-27-arm64` release coverage flag and retains xcresult diagnostics. Only normal
`vX.Y.Z` tags package and publish releases after the required checks pass.
