# Pinchpad

**Language / 语言:** English · [简体中文](README.zh-CN.md)

A native **app launcher and menu bar app clothesline** for macOS. Use a three-finger pinch to unfold a full-screen clothesline of menu bar apps. Click the menu bar icon to open Settings directly. Open the full launcher with a four-finger pinch, a keyboard shortcut, or a hot corner to browse, search, and organize your apps.

- Fully local: no network, no account, no telemetry.
- Independent implementation: it does not modify or repackage any system app.
- Lives in the menu bar and keeps out of the Dock by default; open either panel when you need it.

## Features

**Ways to open**
- Menu bar icon: left-click to open Settings directly; right-click for Settings and Quit
- Three-finger pinch inward unfolds the full-screen menu bar app clothesline
- Four-finger pinch inward opens the full launcher
- Either enabled outward-spread gesture dismisses the visible Pinchpad panel, regardless of how it was opened
- Four-finger spread is passed through to macOS for Show Desktop when enabled in System Settings; Pinchpad only intercepts the inward app-launcher pinch
- Global keyboard shortcut (default `F4`, configurable) and screen hot corners open the full launcher
- Optional second shortcut opens a new terminal window in a fixed working directory; the directory and terminal app are configurable
- Three- and four-finger gestures can be enabled independently in Settings
- Five pinch sensitivity levels in Settings → Trackpad Gestures offer gradual differences in required movement. All levels filter brief jitter while confirming during the pinch, so no extra hold is needed. Each finger count has its own setting, applied immediately and saved across restarts. Both inherit the previous shared level on upgrade.

**Full-screen clothesline**
- Shows third-party running apps that own menu bar icons, in their actual left-to-right order
- Metal pins fix both cable ends about 15 points below the menu bar. Cable length, card weight and suspension locations jointly determine the rope shape
- Each card has a 56-point icon with 4-point margins and matching holes in both upper corners, tied to separate points on the main cable with two 22-point cords. Gravity, both suspension forces and rotational inertia drive the sway and tilt; damping brings it to rest
- The full-screen background is completely transparent, preserving the desktop and windows. Only app cards use glass material. Animation updates stop when settled or hidden
- Hanging cards use one compact size. Overflow pages use bottom controls or left/right arrow keys
- Each opening starts without a selection. Tab selects the next card and the tilde/backtick key selects the previous card, wrapping in both directions across pages. Both single-key bindings are configurable in Settings → Shortcuts & Hot Corners; fn, Control, Option, Command and power are excluded, and assigning a duplicate swaps the bindings. Space immediately dismisses the clothesline before opening the selected app; it does nothing without a selection
- Click to open an app; right-click for native menu, activation and quitting
- Dismiss with the background, Escape or an outward gesture. Uses the existing display preference and the settled physical pose with Reduce Motion

**Free placement and menu bar**
- Left-click opens Settings directly; right-click retains launcher and quit actions. The former organizer popup has been removed.
- Drag cards to arbitrary horizontal and vertical locations within the hanging area, without fixed slots. Positions persist per application using normalized display coordinates.
- Pulling transfers force through the cable, then breaks the two ties. On release, attachments slide along the cable, loose ends thread through the holes and knots tighten before carrying the load again.
- Physics runs at a fixed 120 Hz with interpolation between display frames. A native display link stops when the scene rests or closes; glass and icon content are reused between frames.
- Other apps' real menu bar icons are never moved or hidden.

