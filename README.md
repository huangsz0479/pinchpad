# Pinchpad

**Language / 语言:** English · [简体中文](README.zh-CN.md)

A native **app launcher and menu bar organizer** for macOS. Click the menu bar icon or use a three-finger pinch to access menu bar apps and pinned favorites. Open the full launcher with a four-finger pinch, a keyboard shortcut, or a hot corner to browse, search, and organize your apps.

- Fully local: no network, no account, no telemetry.
- Independent implementation: it does not modify or repackage any system app.
- Lives in the menu bar and keeps out of the Dock by default; open either panel when you need it.

## Features

**Ways to open**
- Menu bar icon: left-click to toggle the organizer; right-click for Settings and Quit
- Three-finger pinch inward opens the organizer
- Four-finger pinch inward opens the full launcher
- Either enabled outward-spread gesture dismisses the visible Pinchpad panel, regardless of how it was opened
- Four-finger spread is passed through to macOS for Show Desktop when enabled in System Settings; Pinchpad only intercepts the inward app-launcher pinch
- Global keyboard shortcut (default `F4`, configurable) and screen hot corners open the full launcher
- Three- and four-finger gestures can be enabled independently in Settings
- Five pinch sensitivity levels in Settings → Gestures & Keys offer gradual differences in required movement. All levels filter brief jitter while confirming during the pinch, so no extra hold is needed. The setting applies to both finger counts, takes effect immediately, and is saved across restarts.

**Menu bar organizer**
- The menu bar section shows third-party apps that actually own menu bar icons, in their on-screen order
- Pin favorite apps in a separate section; your collection persists across restarts
- Click the add tile to search and pin apps directly, or pin them from the full launcher's context menu
- Click an icon to open or bring its app forward; right-click to unpin it or open a menu bar app's own menu
- Native Liquid Glass on macOS 26 and later, with a system-material fallback on older versions
- A 460-point-wide panel with five app columns starts two screen pixels below the menu bar and ends six points plus 200 screen pixels above the Dock area; click outside or press `Esc` to dismiss
- Does not move or hide other apps' actual menu bar icons

**Browsing and organization**
- Three browsing modes: paged, vertical scrolling, window
- Grid densities from 7×5 to 10×6
- Page navigation: `←` `→`, horizontal trackpad swipe, page dots, side arrows
- Drag to reorder (dragging to an edge turns the page); drop one app onto another to create a folder
- `Cmd` + click for multi-selection; create a folder or hide apps in bulk
- Context menu: open, reveal in Finder, pin to the organizer, rename, hide, pin to Dock, move to Trash
- Live search filter; hold `Option` and click to review an uninstall confirmation, including related support files
- “Organize App Layout” and “Import System App Order”
- Enabled app directories and their subfolders sync automatically: new apps are appended, uninstalled apps are removed, and startup reconciles changes made while Pinchpad was closed. Existing names, hidden states, folders, and app order are preserved.

**Confirmation dialogs**
- Uninstall, rename, and Dock-pinning dialogs use native sheets attached to the launcher, so they stay above it in both full-screen and windowed modes
- The sheet owns keyboard focus while open; background clicks do not dismiss the launcher beneath it
- Cancelling leaves the requested change unapplied; closing the launcher also cancels any pending confirmation

**Appearance**
- Three backdrop styles: wallpaper blur / dimmed / dark
- Opening animation: the original four-ring center-out icon wave, with native background fades and display-aware refresh-rate hints
- Respects the system Reduce Motion setting

**System integration**
- Launch at login
- Menu bar icon; optional Dock icon
- Temporarily hide the Dock while the panel is open
- Choose the screen to appear on: main / screen with pointer / active screen
- Multi-display, all spaces, above full-screen apps

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (built for `arm64-apple-macosx14.0`)
- Building requires a toolchain with the macOS 26 SDK or later; the deployment target remains macOS 14
- Xcode Command Line Tools for building (`swiftc`, `xcrun`, `codesign`, `security`, `openssl`). No Xcode project or Apple Developer account required.

