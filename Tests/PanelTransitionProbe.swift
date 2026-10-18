import CoreGraphics
import Foundation

// Run against the already-running, signed Pinchpad.app; this never starts another app.
//
// 面板的渐显/渐隐现在由 AppDelegate 在内容图层上做 CA 动画（纯合成器），窗口 alpha
// 本身不再渐变：打开时窗口 alpha 立即到 1，关闭后回到常驻预热态的 0.01。
// 所以这里验证的是「窗口按时出现/消失」+ 源码里的低开销不变量，而不是窗口 alpha 的逐帧步进。
guard CommandLine.arguments.count == 3, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("Usage: swift PanelTransitionProbe.swift <running Pinchpad PID> <source root>\n", stderr)
    exit(2)
}
let root = URL(fileURLWithPath: CommandLine.arguments[2])

func clickTray() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = [
        "-e",
        "tell application \"System Events\" to tell process \"Pinchpad\" to click (first menu bar item of menu bar 2 whose description is \"Pinchpad\")"
    ]
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "PanelTransitionProbe", code: Int(process.terminationStatus))
    }
}

/// 面板是应用里面积最大的窗口（拖拽浮窗、状态栏项都很小）。
func panelAlpha() -> Double? {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    var best: (area: Double, alpha: Double)?
    for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid {
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let area = (bounds["Width"] as? Double ?? 0) * (bounds["Height"] as? Double ?? 0)
        guard area > 100_000, let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue else { continue }
        if best == nil || area > best!.area { best = (area, alpha) }
    }
    return best?.alpha
}

/// 轮询直到窗口 alpha 满足条件，返回耗时（毫秒）；超时返回 nil。
func waitForAlpha(_ predicate: (Double) -> Bool, timeout: TimeInterval) -> Double? {
    let started = ProcessInfo.processInfo.systemUptime
    while ProcessInfo.processInfo.systemUptime - started < timeout {
        if let alpha = panelAlpha(), predicate(alpha) {
            return (ProcessInfo.processInfo.systemUptime - started) * 1_000
        }
        usleep(4_000)
    }
    return nil
}

func assertSource(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw NSError(domain: "PanelTransitionProbe", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

var testing = false
do {
    let view = try String(contentsOf: root.appendingPathComponent("Sources/PinchpadView.swift"), encoding: .utf8)
    let app = try String(contentsOf: root.appendingPathComponent("Sources/AppMain.swift"), encoding: .utf8)
    let model = try String(contentsOf: root.appendingPathComponent("Sources/AppModel.swift"), encoding: .utf8)

    // 渐显必须走内容图层上的合成器动画，窗口模式下才允许窗口 alpha 动画。
    try assertSource(app.contains("CABasicAnimation(keyPath: \"opacity\")"),
                     "Full-screen panel fade must use a compositor-only layer animation")
    try assertSource(app.contains("panel.animator().alphaValue"),
                     "Windowed mode should keep the window-level fade")
    // 入场波纹必须延后到淡入完成，不能在渐显窗口里跑 SwiftUI 属性动画。
    try assertSource(model.contains("func beginEntrance()"),
                     "Entrance ripple must be triggered after the fade completes")
    try assertSource(!model.contains("bloomID += 1"),
                     "open() must not start the bloom inside the fade window")
    try assertSource(!view.contains("searchSettled"),
                     "Per-frame search-field slide animation must stay removed")
    try assertSource(!view.contains(".opacity(revealed ? 1 : 0)")
                     && !view.contains(".scaleEffect(revealed ? 1 : 1.16"),
                     "Full-grid fade/scale animation must not come back")
    // 布局必须幂等：不能在渐显前对全屏窗口重复 setFrame。
    try assertSource(app.contains("if panel.frame != target"),
                     "layout() must skip redundant setFrame calls")
    try assertSource(app.contains("private func rebuildAuroraIfNeeded()"),
                     "Aurora rebuilding should be guarded by a size/backdrop check")
    try assertSource(app.contains("guard !auroraBuilt || size != auroraBuiltSize"),
                     "Aurora must not be rebuilt on every open")

    let binary = root.deletingLastPathComponent().appendingPathComponent("Pinchpad.app/Contents/MacOS/Pinchpad")
    let built = try binary.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
    for file in ["AppMain.swift", "AppModel.swift", "PinchpadView.swift"] {
        let source = root.appendingPathComponent("Sources/\(file)")
        let edited = try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        try assertSource(built >= edited, "Running app predates \(file)")
    }

    if let alpha = panelAlpha(), alpha > 0.02 {
        try clickTray()
        usleep(500_000)
    }
    testing = true

    // 打开：先量窗口从不可见到可见的延迟，再确认它最终完全显示。
    let openStart = ProcessInfo.processInfo.systemUptime
    try clickTray()
    guard waitForAlpha({ $0 > 0.9 }, timeout: 0.6) != nil else {
        throw NSError(domain: "PanelTransitionProbe", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Panel never became visible"])
    }
    let openLatency = (ProcessInfo.processInfo.systemUptime - openStart) * 1_000
    // 内容入场波纹约 0.45s 结束，然后才验证关闭。
    usleep(700_000)

    let closeStart = ProcessInfo.processInfo.systemUptime
    try clickTray()
    guard waitForAlpha({ $0 <= 0.02 }, timeout: 0.6) != nil else {
        throw NSError(domain: "PanelTransitionProbe", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "Panel remained visible after closing"])
    }
    let closeLatency = (ProcessInfo.processInfo.systemUptime - closeStart) * 1_000

    try assertSource(openLatency < 450, "Panel open took \(Int(openLatency))ms")
    try assertSource(closeLatency < 450, "Panel close took \(Int(closeLatency))ms")
    print("open: visible in \(Int(openLatency))ms, close: hidden in \(Int(closeLatency))ms")
    print("PASS: running Pinchpad opens/closes with compositor-only fades")
} catch {
    if testing, let alpha = panelAlpha(), alpha > 0.02 { try? clickTray() }
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
