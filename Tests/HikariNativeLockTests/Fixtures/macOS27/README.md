# macOS 27 user Aerial fixture

Derived read-only on 2026-11-13 from macOS 27.2.1 (26B131), Apple Silicon.
The index retains the observed SystemDefault, one display and two Spaces,
including nested binary Configuration and EncodedOptionValues plists. UUIDs,
asset labels, URLs and dates are replaced; no user media or original identifiers
are included. entries.json is a minimal schema-1 catalog with the observed
asset/category field types, linked to a synthetic Apple asset.

The observed user cache is stale: the actual 27 extension fallback is schema 2.
`bundled-schema2.json` separately models the bundled catalog's version and
ordinary/group/variant/videoGravity records, with synthetic identifiers and URLs.
Neither fixture alone identifies which catalog the live renderer selects.

These files establish parser/transaction coverage. They do not establish
WallpaperAgent restart, Lock Screen playback, reboot or TCC behavior.
Tests copy them to a unique temporary directory before performing any write.
