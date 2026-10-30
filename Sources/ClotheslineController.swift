import AppKit
import Combine
import SwiftUI

@MainActor
final class ClotheslinePresentation: ObservableObject {
    struct Content {
        var layout = ClotheslineLayout(items: [], bounds: CGRect(x: 0, y: 0, width: 1, height: 1))
        var apps: [String: RunningApp] = [:]
        var page = 0
    }
    @Published var content = Content()
    @Published var frame: ClotheslineLayout.Frame?
    @Published var moving = false
    @Published var cardsOpacity: Double = 1
    @Published var selectedID: String?
    var began = Date.distantPast
    var framesPerSecond = 60
}

@MainActor
private struct ClotheslineView: View {
    @ObservedObject var presentation: ClotheslinePresentation
    let model: AppModel
    var close: () -> Void
    var launch: () -> Void
    var canOpen: () -> Bool
    var turnPage: (Int) -> Void

    var body: some View {
        let content = presentation.content
        ZStack {
            Color.clear.contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityLabel("关闭菜单栏应用面板")
                .accessibilityAddTraits(.isButton)
            ClotheslineScene(layout: content.layout, page: content.page, elapsed: ClotheslineMotion.duration,
                             selectedID: presentation.selectedID, liveFrame: presentation.frame) { card in
                if let app = content.apps[card.id] {
                    ClotheslineAppCard(app: app, model: model, launch: launch, canOpen: canOpen).equatable()
                }
            }
            .opacity(presentation.cardsOpacity)
            if content.apps.isEmpty {
                Text("暂无菜单栏应用")
                    .font(.system(size: 17, weight: .medium))
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .position(x: content.layout.bounds.midX, y: content.layout.bounds.midY)
            }
            if content.layout.pages.count > 1 {
                ClotheslinePager(page: content.page, count: content.layout.pages.count, turnPage: turnPage)
                    .position(x: content.layout.bounds.midX, y: content.layout.pagerY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("菜单栏应用晾衣绳")
    }
}

/// Keep native glass, icon lookup and context menus outside per-frame pose work.
private struct ClotheslineAppCard: View, Equatable {
    let app: RunningApp
    let model: AppModel
    var launch: () -> Void
    var canOpen: () -> Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.app == rhs.app && lhs.model === rhs.model }
    var body: some View {
        RunningCell(app: app, model: model, onClose: launch, hanging: true, canOpen: canOpen)
    }
}

/// Owns one full-screen surface. Hidden surfaces have no event monitors or animation clock.
@MainActor
final class ClotheslineController: NSObject {
    private let model: AppModel
    private let presentation = ClotheslinePresentation()
    private var session = ClotheslineSession()
    private var panel: NSPanel?
    private var display: NSScreen?
    private var subscriptions: Set<AnyCancellable> = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var menus: Set<ObjectIdentifier> = []
    private var refreshPending = false
    private var dynamics: ClotheslineDynamics?
    private var displayLink: CADisplayLink?
    private var lastFrameTime: TimeInterval = 0
    private var pendingPointer: (id: String, start: CGPoint, dragging: Bool)?
    private var pageSimulations: [Int: ClotheslineDynamics] = [:]
    private var pageTransition: DispatchWorkItem?
    private var pointerReadyAt = Date.distantPast

    var isShown: Bool { session.isShown }

    init(model: AppModel) {
        self.model = model
        super.init()
        // Published values arrive before their stored properties change. Read the
        // complete model on the next main-loop turn, not a partly updated snapshot.
        model.$runningApps.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &subscriptions)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(menuBegan(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(menuEnded(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    func show() {
        guard !isShown, let screen = model.targetScreen() else { return }
        display = screen
        session.open()
        pageSimulations.removeAll()
        dynamics = nil
        pendingPointer = nil
        presentation.selectedID = nil
        let window = ensurePanel()
        window.setFrame(screen.frame, display: false)
        window.ignoresMouseEvents = false
        presentation.framesPerSecond = max(30, min(120, screen.maximumFramesPerSecond))
        pointerReadyAt = Date().addingTimeInterval(0.2)
        refreshContent()
        installMonitors()
        window.alphaValue = reduceMotion ? 1 : 0
        window.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                window.animator().alphaValue = 1
            }
        }
        model.refreshRunningApps()
    }

    func dismiss(animated: Bool = true) {
        guard isShown else {
            // Switching to another surface may interrupt an already-running fade.
            if !animated, let panel { LauncherPanelVisibility.suspend(panel) }
            return
        }
        session.close()
        presentation.selectedID = nil
        let token = session.generation
        cancelMovement()
        menus.removeAll()
        refreshPending = false
        removeMonitors()
        guard let window = panel else { return }
        window.ignoresMouseEvents = true
        if window.isKeyWindow { window.resignKey() }
        if !animated || reduceMotion {
            LauncherPanelVisibility.suspend(window)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak window] in
            DispatchQueue.main.async {
                guard let self, let window, !self.isShown, self.session.generation == token else { return }
                LauncherPanelVisibility.suspend(window)
            }
        })
    }

    func screenParametersChanged() {
        guard isShown else { return }
        // Keep the opening display while it exists; moving the pointer cannot
        // move the open clothesline. Unplugging that display safely dismisses it.
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = display?.deviceDescription[key] as? NSNumber,
              let display = NSScreen.screens.first(where: { ($0.deviceDescription[key] as? NSNumber) == number }) else {
            dismiss(animated: false)
            return
        }
        self.display = display
        panel?.setFrame(display.frame, display: false)
        refreshContent()
    }

    func shutdown() {
        dismiss(animated: false)
        cancelMovement()
        removeMonitors()
        subscriptions.removeAll()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func canHandlePointer() -> Bool {
        isShown && Date() >= pointerReadyAt && Date() >= PinchMonitor.shared.pinchPointerGuardUntil()
    }

    private func dismissFromPointer() {
        guard menus.isEmpty, canHandlePointer() else { return }
        dismiss()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let window = ClotheslinePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.title = "Pinchpad 菜单栏应用"
        let host = PanelHost(rootView: ClotheslineView(
            presentation: presentation, model: model,
            close: { [weak self] in self?.dismissFromPointer() },
            launch: { [weak self] in self?.dismiss(animated: false) },
            canOpen: { [weak self] in self?.canHandlePointer() ?? false },
            turnPage: { [weak self] delta in
                guard let self, self.canHandlePointer() else { return }
                self.turnPage(delta)
            }
        ))
        host.autoresizingMask = [.width, .height]
        host.sizingOptions = []
        host.safeAreaRegions = []
        // Only the cards draw material. The screen-sized host must never blur,
        // dim or paint over the user's desktop and other open windows.
        window.contentView = host
        panel = window
        return window
    }

    private func scheduleRefresh() {
        guard isShown else { return }
        DispatchQueue.main.async { [weak self] in self?.refreshContent() }
    }

    private func refreshContent() {
        guard isShown, let display else { return }
        guard menus.isEmpty, pendingPointer == nil, dynamics?.isInteracting != true else { refreshPending = true; return }
        refreshPending = false
        let frame = display.frame
        let visible = display.visibleFrame
        let top = max(frame.maxY - visible.maxY, display.safeAreaInsets.top, NSStatusBar.system.thickness)
        let safe = CGRect(x: visible.minX - frame.minX, y: top,
                          width: visible.width, height: max(1, frame.height - top - (visible.minY - frame.minY)))
        let apps = model.runningApps
        let proposed = ClotheslineLayout(items: apps.map { .init(id: $0.id, size: .small) }, bounds: safe)
        let previous = presentation.content
        let layout = proposed == previous.layout ? previous.layout : proposed
        if let id = presentation.selectedID, !apps.contains(where: { $0.id == id }) { presentation.selectedID = nil }
        let selectedPage = presentation.selectedID.flatMap { id in layout.pages.firstIndex { $0.contains { $0.id == id } } }
        let page = selectedPage ?? min(session.page, max(0, layout.pages.count - 1))
        let changed = layout != previous.layout || page != previous.page
        if changed {
            pageSimulations.removeAll()
            cancelMovement()
            session.select(page, count: layout.pages.count)
        }
        presentation.content = .init(layout: layout, apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), page: page)
        if changed || !presentation.moving && presentation.began == .distantPast { startMovement() }
    }

    private func positions() -> [String: ClotheslinePosition] {
        Dictionary(uniqueKeysWithValues: presentation.content.apps.values.compactMap { app in
            model.settings.clotheslinePositions[app.placementKey].map { (app.id, $0) }
        })
    }

    private func startMovement() {
        presentation.cardsOpacity = 1
        let content = presentation.content
        let simulation = pageSimulations[content.page]
            ?? ClotheslineDynamics(layout: content.layout, page: content.page, positions: positions())
        pageSimulations[content.page] = simulation
        dynamics = simulation
        if reduceMotion { simulation.settle() }
        presentation.frame = simulation.frame()
        presentation.began = Date()
        resumeDisplayLink()
    }

    private func resumeDisplayLink() {
        guard isShown, let panel, dynamics?.isResting == false else { return }
        presentation.moving = true
        guard displayLink == nil else { return }
        let link = panel.displayLink(target: self, selector: #selector(displayFrame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30,
            maximum: Float(presentation.framesPerSecond), preferred: Float(presentation.framesPerSecond))
        lastFrameTime = 0
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func displayFrame(_ link: CADisplayLink) {
        guard isShown, let dynamics else { stopDisplayLink(); return }
        let now = link.targetTimestamp
        let elapsed = lastFrameTime > 0 ? now - lastFrameTime : 1 / Double(presentation.framesPerSecond)
        lastFrameTime = now
        dynamics.advance(by: elapsed)
        presentation.frame = dynamics.frame()
        if dynamics.isResting {
            stopDisplayLink()
            if refreshPending { scheduleRefresh() }
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTime = 0
        presentation.moving = false
    }

    private func cancelMovement() {
        if pendingPointer != nil { finishPointer() }
        stopDisplayLink()
        pageTransition?.cancel()
        pageTransition = nil
        presentation.began = .distantPast
        presentation.cardsOpacity = 1
    }

    private func turnPage(_ delta: Int) {
        guard isShown, menus.isEmpty, pendingPointer == nil else { return }
        let count = presentation.content.layout.pages.count
        let target = min(max(0, session.page + delta), max(0, count - 1))
        guard target != session.page else { return }
        presentation.selectedID = nil
        cancelMovement()
        let token = session.select(target, count: count)
        if reduceMotion {
            presentation.content.page = target
            startMovement()
            return
        }
        withAnimation(.easeOut(duration: ClotheslineMotion.pageFadeDuration)) { presentation.cardsOpacity = 0 }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.session.accepts(token) else { return }
            self.presentation.content.page = target
            self.pageTransition = nil
            self.startMovement()
        }
        pageTransition = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ClotheslineMotion.pageFadeDuration, execute: work)
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .systemDefined, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            guard let self, self.isShown, self.menus.isEmpty else { return event }
            if event.type == .keyDown || event.type == .flagsChanged || event.type == .systemDefined {
                if event.type == .keyDown, self.handleKey(event.keyCode) { return nil }
                return event
            }
            if self.handlePointer(event) { return nil }
            if (event.type == .leftMouseDown || event.type == .rightMouseDown), event.window !== self.panel {
                self.dismissFromPointer()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged, .systemDefined, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.isShown, self.menus.isEmpty else { return }
                if event.type == .keyDown || event.type == .flagsChanged || event.type == .systemDefined {
                    if event.type == .keyDown { _ = self.handleKey(event.keyCode) }
                } else { self.dismissFromPointer() }
            }
        }
    }

    private func handlePointer(_ event: NSEvent) -> Bool {
        guard let panel, let dynamics else { return false }
        guard event.window === panel || pendingPointer != nil else { return false }
        let location = event.window === panel ? event.locationInWindow
            : panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = CGPoint(x: location.x, y: panel.frame.height - location.y)
        switch event.type {
        case .leftMouseDown:
            guard canHandlePointer(), let id = dynamics.hitTest(point) else { return false }
            pendingPointer = (id, point, false)
            return true
        case .leftMouseDragged:
            guard var pointer = pendingPointer else { return false }
            if !pointer.dragging, hypot(point.x - pointer.start.x, point.y - pointer.start.y) >= 4 {
                pointer.dragging = dynamics.beginDrag(id: pointer.id, at: pointer.start)
                pendingPointer = pointer
                presentation.selectedID = pointer.id
            }
            if pointer.dragging {
                dynamics.moveDrag(to: point)
                resumeDisplayLink()
            }
            return true
        case .leftMouseUp:
            guard let pointer = pendingPointer else { return false }
            if pointer.dragging {
                dynamics.moveDrag(to: point)
                finishPointer()
            } else {
                pendingPointer = nil
                guard dynamics.hitTest(point) == pointer.id, canHandlePointer() else { return true }
                presentation.selectedID = pointer.id
                openSelectedApp()
            }
            return true
        default: return false
        }
    }

    private func finishPointer() {
        pendingPointer = nil
        if let placement = dynamics?.endDrag(), let app = presentation.content.apps[placement.id] {
            model.settings.clotheslinePositions[app.placementKey] = placement.position
        }
        if reduceMotion { dynamics?.settle(); presentation.frame = dynamics?.frame() }
        else { resumeDisplayLink() }
        pointerReadyAt = Date().addingTimeInterval(0.15)
    }

    private func handleKey(_ key: UInt16) -> Bool {
        guard pendingPointer == nil else {
            if key == 53 { finishPointer(); dismiss() }
            return true
        }
        if key == 48 { selectApp(); return true }
        switch key {
        case 53: dismiss()
        case 49: openSelectedApp()
        case 123: turnPage(-1)
        case 124: turnPage(1)
        default: return false
        }
        return true
    }

    private func selectApp() {
        guard isShown, menus.isEmpty else { return }
        let layout = presentation.content.layout
        let cards = layout.pages.flatMap { $0 }
        let current = presentation.selectedID.flatMap { id in cards.firstIndex { $0.id == id } }
        let start = layout.pages.prefix(session.page).reduce(0) { $0 + $1.count }
        guard !cards.isEmpty else { return }
        let index = ((current ?? (start - 1)) + 1) % cards.count
        let next = cards[index]
        let page = layout.pages.firstIndex { $0.contains { $0.id == next.id } } ?? 0
        if page != presentation.content.page || pageTransition != nil {
            cancelMovement()
            session.select(page, count: layout.pages.count)
            presentation.content.page = page
            startMovement()
        }
        presentation.selectedID = next.id
    }

    private func openSelectedApp() {
        guard isShown, menus.isEmpty, let id = presentation.selectedID,
              let app = presentation.content.apps[id] else { return }
        // Remove the surface synchronously, then hand off to Launch Services on
        // the next main-loop turn, so the old overlay cannot cover the new app.
        dismiss(animated: false)
        DispatchQueue.main.async { app.open() }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    @objc private func menuBegan(_ notification: Notification) {
        guard isShown, let menu = notification.object as? NSMenu else { return }
        menus.insert(ObjectIdentifier(menu))
    }

    @objc private func menuEnded(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        menus.remove(ObjectIdentifier(menu))
        if menus.isEmpty, refreshPending { scheduleRefresh() }
    }

    @objc private func accessibilityChanged() {
        if reduceMotion {
            cancelMovement()
            presentation.content.page = session.page
            startMovement()
        }
    }
}

private final class ClotheslinePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
