"""Replay production lifecycle and event routing with in-memory platform doubles.

No native windows, event taps, running application discovery or AX queries.
The methods under test are extracted unchanged from ClotheslineController.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


controller = (root / 'Sources/ClotheslineController.swift').read_text()
model = (root / 'Sources/Model.swift').read_text()
methods = '\n'.join(block(controller, marker) for marker in [
    'func show()', 'func dismiss(', 'func screenParametersChanged()',
    'private var reduceMotion:', 'private func canHandlePointer()', 'private func dismissFromPointer()',
    'private func scheduleRefresh()', 'private func refreshContent()', 'private func positions()', 'private func startMovement()',
    'private func resumeDisplayLink()', '@objc private func displayFrame(', 'private func stopDisplayLink()',
    'private func cancelMovement()', 'private func turnPage(', 'private func installMonitors()',
    'private func handlePointer(', 'private func finishPointer()', 'func handleShortcut(', 'private func handleKey(', 'private func selectApp(', 'private func openSelectedApp()', 'private func removeMonitors()',
    '@objc private func menuBegan(', '@objc private func menuEnded(', '@objc private func accessibilityChanged()',
]).replace('private func displayFrame(', 'func displayFrame(')
fields = controller[controller.index('    private let model:'):controller.index('    init(model:')]
source = r'''import Foundation
import Combine
import CoreGraphics

struct RunningApp {
    let id: String
    var placementKey: String { id }
    var size: TrayAppSize = .medium
    static var onOpen: ((String) -> Void)?
    func open() { Self.onOpen?(id) }
}
struct Insets { var top: CGFloat = 32 }
typealias NSDeviceDescriptionKey = String
final class NSScreen: NSObject {
    static var screens = [NSScreen()]
    var frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    var visibleFrame = CGRect(x: 0, y: 48, width: 1440, height: 820)
    var safeAreaInsets = Insets()
    var maximumFramesPerSecond = 120
    var deviceDescription: [String: Any] = ["NSScreenNumber": NSNumber(value: 1)]
}
final class NSStatusBar { static let system = NSStatusBar(); let thickness: CGFloat = 25 }
enum EffectState { case active, inactive }
final class NSVisualEffectView { var state = EffectState.inactive }
struct CAFrameRateRange { var minimum: Float; var maximum: Float; var preferred: Float }
final class CADisplayLink: NSObject {
    static var active: [CADisplayLink] = []
    var targetTimestamp: TimeInterval = 0
    var preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
    var callback: ((CADisplayLink) -> Void)?
    func add(to loop: RunLoop, forMode mode: RunLoop.Mode) { Self.active.append(self) }
    func invalidate() { Self.active.removeAll { $0 === self }; callback = nil }
    static func step() { for link in active { link.targetTimestamp += 1.0 / 120; link.callback?(link) } }
}
final class NSPanel {
    var frame = CGRect.zero
    var ignoresMouseEvents = true
    var contentView: Any? = NSVisualEffectView()
    var alphaValue: CGFloat = 1
    var isVisible = false
    var isKeyWindow = false
    func setFrame(_ frame: CGRect, display: Bool) { self.frame = frame }
    func resignKey() { isKeyWindow = false }
    func makeKeyAndOrderFront(_ sender: Any?) { isVisible = true; isKeyWindow = true }
    func animator() -> NSPanel { self }
    func convertPoint(fromScreen point: CGPoint) -> CGPoint { point }
    @MainActor func displayLink(target: ClotheslineController, selector: Selector) -> CADisplayLink {
        let link = CADisplayLink()
        link.callback = { [weak target] in target?.displayFrame($0) }
        return link
    }
}
final class NSAnimationContext {
    var duration = 0.0
    static func runAnimationGroup(_ body: (NSAnimationContext) -> Void, completionHandler: (() -> Void)? = nil) {
        let context = NSAnimationContext()
        body(context)
        if let completionHandler { DispatchQueue.main.asyncAfter(deadline: .now() + context.duration, execute: completionHandler) }
    }
}
struct Animation { static func easeOut(duration: TimeInterval) -> Animation { Animation() } }
func withAnimation(_ animation: Animation, _ body: () -> Void) { body() }
final class NSWorkspace {
    static let shared = NSWorkspace()
    var accessibilityDisplayShouldReduceMotion = false
}
final class PinchMonitor {
    static let shared = PinchMonitor()
    var guardedUntil = Date.distantPast
    func pinchPointerGuardUntil() -> Date { guardedUntil }
}
enum LauncherPanelVisibility {
    static func suspend(_ panel: NSPanel) {
        panel.isVisible = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 1
        (panel.contentView as? NSVisualEffectView)?.state = .inactive
    }
}
final class NSMenu: NSObject {}
final class NSEvent {
    enum Kind { case keyDown, flagsChanged, systemDefined, leftMouseDown, leftMouseDragged, leftMouseUp, rightMouseDown }
    static var locals: [UUID: (NSEvent) -> NSEvent?] = [:]
    static var globals: [UUID: (NSEvent) -> Void] = [:]
    static var mouseLocation = CGPoint.zero
    var locationInWindow = CGPoint.zero
    let type: Kind
    let keyCode: UInt16
    var window: NSPanel?
    init(_ type: Kind, keyCode: UInt16 = 0, window: NSPanel? = nil) {
        self.type = type; self.keyCode = keyCode; self.window = window
    }
    static func addLocalMonitorForEvents(matching: [Kind], handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        let token = UUID(); locals[token] = handler; return token
    }
    static func addGlobalMonitorForEvents(matching: [Kind], handler: @escaping (NSEvent) -> Void) -> Any? {
        let token = UUID(); globals[token] = handler; return token
    }
    static func removeMonitor(_ token: Any) { locals[token as! UUID] = nil; globals[token as! UUID] = nil }
    static func local(_ event: NSEvent) -> NSEvent? {
        guard let handler = Array(locals.values).first else { return event }
        return handler(event)
    }
    static func global(_ event: NSEvent) { Array(globals.values).forEach { $0(event) } }
}
extension CardNavigationShortcuts {
    static func code(from event: NSEvent) -> UInt16? { accepts(event.keyCode) ? event.keyCode : nil }
}
struct Preferences {
    var cardNavigation = CardNavigationShortcuts()
    var clotheslinePositions: [String: ClotheslinePosition] = [:]
}
@MainActor final class AppModel {
    var settings = Preferences()
    var runningApps = (0..<35).map { RunningApp(id: "\($0)") }
    var refreshes = 0
    var chosenDisplay: NSScreen? = NSScreen.screens.first
    func targetScreen() -> NSScreen? { chosenDisplay }
    func traySize(for app: RunningApp) -> TrayAppSize { app.size }
    func refreshRunningApps() { refreshes += 1 }
}
'''
source += block(model, 'enum TrayAppSize:') + '\n'
source += (root / 'Sources/ClotheslinePreferences.swift').read_text() + '\n'
source += (root / 'Sources/ClotheslineLayout.swift').read_text() + '\n'
source += (root / 'Sources/ClotheslineDynamics.swift').read_text() + '\n'
source += '@MainActor\n' + block(controller, 'final class ClotheslinePresentation:') + '\n'
source += '@MainActor final class ClotheslineController: NSObject {\n' + fields + r'''
    init(model: AppModel) { self.model = model; super.init() }
    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let window = NSPanel(); panel = window; return window
    }
''' + methods + r'''
    var window: NSPanel? { panel }
    var selectedID: String? { presentation.selectedID }
    var settlingDuration: TimeInterval { 8 }
    func key(_ key: UInt16) { _ = NSEvent.local(NSEvent(.keyDown, keyCode: key, window: panel)) }
    var shownPage: Int { presentation.content.page }
    var targetPage: Int { session.page }
    var pageCount: Int { presentation.content.layout.pages.count }
    var displayedIDs: Set<String> { Set(presentation.content.apps.keys) }
    var moving: Bool { presentation.moving }
    var hasPendingWork: Bool { displayLink != nil || pageTransition != nil }
    var cardOpacity: Double { presentation.cardsOpacity }
    func refresh() { scheduleRefresh() }
    func page(_ delta: Int) { turnPage(delta) }
    func allowPointer() { pointerReadyAt = .distantPast }
    var firstCard: ClotheslineLayout.Pose { dynamics!.frame().poses[0] }
    func pointer(_ type: NSEvent.Kind, at point: CGPoint) {
        let event = NSEvent(type, window: panel)
        event.locationInWindow = CGPoint(x: point.x, y: panel!.frame.height - point.y)
        _ = NSEvent.local(event)
    }
    func beginMenu(_ menu: NSMenu) { menuBegan(Notification(name: .init("begin"), object: menu)) }
    func endMenu(_ menu: NSMenu) { menuEnded(Notification(name: .init("end"), object: menu)) }
    func reduceMotionChanged() { accessibilityChanged() }
}
@main struct Probe {
    @MainActor static func main() {
        func tick(_ duration: TimeInterval) {
            for _ in 0..<Int(duration * 120) { CADisplayLink.step() }
            RunLoop.main.run(until: Date().addingTimeInterval(min(0.25, duration)))
        }
        let model = AppModel()
        let controller = ClotheslineController(model: model)
        defer { controller.dismiss(animated: false) }
        controller.show()
        let window = controller.window!
        precondition(controller.isShown && window.isVisible && !window.ignoresMouseEvents)
        precondition(NSEvent.locals.count == 1 && NSEvent.globals.count == 1)
        precondition(controller.pageCount > 1 && controller.shownPage == 0 && controller.moving)
        precondition(controller.selectedID == nil, "Opening must not select an app")
        var opened: [String] = []
        RunningApp.onOpen = { id in
            precondition(!controller.isShown && !window.isVisible && NSEvent.locals.isEmpty && NSEvent.globals.isEmpty,
                         "App opens before the clothesline and its monitors are removed")
            opened.append(id)
        }
        controller.key(49)
        tick(0.01)
        precondition(opened.isEmpty && controller.isShown, "Unselected Space opens an app")
        controller.show()
        precondition(controller.window === window && model.refreshes == 1, "Repeated pinch recreates/replays the surface")
        controller.page(1)
        controller.page(1)
        controller.page(-1)
        tick(0.15)
        precondition(controller.shownPage == 1 && controller.cardOpacity == 1, "Rapid page reversal leaves a stale or invisible page")
        controller.page(1)
        controller.dismiss()
        controller.dismiss(animated: false)
        precondition(!window.isVisible, "Immediate surface switch must finish a pending ordinary fade")
        controller.show()
        tick(0.2)
        precondition(controller.shownPage == 0 && window.isVisible, "Old page/fade callback hides or changes the reopened surface")
        tick(controller.settlingDuration + 0.1)
        precondition(!controller.moving && !controller.hasPendingWork, "Animation clock/work remains active after settling")

        for index in 0..<35 {
            controller.key(48)
            precondition(controller.selectedID == "\(index)", "Tab skips or reorders an app")
        }
        controller.key(48)
        precondition(controller.selectedID == "0" && controller.shownPage == 0, "Tab fails to wrap across pages")
        controller.key(50)
        precondition(controller.selectedID == "34", "Previous does not wrap from first to last")
        controller.key(48)
        model.settings.cardNavigation.set(0, for: .next)
        controller.key(0)
        precondition(controller.selectedID == "1", "Custom next key does not select")
        controller.key(48)
        precondition(controller.selectedID == "1", "Old Tab binding still selects")
        controller.key(50)
        precondition(controller.handleShortcut(0, modifiers: 0) && controller.selectedID == "1")
        precondition(!controller.handleShortcut(0, modifiers: 1), "Modified global hotkey intercepted")
        controller.key(50)
        model.settings.cardNavigation = .init()
        controller.key(49)
        precondition(!window.isVisible && !controller.isShown && opened.isEmpty, "Space must dismiss synchronously before opening")
        tick(0.01)
        precondition(opened == ["0"], "Space launches the wrong app or launches more than once")
        controller.show()
        precondition(controller.selectedID == nil, "Selection survives reopening")
        controller.allowPointer()
        let center = controller.firstCard.center
        controller.pointer(.leftMouseDown, at: center)
        let destination = CGPoint(x: center.x + 180.375, y: center.y + 210.625)
        controller.pointer(.leftMouseDragged, at: destination)
        tick(0.3)
        controller.pointer(.leftMouseUp, at: destination)
        precondition(controller.isShown && opened == ["0"], "Dragging launches an app")
        precondition(model.settings.clotheslinePositions["0"] != nil, "Drag does not persist a location")
        controller.dismiss(animated: false)
        controller.show()
        precondition(controller.isShown && controller.displayedIDs.count == 35,
                     "Closing during retying blocks next opening")
        controller.page(1)
        controller.key(48)
        precondition(controller.shownPage == 1 && controller.selectedID == "10" && controller.cardOpacity == 1,
                     "Tab during a page fade selects a hidden app")
        model.runningApps.removeAll { $0.id == "10" }
        controller.refresh()
        tick(0.02)
        precondition(controller.selectedID == nil, "Removed app remains selected")
        controller.key(49)
        tick(0.01)
        precondition(opened == ["0"] && controller.isShown, "Removed selection is launched")
        controller.key(48)
        let retainedSelection = controller.selectedID
        model.runningApps.insert(RunningApp(id: "inserted"), at: 0)
        controller.refresh()
        tick(0.02)
        precondition(controller.selectedID == retainedSelection, "Selection follows an index instead of app identity")
        controller.allowPointer()
        let rootMenu = NSMenu(), submenu = NSMenu()
        controller.beginMenu(rootMenu)
        controller.beginMenu(submenu)
        let beforeMenuSelection = controller.selectedID
        controller.key(48)
        controller.key(49)
        precondition(controller.selectedID == beforeMenuSelection && controller.isShown,
                     "Clothesline keyboard shortcuts steal context-menu input")
        _ = NSEvent.local(NSEvent(.keyDown, keyCode: 53, window: window))
        precondition(controller.isShown, "Escape must reach the tracked menu")
        let visibleBefore = controller.displayedIDs
        model.runningApps = [RunningApp(id: "replacement", size: .large)]
        controller.refresh()
        tick(0.02)
        precondition(controller.displayedIDs == visibleBefore, "Refresh rebuilds cards during context-menu tracking")
        controller.endMenu(submenu)
        tick(0.02)
        precondition(controller.displayedIDs == visibleBefore)
        controller.endMenu(rootMenu)
        tick(0.02)
        precondition(controller.displayedIDs == ["replacement"] && controller.shownPage == 0, "Deferred menu refresh never applies")

        PinchMonitor.shared.guardedUntil = Date().addingTimeInterval(1)
        NSEvent.global(NSEvent(.leftMouseDown))
        tick(0.02)
        precondition(controller.isShown, "Pinch tail dismisses freshly opened cards")
        PinchMonitor.shared.guardedUntil = .distantPast
        NSEvent.global(NSEvent(.leftMouseDown))
        tick(0.02)
        precondition(!controller.isShown && NSEvent.locals.isEmpty && NSEvent.globals.isEmpty,
                     "Outside dismissal leaks input monitors")
        controller.refresh()
        tick(0.2)
        precondition(!window.isVisible && !controller.hasPendingWork, "Hidden refresh reopens a window or retains work")

        model.runningApps = (0..<35).map { RunningApp(id: "\($0)") }
        controller.show()
        controller.page(1)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = true
        controller.reduceMotionChanged()
        tick(0.15)
        precondition(controller.shownPage == 1 && controller.targetPage == 1 && !controller.moving && !controller.hasPendingWork,
                     "Reduce Motion during paging abandons the selected page")
        precondition(NSEvent.local(NSEvent(.keyDown, keyCode: 124, window: window)) == nil,
                     "Handled navigation must not leak into the underlying application")
        precondition(controller.shownPage == 2 && !controller.moving)
        let resized = NSScreen()
        resized.frame = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        resized.visibleFrame = CGRect(x: -1280, y: 48, width: 1280, height: 720)
        NSScreen.screens = [resized]
        controller.screenParametersChanged()
        precondition(controller.isShown && window.frame == resized.frame, "Display identity must survive screen object replacement/resizing")
        model.runningApps = []
        controller.refresh()
        tick(0.02)
        precondition(controller.pageCount == 0 && controller.shownPage == 0 && !controller.moving)
        _ = NSEvent.local(NSEvent(.keyDown, keyCode: 53, window: window))
        precondition(!controller.isShown && !window.isVisible)
        model.chosenDisplay = resized
        controller.show()
        NSScreen.screens = []
        controller.screenParametersChanged()
        precondition(!controller.isShown && !window.isVisible, "Disconnected display leaves an orphan full-screen panel")
        precondition(NSEvent.locals.isEmpty && NSEvent.globals.isEmpty && !controller.hasPendingWork)
        print("PASS: production show/dismiss, rapid paging, stale completions, empty/updated apps, menu tracking and pointer guard")
        print("PASS: initially empty selection, Tab sequence/wrap/paging, refresh identity, menu exclusion, Space dismiss-before-open")
        print("PASS: Reduce Motion mid-transition, keyboard, display removal and idle/hidden teardown; no native windows opened")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-clothesline-lifecycle-') as temp:
    temp = Path(temp)
    (temp / 'Probe.swift').write_text(source)
    binary = temp / 'probe'
    subprocess.run(['swiftc', '-O', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(temp / 'Probe.swift'), '-o', str(binary)],
                   check=True, timeout=60)
    subprocess.run([str(binary)], check=True, timeout=30)
