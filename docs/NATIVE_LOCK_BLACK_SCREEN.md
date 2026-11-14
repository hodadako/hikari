# Native Lock persistent black screen — 2026-11-14

## Release status

At the user's explicit request, 0.5.3 enables the separate macOS 27 Native Lock
backend. This changes product availability, not the evidence below: the final
timing fix still needs manual repeated-lock, reboot and physical display checks.
0.5.2 was published with the feature disabled and its tag remains unchanged.

## Report and evidence

The user reports a Lock Screen that remains black until unlocking and locking
again. This is persistent failure, not a measured short first-frame delay.

Read-only inspection on macOS 27.2.1 (26B131), Apple Silicon, found:

- At 13:25:42 and 13:25:48 KST the Aerial player entered `beginRampingDown` and
  then logged `WallpaperExtensionKit.VideoSampleReadingErrors Code=4` and
  failure to acquire the next sample. Hikari refreshed the renderer after unlock.
- The active Hikari Main10 MOV had `sync` sample groups, but neither `tscl` nor
  `tsas`. Apple's bundled Golden Gate MOV had both descriptions (`sgpd`) and
  compact mappings (`csgm`). The Hikari file was selected and open in the actual
  extension, so a valid Index mapping did not establish a healthy sample reader.
- [AlexisBCD's primary experiment](https://github.com/AlexisBCD/macos-custom-video-wallpaper-fix)
  and [Vidwall Hub](https://github.com/jaywcjlove/vidwall-hub) report this error
  pattern with missing temporal information. Apple does not publicly document
  the wallpaper extension's private Code=4 contract. The local evidence is
  consistent with their interpretation; it is not an Apple support guarantee.

The [public VideoToolbox BaseLayerFrameRate property](https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_baselayerframerate)
requests hierarchical encoding from a supporting encoder. The local SDK header
confirms that purpose and macOS 10.13 availability. It does not document the
wallpaper extension's acceptance criteria.

## Implementation

Only the macOS 27 private Native Lock derivative changes:

1. Keep the existing AVAssetReader composition: full source duration, 1920×1080
   aspect-fit landscape canvas, source orientation applied once, no audio.
2. Use a hardware `VTCompressionSession`, Main10, the existing 12 Mbps/keyframe
   policy, no frame reordering, and a base-layer frame rate of half the source
   frame-rate hint. Use the public property, not a private temporal-layer key.
3. Pass compressed samples with their format descriptions to AVAssetWriter.
   Serialize callbacks, bound writer backpressure waits, propagate reader,
   encoder, frame-drop and writer failures, and drain all callbacks before finish.
4. Check actual MOV descriptions and mappings for both `tscl` and `tsas` before
   publishing the private cache. Metadata reads are bounded; media payloads are
   skipped rather than loaded. A failed preparation never publishes a ready cache.
5. Use a separate 27 cache version. An old Main10-only derivative cannot satisfy
   the new cache validation. The macOS 26 cache version and encoder stay unchanged.

No clip truncation/repetition, binary sample-group patch, private API, extra
playback decoder, permission change or root operation is introduced. Desktop
media and the shared AVPlayer remain unchanged. Existing manifest, index,
transaction backup/hash and Restore behavior remains in effect.

The two-second unlock refresh and its existing purpose are retained. Restarting
a reader may recover a later lock, but cannot supply missing movie metadata.
Timing changes are not used as a substitute for preparing a compatible movie.

## Validation

- Temporary 27 hardware encode: temporal descriptions/mappings present, same
  frame count accepted, duration within one frame, expected size, HEVC format,
  no audio, and a decoded image. Existing destination bytes are not overwritten.
- Parser fixtures reject missing mappings/descriptions, truncated boxes and
  group-like bytes in media payload. Cache-profile regression preserves 26's
  identity. The hardware acceptance test is explicitly skipped on 15/26; it
  must run on 27 and is not reported as old-runtime hardware verification.
- Initial local whole-app Xcode run: 150 tests passed. The final source includes
  one additional interrupted-bootstrap Restore regression; its final whole-suite
  result is recorded separately below.
- Final local `swift test --parallel`: 128 passed. Final whole-app Xcode run:
  151 passed, zero failures. The hardware encoding test executed on this Mac.
  A virtual 27 runner without hardware HEVC explicitly skips that test; other
  errors are failures, not skips.
- Signed Universal 0.5.1 (22) trial app/helper built with minimum deployment 15.0.
  Before the trial, the previous app, current Hikari data, user wallpaper store,
  Aerial preferences and failing logs were backed up. 406 data/store file hashes
  verified. No sudo/root operation.
- The previous schema-2 transaction's live Restore succeeded: both original
  catalog-selection keys became absent, original catalog digest matched, the
  active marker was removed and history remained.
- The same selected reze source was prepared with the new cache profile and
  applied through a new transaction. Independent MOV parsing found `sgpd tscl`,
  `sgpd tsas`, `csgm tscl`, `csgm tsas`; `lsof` confirmed the extension opened
  that new movie. The transaction remains active for manual repeated-lock checks.

Repeated-lock user confirmation, post-unlock sample-reader logs, reboot and
physical display/Spaces checks remain necessary. At this investigation stage the
production 27 gate stayed false; 0.5.2 was later published in that state. The
explicit 0.5.3 enablement decision above does not retroactively validate playback.

## Follow-up: rapid shortcut lock cycles still fail

The user reported intermittent black Lock Screens again after the temporal
movie was applied. Do not consider the encoding change a complete resolution.
Read-only logs from 14:01:09–14:01:38 KST show repeated real lock/unlock cycles:

- No `VideoSampleReadingErrors Code=4` in the captured post-apply interval.
  That is limited evidence, not proof of reliable playback.
- The last unlock notification was at 14:01:24.162; Hikari refreshed at
  14:01:24.814, only about 0.65 seconds later. Another refresh at 14:01:14.716
  preceded the next lock at 14:01:15.197. Recreated extensions logged invalid
  XPC connections and ML enhancement/download errors; these logs alone do not
  establish which error caused the black surface.
- Code allowed a timer from an earlier unlock to set a pending Boolean while
  locked. The periodic five-second pass could consume it after a subsequent
  unlock, bypassing that unlock's two-second timer. Lock notifications did not
  cancel the timer or clear the pending request.

The scheduler now stores a monotonic deadline for the most recent unlock.
Both the timer and periodic maintenance consult that deadline, including mapping
reconciliation. An immediate lock callback cancels old work. Stopping maintenance
also cancels its refresh task. Immediately before process control the controller
rechecks both the scheduler and a fresh session-lock snapshot; a changed session
is an expected deferral and does not mark the transaction damaged. A missing
session key retains notification state rather than asserting unlock.

Fixture tests cover rapid relock, pending-request/retry delay bypass, one-shot
consumption and stop cancellation. Monitor tests use an isolated notification
center (never real lock notifications) and injected session snapshots. They cover
lock cancellation before playback debounce, a lock preceding notification delivery,
missing session values and sleep. This reduces an observed timing hazard; macOS
provides no atomic lock-and-process-control operation, and repeated manual lock
checks are still required. The media, catalog selection and existing transaction
backups are unchanged by this scheduling correction.

Follow-up validation: `swift test --parallel` passed all 132 tests. The initial
sandboxed Xcode attempt could not contact testmanagerd (sandbox restriction), so
no test success is attributed to that attempt. The subsequent normal-permission
`xcodebuild ... CODE_SIGNING_ALLOWED=NO test` passed all 159 tests, zero failures
and zero skips, on macOS 27.2.1 using local Xcode 26.6 / SDK 26.5. The isolated
rapid-lock notification test executed. These results do not prove Lock Screen
presentation or Xcode 27 SDK behavior. The earlier encoder commit's full CI
passed on macOS 15/26 ARM64 and Intel plus `xcode-27`; it does not cover this
new scheduling change until a new CI run finishes.