## Build

```bash
cd Pinchpad
./build.sh
```

Output: `../Pinchpad.app` (a sibling of this project directory).

Notes:

- **Quit the running Pinchpad first** (right-click the menu bar icon → Quit Pinchpad); the script refuses to replace an app that is in use.
- The first build generates a local self-signed identity under `~/Library/Application Support/Pinchpad/signing/` and reuses it for later builds, so system permissions (e.g. Accessibility) survive re-packaging.
- After building: `open ../Pinchpad.app`; the menu bar icon appears.

Regenerate the icon (optional):

```bash
swift generate-icon.swift <output-iconset-directory> <menubar-icon-output-directory>
```

## Usage

| Action | How |
|---|---|
| Open the organizer | Left-click the menu bar icon, or pinch inward with three fingers |
| Open the full launcher | Four-finger pinch / shortcut (default `F4`) / hot corner / all-apps button in the organizer |
| Close the organizer | `Esc`, click outside, click the menu bar icon again, or use an enabled outward-spread gesture |
| Close the full launcher | `Esc`, click empty space, press the shortcut again, or use an enabled outward-spread gesture |
| Show Desktop | Spread the thumb and three fingers outward; enable Show Desktop in macOS Trackpad settings |
| Pin an app | Click the add tile in the organizer, or use the full launcher's context menu |
| Unpin an app | Right-click a pinned app and choose the unpin action |
| Turn pages | `←` `→`, horizontal trackpad swipe, page dots, side arrows |
| Multi-select | `Cmd` + click |
| Create a folder | Drag one app onto another, or multi-select and click “New Folder” |
| Request an uninstall | `Option` + click (can be disabled in Settings), or right-click → Move to Trash; review and confirm the dialog |
| Settings | Right-click the menu bar icon → Settings |

Documentation is available in English and Simplified Chinese. The app interface is currently in Simplified Chinese.

### Gestures and safe removal

Three- and four-finger inward pinches open different Pinchpad panels; an outward spread is not limited to closing the panel opened by the same finger count. The macOS four-finger Show Desktop gesture remains available even when Pinchpad is running. Enable it in **System Settings → Trackpad → More Gestures → Show Desktop**.

Requesting an uninstall does not immediately remove anything. Review the application and any listed support files in the confirmation sheet, then explicitly confirm to move them to Trash. Choose Cancel to leave them untouched. Pinchpad refuses to remove itself or applications under `/System`.

## Local data

| Path | Contents |
|---|---|
| `~/Library/Application Support/Pinchpad/library.json` | Settings, app list, pinned favorites, folders, pages, and current page. Deleting it triggers a fresh scan and a default layout |
| `~/Library/Preferences/app.local.pinchpad.plist` | System preferences placeholder (effectively empty) |
| `~/Library/Application Support/Pinchpad/signing/` | Local signing keychain and p12 used by the build. **Do not delete** — without it the existing app cannot be replaced |

Icon bitmaps, the backdrop glow gradients, and the prewarmed panel textures are **memory-only caches**; they are released on quit and no cache directories are written to disk.

## Signing and permissions

- Uses a **self-signed certificate** generated locally by the build script: `Pinchpad Local` (RSA 2048, valid for 10 years). No network access, no Apple ID, no developer certificate.
- The signing identity lives in `~/Library/Application Support/Pinchpad/signing/` (`pinchpad.keychain-db` and `pinchpad.p12`); its password is `pinchpad-local`. This is a dedicated keychain, separate from the login keychain.
- Trackpad pinch, menu bar app discovery, and opening another app's menu require Accessibility permission under System Settings → Privacy & Security → Accessibility. Keeping the signing identity stable means you do not need to re-grant it after rebuilding.
- The app is not notarized; it is intended for local use.

## Project layout

