"""Replay organizer opening with delayed, in-memory menu-bar discovery.

The scheduling methods are extracted from the real AppDelegate and AppModel.
Only external dependencies are replaced: fixture process metadata, deterministic
menu inspection, and pure recording panel/animation objects. The probe never
queries AX elements, reads user windows, orders a native window, or posts input.
Run: python3 Tests/TrayOpeningProbe.py
"""

from pathlib import Path
import subprocess
import tempfile


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


root = Path(__file__).resolve().parents[1]
app = (root / "Sources/AppMain.swift").read_text()
model = (root / "Sources/AppModel.swift").read_text()
view = (root / "Sources/TrayView.swift").read_text()
delegate_methods = "\n".join(block(app, marker) for marker in (
    "func dismissTray(", "private func showTray()",
))
delegate_methods = delegate_methods.replace("func dismissTray()", "func dismissTray(animated: Bool = true)")
open_running = block(view, "private func openApplication()")
refresh = block(model, "func refreshRunningApps()")
filtering = block(model, "private func userFacing(_ app: NSRunningApplication)")
press = block(model, "func pressMenuBarItem()")
state = "\n".join(line for line in model.splitlines()
                  if line.strip().startswith("private var runningAppsRefresh"))
# Allow the old synchronous implementation to reproduce the scheduling failure.
if not state:
    state = "private var runningAppsRefreshTask: Task<Void, Never>?\nprivate var runningAppsRefreshGeneration = 0"

