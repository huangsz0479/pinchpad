import AppKit
import ApplicationServices

// Run against the signed app. This clicks a real tray icon and checks that its
// application becomes frontmost and that the tray panel is dismissed,
// including reopening an already-running app.
// Usage: swift Tests/TrayActivationProbe.swift <PID> <label> <bundleID> [mouse|drift|ax]
guard CommandLine.arguments.count >= 4, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("Usage: TrayActivationProbe <PID> <label> <bundleID> [mouse|drift|ax]\n", stderr)
    exit(2)
}
let label = CommandLine.arguments[2]
let bundleID = CommandLine.arguments[3]
let mode = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "mouse"

func trayIsVisible() -> Bool {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains {
        let bounds = $0[kCGWindowBounds as String] as? [String: NSNumber] ?? [:]
        return ($0[kCGWindowOwnerPID as String] as? Int32) == pid
            && ($0[kCGWindowLayer as String] as? Int) == NSWindow.Level.mainMenu.rawValue - 1
            && (bounds["Height"]?.intValue ?? 0) > 100
    }
}

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, key as CFString, &value)
    return value
}

func size(of element: AXUIElement) -> CGSize {
    var size = CGSize.zero
    if let value = attribute(element, kAXSizeAttribute) {
        AXValueGetValue(value as! AXValue, .cgSize, &size)
    }
    return size
}

func findIcon(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth < 20 else { return nil }
    let role = attribute(element, kAXRoleAttribute) as? String
    let names = [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute].compactMap {
        attribute(element, $0) as? String
    }
    if (role == kAXButtonRole || role == kAXImageRole), names.contains(label) { return element }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let match = findIcon(in: child, depth: depth + 1) { return match }
    }
    return nil
}

let app = AXUIElementCreateApplication(pid)
let trayVisible = trayIsVisible()
if !trayVisible {
    guard let bar = attribute(app, "AXExtrasMenuBar"),
          let item = (attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement])?.first,
          AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
        fputs("FAIL: cannot open the tray\n", stderr)
        exit(1)
    }
}
// Wait for the initial app discovery and window-resize animation before
// taking screen coordinates; AX may briefly expose the previous layout.
usleep(500_000)
var target: AXUIElement?
for _ in 0..<30 {
    usleep(100_000)
    let windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [])
        + (attribute(app, kAXChildrenAttribute) as? [AXUIElement] ?? [])
    if let tray = windows.first(where: {
        let windowSize = size(of: $0)
        return windowSize.width <= 460 && windowSize.height > 100
    }),
       let icon = findIcon(in: tray) {
        target = icon
        break
    }
}
guard let icon = target else {
    fputs("FAIL: could not find tray icon \(label)\n", stderr)
    exit(1)
}

if mode == "ax" {
    guard AXUIElementPerformAction(icon, kAXPressAction as CFString) == .success else {
        fputs("FAIL: icon has no accessible press action\n", stderr)
        exit(1)
    }
} else {
    var point = CGPoint.zero
    guard let value = attribute(icon, kAXPositionAttribute),
          AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
        fputs("FAIL: cannot read icon position\n", stderr)
        exit(1)
    }
    let iconSize = size(of: icon)
    point.x += iconSize.width / 2
    point.y += iconSize.height / 2
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(80_000)
    if mode == "drift" {
        point.x += 3
        point.y += 2
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(30_000)
    }
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}
let deadline = Date().addingTimeInterval(8)
while Date() < deadline {
    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
        // Let the tray finish closing and ensure it does not steal focus back.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
            && !trayIsVisible() {
            print("PASS: \(mode) click on \(label) opened \(bundleID)")
            exit(0)
        }
    }
    // NSWorkspace updates its frontmost-app cache via run-loop notifications.
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
fputs("FAIL: \(label) did not open or tray stayed visible; frontmost is \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"), trayIsVisible=\(trayIsVisible())\n", stderr)
exit(1)