**Browsing and organization**
- Three browsing modes: paged, vertical scrolling, window
- Grid densities from 7×5 to 10×6
- Page navigation: `←` `→`, horizontal trackpad swipe, page dots, side arrows
- Drag to reorder (dragging to an edge turns the page); drop one app onto another to create a folder
- `Cmd` + click for multi-selection; create a folder or hide apps in bulk
- Context menu: open, reveal in Finder, rename, hide, pin to Dock, move to Trash
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
swift generate-icon.swift AppIcon.iconset Resources
```

Renders the three-color D1 origami mark on a flat off-white macOS icon plate and the same fold contours as a monochrome menu bar template. Exports all sizes in `AppIcon.iconset`, `AppIcon.icns`, the 1024px `Resources/AppIcon-master.png`, editable `Resources/AppIcon.svg` and `Resources/MenuBarIcon.svg`, and 18pt standard and Retina menu bar PNGs. Rebuild the app to include regenerated icons.

## Usage

| Action | How |
|---|---|
| Open the app clothesline | Pinch inward with three fingers |
| Open Settings | Left-click the menu bar icon |
| Reposition a card | Drag a clothesline app card freely; release to retie |
| Next / previous card | Tab / tilde key by default; customize either binding in Settings |
| Open the full launcher | Four-finger pinch / shortcut (default `F4`) / hot corner |
| Close the full launcher | `Esc`, click empty space, press the shortcut again, or use an enabled outward-spread gesture |
| Show Desktop | Spread the thumb and three fingers outward; enable Show Desktop in macOS Trackpad settings |
| Turn pages | `←` `→`, horizontal trackpad swipe, page dots, side arrows |
| Multi-select | `Cmd` + click |
| Create a folder | Drag one app onto another, or multi-select and click “New Folder” |
| Request an uninstall | `Option` + click (can be disabled in Settings), or right-click → Move to Trash; review and confirm the dialog |
| Adjust pinch sensitivity | Settings → Trackpad Gestures → Pinch sensitivity; separate controls for three- and four-finger gestures |
| Open a terminal | Enable and record a shortcut in Settings → Terminal; each press opens a new window in the configured directory |
| Manage app folders | Settings → App Sources; enable a folder or add a custom location |
| Settings | Left-click the menu bar icon, or right-click → Settings |

Documentation is available in English and Simplified Chinese. The app interface is currently in Simplified Chinese.

Settings has nine sidebar pages without scrolling. App sources and hidden apps use pagination. Shortcuts & Hot Corners includes both clothesline navigation bindings. Clicking the menu bar icon opens Settings directly.

### Pinch sensitivity

Open **Settings → Trackpad Gestures (触控板手势)** and adjust the sensitivity for each finger count. The five levels are Very Low, Low, Standard, High, and Very High; Standard is the default.

Start with Standard. If pinches trigger accidentally, lower the sensitivity one step to require a more deliberate movement. If intended pinches are missed, raise it one step. Each level filters brief jitter, and you can lift your fingers naturally after pinching without an extra hold.

Three- and four-finger gestures have independent sliders. Enable the corresponding gesture to adjust its level; changes apply immediately and survive restarts. Both inherit the old shared level on upgrade, then can be tuned separately.

### App library sync

Open **Settings → App Sources (应用来源)** to choose which folders contribute apps. The default sources are `/Applications`, `/System/Applications`, `/System/Applications/Utilities`, and `~/Applications`; their subfolders are included. Use **Add Folder (添加文件夹…)** for apps kept elsewhere.

- Installing an app in an enabled source adds it to the existing layout automatically, without launching the new app or reopening the panel. Allow the file copy to finish and the changes to settle.
- Uninstalling an app, or moving it out of all enabled sources, removes its library entry, pinned favorite, and folder references. Empty folders are removed too.
- Existing apps keep their custom names, hidden states, folders, and order. Newly discovered apps are appended to the layout.
- Enabling, disabling, adding, or removing a source updates the library immediately. Removing a source from Settings leaves its files untouched.
- Starting Pinchpad also reconciles installations and removals made while it was closed. **Rescan (重新扫描)** remains available for a manual refresh.

### Gestures and safe removal

Three- and four-finger inward pinches open different Pinchpad panels; an outward spread is not limited to closing the panel opened by the same finger count. The macOS four-finger Show Desktop gesture remains available even when Pinchpad is running. Enable it in **System Settings → Trackpad → More Gestures → Show Desktop**.

Requesting an uninstall does not immediately remove anything. Review the application and any listed support files in the confirmation sheet, then explicitly confirm to move them to Trash. Choose Cancel to leave them untouched. Pinchpad refuses to remove itself or applications under `/System`.

### Terminal shortcut

Open **Settings → Terminal (终端)** to configure a dedicated shortcut for opening a terminal window.

- Enable the toggle and record any key combination, the same way the launcher shortcut is set.
- **Working directory**: each new terminal window starts in this folder; leave it empty to use your home directory, or pick a folder with **Choose… (选择…)**.
- **Terminal app**: defaults to the built-in Terminal.app; point it at iTerm or another terminal app that opens folders as new sessions.

Pressing the shortcut while the launcher or clothesline is open dismisses it first, then the terminal activates. If the configured folder no longer exists, Pinchpad shows a notice instead of opening anywhere else.

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
│   ├── EntranceMotion.swift    # Entrance-only signals that reuse the mounted icon grids
│   ├── PanelAnimation.swift     # Compositor transitions and display-aware frame-rate hints
│   ├── LauncherPanelVisibility.swift # Suspends hidden panels and effects
│   ├── Model.swift            # Data models and preferences
│   ├── PinchpadView.swift     # Main UI: search, grid, paging, folders, entrance animation
│   ├── PagingMotion.swift     # Paging-only observable state for continuous trackpad motion
│   ├── TrayView.swift         # Liquid Glass organizer, menu bar apps, pins, and app picker
│   ├── SettingsView.swift     # Settings sidebar, sections and shared cards
│   ├── GestureSettingsView.swift # Gestures, shortcuts and terminal
│   ├── PanelSettingsView.swift # General, appearance, layout and about
│   ├── ApplicationSettingsView.swift # Paginated sources and hidden apps
│   ├── SettingsControls.swift # Shortcut recording and organization sheet
│   ├── SettingsPagination.swift # Settings list page boundaries
│   ├── Services.swift         # App scanning, related-file lookup, Dock pinning, global hotkey, hot corners, pinch monitor
│   └── PinchClassifier.swift  # Trackpad multi-finger gesture classification
├── Tests/
│   ├── PanelTransitionProbe.swift # Full-launcher transitions and build-freshness checks
│   ├── PanelAnimationProbe.swift # In-memory transition and frame-rate contract checks
│   ├── IdleResponsivenessProbe.swift # Hidden surfaces and input-thread isolation
│   ├── AlertPresentationProbe.swift # Alert stacking and cancellation in full-screen/windowed modes
│   ├── PinchGestureProbe.swift    # Gesture recognition and three-/four-finger panel routing
│   ├── PageNavigationProbe.py     # Single-step arrow paging and event delivery
│   ├── PagingPerformanceProbe.py # Isolated SwiftUI paging workload and geometry checks
│   ├── OpeningPerformanceProbe.py # Hidden SwiftUI opening workload and icon-wave lifecycle checks
│   ├── TrayOpeningProbe.py      # Organizer reveal and asynchronous discovery with simulated apps
│   ├── AppLibrarySyncProbe.py     # App installation/removal, startup reconciliation, and source changes
│   ├── TrayActivationProbe.swift  # Icon clicks, pointer drift, and accessible press actions
│   ├── TrayCornerProbe.swift      # Transparency checks outside rounded corners
│   ├── TrayPlacementProbe.swift   # Eight-point menu bar gap and window-level checks
│   └── TerminalDirectoryProbe.swift # Terminal launches land a new shell in the configured directory
├── Resources/                 # App icon master and menu bar icons
├── AppIcon.iconset/           # App icon sizes
├── AppIcon.icns
├── Info.plist
├── generate-icon.swift        # Generates the app icon and menu bar glyph
└── build.sh                   # Compile, assemble, sign, verify
```

