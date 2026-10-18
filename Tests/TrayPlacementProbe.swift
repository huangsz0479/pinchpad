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
        && bounds["Width"]?.intValue == 332
        && (bounds["Height"]?.intValue ?? 0) > 100
}), let bounds = tray[kCGWindowBounds as String] as? [String: NSNumber],
   let x = bounds["X"]?.doubleValue, let y = bounds["Y"]?.doubleValue,
   let height = bounds["Height"]?.doubleValue else {
    fputs("FAIL: open the tray before running the probe\n", stderr)
    exit(1)
}
let frame = NSRect(x: x, y: primaryScreen.frame.maxY - y - height, width: 332, height: height)
guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }) else {
    fputs("FAIL: tray is outside all screens\n", stderr)
    exit(1)
}
let menuBottom = min(screen.visibleFrame.maxY,
                     screen.frame.maxY - max(NSStatusBar.system.thickness, screen.safeAreaInsets.top))
let gap = menuBottom - frame.maxY
let expectedGap = 2 / screen.backingScaleFactor
let level = (tray[kCGWindowLayer as String] as? Int) ?? Int.max
print("menu-bar gap: \(gap)pt; tray level: \(level); menu level: \(NSWindow.Level.mainMenu.rawValue)")
guard abs(gap - expectedGap) < 0.01, level < NSWindow.Level.mainMenu.rawValue else {
    fputs("FAIL: tray must sit exactly 2 screen pixels below the menu bar and below its window level\n", stderr)
    exit(1)
}
print("PASS: tray does not cover the menu bar")
