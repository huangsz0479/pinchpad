# Pinchpad

**Language / 语言:** English · [中文](README.md)

A menu bar–resident **app launcher** for macOS. Open it from the menu bar icon, a keyboard shortcut, a screen hot corner, or a trackpad pinch, then browse your apps full-screen by page or by scrolling — with folders, drag-to-reorder, search, and uninstall.

- Fully local: no network, no account, no telemetry.
- Independent implementation: it does not modify or repackage any system app.
- Lives in the menu bar and keeps out of the Dock by default; the panel only appears when you open it.

## Features

**Ways to open**
- Menu bar icon (left click toggles; right click for Settings and Quit)
- Global keyboard shortcut (default `F4`, configurable)
- Screen hot corners
- Three- or four-finger trackpad pinch (each can be toggled independently)

**Browsing and organization**
- Three browsing modes: paged, vertical scrolling, window
- Grid densities from 7×5 to 10×6
- Page navigation: `←` `→`, horizontal trackpad swipe, page dots, side arrows
- Drag to reorder (dragging to an edge turns the page); drop one app onto another to create a folder
- `Cmd` + click for multi-selection; create a folder or hide apps in bulk
- Context menu: open, reveal in Finder, rename, hide, pin to Dock, move to Trash
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
- Xcode Command Line Tools for building (`swiftc`, `xcrun`, `codesign`, `security`, `openssl`). No Xcode project or Apple Developer account required.

## Build

```bash
cd Pinchpad
./build.sh
```

Output: `../Pinchpad.app` (a sibling of this project directory).

Notes:

- **Quit the running Pinchpad first** (menu bar icon → Quit Pinchpad); the script refuses to replace an app that is in use.
- The first build generates a local self-signed identity under `~/Library/Application Support/Pinchpad/signing/` and reuses it for later builds, so system permissions (e.g. Accessibility) survive re-packaging.
- After building: `open ../Pinchpad.app`; the menu bar icon appears.

Regenerate the icon (optional):

```bash
swift generate-icon.swift <output-iconset-directory> <menubar-icon-output-directory>
```

## Usage

| Action | How |
|---|---|
| Open the panel | Menu bar icon / shortcut (default F4) / hot corner / trackpad pinch |
| Close the panel | `Esc`, pinch again, click outside, or press the shortcut again |
| Turn pages | `←` `→`, horizontal trackpad swipe, page dots, side arrows |
| Multi-select | `Cmd` + click |
| Create a folder | Drag one app onto another, or multi-select and click “New Folder” |
| Uninstall | `Option` + click (can be disabled in Settings), or right-click → Move to Trash |
| Settings | Right-click the menu bar icon → Settings |

## Local data

| Path | Contents |
|---|---|
| `~/Library/Application Support/Pinchpad/library.json` | The only app data: settings, app list, folders, pages, current page. Deleting it triggers a fresh scan and a default layout |
| `~/Library/Preferences/app.local.pinchpad.plist` | System preferences placeholder (effectively empty) |
| `~/Library/Application Support/Pinchpad/signing/` | Local signing keychain and p12 used by the build. **Do not delete** — without it the existing app cannot be replaced |

Icon bitmaps, the backdrop glow gradients, and the prewarmed panel textures are **memory-only caches**; they are released on quit and no cache directories are written to disk.

## Signing and permissions

- Uses a **self-signed certificate** generated locally by the build script: `Pinchpad Local` (RSA 2048, valid for 10 years). No network access, no Apple ID, no developer certificate.
- The signing identity lives in `~/Library/Application Support/Pinchpad/signing/` (`pinchpad.keychain-db` and `pinchpad.p12`); its password is `pinchpad-local`. This is a dedicated keychain, separate from the login keychain.
- Trackpad pinch requires Accessibility permission under System Settings → Privacy & Security → Accessibility. Keeping the signing identity stable means you do not need to re-grant it after rebuilding.
- The app is not notarized; it is intended for local use.

## Project layout

```
Pinchpad/
├── Sources/
│   ├── AppMain.swift          # Entry point, panel window, menu bar, hot corner/pinch wiring, fades, backdrop glow
│   ├── AppModel.swift         # Global state, persistence, icon cache, drag & drop, paging, uninstall, import
│   ├── Model.swift            # Data models and preferences
│   ├── PinchpadView.swift     # Main UI: search, grid, paging, folders, entrance animation
│   ├── SettingsView.swift     # Settings window (General / Gestures / Appearance / Apps / About)
│   ├── Services.swift         # App scanning, related-file lookup, Dock pinning, global hotkey, hot corners, pinch monitor
│   └── PinchClassifier.swift  # Trackpad multi-finger gesture classification
├── Tests/
│   └── PanelTransitionProbe.swift  # Open/close and build-freshness checks against the running app
├── Resources/                 # Menu bar icons
├── AppIcon.iconset/           # App icon sources
├── AppIcon.icns
├── Info.plist
├── generate-icon.swift        # Generates the app icon and menu bar glyph
└── build.sh                   # Compile, assemble, sign, verify
```

## Performance notes

- The full-screen panel stays mounted at 1% opacity with its icon textures rasterized in advance; opening only plays compositor animations instead of resubmitting content.
- The opening transition takes about 0.3s: the backdrop fades in over 0.13s while icons appear with a 0.22s `easeOut` and a 30ms stagger per ring — full frame rate on a 60Hz display.
- Idle CPU while hidden is about 0%; resident physical memory is roughly 40–50MB.
- Everything relies on system APIs (panel show/hide, hotkeys, gesture monitoring); there are no polling main-thread animations.

## Testing

```bash
swift Tests/PanelTransitionProbe.swift <running Pinchpad PID> <source root>
```

It verifies that the built app is newer than the sources, that the panel opens and closes on time, and a few low-cost animation invariants. The terminal (or whatever process runs the test) needs System Events automation permission.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Build says `Quit the running Pinchpad before rebuilding...` | Quit Pinchpad from the menu bar first |
| Build says `requires its original signing identity` / `Signing certificate does not match` | The signing directory is missing or was replaced: restore `signing/`, or delete both `Pinchpad.app` and `signing/` and rebuild (a new identity is generated and Accessibility must be granted again) |
| Pinch does not work | Allow Pinchpad under System Settings → Privacy & Security → Accessibility; make sure three/four-finger pinch is enabled in Settings |
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