## Performance notes

- Hidden panels leave the display list and suspend their backdrop effects while retaining their view and icon caches.
- The full launcher preserves the center-out four-ring icon wave and uses native background fades. Only the active page plays the entrance; icons in each ring composite together. The clothesline uses live coupled physics and display-synchronized rendering.
- Entrance signals update the ring wrappers directly, reusing the mounted icon grids when reopening the launcher.
- Native panel fades request a preferred rate of 120 fps when the display supports it, bounded by the display capability. This preference does not measure or guarantee the frame rate of page animations.
- Continuous trackpad motion updates only the pager. Hit-test geometry is paused during swipes and collected for the current page at rest; dragging enables geometry for adjacent pages so edge turns keep working.
- Horizontal page turns require 36–60 points of travel, keeping the distance short on large displays. Quick flicks retain a minimum travel requirement to reject jitter.
- Reordering preserves mounted icon identity instead of rebuilding icons when they cross entrance groups. Passing over an icon retains the arrangement preview; dwelling arms folder merging. Cross-page changes publish once.
- A bounded window keeps up to three page grids mounted, including at the ends, avoiding repeated offscreen page creation when browsing a three-page library.
- Gesture filtering runs on a dedicated run loop so UI work does not block global gesture delivery.
- Menu bar app discovery runs in the background when the organizer opens and when apps launch or quit. The panel opens using cached results; overlapping refreshes are combined and stale results are discarded.
- App-library synchronization watches enabled directories with macOS file events, combines bursts of installation changes, and scans off the main thread. Idle libraries do not poll; changing scan directories takes effect immediately.
- Timing and resource usage depend on the system, hardware, and app library. Use the probes below to check the current build.