```
Pinchpad/
├── Sources/
│   ├── AppMain.swift          # Entry point, panel window, menu bar, hot corner/pinch wiring, fades, backdrop glow
│   ├── AppModel.swift         # Global state, persistence, icon cache, drag & drop, paging, uninstall, import
│   ├── AppLibraryMonitor.swift # Event-driven directory monitoring and installation-change debounce
│   ├── PanelAlertPresenter.swift # Native confirmation sheets attached to their launcher
│   ├── IconEntrance.swift      # Original icon-wave timing and visibility rules
│   ├── PanelAnimation.swift     # Compositor transitions and display-aware frame-rate hints
│   ├── LauncherPanelVisibility.swift # Suspends hidden panels and effects
│   ├── Model.swift            # Data models and preferences
│   ├── PinchpadView.swift     # Main UI: search, grid, paging, folders, entrance animation
│   ├── TrayView.swift         # Liquid Glass organizer, menu bar apps, pins, and app picker
│   ├── SettingsView.swift     # Settings window (General / Gestures / Appearance / Apps / About)
│   ├── Services.swift         # App scanning, related-file lookup, Dock pinning, global hotkey, hot corners, pinch monitor
│   └── PinchClassifier.swift  # Trackpad multi-finger gesture classification
├── Tests/
│   ├── PanelTransitionProbe.swift # Full-launcher transitions and build-freshness checks
│   ├── PanelAnimationProbe.swift # In-memory transition and frame-rate contract checks
│   ├── IdleResponsivenessProbe.swift # Hidden surfaces and input-thread isolation
│   ├── AlertPresentationProbe.swift # Alert stacking and cancellation in full-screen/windowed modes
│   ├── PinchGestureProbe.swift    # Gesture recognition and three-/four-finger panel routing
│   ├── AppLibrarySyncProbe.py     # App installation/removal, startup reconciliation, and source changes
│   ├── TrayActivationProbe.swift  # Icon clicks, pointer drift, and accessible press actions
│   ├── TrayCornerProbe.swift      # Transparency checks outside rounded corners
│   └── TrayPlacementProbe.swift   # Two-pixel menu bar gap and window-level checks
├── Resources/                 # Menu bar icons
├── AppIcon.iconset/           # App icon sources
├── AppIcon.icns
├── Info.plist
├── generate-icon.swift        # Generates the app icon and menu bar glyph
└── build.sh                   # Compile, assemble, sign, verify
```

## Performance notes

- Hidden panels leave the display list and suspend their backdrop effects while retaining their view and icon caches.
- The full launcher preserves the center-out four-ring icon wave and uses native background fades. Only the active page plays the entrance; icons in each ring composite together. The organizer fades in at its final position without crossing the menu bar.
- Native transitions request a preferred rate of 120 fps when the display supports it, bounded by the display capability. A 60 Hz display can only show up to 60 fps.
- Gesture filtering runs on a dedicated run loop so UI work does not block global gesture delivery.
- Menu bar app discovery runs when the organizer opens and when apps launch or quit, rather than on a continuous polling timer.
- App-library synchronization watches enabled directories with macOS file events, combines bursts of installation changes, and scans off the main thread. Idle libraries do not poll; changing scan directories takes effect immediately.
- Timing and resource usage depend on the system, hardware, and app library. Use the probes below to check the current build.

## Testing