harness = r'''import Combine
import CoreFoundation
import Darwin
import Foundation

// In-memory domain doubles, never native AppKit or accessibility objects.
enum ActivationPolicy { case regular, accessory, prohibited }
final class NSRunningApplication {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let bundleURL: URL?
    var activationPolicy: ActivationPolicy = .accessory
    var isTerminated = false
    init(_ pid: pid_t, _ name: String, bundleID: String? = nil, path: String? = nil) {
        processIdentifier = pid
        bundleIdentifier = bundleID ?? "fixture.\(name)"
        localizedName = name
        bundleURL = URL(fileURLWithPath: path ?? "/fixture/\(name).app")
    }
}

@MainActor
final class NSWorkspace {
    static let shared = NSWorkspace()
    var runningApplications: [NSRunningApplication] = []
    var accessibilityDisplayShouldReduceMotion = false
}

final class MenuItem {
    let pid: pid_t
    var presses = 0
    init(_ pid: pid_t) { self.pid = pid }
}
typealias AXUIElement = MenuItem
enum AXError { case success }
let kAXPressAction = "AXPress"
func AXUIElementPerformAction(_ item: AXUIElement, _ action: CFString) -> AXError {
    item.presses += 1
    return .success
}

struct RunningApp {
    let application: NSRunningApplication
    let menuBarItem: AXUIElement
    let menuBarX: CGFloat
''' + press + r'''
    @MainActor func open() {
        LaunchRecorder.requests += 1
        LaunchRecorder.openedWhileVisible = LaunchRecorder.panel?.isVisible == true
        Thread.sleep(forTimeInterval: 0.06)
    }
}

@MainActor enum LaunchRecorder {
    static var requests = 0
    static var panel: TrayPanel?
    static var openedWhileVisible = false
}

@MainActor struct RunningCell {
    var app: RunningApp
    var onClose: () -> Void
    var canOpen: () -> Bool = { true }
''' + open_running + r'''
    func probeOpen() { openApplication() }
}

struct CatalogApp { var hidden = false }

enum ProbeDiscovery {
    struct Plan {
        let delay: TimeInterval
        let x: CGFloat
        let item: AXUIElement
    }
    private static let lock = NSLock()
    private static var plans: [pid_t: Plan] = [:]
    private static var begun: [pid_t: Int] = [:]
    private static var completed: [pid_t: Int] = [:]
    private static var active = 0
    private static var maximumActive = 0
    private static var inspectedOnMain = false
    static func configure(_ pid: pid_t, delay: TimeInterval, x: CGFloat) {
        lock.lock()
        plans[pid] = Plan(delay: delay, x: x, item: MenuItem(pid))
        lock.unlock()
    }
    static func count(_ pid: pid_t) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return begun[pid, default: 0]
    }
    static func item(_ pid: pid_t) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        return plans[pid]?.item
    }
    static var maxConcurrent: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumActive
    }
    static var usedMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inspectedOnMain
    }
    static func inspect(_ pid: pid_t) -> (item: AXUIElement, x: CGFloat)? {
        lock.lock()
        let plan = plans[pid]
        begun[pid, default: 0] += 1
        active += 1
        maximumActive = max(maximumActive, active)
        inspectedOnMain = inspectedOnMain || Thread.isMainThread
        lock.unlock()
        if let plan { Thread.sleep(forTimeInterval: plan.delay) }
        lock.lock()
        active -= 1
        completed[pid, default: 0] += 1
        lock.unlock()
        return plan.map { ($0.item, $0.x) }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var runningApps: [RunningApp] = []
''' + state + r'''
    var hiddenBundleIDs: Set<String> = []
    func catalogApp(bundleID: String) -> CatalogApp? {
        hiddenBundleIDs.contains(bundleID) ? CatalogApp(hidden: true) : nil
    }
    private nonisolated static func menuBarItem(processID: pid_t) -> (item: AXUIElement, x: CGFloat)? {
        ProbeDiscovery.inspect(processID)
    }
    // Legacy overload lets this probe go red on the original synchronous route.
    private func menuBarItem(of app: NSRunningApplication) -> (item: AXUIElement, x: CGFloat)? {
        Self.menuBarItem(processID: app.processIdentifier)
    }
''' + filtering + "\n" + refresh + r'''
    var probeIsRefreshing: Bool { runningAppsRefreshTask != nil }
    var probeGeneration: Int { runningAppsRefreshGeneration }
}

final class ProbeWindow {}
final class ProbeButton { var window: ProbeWindow? = ProbeWindow() }
final class ProbeStatusItem { var button: ProbeButton? = ProbeButton() }

final class TrayPanel {
    var alphaValue: CGFloat = 1
    var isKeyWindow = false
    var isVisible = false
    var orderedAt: [TimeInterval] = []
    func animator() -> TrayPanel { self }
    func makeKeyAndOrderFront(_ sender: Any?) {
        orderedAt.append(ProcessInfo.processInfo.systemUptime)
        isVisible = true
        isKeyWindow = true
    }
    func resignKey() { isKeyWindow = false }
    func orderOut(_ sender: Any?) { isVisible = false }
}

enum TimingName { case easeIn, easeOut }
final class CAMediaTimingFunction { init(name: TimingName) {} }
final class NSAnimationContext {
    var duration: TimeInterval = 0
    var timingFunction: CAMediaTimingFunction?
    static var durations: [TimeInterval] = []
    static func runAnimationGroup(_ body: (NSAnimationContext) -> Void, completionHandler: (() -> Void)? = nil) {
        let context = NSAnimationContext()
        body(context)
        durations.append(context.duration)
        completionHandler?()
    }
}

@MainActor
final class AppDelegate {
    var statusItem: ProbeStatusItem? = ProbeStatusItem()
    var trayPanel: TrayPanel?
    var trayToken = 0
    var trayShown = false
    var monitorCount = 0
    func ensureTrayPanel() -> TrayPanel {
        if let trayPanel { return trayPanel }
        let panel = TrayPanel()
        trayPanel = panel
        return panel
    }
    func installTrayMonitor() { monitorCount = 1 }
    func removeTrayMonitor() { monitorCount = 0 }
    func layoutTray() {}
    var revealActive = false
    func animateTrayReveal() { revealActive = true }
    func resetTrayReveal() { revealActive = false }
''' + delegate_methods + r'''
    func probeOpen() { showTray() }
}

@main
struct TrayOpeningProbe {
    @MainActor
    static func main() {
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        @discardableResult
        func wait(_ seconds: TimeInterval = 1.5, until condition: () -> Bool) -> Bool {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            repeat {
                if condition() { return true }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
            } while ProcessInfo.processInfo.systemUptime < deadline
            return condition()
        }
        let model = AppModel.shared
        func ids() -> [pid_t] { model.runningApps.map { $0.application.processIdentifier } }
        var history: [[pid_t]] = []
        let subscription = model.$runningApps.sink { history.append($0.map { $0.application.processIdentifier }) }
        defer { subscription.cancel() }
        let alpha = NSRunningApplication(1, "Alpha")
        let beta = NSRunningApplication(2, "Beta")
        let duplicateAlpha = NSRunningApplication(3, "AlphaDuplicate", bundleID: alpha.bundleIdentifier)
        NSWorkspace.shared.runningApplications = [alpha, beta, duplicateAlpha]
        ProbeDiscovery.configure(1, delay: 0.08, x: 200)
        ProbeDiscovery.configure(2, delay: 0.08, x: 100)
        let delegate = AppDelegate()
        var heartbeatAt: TimeInterval?
        let started = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
            heartbeatAt = ProcessInfo.processInfo.systemUptime
        }
        delegate.statusItem = nil
        delegate.probeOpen()
        let returned = ProcessInfo.processInfo.systemUptime
        let ordered = delegate.trayPanel?.orderedAt.first ?? returned
        let revealMS = (ordered - started) * 1_000
        let returnMS = (returned - started) * 1_000
        print(String(format: "organizer order latency with 160 ms fixture discovery: %.2f ms", revealMS))
        print(String(format: "organizer open call main-thread time: %.2f ms", returnMS))
        require(revealMS < 40, "Menu-bar discovery blocks organizer reveal (\(Int(revealMS)) ms; limit 40 ms)")
        require(returnMS < 40, "Menu-bar discovery blocks the main thread (\(Int(returnMS)) ms; limit 40 ms)")
        require(delegate.trayShown && delegate.trayPanel?.isVisible == true && delegate.monitorCount == 1,
                "Opening does not reveal the organizer and install its dismissal monitor")
        require(delegate.revealActive, "Ordinary opening must animate the retained glass surface")
        require(wait(0.04) { heartbeatAt != nil }, "Main-thread heartbeat stalls behind menu discovery")
        let heartbeatMS = ((heartbeatAt ?? ProcessInfo.processInfo.systemUptime) - started) * 1_000
        print(String(format: "main-thread heartbeat during discovery: %.2f ms", heartbeatMS))
        require(heartbeatMS < 60, "Menu inspection delays main-thread heartbeat")
        require(wait { !model.probeIsRefreshing && ids() == [2, 1] },
                "Discovery loses applications or their menu-bar left-to-right order")
        require(!ProbeDiscovery.usedMainThread, "Menu inspection still runs on the main thread")
        require(ProbeDiscovery.count(3) == 0, "Duplicate bundle identifiers reach menu inspection")
        require(model.runningApps.allSatisfy {
            $0.menuBarItem.pid == $0.application.processIdentifier
                && $0.menuBarItem === ProbeDiscovery.item($0.application.processIdentifier)
        }, "Discovery loses fresh menu elements needed by Open Menu")
        if let entry = model.runningApps.first {
            require(entry.pressMenuBarItem() && entry.menuBarItem.presses == 1,
                    "Open Menu no longer presses the discovery result's matching element")
        }
        delegate.dismissTray()
        require(wait(0.1) { !delegate.trayShown && delegate.trayPanel?.isVisible == false && delegate.monitorCount == 0 },
                "Dismissal leaves the organizer or its monitor active")
        require(!delegate.revealActive, "Dismissal leaves an unfinished reveal transform attached")
        print("PASS: organizer reveals and main-thread heartbeat runs before delayed discovery finishes")

        // Eligible cached entries stay usable until a new menu snapshot is ready.
        let cachedItems = model.runningApps.map(\.menuBarItem)
        ProbeDiscovery.configure(1, delay: 0.06, x: 50)
        ProbeDiscovery.configure(2, delay: 0.06, x: 100)
        model.refreshRunningApps()
        require(ids() == [2, 1] && model.runningApps.map(\.menuBarItem).elementsEqual(cachedItems, by: ===),
                "Refreshing clears or replaces eligible cached menus before discovery completes")
        require(wait { !model.probeIsRefreshing && ids() == [1, 2] }, "Refreshed menu positions never replace the cache")
        require(model.runningApps.allSatisfy { $0.menuBarItem === ProbeDiscovery.item($0.application.processIdentifier) },
                "A completed refresh retains old menu handles instead of fresh discovery results")
        print("PASS: cached menus remain usable and completed refresh replaces positions and handles")

        // Overlapping notifications coalesce behind one active inspection batch.
        let slow = NSRunningApplication(11, "Stale")
        let skipped = NSRunningApplication(22, "Skipped")
        let latest = NSRunningApplication(33, "Latest")
        ProbeDiscovery.configure(11, delay: 0.16, x: 150)
        ProbeDiscovery.configure(22, delay: 0.01, x: 140)
        ProbeDiscovery.configure(33, delay: 0.01, x: 80)
        ProbeDiscovery.configure(2, delay: 0.01, x: 100)
        NSWorkspace.shared.runningApplications = [slow, beta]
        let beforeGeneration = model.probeGeneration
        let beforeHistory = history.count
        model.refreshRunningApps()
        require(ids() == [2], "Cached app absent from the current process snapshot is not pruned immediately")
        require(wait(0.2) { ProbeDiscovery.count(11) > 0 }, "Slow overlapping fixture never starts")
        NSWorkspace.shared.runningApplications = [skipped, beta]
        model.refreshRunningApps()
        NSWorkspace.shared.runningApplications = [latest, beta]
        model.refreshRunningApps()
        require(model.probeGeneration == beforeGeneration + 3, "Refresh requests do not advance the stale-result generation")
        require(wait { !model.probeIsRefreshing && ids() == [33, 2] },
                "Coalesced refresh never publishes the latest process snapshot")
        require(model.probeGeneration == beforeGeneration + 4,
                "A stale completed batch does not schedule exactly one latest refresh")
        require(ProbeDiscovery.count(11) == 1 && ProbeDiscovery.count(22) == 0 && ProbeDiscovery.count(33) == 1,
                "Overlapping notifications duplicate work or inspect superseded intermediate snapshots")
        require(!history.dropFirst(beforeHistory).contains { $0.contains(11) || $0.contains(22) },
                "Stale or superseded menu results are published before the latest snapshot")
        require(ProbeDiscovery.maxConcurrent == 1, "Menu inspection batches overlap instead of using one worker")
        print("PASS: one discovery worker coalesces refreshes and rejects stale generations")

        // Cache pruning happens synchronously, without waiting on another AX batch.
        model.hiddenBundleIDs.insert(latest.bundleIdentifier!)
        beta.isTerminated = true
        let hidden = NSRunningApplication(44, "Hidden")
        let terminated = NSRunningApplication(55, "Terminated")
        let system = NSRunningApplication(66, "System", path: "/System/Applications/System.app")
        let duplicate = NSRunningApplication(77, "LatestDuplicate", bundleID: latest.bundleIdentifier)
        let prohibited = NSRunningApplication(88, "Prohibited")
        model.hiddenBundleIDs.insert(hidden.bundleIdentifier!)
        terminated.isTerminated = true
        prohibited.activationPolicy = .prohibited
        NSWorkspace.shared.runningApplications = [latest, beta, hidden, terminated, system, duplicate, prohibited]
        model.refreshRunningApps()
        require(model.runningApps.isEmpty, "Hidden or terminated cached applications remain visible during discovery")
        require(wait { !model.probeIsRefreshing }, "Empty eligible process snapshot never finishes")
        require([44, 55, 66, 77, 88].allSatisfy { ProbeDiscovery.count(pid_t($0)) == 0 },
                "Hidden, terminated, duplicate-hidden, system or prohibited processes reach menu inspection")
        print("PASS: hidden, terminated and ineligible processes are pruned before discovery")

        // An app can become ineligible after the snapshot without another refresh.
        let hiddenDuringQuery = NSRunningApplication(99, "HiddenDuringQuery")
        let terminatedDuringQuery = NSRunningApplication(100, "TerminatedDuringQuery")
        ProbeDiscovery.configure(99, delay: 0.08, x: 200)
        ProbeDiscovery.configure(100, delay: 0.01, x: 100)
        NSWorkspace.shared.runningApplications = [hiddenDuringQuery, terminatedDuringQuery]
        model.refreshRunningApps()
        require(wait(0.2) { ProbeDiscovery.count(99) > 0 }, "Eligibility revalidation fixture never starts")
        model.hiddenBundleIDs.insert(hiddenDuringQuery.bundleIdentifier!)
        terminatedDuringQuery.isTerminated = true
        require(wait { !model.probeIsRefreshing }, "Eligibility revalidation fixture never finishes")
        require(model.runningApps.isEmpty, "Completed discovery resurrects newly hidden or terminated apps")
        print("PASS: completed snapshots revalidate applications before publishing menu handles")

        // A queued close completion must not hide a newly reopened organizer.
        beta.isTerminated = false
        NSWorkspace.shared.runningApplications = [beta]
        ProbeDiscovery.configure(2, delay: 0.12, x: 100)
        let retainedPanel = delegate.trayPanel
        let betaCount = ProbeDiscovery.count(2)
        delegate.probeOpen()
        require(wait(0.2) { ProbeDiscovery.count(2) > betaCount }, "Close/reopen fixture never starts discovery")
        delegate.dismissTray()
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = true
        let reopenStarted = ProcessInfo.processInfo.systemUptime
        delegate.probeOpen()
        require((ProcessInfo.processInfo.systemUptime - reopenStarted) * 1_000 < 40,
                "Reopening waits for an already running menu discovery")
        require(delegate.trayPanel === retainedPanel, "Reopening recreates the retained organizer panel")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        require(delegate.trayShown && delegate.trayPanel?.isVisible == true && delegate.monitorCount == 1,
                "Stale close completion hides the reopened organizer or removes its monitor")
        require(!delegate.revealActive, "Reduce Motion reopening must not retain the earlier scale animation")
        require(wait { !model.probeIsRefreshing && ids() == [2] },
                "Close/reopen loses the pending latest menu refresh")
        require(delegate.trayShown && delegate.trayPanel?.isVisible == true,
                "Completing menu discovery changes the reopened organizer's visibility")
        delegate.dismissTray()
        require(!delegate.trayShown && delegate.trayPanel?.isVisible == false && delegate.monitorCount == 0,
                "Reduce Motion dismissal leaves the organizer visible")
        print("PASS: close/reopen and Reduce Motion preserve visibility, cache refresh and dismissal")

        let launchFailuresBefore = failures.count
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = false
        delegate.probeOpen()
        LaunchRecorder.panel = delegate.trayPanel
        let animationCount = NSAnimationContext.durations.count
        let cell = RunningCell(app: RunningApp(application: beta, menuBarItem: MenuItem(2), menuBarX: 100),
                               onClose: { delegate.dismissTray(animated: false) })
        let launchStarted = ProcessInfo.processInfo.systemUptime
        cell.probeOpen()
        let launchMS = (ProcessInfo.processInfo.systemUptime - launchStarted) * 1_000
        print(String(format: "organizer launch callback with 60 ms fixture open: %.3f ms", launchMS))
        require(!delegate.trayShown && delegate.trayPanel?.isVisible == false
                && delegate.trayPanel?.isKeyWindow == false && delegate.monitorCount == 0,
                "Launching leaves the organizer visible or capturing input")
        require(NSAnimationContext.durations.count == animationCount,
                "Launching waits for an organizer closing animation")
        require(LaunchRecorder.requests == 0 && launchMS < 20,
                "Organizer application open blocks the dismissal main-loop turn")
        require(wait { LaunchRecorder.requests == 1 } && !LaunchRecorder.openedWhileVisible,
                "Organizer open request did not follow its immediate dismissal")
        delegate.probeOpen()
        delegate.dismissTray()
        require(NSAnimationContext.durations.last == 0.1,
                "Ordinary organizer dismissal lost its animation")
        require(wait { delegate.trayPanel?.isVisible == false }, "Final fixture dismissal did not finish")
        if failures.count == launchFailuresBefore {
            print("PASS: organizer launch dismisses immediately, defers opening, and retains ordinary close animation")
        }
        if failures.isEmpty {
            print("PASS: organizer opening scheduling and menu discovery regressions")
        } else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="pinchpad-tray-opening-") as directory_name:
    directory = Path(directory_name)
    source = directory / "TrayOpeningProbe.swift"
    source.write_text(harness)
    binary = directory / "TrayOpeningProbe"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library", "-O",
        "-module-cache-path", "/tmp/pinchpad-probe-module-cache",
        str(source), "-o", str(binary),
    ], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