## Testing

The clothesline checks use offline geometry, lifecycle fixtures and offscreen rendering. They do not open test windows or inspect the desktop:

```bash
swiftc -O -swift-version 5 -parse-as-library Sources/Model.swift Sources/ClotheslinePreferences.swift Sources/PinchClassifier.swift Sources/ClotheslineLayout.swift Tests/ClotheslineLayoutProbe.swift -o /tmp/ClotheslineLayoutProbe && /tmp/ClotheslineLayoutProbe
swiftc -O -parse-as-library Sources/Model.swift Sources/PinchClassifier.swift Sources/ClotheslinePreferences.swift Sources/ClotheslineLayout.swift Sources/ClotheslineDynamics.swift Tests/ClotheslineDynamicsProbe.swift -o /tmp/ClotheslineDynamicsProbe && /tmp/ClotheslineDynamicsProbe
swiftc -O -parse-as-library Sources/Model.swift Sources/PinchClassifier.swift Sources/ClotheslinePreferences.swift Sources/CardKeyEditor.swift Tests/CardNavigationProbe.swift -o /tmp/CardNavigationProbe && /tmp/CardNavigationProbe
python3 Tests/ClotheslineLifecycleProbe.py
python3 Tests/ClotheslineRoutingProbe.py
python3 Tests/ClotheslineRenderProbe.py
python3 Tests/ClotheslineIconAlignmentProbe.py
python3 Tests/ClotheslineTransparencyProbe.py
```

Offscreen images in `.build/clothesline/review/` cover light/dark appearance, narrow and ultrawide screens, empty lists and animation samples. They verify layout; native desktop glass composition and physical trackpad feel still need manual acceptance.

```bash
swift Tests/PanelTransitionProbe.swift <running Pinchpad PID> <source root>

# Gesture recognition and routing without a trackpad or running app:
swiftc -swift-version 5 Sources/Model.swift Sources/ClotheslinePreferences.swift Sources/PinchClassifier.swift \
  Sources/Services.swift Tests/PinchGestureProbe.swift -lsqlite3 \
  -o /tmp/PinchGestureProbe && /tmp/PinchGestureProbe

# Arrow paging and event delivery without system input or loading the user's library:
python3 Tests/PageNavigationProbe.py

# Short swipes, quick flicks, jitter rejection, cancellation and boundaries without windows:
python3 Tests/PagingThresholdProbe.py

# Offscreen drag identity, stable previews, folder merging, cross-page order and entrance grouping:
python3 Tests/DragPerformanceProbe.py

# Offscreen settings pages and dropdown bounds:
python3 Tests/SettingsLayoutProbe.py
python3 Tests/SettingsPickerAlignmentProbe.py

# Replay scrolling in an isolated, never-shown SwiftUI fixture; check work counts, not screen FPS:
python3 Tests/PagingPerformanceProbe.py --check

# Hidden opening/layout and original icon-wave checks; excludes window-server/GPU frame timing:
python3 Tests/OpeningPerformanceProbe.py --check

# Simulated menu bar discovery; does not inspect or operate other apps:
python3 Tests/TrayOpeningProbe.py

# App installation/removal and source changes using temporary app bundles; no UI or user library:
python3 Tests/AppLibrarySyncProbe.py

# Animation contracts and refresh-rate hints without windows or a running app:
swiftc Sources/IconEntrance.swift Sources/PanelAnimation.swift Tests/PanelAnimationProbe.swift \
  -o /tmp/PanelAnimationProbe && /tmp/PanelAnimationProbe

# Input isolation and panel shutdown; no system input is posted or windows displayed:
swiftc -swift-version 5 Sources/Model.swift Sources/ClotheslinePreferences.swift Sources/PinchClassifier.swift \
  Sources/Services.swift Sources/LauncherPanelVisibility.swift \
  Tests/IdleResponsivenessProbe.swift -lsqlite3 \
  -o /tmp/IdleResponsivenessProbe && /tmp/IdleResponsivenessProbe

# Native confirmation layering; the test only cancels, never deletes anything:
swiftc -swift-version 5 Sources/PanelAlertPresenter.swift \
  Tests/AlertPresentationProbe.swift -o /tmp/AlertPresentationProbe \
  && /tmp/AlertPresentationProbe

# Terminal launch path: opens a real terminal window in a temp directory and
# checks that a new shell appears with that directory as its working directory:
swift Tests/TerminalDirectoryProbe.swift "$(mktemp -d)"
```