```bash
swift Tests/PanelTransitionProbe.swift <running Pinchpad PID> <source root>

# Open the organizer before running these:
swift Tests/TrayCornerProbe.swift <running Pinchpad PID>
swift Tests/TrayPlacementProbe.swift <running Pinchpad PID>

# The app must appear in the organizer; this actually clicks and opens it:
swift Tests/TrayActivationProbe.swift <running Pinchpad PID> "<app name>" <bundleID> mouse

# Gesture recognition and routing without a trackpad or running app:
swiftc -swift-version 5 Sources/Model.swift Sources/PinchClassifier.swift \
  Sources/Services.swift Tests/PinchGestureProbe.swift -lsqlite3 \
  -o /tmp/PinchGestureProbe && /tmp/PinchGestureProbe

# Arrow paging and event delivery without system input or loading the user's library:
python3 Tests/PageNavigationProbe.py

# App installation/removal and source changes using temporary app bundles; no UI or user library:
python3 Tests/AppLibrarySyncProbe.py

# Animation contracts and refresh-rate hints without windows or a running app:
swiftc Sources/IconEntrance.swift Sources/PanelAnimation.swift Tests/PanelAnimationProbe.swift \
  -o /tmp/PanelAnimationProbe && /tmp/PanelAnimationProbe

# Input isolation and panel shutdown; no system input is posted or windows displayed:
swiftc -swift-version 5 Sources/Model.swift Sources/PinchClassifier.swift \
  Sources/Services.swift Sources/LauncherPanelVisibility.swift \
  Tests/IdleResponsivenessProbe.swift -lsqlite3 \
  -o /tmp/IdleResponsivenessProbe && /tmp/IdleResponsivenessProbe

# Native confirmation layering; the test only cancels, never deletes anything:
swiftc -swift-version 5 Sources/PanelAlertPresenter.swift \
  Tests/AlertPresentationProbe.swift -o /tmp/AlertPresentationProbe \
  && /tmp/AlertPresentationProbe
```

The probes cover:

- Original wave timing and visibility rules, background fade endpoints, interrupted transitions, and refresh-rate hints for 60/120/144/240 Hz displays. These in-memory checks do not measure displayed frame rate; that requires validation on the target display.
- Build freshness and full-launcher opening/closing transitions.
- Organizer corner transparency, two-pixel menu bar spacing, Dock clearance, and app activation.
- Five sensitivity levels, live updates and preference migration; three-/four-finger panel routing, Show Desktop event pass-through, and preservation of system horizontal/vertical swipes.
- Automatic installation/removal, offline startup changes, nested and recreated sources, path aliases, app moves, preserved metadata/layout, stale-scan rejection, and idle behavior. The library probe only creates/removes temporary fixtures.
- Confirmation sheets appearing above full-screen/windowed launchers, with cancellation leaving the launcher visible.

The activation probe also supports `drift` (a click with slight pointer movement) and `ax` (an accessible press action). The gesture probe does not install device hooks or require a running app. The alert probe opens test dialogs and only cancels them; it does not delete anything. Grant the terminal or test host the relevant Accessibility, screen capture, and automation permissions for tests that interact with the running app.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Build says `Quit the running Pinchpad before rebuilding...` | Quit Pinchpad from the menu bar first |
| Build says `requires its original signing identity` / `Signing certificate does not match` | The signing directory is missing or was replaced: restore `signing/`, or delete both `Pinchpad.app` and `signing/` and rebuild (a new identity is generated and Accessibility must be granted again) |
| Pinch does not work | Allow Pinchpad under System Settings → Privacy & Security → Accessibility; make sure three/four-finger pinch is enabled in Settings |
| Four-finger spread does not show the desktop | Enable Show Desktop under System Settings → Trackpad → More Gestures, and use a current Pinchpad build that passes this gesture through to macOS |
| A confirmation dialog is hidden behind the launcher | Update and rebuild Pinchpad. Current builds attach confirmations as native sheets rather than relying on a manually raised window level |
| No apps in the menu bar section | Grant Pinchpad Accessibility permission, then reopen the organizer. This section shows third-party apps with menu bar icons, not every running app |
| Shortcut does nothing | The combination may be taken by the system or another app; Settings reports conflicts and you can choose another |
| First open feels slow | One-time cost from the first activation and keyboard focus initialization after login |
| Wrong icons or positions after opening | Settings → Apps → Rescan, or delete `library.json` to restore the default layout |

## Uninstall

1. Quit Pinchpad from the menu bar.
2. Delete `Pinchpad.app`.
3. Delete `~/Library/Application Support/Pinchpad/` (settings, layout, and the signing identity live there).
4. Remove Pinchpad from System Settings → General → Login Items and from Privacy & Security → Accessibility.

## License

Released under the **MIT License**. See [LICENSE](LICENSE).

Copyright (c) 2026 huangsz
