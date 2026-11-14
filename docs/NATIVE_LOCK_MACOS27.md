# Native Lock on macOS 27 — 0.5.3 enablement and investigation

## Evidence and release gate

The first authorized live trial **failed actual Lock Screen playback**: the user
still saw Apple's default video. Its Index mapping remained correct for 30 seconds,
but that did not prove the renderer accepted the custom asset. The failed
transaction was explicitly restored; its journal, backups and logs were retained.
That initial failure predates the later schema-2 activation and temporal encoder
changes documented below. 0.5.2 shipped with the 27 feature disabled. The user
then explicitly requested an enabled release: 0.5.3 sets
`goldenGateNativeLockEnabled` true for the separate `userAerials27` backend.
The product flag is deliberately named for enablement, not runtime validation.
Apply/Restore and renderer file access were observed on one 27.2.1 Mac. The last
manual report still showed intermittent black presentation; repeated-lock results
after the final timing fix, reboot and physical display checks remain incomplete.
Neither CI nor enablement is a claim that these scenarios passed. Schema/index,
backup/hash, ownership and journal-origin checks still reject unsafe operations.

Apple's [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
do not publish an Aerial manifest/index write contract. Their cross-team app data
access changes do not justify bypassing TCC. The observations below are from one
Mac, not an Apple compatibility guarantee.

## Observations on 2026-11-13

Apple Silicon, macOS 27.2.1 (26B131), local Xcode 26.6/SDK 26.5:

- The current user's `com.apple.wallpaper/aerials/manifest/entries.json` was
  **schema 1**, with 158 assets and 7 categories. Its download metadata dated
  back to macOS 26. Reading this cache did not identify the active catalog.
- The system extension's bundled `Contents/Resources/entries.json` was
  **schema 2**, with 164 assets and 6 categories. Most asset fields remain the
  same; some records also have `group`, or `variant` and `videoGravity`.
- During the failed trial, WallpaperAerialsExtension logged
  `Loading fallback manifest (AerialManifestLocalPathOverride: none)` and
  `ConfigDataPreference: false`. `lsof` showed it opening
  `/System/Library/Wallpapers/.default/Golden Gate.mov`, not Hikari's video.
  Renderer/snapshot creation errors were also present. These facts establish
  an inactive catalog mismatch; they do not prove why Apple chose fallback.
- `AerialManifestLocalPathOverride` and `AerialManifestForceLocal` were absent
  from the user's `com.apple.wallpaper.aerial` preferences. Existing scheduler
  and resource-update preferences were preserved.
- All 54 observed Linked containers had `Type = linked`, one Aerial provider,
  a binary `{assetID: UUID}` configuration and binary placement options.
  Changing all those choices alone was insufficient for actual playback.
- Media/previews remain in `aerials/videos` and `aerials/thumbnails`. File
  ownership/permissions do not by themselves prove renderer access or TCC state.

## External project observations

