import AppKit
import SwiftUI

@main
struct PinchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var current: AppDelegate?
    private var panel: NSPanel?
    private var host: NSHostingView<PinchpadRoot>?
    private var panelWindowed = false
    private var statusItem: NSStatusItem?
    private lazy var clothesline = ClotheslineController(model: AppModel.shared)
    private var lastStatusItemRect: CGRect?
    private var inputMonitor: Any?
    private var outsideMonitor: Any?
    private var auroraView: NSView?
    private var visibilityToken = 0
    private var panelRevealed = false
    private var interactionReadyAt: TimeInterval = 0
    private var auroraBuilt = false
    private var auroraBuiltSize: CGSize = .zero
    private var auroraBuiltBackdrop: BackdropKind?
    private var swipeAccum: CGFloat = 0
    private var swipeSamples: [(TimeInterval, CGFloat)] = []
    private var swipeIdleWork: DispatchWorkItem?
    private static let coverLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)

    var alertParentWindow: NSWindow? {
        AppModel.shared.isOpen ? panel : NSApp.keyWindow
    }

    override init() {
        super.init()
        AppDelegate.current = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        model.onOpenChange = { [weak self] animated in self?.sync(animated: animated) }
        model.onContentReady = { [weak self] in self?.warmPanel() }
        refreshTray()
        installInputMonitor()
        model.start()
        prewarmPanel()
        if CommandLine.arguments.contains("--show") {
            model.open()
        }
        if CommandLine.arguments.contains("--settings") {
            SettingsOpener.open()
        }
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        clothesline.screenParametersChanged()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clothesline.shutdown()
    }

    /// 只在屏幕外预热布局和保留视图缓存，不让隐藏的全屏毛玻璃参与桌面合成。
    private func prewarmPanel() {
        guard !AppModel.shared.isOpen else { return }
        ensurePanel()
        layout()
        guard let panel else { return }
        LauncherPanelVisibility.suspend(panel)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        AppModel.shared.prepareEntrance()
    }

    private func warmPanel() {
        prewarmPanel()
    }

    func refreshTray() {
        let show = AppModel.shared.settings.showMenuBar
        if !show {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = Bundle.main.image(forResource: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Pinchpad")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            image?.accessibilityDescription = "Pinchpad"
            item.button?.image = image
            item.button?.toolTip = "Pinchpad"
            item.button?.target = self
            item.button?.action = #selector(statusClicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.isVisible = true
            statusItem = item
        }
        statusItem?.isVisible = true
    }

    @objc private func statusClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popTrayMenu()
        } else {
            openSettingsFromTray()
        }
    }

    private func popTrayMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开", action: #selector(openFromTray), keyEquivalent: "")
        openItem.target = self
        let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettingsFromTray), keyEquivalent: "")
        settingsItem.target = self
        let quitItem = NSMenuItem(title: "退出 Pinchpad", action: #selector(quitFromTray), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(openItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    func openClotheslineFromPinch() {
        guard !clothesline.isShown else { return }
        AppModel.shared.close(animated: false)
        clothesline.show()
    }

    func dismissCompanionPanels() {
        clothesline.dismiss()
    }

    func handleClotheslineShortcut(_ code: UInt32, modifiers: UInt32) -> Bool {
        clothesline.handleShortcut(code, modifiers: modifiers)
    }

    @objc private func openFromTray() { AppModel.shared.open() }
    @objc private func openSettingsFromTray() {
        clothesline.dismiss(animated: false)
        AppModel.shared.close(animated: false)
        SettingsOpener.open()
    }
    @objc private func quitFromTray() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsFromTray()
        return true
    }

    private func sync(animated: Bool = true) {
        let model = AppModel.shared
        if model.isOpen {
            clothesline.dismiss(animated: false)
            let createdPanel = ensurePanel()
            layout()
            if createdPanel {
                // 新 host 先在不可见状态挂载接收器，再发送入场复位/播放信号。
                // 复用的面板不走这里，淡出中重新打开才能延续现有图标状态。
                panel?.contentView?.layoutSubtreeIfNeeded()
                panel?.displayIfNeeded()
                model.prepareEntrance()
                panel?.contentView?.layoutSubtreeIfNeeded()
            }
            setDockHidden(model.settings.hideDockWhileOpen)
            // 已经显示时只重排布局：改设置/换屏触发的 sync 不应该再播一次淡入。
            if !panelRevealed {
                visibilityToken += 1
                reveal()
            }
            installOutsideMonitor()
        } else {
            visibilityToken += 1
            let token = visibilityToken
            if let sheet = panel?.attachedSheet {
                panel?.endSheet(sheet, returnCode: .alertSecondButtonReturn)
            }
            panelRevealed = false
            removeOutsideMonitor()
            if animated {
                conceal(token: token)
            } else {
                // Launching another app must release the surface and focus before
                // Launch Services does any work; ordinary dismissal keeps its fade.
                model.isOptionPressed = false
                model.interactionReady = false
                finishConceal(token: token)
            }
        }
        model.keepOutOfDock()
    }

    private func setDockHidden(_ hidden: Bool) {
        var options = NSApp.presentationOptions
        if hidden {
            options.insert(.hideDock)
        } else {
            options.remove(.hideDock)
        }
        if options != NSApp.presentationOptions {
            NSApp.presentationOptions = options
        }
    }

    @discardableResult
    private func ensurePanel() -> Bool {
        let windowed = AppModel.shared.settings.browsing == .window
        if let panel, panelWindowed != windowed {
            panel.orderOut(nil)
            panel.delegate = nil
            // 模式切换会销毁旧窗口；只 orderOut 会留下旧 host 继续订阅模型和入场信号。
            panel.contentView = nil
            panel.close()
            self.panel = nil
            self.host = nil
            self.auroraView = nil
            panelRevealed = false
        }
        guard panel == nil else { return false }
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: windowed ? [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel] : [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = windowed
        panel.level = windowed ? .floating : Self.coverLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = "Pinchpad"
        if windowed {
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.titlebarSeparatorStyle = .none
            panel.isMovableByWindowBackground = true
        }
        let effect = NSVisualEffectView()
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .inactive
        effect.autoresizingMask = [.width, .height]
        let host = PanelHost(rootView: PinchpadRoot(model: AppModel.shared))
        host.autoresizingMask = [.width, .height]
        host.sizingOptions = []
        host.safeAreaRegions = []
        let aurora = NSView(frame: effect.bounds)
        aurora.wantsLayer = true
        aurora.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        effect.addSubview(aurora, positioned: .below, relativeTo: host)
        auroraView = aurora
        panel.contentView = effect
        self.panel = panel
        self.host = host
        self.panelWindowed = windowed
        // 新窗口的图层树是空的，aurora 需要按新尺寸重建一次。
        auroraBuilt = false
        auroraBuiltSize = .zero
        auroraBuiltBackdrop = nil
        return true
    }

    private func layout() {
        guard let panel, let screen = AppModel.shared.targetScreen() else { return }
        let target: NSRect
        if panelWindowed {
            let size = AppModel.shared.windowSize(for: screen)
            target = NSRect(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        } else {
            target = screen.frame
        }
        // 幂等：启动预热时已经摆好位置。对全屏 layer-backed 面板来说，即使矩形
        // 相同，重复 setFrame 也会让整棵内容重新布局并多一次 WindowServer 提交，
        // 而它刚好落在开场淡入之前——这就是原先打开时约 100ms 卡顿的来源。
        if panel.frame != target {
            panel.setFrame(target, display: false)
        }
        rebuildAuroraIfNeeded()
    }

    /// 只在尺寸或背景样式变化时重建 aurora。每次打开都删光再重建 4 个大图层，
    /// 会把一次全量图层提交压到淡入前的提交窗口里。
    private func rebuildAuroraIfNeeded() {
        guard let panel, let effect = panel.contentView as? NSVisualEffectView else { return }
        let size = effect.bounds.size
        let backdrop = AppModel.shared.settings.backdrop
        guard !auroraBuilt || size != auroraBuiltSize || backdrop != auroraBuiltBackdrop else { return }
        auroraBuilt = true
        auroraBuiltSize = size
        auroraBuiltBackdrop = backdrop
        rebuildAurora()
        // 重建只发生在尺寸/背景样式变化时：如果面板正开着，新图层要把漂移动画补上，
        // 否则换屏/改背景后光晕会停住。正常打开不受影响（不会走这条路径）。
        if AppModel.shared.isOpen {
            attachAuroraMotion()
        }
    }

    // MARK: - Aurora backdrop

    /// 背景光晕的全部信息；位置/大小/漂移幅度都是相对面板尺寸的比例，重建时换算。
    private struct AuroraBlob {
        var hue: CGFloat; var sat: CGFloat; var bri: CGFloat
        var size: CGFloat; var aspect: CGFloat
        var x: CGFloat; var y: CGFloat
        var dx: CGFloat; var dy: CGFloat
        var durX: CFTimeInterval; var durY: CFTimeInterval
        var breathe: CGFloat; var durBreathe: CFTimeInterval
        var color: NSColor { NSColor(hue: hue, saturation: sat, brightness: bri, alpha: 1) }
    }

    private static let auroraSpecs: [AuroraBlob] = [
        AuroraBlob(hue: 0.60, sat: 0.65, bri: 0.85, size: 0.85, aspect: 1.35,
                   x: 0.50, y: 0.42, dx: 0.10, dy: 0.06, durX: 30, durY: 41, breathe: 1.08, durBreathe: 52),
        AuroraBlob(hue: 0.53, sat: 0.60, bri: 0.90, size: 0.70, aspect: 1.20,
                   x: 0.72, y: 0.66, dx: -0.11, dy: 0.08, durX: 34, durY: 47, breathe: 0, durBreathe: 0),
        AuroraBlob(hue: 0.72, sat: 0.55, bri: 0.80, size: 0.78, aspect: 1.25,
                   x: 0.30, y: 0.58, dx: 0.09, dy: -0.07, durX: 38, durY: 29, breathe: 1.12, durBreathe: 44),
        AuroraBlob(hue: 0.58, sat: 0.50, bri: 0.85, size: 0.55, aspect: 1.30,
                   x: 0.60, y: 0.30, dx: -0.08, dy: 0.05, durX: 26, durY: 36, breathe: 0, durBreathe: 0)
    ]

    /// 光晕渐变压成一次性 CGImage，之后所有动画都是渲染进程侧的图层变换，app 零逐帧开销。
    private static var glowCache: [NSColor: CGImage] = [:]

    private func glowImage(for color: NSColor) -> CGImage? {
        if let cached = Self.glowCache[color] { return cached }
        let side = 256
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color.withAlphaComponent(0.55).cgColor,
                     color.withAlphaComponent(0.2).cgColor,
                     NSColor.clear.cgColor] as CFArray,
            locations: [0, 0.45, 1]
        ) else { return nil }
        let center = CGFloat(side) / 2
        ctx.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: center, y: center), startRadius: 0,
            endCenter: CGPoint(x: center, y: center), endRadius: center,
            options: [.drawsAfterEndLocation]
        )
        let image = ctx.makeImage()
        Self.glowCache[color] = image
        return image
    }

    private func rebuildAurora() {
        guard let auroraView, let container = auroraView.layer else { return }
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        // 首次 layout 时 layer.bounds 可能还没同步，用 view 的 bounds 更可靠。
        let bounds = auroraView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let base = min(bounds.width, bounds.height)
        // 光晕位于 SwiftUI 暗化层之下，按背景样式补偿可见强度。
        let opacity: Float
        switch AppModel.shared.settings.backdrop {
        case .blur: opacity = 0.8
        case .dim: opacity = 0.9
        case .plain: opacity = 1
        }
        for spec in Self.auroraSpecs {
            let blob = CALayer()
            blob.contents = glowImage(for: spec.color)
            blob.contentsGravity = .resize
            blob.bounds = CGRect(x: 0, y: 0, width: base * spec.size * spec.aspect, height: base * spec.size)
            blob.position = CGPoint(x: bounds.width * spec.x, y: bounds.height * spec.y)
            blob.opacity = opacity
            container.addSublayer(blob)
        }
        // 这里不再 attachAuroraMotion()：淡入时 reveal() 统一挂一次，
        // 避免每次打开重复 add/remove 十几条 CAAnimation。
    }

    /// 打开时给每团光晕挂 CABasicAnimation（x/y 不同周期形成漂移轨迹 + 呼吸缩放），
    /// 关闭或减弱动态时移除；动画全程在 render server 侧，不占 app CPU。
    private func attachAuroraMotion() {
        guard let sublayers = auroraView?.layer?.sublayers else { return }
        let animate = AppModel.shared.isOpen && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let bounds = auroraView?.layer?.bounds ?? .zero
        for (index, blob) in sublayers.enumerated() {
            blob.removeAllAnimations()
            guard animate, index < Self.auroraSpecs.count else { continue }
            let spec = Self.auroraSpecs[index]
            for (keyPath, from, to, duration) in [
                ("transform.translation.x", -bounds.width * spec.dx, bounds.width * spec.dx, spec.durX),
                ("transform.translation.y", -bounds.height * spec.dy, bounds.height * spec.dy, spec.durY)
            ] {
                let anim = CABasicAnimation(keyPath: keyPath)
                anim.fromValue = from
                anim.toValue = to
                anim.duration = duration
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                blob.add(anim, forKey: keyPath)
            }
            if spec.breathe > 0 {
                let anim = CABasicAnimation(keyPath: "transform.scale")
                anim.fromValue = 1
                anim.toValue = spec.breathe
                anim.duration = spec.durBreathe
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                blob.add(anim, forKey: "breathe")
            }
        }
    }

    /// 淡入/淡出用的图层动画 key。
    private static let contentFadeKey = "app.local.pinchpad.reveal"
    /// 全屏面板的淡入淡出时长；窗口模式沿用窗口 alpha 动画。
    private static let contentFadeDuration = PanelAnimation.opacityDuration
    private static let contentFadeOutDuration = PanelAnimation.closingDuration

    /// 背景走原生淡入；图标保留从中心向外的四环出场。
    /// 两者同步启动，整窗不再叠加缩放。
    private func reveal() {
        guard let panel else { return }
        let presentation = panel.isVisible ? panel.contentView?.layer?.presentation() : nil
        let fromOpacity = presentation?.opacity ?? 0
        panelRevealed = true
        let token = visibilityToken
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        AppModel.shared.interactionReady = false
        (panel.contentView as? NSVisualEffectView)?.state = .active
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.ignoresMouseEvents = false
        if !panel.isVisible { panel.orderFrontRegardless() }
        if panelWindowed || reduceMotion {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.makeKey()
        }
        attachAuroraMotion()
        let replayingEntrance = AppModel.shared.beginEntrance()
        if reduceMotion {
            interactionReadyAt = 0
        } else if replayingEntrance {
            interactionReadyAt = ProcessInfo.processInfo.systemUptime + IconEntrance.totalDuration
        }

        guard !reduceMotion else {
            if let layer = panel.contentView?.layer {
                layer.removeAnimation(forKey: Self.contentFadeKey)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.opacity = 1
                layer.transform = CATransform3DIdentity
                CATransaction.commit()
            }
            panel.alphaValue = 1
            finishReveal(token: token)
            return
        }

        if panelWindowed {
            // 有标题栏的小窗口让整窗一起渐显，视觉更自然。
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.contentFadeDuration
                context.timingFunction = PanelAnimation.timingFunction
                panel.animator().alphaValue = 1
            }, completionHandler: {
                DispatchQueue.main.async { self.finishReveal(token: token) }
            })
            return
        }

        // 先提交内容动画，再让窗口可见，避免首次打开闪出一帧完整面板。
        guard let layer = panel.contentView?.layer else {
            panel.alphaValue = 1
            finishReveal(token: token)
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        let entrance = PanelAnimation.opening(
            maximumFramesPerSecond: panel.screen?.maximumFramesPerSecond ?? 60,
            fromOpacity: fromOpacity
        )
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async { self?.finishReveal(token: token) }
        }
        layer.add(entrance, forKey: Self.contentFadeKey)
        CATransaction.commit()
        panel.alphaValue = 1
    }

    /// 背景浮现结束：恢复 hover。
    private func finishReveal(token: Int) {
        guard token == visibilityToken, AppModel.shared.isOpen else { return }
        let remaining = interactionReadyAt - ProcessInfo.processInfo.systemUptime
        if remaining > 0 {
            // Hover changes each icon's scale too. Wait for the outer wave to
            // settle instead of introducing a second scale during its entrance.
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                self?.finishReveal(token: token)
            }
            return
        }
        AppModel.shared.interactionReady = true
    }

    private func conceal(token: Int) {
        AppModel.shared.isOptionPressed = false
        AppModel.shared.interactionReady = false
        guard let panel else {
            AppModel.shared.completeClose()
            setDockHidden(false)
            return
        }
        // 淡出期间点击直接穿透；淡出结束后窗口移出显示列表。
        panel.ignoresMouseEvents = true
        guard panel.isVisible else {
            finishConceal(token: token)
            return
        }
        if panelWindowed || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                finishConceal(token: token)
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.contentFadeOutDuration
                context.timingFunction = PanelAnimation.timingFunction
                panel.animator().alphaValue = 0
            }, completionHandler: {
                DispatchQueue.main.async { self.finishConceal(token: token) }
            })
            return
        }
        guard let layer = panel.contentView?.layer else {
            finishConceal(token: token)
            return
        }
        // 与淡入对称：全屏面板只做内容图层的合成器淡出。
        // 从当前 presentation 值出发，连开连关时不会先跳回全不透明再淡出。
        let fromOpacity = layer.presentation()?.opacity ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()
        let fade = PanelAnimation.closing(
            fromOpacity: fromOpacity,
            maximumFramesPerSecond: panel.screen?.maximumFramesPerSecond ?? 60
        )
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async { self?.finishConceal(token: token) }
        }
        layer.add(fade, forKey: Self.contentFadeKey)
        CATransaction.commit()
    }

    private func finishConceal(token: Int) {
        guard token == visibilityToken, !AppModel.shared.isOpen else { return }
        if let panel {
            if panel.isKeyWindow { panel.resignKey() }
            LauncherPanelVisibility.suspend(panel)
        }
        // 淡出结束后再停 aurora，避免光晕在可见的淡出过程中跳回基准位置。
        auroraView?.layer?.sublayers?.forEach { $0.removeAllAnimations() }
        AppModel.shared.completeClose()
        AppModel.shared.prepareEntrance()
        setDockHidden(false)
    }

    private func installInputMonitor() {
        guard inputMonitor == nil else { return }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseDown, .leftMouseUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handleInput(event)
        }
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.closeIfClickedOutside() }
        }
    }

    private func removeOutsideMonitor() {
        guard let outsideMonitor else { return }
        NSEvent.removeMonitor(outsideMonitor)
        self.outsideMonitor = nil
    }

    private func closeIfClickedOutside() {
        guard AppModel.shared.isOpen, panel?.attachedSheet == nil else { return }
        guard !isStatusItemClick() else { return }
        AppModel.shared.closeFromPointer()
    }

    private func isStatusItemClick() -> Bool {
        // A deliberately hidden icon has no hit area. Only an existing status
        // item may need the temporary window-recreation fallback below.
        guard statusItem != nil else { return false }
        // AppKit 的状态项命中区比 button.bounds 宽几 pt——放宽 6pt 对齐它的行为，
        // 否则贴着图标边缘的点击会被当成「外部点击」误杀面板。
        if let button = statusItem?.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            lastStatusItemRect = rect
            return rect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        }
        // button.window 在状态项刚创建/窗口重建的极短窗口里可能是 nil：
        // 退回上次缓存的位置判断；连缓存都没有时宁可当成图标点击放过
        // （图标自己的 action 会打开设置），不能让外部关闭误杀刚弹出的面板。
        guard let rect = lastStatusItemRect else { return true }
        return rect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
    }

    private func handleInput(_ event: NSEvent) -> NSEvent? {
        guard let panel, AppModel.shared.isOpen else { return event }
        if event.type == .flagsChanged {
            let option = event.modifierFlags.contains(.option)
            if AppModel.shared.isOptionPressed != option {
                AppModel.shared.isOptionPressed = option
            }
            return event
        }
        // Let the sheet own clicks, Escape, and keyboard focus until it finishes.
        guard panel.attachedSheet == nil else { return event }
        if event.type == .leftMouseUp {
            if AppModel.shared.draggingID != nil {
                AppModel.shared.scheduleEndDrag()
            }
            return event
        }
        if event.type == .leftMouseDown {
            if event.window === statusItem?.button?.window { return event }
            if event.window === panel {
                AppModel.shared.recordPointerDown(at: event.timestamp)
            }
            if let window = event.window, window !== panel, window.level.rawValue > Self.coverLevel.rawValue {
                return event
            }
            if event.window !== panel {
                AppModel.shared.closeFromPointer()
            }
            return event
        }
        if event.type == .keyDown, event.keyCode == 53, event.window === panel || panel.isKeyWindow {
            AppModel.shared.closeTop()
            return nil
        }
        if event.type == .keyDown, (event.window === panel || panel.isKeyWindow) {
            let model = AppModel.shared
            if model.query.isEmpty, model.openFolderID == nil, !model.folderNameEditing {
                if event.keyCode == 123 { model.turnPage(-1); return nil }
                if event.keyCode == 124 { model.turnPage(1); return nil }
            }
        }
        if event.type == .scrollWheel, event.window === panel {
            return handlePageSwipe(event)
        }
        return event
    }

    private func handlePageSwipe(_ event: NSEvent) -> NSEvent? {
        let model = AppModel.shared
        guard model.settings.browsing != .scroll, model.openFolderID == nil, model.query.isEmpty,
              model.draggingID == nil else { return event }
        if event.momentumPhase.rawValue != 0 { return nil }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas {
            if abs(dy) > 1.0 { model.turnPage(dy > 0 ? -1 : 1) }
            else if abs(dx) > abs(dy), abs(dx) > 2 { model.turnPage(dx > 0 ? -1 : 1) }
            return nil
        }
        let phase = event.phase
        let width = max(model.paging.presentation.sample?.pageWidth ?? panel?.frame.width ?? 0, 1)
        if phase.contains(.began)
            || (!model.paging.isSwiping && (phase.contains(.changed) || phase.contains(.stationary))) {
            let presented = model.paging.presentedOffset(on: model.clampedPage)
            let resisted = (model.clampedPage == 0 && presented > 0)
                || (model.clampedPage == model.pages.count - 1 && presented < 0)
            // Undo the edge resistance before accumulating new finger motion.
            // Otherwise touching an existing bounce would apply resistance twice.
            swipeAccum = resisted ? presented / 0.42 : presented
            swipeSamples = []
            model.paging.interruptedSettlement = !model.paging.isSwiping
                && abs(presented - model.paging.offset) > 1
            model.paging.isSwiping = true
            model.paging.offset = presented
        }
        guard model.paging.isSwiping else { return event }
        swipeAccum += dx
        swipeSamples.append((event.timestamp, dx))
        swipeSamples = swipeSamples.filter { event.timestamp - $0.0 < 0.12 }

        var offset = swipeAccum
        let atStart = model.clampedPage <= 0
        let atEnd = model.clampedPage >= model.pages.count - 1
        if (atStart && offset > 0) || (atEnd && offset < 0) { offset *= 0.42 }
        model.paging.offset = max(-width, min(width, offset))

        swipeIdleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settleSwipe() }
        swipeIdleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)

        if phase.contains(.ended) || phase.contains(.cancelled) {
            settleSwipe(cancelled: phase.contains(.cancelled))
        }
        return nil
    }

    private func settleSwipe(cancelled: Bool = false) {
        swipeIdleWork?.cancel()
        swipeIdleWork = nil
        let model = AppModel.shared
        guard model.paging.isSwiping else { return }
        let width = max(model.paging.presentation.sample?.pageWidth ?? panel?.frame.width ?? 0, 1)
        let span = max((swipeSamples.last?.0 ?? 0) - (swipeSamples.first?.0 ?? 0), 0.03)
        let velocity = swipeSamples.reduce(0) { $0 + $1.1 } / span
        // A page fills the screen, but finger travel should stay short on a
        // large display too. Keep a small dead zone so a noisy sample cannot
        // become a flick just because its timestamp interval is very short.
        let flick = abs(velocity) > 360 && abs(swipeAccum) >= 14
        let dragged = abs(swipeAccum) >= min(60, max(36, width * 0.055))
        let pageDelta: Int
        if cancelled {
            pageDelta = 0
        } else if model.paging.interruptedSettlement {
            // After catching a spring between pages, decide from its real
            // position. Its residual offset is not new finger travel.
            let projected = model.paging.offset + velocity * 0.12
            let destination = Int((CGFloat(model.clampedPage) - projected / width).rounded())
            pageDelta = max(-1, min(1, destination - model.clampedPage))
        } else {
            pageDelta = dragged || flick ? ((dragged ? swipeAccum : velocity) > 0 ? -1 : 1) : 0
        }
        let settle: Animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.42, dampingFraction: 0.84)
        withAnimation(settle) {
            model.paging.isSwiping = false
            model.paging.offset = 0
            if pageDelta != 0 { model.turnPage(pageDelta) }
        }
        model.paging.interruptedSettlement = false
        swipeAccum = 0
        swipeSamples = []
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        AppModel.shared.close()
        return false
    }
}

final class PanelHost<Content: View>: NSHostingView<Content> {
    /// 面板常在 App 还没激活完就吃到第一次点击；不接管 first mouse 的话那一下只会用来激活窗口。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        AppModel.shared.closeTop()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            AppModel.shared.closeTop()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
enum SettingsOpener {
    private static var window: NSWindow?

    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        let window = self.window ?? makeWindow()
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppModel.shared.keepOutOfDock()
    }

    private static func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(model: AppModel.shared))
        let window = NSWindow(contentViewController: host)
        window.title = "Pinchpad 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(SettingsView.windowSize)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }
}
