# Performance

Low resource use is a product requirement, not a later optimization.

## Implementation guardrails

- MP4 files are streamed by AVFoundation and are never loaded fully into memory.
- Each connected display owns one queue player/looper. The MP4 URL is shared,
  not the decoder or player output. One stable display is the audio owner when
  mute is disabled.
- Thumbnails are capped at 640 × 360.
- Pausing stops player progression; shutdown removes all items and loopers.
- Notification-driven state handling avoids polling timers; a low-frequency
  five-second drift check only seeks sessions that exceed the configured
  tolerance.
- Native Lock playback is owned by the macOS Lock Screen transaction lifecycle.
- Display changes are diffed by CGDirectDisplayID. Unchanged windows and
  players are reused; removed displays release their window, player item, and
  looper immediately.

## Manual three-display QA

GitHub-hosted macOS runners do not expose a physical three-monitor topology.
Run this checklist on a 14-inch MacBook Pro with two QHD 27-inch monitors in
extended mode (three displays total). Record the macOS version, video codec,
resolution, and the existing wallpaper/screen-saver settings before starting.

1. Record each display's existing wallpaper settings.
2. Launch Hikari and confirm the same MP4 is visible and moving on all three
   displays.
3. Leave it playing for at least 10 minutes and check for visible drift.
4. Disconnect one external display, then reconnect it; verify exactly one
   Hikari surface returns for the display.
5. Change the main display from the built-in panel to an external display.
6. Move through Spaces on each display and verify the wallpaper remains at the
   desktop level without covering the menu bar, Dock, icons, or app windows.
7. Put the Mac to sleep, wake it, lock it, and unlock it. Confirm all three
   players recover only after WindowServer is ready.
8. Confirm a user pause remains paused after wake/unlock, while system pause
   reasons clear only when their corresponding state clears.
9. Confirm the menu bar is rendered by macOS and has normal length/scale on
   each external display.
10. Quit Hikari from the menu bar or Settings window and verify that the
    wallpaper state is unchanged.
11. Watch Activity Monitor or Instruments during the run; player/window count
    must never exceed display count and RSS/CPU must not grow continuously.

## Release measurements

Before tagging 0.1, record results for:

1. 1080p H.264 playback for 8 hours, target RSS ≤ 150 MB.
2. 4K playback for 1 hour, target RSS ≤ 250 MB.
3. Ten content replacements without sustained memory growth.
4. Twenty sleep/wake and lock/unlock cycles.
5. Twenty Native Lock apply/restore cycles where the supported macOS version
   permits the manual test.
6. Ten external-display attach/detach cycles.
7. A missing or corrupt selected media file.

Use Instruments Allocations, Leaks, Time Profiler, Energy Log, Core Animation,
and Activity Monitor. Record macOS version, hardware, codec, resolution, display
count, baseline RSS, final RSS, average CPU, and Energy Impact.

Changes to `VideoRenderer`, `WallpaperController`, or Native Lock playback should
include before/after measurements in their pull request. Normal Hikari launch,
playback, sleep/wake, and quit do not write Native Lock system state.
Legacy `DesktopPosters` files from pre-Hikari versions, if present, remain
ordinary files inside the migrated Application Support directory and are not read,
deleted, or passed to WindowServer.
