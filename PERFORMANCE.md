# Performance

Low resource use is a product requirement, not a later optimization.

## Implementation guardrails

- MP4 files are streamed by AVFoundation and are never loaded fully into memory.
- One queue player is shared by wallpaper surfaces.
- Thumbnails are capped at 640 × 360.
- Pausing stops player progression; shutdown removes all items and loopers.
- Notification-driven state handling avoids polling timers.
- Screen saver playback exists only for the screen saver lifecycle.
- Rebuilding displays first closes and detaches every old window.

## Release measurements

Before tagging 0.1, record results for:

1. 1080p H.264 playback for 8 hours, target RSS ≤ 150 MB.
2. 4K playback for 1 hour, target RSS ≤ 250 MB.
3. Ten content replacements without sustained memory growth.
4. Twenty sleep/wake and lock/unlock cycles.
5. Twenty screen saver start/stop cycles.
6. Ten external-display attach/detach cycles.
7. A missing or corrupt selected media file.

Use Instruments Allocations, Leaks, Time Profiler, Energy Log, Core Animation,
and Activity Monitor. Record macOS version, hardware, codec, resolution, display
count, baseline RSS, final RSS, average CPU, and Energy Impact.

Changes to `VideoRenderer`, `WallpaperController`, or screen saver playback should
include before/after measurements in their pull request.
