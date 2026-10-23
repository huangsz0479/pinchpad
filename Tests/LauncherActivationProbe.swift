import AppKit
import ApplicationServices

// Run against the signed app. Reopens the app bundle to surface the launcher,
// clicks a real launcher icon, and checks that the target application becomes
// frontmost AND that the launcher window leaves the screen. Also reports
// whether the settings window ("Pinchpad 设置") is visible, since it can be
// confused with the launcher.
// Usage: swift Tests/LauncherActivationProbe.swift <PID> <label> <bundleID> [mouse|drift] [already-open]
guard CommandLine.arguments.count >= 4, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("Usage: LauncherActivationProbe <PID> <label> <bundleID> [mouse|drift] [already-open]\n", stderr)
    exit(2)
}
let label = CommandLine.arguments[2]
let bundleID = CommandLine.arguments[3]
let mode = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "mouse"
let alreadyOpen = CommandLine.arguments.contains("already-open")

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

func position(of element: AXUIElement) -> CGPoint {
    var point = CGPoint.zero
    if let value = attribute(element, kAXPositionAttribute) {
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
    }
    return point
}

struct WindowInfo {
    let number: Int
    let name: String
    let layer: Int
    let bounds: CGRect
}

func pinchpadWindows() -> [WindowInfo] {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.compactMap { dict in
        guard (dict[kCGWindowOwnerPID as String] as? Int32) == pid,
              let number = dict[kCGWindowNumber as String] as? Int else { return nil }
        var bounds = CGRect.zero
        if let b = dict[kCGWindowBounds as String] as? [String: NSNumber] {
            bounds = CGRect(x: b["X"]?.doubleValue ?? 0, y: b["Y"]?.doubleValue ?? 0,
                            width: b["Width"]?.doubleValue ?? 0, height: b["Height"]?.doubleValue ?? 0)
        }
        return WindowInfo(number: number,
                          name: dict[kCGWindowName as String] as? String ?? "",
                          layer: dict[kCGWindowLayer as String] as? Int ?? -999,
                          bounds: bounds)
    }
}

let app = AXUIElementCreateApplication(pid)

func axWindowTitles() -> [String] {
    (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).map {
        attribute($0, kAXTitleAttribute) as? String ?? "<untitled>"
    }
}

func printInventory(_ tag: String) {
    print("--- \(tag) CGWindow inventory (pid \(pid)) ---")
    for w in pinchpadWindows() {
        print("  #\(w.number) name=\(w.name.isEmpty ? "<none>" : w.name) layer=\(w.layer) bounds=\(Int(w.bounds.width))x\(Int(w.bounds.height))@\(Int(w.bounds.origin.x)),\(Int(w.bounds.origin.y))")
    }
    print("--- \(tag) AX window titles: \(axWindowTitles()) ---")
}

func findLauncherAXWindow() -> AXUIElement? {
    (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).first {
        attribute($0, kAXTitleAttribute) as? String == "Pinchpad"
    }
}

func findIcon(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth < 30 else { return nil }
    let names = [kAXDescriptionAttribute, kAXTitleAttribute].compactMap {
        attribute(element, $0) as? String
    }
    if names.contains(label) {
        let iconSize = size(of: element)
        if iconSize.width > 0 && iconSize.height > 0 { return element }
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let match = findIcon(in: child, depth: depth + 1) { return match }
    }
    return nil
}

func dumpAX(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 4) {
    guard depth <= maxDepth else { return }
    let role = attribute(element, kAXRoleAttribute) as? String ?? "?"
    let title = attribute(element, kAXTitleAttribute) as? String
    let desc = attribute(element, kAXDescriptionAttribute) as? String
    let s = size(of: element)
    print("\(String(repeating: "  ", count: depth))\(role) title=\(title ?? "-") desc=\(desc ?? "-") size=\(Int(s.width))x\(Int(s.height))")
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        dumpAX(child, depth: depth + 1, maxDepth: maxDepth)
    }
}

if !alreadyOpen {
    guard let running = NSRunningApplication(processIdentifier: pid),
          let bundleURL = running.bundleURL else {
        fputs("FAIL: cannot resolve bundle path for pid \(pid)\n", stderr)
        exit(1)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [bundleURL.path]
    try? process.run()
    process.waitUntilExit()
    // `open` on a running app delivers a reopen event; give the launcher time
    // to appear before scanning windows.
    usleep(800_000)
}

printInventory("before")

guard let launcher = findLauncherAXWindow() else {
    fputs("FAIL: no AX window titled 'Pinchpad' (launcher not on screen?)\n", stderr)
    print("AX windows: \(axWindowTitles())")
    exit(1)
}

let launcherPos = position(of: launcher)
let launcherSize = size(of: launcher)
// Identify the launcher's CGWindow number by title match first, then by
// geometry; the settings window ("Pinchpad 设置") must never be matched.
func launcherWindowNumber() -> Int? {
    let windows = pinchpadWindows()
    if let named = windows.first(where: { $0.name == "Pinchpad" }) { return named.number }
    return windows.first(where: {
        abs($0.bounds.origin.x - launcherPos.x) < 4
            && abs($0.bounds.origin.y - launcherPos.y) < 4
            && abs($0.bounds.width - launcherSize.width) < 4
            && abs($0.bounds.height - launcherSize.height) < 4
    })?.number
}
guard let windowNumber = launcherWindowNumber() else {
    fputs("FAIL: launcher AX window has no matching onscreen CGWindow\n", stderr)
    exit(1)
}
print("launcher CGWindow number = \(windowNumber)")

var target: AXUIElement?
for _ in 0..<30 {
    usleep(100_000)
    if let icon = findIcon(in: launcher) {
        target = icon
        break
    }
}
guard let icon = target else {
    fputs("FAIL: could not find launcher icon \(label); AX subtree follows\n", stderr)
    dumpAX(launcher)
    exit(1)
}

var point = position(of: icon)
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

let deadline = Date().addingTimeInterval(3)
var lastFront: String?
while Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    lastFront = front
    let visible = pinchpadWindows().contains { $0.number == windowNumber }
    if front == bundleID && !visible {
        printInventory("after")
        print("PASS: target app frontmost and launcher removed from screen")
        exit(0)
    }
}

printInventory("after")
let front = lastFront ?? "unknown"
let launcherStillOnscreen = pinchpadWindows().contains { $0.number == windowNumber }
let settingsVisible = axWindowTitles().contains("Pinchpad 设置")
    || pinchpadWindows().contains { $0.name == "Pinchpad 设置" }
fputs("""
FAIL: label=\(label) bundleID=\(bundleID)
  frontmost=\(front)
  launcherOnscreen=\(launcherStillOnscreen) (window #\(windowNumber))
  settingsVisible=\(settingsVisible)
""", stderr)
exit(1)
