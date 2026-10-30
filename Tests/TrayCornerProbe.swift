import AppKit

// Open the tray first, then run: swift Tests/TrayCornerProbe.swift <Pinchpad PID>
guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    fatalError("Usage: swift Tests/TrayCornerProbe.swift <Pinchpad PID>")
}

let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
guard let tray = windows.first(where: {
    let bounds = $0[kCGWindowBounds as String] as? [String: NSNumber] ?? [:]
    return ($0[kCGWindowOwnerPID as String] as? Int32) == pid
        && ($0[kCGWindowLayer as String] as? Int) == NSWindow.Level.mainMenu.rawValue - 1
        && (bounds["Height"]?.intValue ?? 0) > 100
}), let number = tray[kCGWindowNumber as String] as? Int else {
    fatalError("Open the Pinchpad tray before running the probe")
}

let captureURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("pinchpad-corners-\(UUID().uuidString).png")
defer { try? FileManager.default.removeItem(at: captureURL) }
let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
// Exclude the system's external window shadow: this checks the surface itself.
capture.arguments = ["-x", "-o", "-l", "\(number)", captureURL.path]
try capture.run()
capture.waitUntilExit()
guard capture.terminationStatus == 0,
      let bitmap = NSBitmapImageRep(data: try Data(contentsOf: captureURL)) else {
    fatalError("Could not capture tray window")
}

let w = bitmap.pixelsWide
let h = bitmap.pixelsHigh
for (name, x, y) in [
    ("top-left", 1, 1), ("top-right", w - 2, 1),
    ("bottom-left", 1, h - 2), ("bottom-right", w - 2, h - 2)
] {
    let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
    print("\(name): alpha=\(alpha)")
    guard alpha < 0.01 else {
        fatalError("Nontransparent pixels outside the rounded \(name) corner")
    }
}
// The center now lies in the transparent gap between independent controls.
let hasContent = stride(from: 2, to: h - 2, by: max(1, h / 40)).contains { y in
    stride(from: 2, to: w - 2, by: max(1, w / 40)).contains { x in
        bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.5
    }
}
guard hasContent else {
    fatalError("Window is empty; cannot validate its corners")
}
print("PASS: all four outer corners are transparent")