The probes cover:

- Original wave timing and visibility rules, background fade endpoints, interrupted transitions, and refresh-rate hints for 60/120/144/240 Hz displays. These in-memory checks do not measure displayed frame rate; that requires validation on the target display.
- Build freshness and full-launcher opening/closing transitions.
- Continuous swipe isolation, actual page offsets, restored hit-test geometry and page-navigation behavior in a hidden SwiftUI fixture. Its timings describe event handling and forced layout, excluding visible-window composition and GPU work.
- Organizer corner transparency, compact positioning below the menu bar, screen bounds, Dock clearance, and app activation.
- Five sensitivity levels, live updates and preference migration; three-/four-finger panel routing, Show Desktop event pass-through, and preservation of system horizontal/vertical swipes.
- Automatic installation/removal, offline startup changes, nested and recreated sources, path aliases, app moves, preserved metadata/layout, stale-scan rejection, and idle behavior. The library probe only creates/removes temporary fixtures.
- Confirmation sheets appearing above full-screen/windowed launchers, with cancellation leaving the launcher visible.
- Terminal launches: a folder handed to the terminal app through Launch Services becomes the new shell's working directory. The probe opens a real terminal window in a temporary directory.

The activation probe also supports `drift` (a click with slight pointer movement) and `ax` (an accessible press action). The gesture probe does not install device hooks or require a running app. The alert probe opens test dialogs and only cancels them; it does not delete anything. Grant the terminal or test host the relevant Accessibility, screen capture, and automation permissions for tests that interact with the running app.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Build says `Quit the running Pinchpad before rebuilding...` | Quit Pinchpad from the menu bar first |
| Build says `requires its original signing identity` / `Signing certificate does not match` | The signing directory is missing or was replaced: restore `signing/`, or delete both `Pinchpad.app` and `signing/` and rebuild (a new identity is generated and Accessibility must be granted again) |
| Pinch does not work | Allow Pinchpad under System Settings → Privacy & Security → Accessibility; make sure three/four-finger pinch is enabled in Settings |
| Pinches trigger accidentally or are missed | Settings → Trackpad Gestures → Pinch sensitivity: lower it for accidental triggers, or raise it for missed pinches; adjust each finger count independently |
| Four-finger spread does not show the desktop | Enable Show Desktop under System Settings → Trackpad → More Gestures, and use a current Pinchpad build that passes this gesture through to macOS |
| A confirmation dialog is hidden behind the launcher | Update and rebuild Pinchpad. Current builds attach confirmations as native sheets rather than relying on a manually raised window level |
| No apps in the menu bar section | Grant Pinchpad Accessibility permission, then reopen the clothesline. This section shows third-party apps with menu bar icons, not every running app |
| Shortcut does nothing | The combination may be taken by the system or another app; Settings reports conflicts and you can choose another |
| First open feels slow | One-time cost from the first activation and keyboard focus initialization after login |
| A newly installed app is missing, or an uninstalled app still appears | Wait for installation to finish, check its folder is enabled in Settings → App Sources, then choose Rescan if needed; add a custom source for apps stored elsewhere |
| Want to change the app order | Drag icons, use “Organize App Layout” in Settings → Layout & Organization, or “Import System App Order” in Settings → App Sources |

## Uninstall

1. Quit Pinchpad from the menu bar.
2. Delete `Pinchpad.app`.
3. Delete `~/Library/Application Support/Pinchpad/` (settings, layout, and the signing identity live there).
4. Remove Pinchpad from System Settings → General → Login Items and from Privacy & Security → Accessibility.

## License

Released under the **MIT License**. See [LICENSE](LICENSE).

Copyright (c) 2026 huangsz
