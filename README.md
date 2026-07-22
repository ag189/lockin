# Lockin

A macOS menu bar timer for project- and task-based time tracking. It runs alongside
[ActivityWatch](https://activitywatch.net) and supplies the *declared* half of the record — what
you say you're working on — logging each session locally and syncing completed sessions to
ActivityWatch as their own Timeline lane.

- Menu bar only (`LSUIElement`), no dock icon, no main window.
- Local SQLite is the source of truth; ActivityWatch sync is best-effort and asynchronous.
- No network access except `localhost:5600`. No accounts, no telemetry, no cloud.
- Requires no system permissions.

## Requirements

- macOS 14+
- To build: Swift 5.9+ toolchain (Command Line Tools are enough for an arm64 build and to run).
- Full **Xcode** is required only to produce a universal (arm64 + x86_64) binary and to run the
  XCTest suite (`swift test`) — both depend on components (`xcbuild`, `XCTest`) that ship only with
  Xcode, not the standalone Command Line Tools.

## Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite (via SPM).
- Global hotkeys and the shortcut recorder are implemented in-house against Carbon
  (`Sources/Lockin/Support/Shortcuts.swift`). The original spec named `KeyboardShortcuts`, but its
  current releases use the SwiftUI `#Preview` macro, whose compiler plugin ships only with full
  Xcode and cannot build under the Command Line Tools toolchain. The in-house module keeps the app
  buildable everywhere and reduces the external dependency count to one.

## Build and run

```bash
# Debug build + run (menu bar app)
swift build
./.build/debug/Lockin

# Verify core logic + live ActivityWatch sync (no Xcode/XCTest needed)
./.build/debug/Lockin --selftest

# Full XCTest suite (requires Xcode)
swift test
```

## Package a distributable app

```bash
# Build Lockin.app (ad-hoc signed, runs locally). Native arch under CLT; universal under Xcode.
scripts/build_app.sh

# For distribution: sign with your Developer ID, then package + notarize (needs your Apple creds)
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build_app.sh
scripts/package_dmg.sh
xcrun notarytool submit build/Lockin.dmg --keychain-profile "lockin" --wait
xcrun stapler staple build/Lockin.dmg
```

Notarization and the universal binary cannot be produced unattended here:
- **Universal binary** needs full Xcode (`xcbuild`). Under Command Line Tools the build is arm64-only.
- **Notarization** needs your Apple Developer Program membership, a Developer ID Application
  certificate, and notary credentials. Without notarization Gatekeeper will quarantine the app on
  first launch.

## Data

- Database: `~/Library/Application Support/Lockin/lockin.sqlite` (WAL mode).
- ActivityWatch bucket: `lockin-sessions_<hostname>`, type `currentwindow`, created idempotently.
  The hostname is discovered at runtime from an existing `aw-watcher-*` bucket so the lane lands in
  the same device group. No `aw-watcher-*` bucket is ever modified.

## Architecture

```
main.swift ─ AppDelegate ─┬─ StatusItemController (NSStatusItem label: dot + monospaced timer)
                          ├─ PanelController (key-capable NSPanel hosting SwiftUI popover)
                          ├─ HotkeyCenter (Carbon global shortcuts)
                          └─ AppModel ─┬─ Store (GRDB / SQLite, source of truth)
                                       └─ AWSync (async retry queue → localhost:5600)
```

Reports, classification, calendar sync, blocking, and nudges are intentionally out of scope for v1.
