# Pinchpad

**Language / 语言:** English · [简体中文](README.zh-CN.md)

A native **app launcher and menu bar organizer** for macOS. Click the menu bar icon or use a three-finger pinch to access menu bar apps and pinned favorites. Open the full launcher with a four-finger pinch, a keyboard shortcut, or a hot corner to browse, search, and organize your apps.

- Fully local: no network, no account, no telemetry.
- Independent implementation: it does not modify or repackage any system app.
- Lives in the menu bar and keeps out of the Dock by default; open either panel when you need it.

## Features

**Ways to open**
- Menu bar icon: left-click to toggle the organizer; right-click for Settings and Quit
- Three-finger pinch inward to open the organizer; spread outward to close it
- Four-finger pinch inward to open the full launcher; spread outward to close it
- Either enabled outward-spread gesture dismisses the visible panel, even if it was opened another way
- Four-finger spread still reaches macOS for Show Desktop; Pinchpad only intercepts the inward app-launcher pinch
- Global keyboard shortcut (default `F4`, configurable) and screen hot corners open the full launcher
- Three- and four-finger gestures can be enabled independently in Settings

**Menu bar organizer**
- The menu bar section shows third-party apps that actually own menu bar icons, in their on-screen order
- Pin favorite apps in a separate section; your collection persists across restarts
- Click the add tile to search and pin apps directly, or pin them from the full launcher's context menu
- Click an icon to open or bring its app forward; right-click to unpin it or open a menu bar app's own menu
- Native Liquid Glass on macOS 26 and later, with a system-material fallback on older versions
- Sits two screen pixels below the menu bar; click outside or press `Esc` to dismiss
- Does not move or hide other apps' actual menu bar icons

**Browsing and organization**
- Three browsing modes: paged, vertical scrolling, window
- Grid densities from 7×5 to 10×6
- Page navigation: `←` `→`, horizontal trackpad swipe, page dots, side arrows
- Drag to reorder (dragging to an edge turns the page); drop one app onto another to create a folder
- `Cmd` + click for multi-selection; create a folder or hide apps in bulk
- Context menu: open, reveal in Finder, pin to the organizer, rename, hide, pin to Dock, move to Trash
- Live search filter; hold `Option` and click to uninstall directly (with a confirmation list of related files)
- “Organize App Layout” and “Import System App Order”

**Appearance**
- Three backdrop styles: wallpaper blur / dimmed / dark
- Opening animation: the backdrop fades in quickly, icons pop in ring by ring from the center
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
| Close the organizer | `Esc`, click outside, click the menu bar icon again, or spread three fingers outward |
| Close the full launcher | `Esc`, click empty space, press the shortcut again, or spread four fingers outward |
| Pin an app | Click the add tile in the organizer, or use the full launcher's context menu |
| Unpin an app | Right-click a pinned app and choose the unpin action |
| Turn pages | `←` `→`, horizontal trackpad swipe, page dots, side arrows |
| Multi-select | `Cmd` + click |
| Create a folder | Drag one app onto another, or multi-select and click “New Folder” |
| Uninstall | `Option` + click (can be disabled in Settings), or right-click → Move to Trash |
| Settings | Right-click the menu bar icon → Settings |

Documentation is available in English and Simplified Chinese. The app interface is currently in Simplified Chinese.

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
│   ├── PanelAlertPresenter.swift # Native confirmation sheets attached to their launcher
│   ├── Model.swift            # Data models and preferences
│   ├── PinchpadView.swift     # Main UI: search, grid, paging, folders, entrance animation
│   ├── TrayView.swift         # Liquid Glass organizer, menu bar apps, pins, and app picker
│   ├── SettingsView.swift     # Settings window (General / Gestures / Appearance / Apps / About)
│   ├── Services.swift         # App scanning, related-file lookup, Dock pinning, global hotkey, hot corners, pinch monitor
│   └── PinchClassifier.swift  # Trackpad multi-finger gesture classification
├── Tests/
│   ├── PanelTransitionProbe.swift # Full-launcher transitions and build-freshness checks
│   ├── AlertPresentationProbe.swift # Alert stacking and cancellation in full-screen/windowed modes
│   ├── PinchGestureProbe.swift    # Gesture recognition and three-/four-finger panel routing
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

- The full-screen panel stays mounted at 1% opacity with its icon textures rasterized in advance; opening only plays compositor animations instead of resubmitting content.
- The full launcher uses compositor fades. The organizer fades in at its final position without crossing the menu bar.
- Menu bar app discovery runs when the organizer opens and when apps launch or quit, rather than on a continuous polling timer.
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

# Native confirmation layering; the test only cancels, never deletes anything:
swiftc -swift-version 5 Sources/PanelAlertPresenter.swift \
  Tests/AlertPresentationProbe.swift -o /tmp/AlertPresentationProbe \
  && /tmp/AlertPresentationProbe
```

The probes check build freshness, full-launcher transitions, organizer transparency and placement, and app activation. The activation probe also supports `drift` (a click with slight pointer movement) and `ax` (an accessible press action). Grant the terminal or test host the relevant Accessibility, screen capture, and automation permissions.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Build says `Quit the running Pinchpad before rebuilding...` | Quit Pinchpad from the menu bar first |
| Build says `requires its original signing identity` / `Signing certificate does not match` | The signing directory is missing or was replaced: restore `signing/`, or delete both `Pinchpad.app` and `signing/` and rebuild (a new identity is generated and Accessibility must be granted again) |
| Pinch does not work | Allow Pinchpad under System Settings → Privacy & Security → Accessibility; make sure three/four-finger pinch is enabled in Settings |
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
