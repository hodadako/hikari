# Native Lock on macOS 27 — 0.5.1 candidate

## Evidence and release gate

This is a candidate implementation. Do not tag/release it as verified Native
Lock support until an explicitly authorized live Apply/Restore validation has
completed. `goldenGateRuntimeValidated` is false in production; fixtures inject
the candidate capability without changing the live policy. The installed app stayed on 0.5.0 through read-only development. A separately
authorized local validation build is described below. Fixture and
build results do not establish Lock Screen playback or WallpaperAgent lifecycle.

Apple's [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
do not publish an Aerial manifest/index write contract. They describe stricter
cross-team app data access; no TCC bypass is used. Observations below are from
this Mac, not an Apple compatibility guarantee or an external project's result.

## Read-only observations — 2026-11-13

Apple Silicon, macOS 27.2.1 (26B131), Xcode 26.6/SDK 26.5:

- The user store remains `~/Library/Application Support/com.apple.wallpaper/`.
  `aerials/manifest/entries.json` is schema 1, with 158 assets and 7 categories.
  Media and previews use `aerials/videos` and `aerials/thumbnails`.
- Manifest and `Store/Index.plist` are owned by the current user, mode 0644;
  media directories are 0755. Existing Hikari media are still present. These
  permissions alone do not establish access from a newly signed app.
- Index has `AllSpacesAndDisplays`, `Displays`, `Spaces`, `SystemDefault`.
  All 54 observed Linked containers have one `com.apple.wallpaper.choice.aerials`
  choice with binary plist `{assetID: UUID}` configuration. Placement is a
  binary plist with `values.placement.picker._0.id = FillScreen`.
- WallpaperAgent and WallpaperAerialsExtension are running from Apple's system
  bundles. Existence/process names do not prove restart behavior.
- The existing pre-upgrade active userAerials journal has no OS provenance
  field. Its manifest and index backup hashes validate. The original index
  has 30 Linked choices and passes the candidate's read-only compatibility
  checks. A selective restore plan can be computed without writing any file.
- The checked-in fixture retains representative observed nesting and binary
  fields, replacing personal identifiers, dates, URLs and asset labels.

## Candidate implementation

| Runtime | Backend | Transactions / recovery |
| --- | --- | --- |
| macOS 15 | Root-owned legacy catalog | Existing explicit administrator Apply/Restore; no new root operations |
| macOS 26 | User Aerial store | Existing automatic selection, bootstrap and restore retained |
| macOS 27 | User Aerial store with extra contract checks | Candidate Apply/replace/restore; requires initialized Linked layout; live validation pending |
| Other major versions | None | Preserve unfinished journals/backups; no Apply/Restore/maintenance |

27 shares the schema-1 transaction engine with 26, with an independent preflight
for provider, binary configuration, asset references, placement and topology.
It refuses uninitialized Linked layouts rather than assuming 26's automatic
topology materialization works on 27. The legacy root catalog stays 15-only.

New journals record `operatingSystemMajorVersion` before shared writes, including
interrupted preparation. Missing provenance in old userAerials journals means
26. A 27 app never silently adopts an older journal for automatic replacement,
reconciliation or renderer refresh. Explicit 26 → 27 Restore validates current
and original contracts and both backup hashes before journal/agent/index changes.
It always merges only owned Linked choices into the current topology and removes
only the transaction's Aerial records and hash-matching files. It never replays
the whole old index or manifest. An asset referenced outside Linked blocks this
upgrade restore. Unknown/legacy root backends remain preserved and blocked.

The original transaction directories and backups are retained after Restore.
Updates remain blocked until every unfinished transaction is resolved. Desktop
player, windows, settings, library, bundle identity and minimum deployment 15.0
are unchanged. Restoring on 26 after creating a 27 transaction is blocked.

Restore now checks both rollback inputs before moving the journal to restoring;
a corrupt manifest backup cannot first change the wallpaper index. Both manifest
and index restores recheck their input digest before committing a shared write.

## Reproducible validation

- `swift test --parallel` and Hikari `xcodebuild build/test` exercise temporary
  stores only. New 27 tests cover observed schema, apply/restore, replacement,
  journal reopen, Desktop/Idle preservation, external topology, old journal
  decoding, corrupt backups, malformed placement/provider/schema and failed media.
- `xcode-27` remains the verified GitHub label. It runs the 27 fixture suite
  explicitly, keeps xcresult diagnostics, and adds a `macos-27-arm64` release
  coverage flag. The four existing 15/26 coverage flags, Universal/minimum-OS
  checks, release packaging, checksum and updater asset names remain.
- Local read-only preflight recognizes 54 live and 30 original backup Linked
  choices and validates both backup hashes. No WallpaperAgent signals, sudo,
  system wallpaper writes or live Apply/Restore have been performed in this step.

## Explicitly authorized live validation still required

1. Quit Hikari, back up the app, Hikari support data and user wallpaper store;
   hash all originals. Close other wallpaper writers.
2. Use the candidate's normal Restore logic for the existing 26 journal,
   verifying selective preservation of the current topology and external records.
3. Apply the currently selected video, verify all Linked mappings for the existing
   30-second stabilization period, then test replacement and Restore.
4. Verify lock → unlock → next lock playback and renderer recovery manually;
   test reboot, failed/interrupted operations and external display/Spaces.
5. Record actual results and remaining limits here before enabling release.

Never simulate corrupt files in the real store. Failure injection belongs in
fixtures. Never overwrite or delete existing backup/transaction history. A failed
live step stops further trials and retains the recovery journal.

## Authorized live validation — 2026-11-13

The user explicitly approved this Mac's Apply/Restore trial. Before writes,
the installed 0.5.0, all 128 Hikari files and all 245 user-wallpaper-store files
were backed up and verified by SHA-256. No sudo/root operation was used.

- An ad-hoc signed Universal 0.5.1 (22) validation build was installed. Its
  first launch changed none of the 128 Hikari or three watched wallpaper files;
  the upgraded 26 journal stayed in recovery UI without automatic writes.
- The existing 26 journal's explicit selective Restore succeeded, retaining
  all 54 current Linked topology paths. Exactly its owned Aerial asset was
  removed; all other manifest assets and the original transaction backups
  remained. The old journal is restored and its active marker was removed.
- The currently selected video was applied as a new journal with OS 27
  provenance. All 54/54 Linked choices retained the new asset through the
  normal 30-second stabilization check. Media and preview digests matched.
  WallpaperAgent and WallpaperAerialsExtension were replaced successfully.
- Explicit Restore of this new 27 transaction succeeded. The manifest returned
  byte-for-byte to its original. The index differed only in 54 LastSet and 54
  LastUse timestamps; every other decoded value matched. Owned media/preview
  were removed and both original backups were retained.
- The selected video was applied again for manual Lock Screen playback checks,
  and the second 30-second stabilization passed. It remains active in the
  locally authorized validation build while manual checks are pending.
- Existing settings, library, icons, media, preparation cache and original
  backups retained their hashes. The root-owned idleassets catalog hash was
  unchanged. No other video was selected or imported during these trials.

Actual lock → unlock → next lock playback is awaiting the user's observation.
Reboot, physical display changes and replacement with a different video remain
manual validation items. Production release gating remains separate from the
authorized local validation build.
