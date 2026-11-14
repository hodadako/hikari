# Native Lock persistent black screen — 2026-11-14

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
physical display/Spaces checks remain necessary. Production's 27 gate stays
false; no tag or GitHub Release is created from this investigation.
