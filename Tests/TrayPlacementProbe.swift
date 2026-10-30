import AppKit

// Open the tray, then run: swift Tests/TrayPlacementProbe.swift <Pinchpad PID>
guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]),
      let primaryScreen = NSScreen.screens.first else {
    fputs("Usage: swift Tests/TrayPlacementProbe.swift <Pinchpad PID>\n", stderr)
    exit(2)
}
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
guard let tray = windows.first(where: {
    let bounds = $0[kCGWindowBounds as String] as? [String: NSNumber] ?? [:]
    return ($0[kCGWindowOwnerPID as String] as? Int32) == pid
        && ($0[kCGWindowLayer as String] as? Int) == NSWindow.Level.mainMenu.rawValue - 1
        && (bounds["Height"]?.intValue ?? 0) > 100
}), let bounds = tray[kCGWindowBounds as String] as? [String: NSNumber],
   let x = bounds["X"]?.doubleValue, let y = bounds["Y"]?.doubleValue,
   let width = bounds["Width"]?.doubleValue,
   let height = bounds["Height"]?.doubleValue else {
    fputs("FAIL: open the tray before running the probe\n", stderr)
    exit(1)
}
let frame = NSRect(x: x, y: primaryScreen.frame.maxY - y - height, width: width, height: height)
guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }) else {
    fputs("FAIL: tray is outside all screens\n", stderr)
    exit(1)
}
let menuBottom = min(screen.visibleFrame.maxY,
                     screen.frame.maxY - max(NSStatusBar.system.thickness, screen.safeAreaInsets.top))
let gap = menuBottom - frame.maxY
let expectedGap: CGFloat = 8
let expectedWidth = min(360, max(1, screen.visibleFrame.width - 24))
let bottomGap = frame.minY - screen.visibleFrame.minY
let level = (tray[kCGWindowLayer as String] as? Int) ?? Int.max
print("menu-bar gap: \(gap)pt; bottom gap: \(bottomGap)pt; width: \(width)pt; tray level: \(level)")
guard abs(gap - expectedGap) < 0.01, bottomGap >= 12 - 0.01,
      abs(width - expectedWidth) < 0.01, height <= 600,
      level < NSWindow.Level.mainMenu.rawValue else {
    fputs("FAIL: compact tray must be 360pt wide (or fit the screen), start 8pt below the menu bar, remain at most 600pt high, and keep 12pt above the usable screen bottom\n", stderr)
    exit(1)
}
print("PASS: compact tray stays within the usable screen without covering the menu bar or Dock")