The primary-source [pdfux Golden Gate experiment](https://gist.github.com/pdfux/5659724021e584313c00b843312e909d)
reports selecting a copied schema-2 catalog with the two Aerial preferences
above on 27.0/27.2 beta. Hikari does not execute that script or blindly delete
preferences on undo: it journals their original values and selectively restores
only its own selection.

[Vidwall Hub](https://github.com/jaywcjlove/vidwall-hub) reports HEVC temporal
scalability requirements for repeated Lock Screen playback on 27. This remains
an external observation, not a verified Hikari codec requirement. Do not shorten
user videos or add a new encoder solely on that report. Actual custom-file
selection, playback and the next lock must each be checked separately.

## Candidate implementation

| Runtime | Backend | Status |
| --- | --- | --- |
| macOS 15 | Root-owned idleassets catalog | Existing administrator Apply/Restore unchanged; no root trial performed |
| macOS 26 | Shared user schema-1 Aerial catalog (`userAerials`) | Existing bootstrap, selection and recovery retained |
| macOS 27 | Separate user schema-2 catalog (`userAerials27`) | New candidate; production writes remain gated |
| Other major versions | None | Preserve journals/backups; no Apply/Restore/maintenance |

`NativeLockGoldenGateActivation` copies the recognized bundled schema-2 catalog
to `aerials/Hikari/<transaction UUID>/entries.json`, preserving Apple's records.
It does not change Apple's bundle or the stale shared schema-1 cache. The common
transaction engine receives its schema and locations explicitly. An initialized,
recognized Linked layout is required on 27; 26's layout bootstrap is not assumed.
A prior third-party asset can exist only in the schema-1 cache. Apply may recognize
its UUID from that parsed cache as the previous selection, without importing its
records into schema 2. Unknown references and malformed cache still block Apply.
Maintenance must find Hikari's owned asset in the actual selected schema-2 catalog.

Before preference changes, the transaction saves a private, durable original
preference record and journals its SHA-256. It includes transaction/asset/path
identity and the original catalog digest. Only `AerialManifestLocalPathOverride`
and `AerialManifestForceLocal` can be written. Existing third-party overrides
block Apply. Catalog, media, preview and index still use original backups, hashes,
atomic commits and recovery-required on failure. A crash between catalog commit
and systemApplied can recover using the prepared activation digest. Preference
selection is restored only while it still names this transaction's catalog;
foreign selections and changed values are preserved. Catalog audit copies and
transaction history remain after Restore.

New journals record OS provenance. Automatic maintenance on 27 requires both
`userAerials27` and OS 27, the owned asset's presence, and the selected catalog
preferences. It marks recovery-required before reconciliation if those checks
fail. A valid Apple selection cannot disguise a missing Hikari asset.

Explicit 26 → 27 Restore uses schema 1 and a selective Linked-only merge into
the current topology. The earlier failed schema-1/OS-27 trial is also restore-only.
It never adopts either for automatic maintenance or replays the old whole index.
Restore validates both original backup digests and readable current structures
before journal/agent/index changes. Foreign photo providers or removal of Linked
choices do not block cleanup of Hikari's own catalog/media. Owned assets now used
outside Linked block cross-version cleanup. Both shared-file restores recheck
input digests. A no-op index restore retains the foreign selection's exact bytes.

Original backup/history, minimum deployment 15.0, bundle identity, settings,
library, desktop windows/shared AVPlayer and updater assets are preserved. A 27
transaction cannot be restored by a 26 runtime. Unfinished transactions block
in-app updates.

## Tests and CI

- `swift test --parallel`: 123 tests passed after the schema-2 changes.
- Local `xcodebuild ... test`: 146 tests passed on 27.2.1, built with SDK 26.5.
  The separate Universal Release build checks app/helper compilation.
- Temporary fixtures cover both the stale schema-1 cache and a sanitized
  schema-2 bundled catalog. Fake preferences cover unsupported OS/schema,
  foreign overrides, original nil/false/true values, external preference changes,
  tampered backups, sync failure, interrupted catalog commit and cleanup after
  switching to a photo/no-Linked selection. No fixture test writes the real store.
- The verified `xcode-27` CI label runs both Golden Gate suites and Xcode tests;
  xcresult and the new release coverage flag remain. The existing 15/26 ARM64
  and Intel jobs, Universal/minimum-OS checks, packaging, checksum and Codecov
  flags remain. New source changes require fresh CI results.

## Authorized live trials

The user explicitly approved Apply/Restore on this Mac, without sudo/root.
Before the first trial, the installed 0.5.0, all 128 Hikari files and 245 user
wallpaper files were backed up and SHA-256 verified.

1. A locally enabled, signed Universal 0.5.1 (22) trial preserved the old 26
   journal on launch. Its explicit selective Restore succeeded, keeping all 54
   current topology paths and foreign assets/backups.
2. Schema-1 Apply → 30-second mapping check → Restore succeeded at file level.
   Manifest bytes were restored; only Index LastSet/LastUse timestamps differed.
   A second Apply also passed mapping checks. **The user's actual Lock Screen
   check then failed: the default video remained.** This supersedes the earlier
   pending-playback record; it is not a successful Native Lock validation.
3. Failure evidence was copied before explicit Restore of the final trial
   transaction. The installed app returned to a gated 0.5.1 build with desktop
   playback available. The root catalog and original backups were not changed.
4. Before the schema-2 retry, a fresh copy of the current app, Hikari data,
   wallpaper store and full Aerial preference snapshot was made. 388 data/store
   files were hash-verified; both catalog-selection preference keys were absent.
   The initial schema-2 preflight rejected a prior third-party video absent from
   the bundled catalog. It wrote no shared catalog preferences or Index; its
   prepared transaction was explicitly restored. Recognition of the old selection
   is now separate from the new target catalog and covered by a regression test.
   The retry's renderer/file and manual playback results must be recorded
   separately before enabling production support.
5. The revised locally enabled Universal build applied the selected video and
   passed 30-second stabilization with 54/54 Linked choices. The extension logged
   the transaction's override path and `AerialManifestForceLocal` selection;
   `lsof` showed the Hikari movie open, replacing the previous default-movie
   observation. All 164 bundled Apple assets remained unchanged in schema 2;
   the activation backup digest verified; shared schema-1 and root catalogs
   retained their hashes. The transaction remains active for the user's manual
   lock → unlock → next lock check. This is file-selection evidence, not yet
   confirmed moving playback. Renderer logs still contain XPC/view-model,
   ML-enhancement and local re-download errors; their user-visible effect is
   not established and they must not be described as a clean renderer log.

On 2026-11-14 the user reported intermittent persistent black screens. Actual
logs and MOV comparison identified missing temporal information as the primary
candidate; [the encoder follow-up](NATIVE_LOCK_BLACK_SCREEN.md) records evidence,
implementation and live trial limits. The earlier schema-2 transaction's live
Restore, including both catalog preferences, has now passed.

Remaining release checks: actual selected-file decoding, lock → unlock → next
lock, Restore of catalog preferences, replacement, reboot, external displays and
Spaces. File-open evidence alone is not proof of moving Lock Screen playback.
Never inject failures into the real store or discard old recovery history.
