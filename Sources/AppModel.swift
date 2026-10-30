import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    private static let panelCloseSuppressInterval: TimeInterval = 0.35
    private static let dragIgnoreInterval: TimeInterval = 0.3
    private static let edgeNudgeDelay: TimeInterval = 0.28
    private static let edgeTurnDelay: TimeInterval = 0.55
    private static let edgeDragThreshold: CGFloat = 70
    private static let gapSettleDelay: TimeInterval = 0.045
    private static let folderHoverDelay: TimeInterval = 0.3
    private static let hotCornerInset: CGFloat = 6
    private static let hotCornerActivationDelay: TimeInterval = 0.12

    @Published var settings: Preferences {
        didSet {
            guard ready, settings != oldValue else { return }
            persist()
            if settings.sources != oldValue.sources {
                updateAppSources()
            }
            if settings.f4Enabled != oldValue.f4Enabled
                || settings.hotKeyCode != oldValue.hotKeyCode
                || settings.hotKeyModifiers != oldValue.hotKeyModifiers {
                notice = registerHotKey()
            }
            if settings.terminalHotKeyEnabled != oldValue.terminalHotKeyEnabled
                || settings.terminalHotKeyCode != oldValue.terminalHotKeyCode
                || settings.terminalHotKeyModifiers != oldValue.terminalHotKeyModifiers {
                notice = registerTerminalHotKey()
            }
            if settings.hotCorner != oldValue.hotCorner {
                CornerMonitor.shared.apply(settings.hotCorner)
            }
            if settings.pinchThree != oldValue.pinchThree || settings.pinchFour != oldValue.pinchFour {
                PinchMonitor.shared.apply(counts: settings.pinchCounts,
                                          threeSensitivity: settings.pinchThreeSensitivity,
                                          fourSensitivity: settings.pinchFourSensitivity)
            } else if settings.pinchThreeSensitivity != oldValue.pinchThreeSensitivity
                        || settings.pinchFourSensitivity != oldValue.pinchFourSensitivity {
                PinchMonitor.shared.setSensitivities(three: settings.pinchThreeSensitivity,
                                                    four: settings.pinchFourSensitivity)
            }
            if settings.showMenuBar != oldValue.showMenuBar {
                AppDelegate.current?.refreshTray()
            }
            if settings.showDockIcon != oldValue.showDockIcon {
                let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory
                NSApp.setActivationPolicy(policy)
            }
            if settings.launchAtLogin != oldValue.launchAtLogin {
                applyLaunchAtLogin()
            }
            if isOpen, settings.hideDockWhileOpen != oldValue.hideDockWhileOpen {
                onOpenChange?(true)
            }
            let layoutChanged = settings.browsing != oldValue.browsing
                || settings.columns != oldValue.columns
                || settings.rows != oldValue.rows
                || settings.showOn != oldValue.showOn
            if isOpen && layoutChanged {
                onOpenChange?(true)
            }
        }
    }
    @Published var apps: [AppItem] {
        didSet { rebuildIndexes() }
    }
    @Published var folders: [FolderItem] {
        didSet { rebuildIndexes() }
    }
    @Published var pages: [Page]
    @Published var currentPage: Int
    /// 收进菜单栏收纳面板的应用，按钉选先后排序。
    @Published var pinnedAppIDs: [String]
    @Published var pageDirection: Int = 1
    @Published var isOpen = false
    let entrance = EntranceMotion()
    private var entranceNeedsReplay = true
    @Published var query = ""
    @Published var selection: Set<String> = []
    @Published var openFolderID: UUID?
    @Published var isScanning = false
    @Published var notice: String?
    @Published var draggingID: String?
    @Published var folderHoverID: String?
    @Published var folderNameEditing = false
    @Published var isOptionPressed = false {
        didSet {
            guard isOptionPressed != oldValue else { return }
            jiggleTimer?.invalidate()
            jiggleTimer = nil
            if isOptionPressed {
                let timer = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if !NSEvent.modifierFlags.contains(.option) || !self.isOpen {
                            self.isOptionPressed = false
                            return
                        }
                        self.jiggleTick &+= 1
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                jiggleTimer = timer
            } else {
                jiggleTick = 0
            }
        }
    }
    @Published var jiggleTick = 0
    private var jiggleTimer: Timer?
    let paging = PagingMotion()
    @Published var iconRevision = 0
    private(set) var libraryRevision = 0

    /// 参数表示是否保留显示/关闭动画；启动应用时立即收起面板。
    var onOpenChange: ((Bool) -> Void)?
    /// 每次扫描完成后触发（含「无变化」的早退），用于预热面板渲染。
    var onContentReady: (() -> Void)?
    /// 面板淡入/淡出期间为 false：此时不响应 hover，避免和窗口动画抢帧。
    /// 刻意不做 @Published——它只影响事件处理，不应该触发整棵视图树重算。
    var interactionReady = true
    private var ignorePointerUntil = Date.distantPast
    private var pointerSessionBegan: TimeInterval = 0
    private var pointerPressBegan: TimeInterval?
    private var suppressPanelCloseUntil = Date.distantPast
    private var edgeTimer: Timer?
    private var pendingHoverID: String?
    private var hoverMark: Date?
    private var previewAnchorPoint: CGPoint?
    private var dragDirty = false
    private var orderAtDragStart: [Slot] = []
    private var previewIndex: Int?
    private var lastEdgeTurn = Date.distantPast
    private var edgeArmed: Date?
    private var slotFrames: [String: CGRect] = [:]
    private var dragPanel: NSPanel?
    private var dragMonitor: Any?
    private var pendingGap: Int?
    private var pendingGapMark: Date?
    private var ready = false
    private var iconCache: [String: NSImage] = [:]
    private var iconPrefetchTask: Task<Void, Never>?
    private var iconPrefetchGeneration = 0
    private let fileURL: URL
    private let persistQueue = DispatchQueue(label: "app.local.pinchpad.persist", qos: .utility)
    private var appsByID: [String: AppItem] = [:]
    private var foldersByID: [UUID: FolderItem] = [:]
    private var rescanPending = false
    private lazy var appLibraryMonitor = AppLibraryMonitor { [weak self] in self?.rescan() }

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let directory = appSupport.appendingPathComponent("Pinchpad")
        let legacy = appSupport.appendingPathComponent("Gepan")
        if let stale = try? FileManager.default.contentsOfDirectory(atPath: legacy.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in stale {
                let destination = directory.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.moveItem(at: legacy.appendingPathComponent(name), to: destination)
                }
            }
            try? FileManager.default.removeItem(at: legacy)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
            settings = snapshot.settings
            apps = snapshot.apps
            folders = snapshot.folders
            pages = snapshot.pages.isEmpty ? [Page()] : snapshot.pages
            currentPage = snapshot.currentPage
            pinnedAppIDs = snapshot.pinnedAppIDs ?? []
        } else {
            settings = Preferences()
            apps = []
            folders = []
            pages = [Page()]
            currentPage = 0
            pinnedAppIDs = []
        }
        rebuildIndexes()
        ready = true
        wireMonitors()
        updateAppSources()
        prefetchIcons()
    }

    func icon(for app: AppItem) -> NSImage {
        if let cached = iconCache[app.id] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.path)
        image.size = NSSize(width: 128, height: 128)
        iconCache[app.id] = image
        return image
    }

    private func prefetchIcons() {
        iconPrefetchTask?.cancel()
        iconPrefetchGeneration += 1
        let generation = iconPrefetchGeneration
        let missing = apps.filter { iconCache[$0.id] == nil }
        guard !missing.isEmpty else {
            iconPrefetchTask = nil
            return
        }
        iconPrefetchTask = Task.detached(priority: .utility) {
            var loaded: [(id: String, path: String, image: NSImage)] = []
            for app in missing {
                guard !Task.isCancelled else { return }
                let image = NSWorkspace.shared.icon(forFile: app.path)
                image.size = NSSize(width: 128, height: 128)
                // NSImage 的位图是惰性解码的；这里预解出 CGImage 缓存进 rep，
                // 否则第一次打开时几十张图标会在主线程同步解码。
                var proposed = NSRect(origin: .zero, size: image.size)
                _ = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
                loaded.append((app.id, app.path, image))
            }
            guard !Task.isCancelled else { return }
            let images = loaded
            await MainActor.run {
                let model = AppModel.shared
                guard model.iconPrefetchGeneration == generation else { return }
                var added = false
                for item in images where model.appsByID[item.id]?.path == item.path && model.iconCache[item.id] == nil {
                    model.iconCache[item.id] = item.image
                    added = true
                }
                model.iconPrefetchTask = nil
                if added { model.iconRevision += 1 }
            }
        }
    }

    func app(_ id: String) -> AppItem? { appsByID[id] }
    func folder(_ id: UUID) -> FolderItem? { foldersByID[id] }

    private func rebuildIndexes() {
        appsByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        libraryRevision += 1
    }

    var openFolder: FolderItem? {
        guard let openFolderID else { return nil }
        return folder(openFolderID)
    }

    func slots(on page: Int) -> [Slot] {
        guard pages.indices.contains(page) else { return [] }
        return pages[page].slots.filter(isVisible)
    }

    var visibleSlots: [Slot] {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            return searchSlots()
        }
        if settings.browsing == .scroll {
            return pages.flatMap(\.slots).filter(isVisible)
        }
        let index = clampedPage
        return pages[index].slots.filter(isVisible)
    }

    var clampedPage: Int {
        min(max(0, currentPage), max(0, pages.count - 1))
    }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func openFromPinch() {
        if !isOpen { open() }
    }

    private var pointerGuarded: Bool {
        Date() < ignorePointerUntil || Date() < PinchMonitor.shared.pinchPointerGuardUntil()
    }

    func beginPointerSession() {
        pointerSessionBegan = ProcessInfo.processInfo.systemUptime
        pointerPressBegan = nil
    }

    func recordPointerDown(at timestamp: TimeInterval) {
        guard isOpen, draggingID == nil, timestamp >= pointerSessionBegan else { return }
        pointerPressBegan = timestamp
    }

    func closeFromPointer() {
        guard !pointerGuarded else { return }
        close()
    }

    func open() {
        // 已经打开时（Dock 图标被再点一次、open -a 等）不要再走一遍打开流程：
        // 否则会把图标复位成隐藏态却不播动画，面板会变成空的。
        guard !isOpen else { return }
        beginPointerSession()
        // 淡出尚未结束就重新打开时，当前图标仍在原位；只延续窗口过渡。
        // 返回另一页则需要为新的目标页播放入场。
        if settings.returnToFirstPage, currentPage != 0 {
            currentPage = 0
            entranceNeedsReplay = true
        }
        if entranceNeedsReplay { prepareEntrance() }
        // 只有在应用未激活时才激活；重复 open 时把省下的激活等待让给淡入。
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        // 下面这些在 completeClose 里都已经清空；只有真的非空才发布，避免隐藏态整树重绘。
        if !query.isEmpty { query = "" }
        if !selection.isEmpty { selection = [] }
        if openFolderID != nil { openFolderID = nil }
        if folderNameEditing { folderNameEditing = false }
        isOpen = true
        onOpenChange?(true)
    }

    func prepareEntrance() {
        entranceNeedsReplay = true
        entrance.prepare()
    }

    @discardableResult
    func beginEntrance() -> Bool {
        guard entranceNeedsReplay else { return false }
        entranceNeedsReplay = false
        entrance.play()
        return true
    }

    func close(animated: Bool = true) {
        guard isOpen else {
            // 另一入口可能在普通淡出结束前启动应用，仍需立即移除旧面板。
            if !animated { onOpenChange?(false) }
            return
        }
        // 拖拽中关面板（Esc / 点外部 / 捏合）时，否则 60Hz 的 edgeTimer 和
        // 拖拽浮窗会一直留在隐藏态。
        if draggingID != nil {
            endDrag()
        }
        paging.offset = 0
        paging.isSwiping = false
        isOpen = false
        onOpenChange?(animated)
    }

    func completeClose() {
        guard !isOpen else { return }
        entranceNeedsReplay = true
        // 同样只在真正有值时才发布：隐藏面板不需要为四个空值再整树重绘一次。
        if openFolderID != nil { openFolderID = nil }
        if folderNameEditing { folderNameEditing = false }
        if !selection.isEmpty { selection = [] }
        if !query.isEmpty { query = "" }
    }

    func closeTop() {
        if folderNameEditing {
            folderNameEditing = false
            suppressPanelCloseUntil = Date().addingTimeInterval(Self.panelCloseSuppressInterval)
            return
        }
        if openFolderID != nil {
            folderNameEditing = false
            openFolderID = nil
            suppressPanelCloseUntil = Date().addingTimeInterval(Self.panelCloseSuppressInterval)
            return
        }
        if Date() < suppressPanelCloseUntil { return }
        if !query.isEmpty {
            query = ""
            return
        }
        close()
    }

    func turnPage(_ delta: Int) {
        guard query.isEmpty, settings.browsing != .scroll, openFolderID == nil else { return }
        let next = min(max(0, clampedPage + delta), max(0, pages.count - 1))
        guard next != clampedPage else { return }
        pageDirection = next > clampedPage ? 1 : -1
        currentPage = next
        if draggingID == nil { persist() }
    }

    func showPage(_ index: Int) {
        let next = min(max(0, index), max(0, pages.count - 1))
        guard next != clampedPage else { return }
        pageDirection = next > clampedPage ? 1 : -1
        currentPage = next
        persist()
    }

    var hotKeyLabel: String {
        HotKeyCenter.title(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
    }

    var terminalHotKeyLabel: String {
        HotKeyCenter.title(keyCode: settings.terminalHotKeyCode, modifiers: settings.terminalHotKeyModifiers)
    }

    func registerHotKey() -> String? {
        HotKeyCenter.shared.apply(
            id: HotKeyCenter.launcherID,
            enabled: settings.f4Enabled,
            keyCode: settings.hotKeyCode,
            modifiers: settings.hotKeyModifiers
        ) { AppModel.shared.toggle() }
    }

    func registerTerminalHotKey() -> String? {
        HotKeyCenter.shared.apply(
            id: HotKeyCenter.terminalID,
            enabled: settings.terminalHotKeyEnabled,
            keyCode: settings.terminalHotKeyCode,
            modifiers: settings.terminalHotKeyModifiers
        ) { AppModel.shared.openTerminal() }
    }

    // MARK: - 终端快捷键

    /// 终端启动目录：展开 ~，留空时使用用户主目录；失效目录在打开时提示。
    var resolvedTerminalDirectory: String {
        let expanded = (settings.terminalDirectory as NSString).expandingTildeInPath
        if expanded.isEmpty { return FileManager.default.homeDirectoryForCurrentUser.path }
        return expanded
    }

    /// 终端应用：配置了但文件已不在时退回系统自带 Terminal.app。
    var resolvedTerminalAppPath: String {
        let path = settings.terminalAppPath
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) { return path }
        return "/System/Applications/Utilities/Terminal.app"
    }

    var terminalDirectoryLabel: String {
        resolvedTerminalDirectory.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"
        )
    }

    var terminalAppLabel: String {
        URL(fileURLWithPath: resolvedTerminalAppPath).deletingPathExtension().lastPathComponent
    }

    /// 全局快捷键入口：在选定终端里打开一个新窗口，工作目录固定为配置目录。
    /// 走 LaunchServices 的 open-documents（等价 `open -a 终端 目录`），
    /// Terminal / iTerm 这类应用收到文件夹会把它当成新会话的 cwd。
    func openTerminal() {
        let directory = resolvedTerminalDirectory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            notice = "终端启动目录不存在：\(terminalDirectoryLabel)。到设置里重新选一个。"
            return
        }
        let appURL = URL(fileURLWithPath: resolvedTerminalAppPath)
        close()
        AppDelegate.current?.dismissTray()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: directory, isDirectory: true)],
            withApplicationAt: appURL, configuration: configuration
        ) { _, error in
            guard let error else { return }
            Task { @MainActor in
                AppModel.shared.notice = "没能打开终端：\(error.localizedDescription)"
            }
        }
    }

    func chooseTerminalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: resolvedTerminalDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.terminalDirectory = url.path
    }

    func chooseTerminalApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.terminalAppPath = url.path
    }

    func targetScreen() -> NSScreen? {
        switch settings.showOn {
        case .main:
            return NSScreen.screens.first
        case .cursor:
            let point = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        case .active:
            return NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        }
    }

    func windowSize(for screen: NSScreen) -> NSSize {
        let cell: CGFloat = 104
        let width = CGFloat(settings.columns) * cell + 96
        let height = CGFloat(settings.rows) * cell + 150
        return NSSize(
            width: min(width, screen.visibleFrame.width - 80),
            height: min(height, screen.visibleFrame.height - 80)
        )
    }

    func rescan() {
        guard !isScanning else {
            rescanPending = true
            return
        }
        isScanning = true
        let paths = settings.sources.filter(\.enabled).map(\.path)
        Task.detached(priority: .utility) { [weak self] in
            let found = AppScanner.scan(paths: paths)
            await self?.finishScan(found, paths: paths)
        }
    }

    private func updateAppSources() {
        appLibraryMonitor.apply(paths: settings.sources.filter(\.enabled).map(\.path))
        rescan()
    }

    private func finishScan(_ found: [AppScanner.Found], paths: [String]) {
        let currentPaths = settings.sources.filter(\.enabled).map(\.path)
        guard !rescanPending, paths == currentPaths else {
            rescanPending = false
            isScanning = false
            rescan()
            return
        }
        merge(found)
    }

    func launch(_ app: AppItem) {
        // 先移除面板，下一轮主循环再联系 Launch Services，避免启动或历史更新
        // 阻塞点击反馈。Esc、背景点击等普通关闭仍保留淡出动画。
        close(animated: false)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: app.path), configuration: configuration
            ) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    AppModel.shared.notice = "没能打开应用：\(error.localizedDescription)"
                }
            }
            if let index = self.apps.firstIndex(where: { $0.id == app.id }) {
                self.apps[index].lastOpenedAt = Date()
                self.persist()
            }
        }
    }

    func activate(_ slot: Slot) {
        // A new mouse press after this panel opened is explicit intent. The pinch
        // tail only guards releases inherited from the gesture that opened it.
        let freshPress = pointerPressBegan != nil
        pointerPressBegan = nil
        guard draggingID == nil, freshPress || !pointerGuarded else { return }
        if case .app(let id) = slot,
           settings.optionClickUninstall,
           NSEvent.modifierFlags.contains(.option),
           let app = app(id) {
            promptUninstall(app)
            return
        }
        switch slot {
        case .app(let id):
            guard let app = app(id) else { return }
            launch(app)
        case .folder(let id):
            openFolderID = id
            selection = []
        }
    }

    func toggleSelect(_ slot: Slot) {
        pointerPressBegan = nil
        if selection.contains(slot.id) {
            selection.remove(slot.id)
        } else {
            selection.insert(slot.id)
        }
    }

    func move(_ sourceID: String, onto targetID: String) {
        guard sourceID != targetID, query.isEmpty else { return }
        guard let from = flatIndex(of: sourceID), let to = flatIndex(of: targetID), from != to else { return }
        adoptCustomOrder()
        guard let source = removeSlot(sourceID) else { return }
        if from < to {
            insert(source, after: targetID)
        } else {
            insert(source, before: targetID)
        }
        persist()
    }

    func noteSlotFrames(_ frames: [String: CGRect]) {
        // 滑动时暂停收集，保留上一份命中区域；收尾恢复后立即接收最新坐标。
        if paging.isSwiping && settings.browsing != .scroll && query.isEmpty { return }
        slotFrames = frames
    }

    func beginDrag(_ id: String, iconWidth: CGFloat? = nil) {
        pointerPressBegan = nil
        guard draggingID == nil, !paging.isSwiping, query.isEmpty, openFolderID == nil else { return }
        adoptCustomOrder()
        draggingID = id
        folderHoverID = nil
        pendingHoverID = nil
        hoverMark = nil
        previewAnchorPoint = nil
        edgeArmed = nil
        dragDirty = false
        orderAtDragStart = pages.flatMap(\.slots)
        previewIndex = nil
        pendingGap = nil
        pendingGapMark = nil
        showDragImage(for: id, iconWidth: iconWidth)
        edgeTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointerDrag() }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeTimer = timer
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.trackPointerDrag() }
            return event
        }
    }

    func scheduleEndDrag() {
        endDrag()
    }

    func endDrag() {
        guard draggingID != nil else { return }
        let source = draggingID
        let folderTarget = folderHoverID
        let dirty = dragDirty
        draggingID = nil
        folderHoverID = nil
        pendingHoverID = nil
        hoverMark = nil
        previewAnchorPoint = nil
        dragDirty = false
        pendingGap = nil
        pendingGapMark = nil
        edgeTimer?.invalidate()
        edgeTimer = nil
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
        hideDragImage()
        ignorePointerUntil = Date().addingTimeInterval(Self.dragIgnoreInterval)
        if let source, let folderTarget, folderTarget != source {
            writeBack(orderAtDragStart)
            absorb(source, into: folderTarget)
        } else if dirty {
            reflow()
            persist()
        }
    }

    func rename(_ slot: Slot) {
        let current: String
        switch slot {
        case .app(let id): current = app(id)?.effectiveName ?? ""
        case .folder(let id): current = folder(id)?.name ?? ""
        }
        promptText("重命名", value: current) { next in
            guard let next, !next.isEmpty else { return }
            switch slot {
            case .app(let id):
                guard let index = self.apps.firstIndex(where: { $0.id == id }) else { return }
                self.apps[index].customName = next
            case .folder(let id):
                guard let index = self.folders.firstIndex(where: { $0.id == id }) else { return }
                self.folders[index].name = next
            }
            self.persist()
        }
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folderNameEditing = false
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = trimmed
        persist()
    }

    func hide(_ slot: Slot) {
        switch slot {
        case .app(let id):
            guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
            apps[index].hidden = true
        case .folder:
            return
        }
        selection = []
        persist()
    }

    func unhide(_ id: String) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[index].hidden = false
        persist()
    }

    func reveal(_ app: AppItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    func makeFolder(from slots: [Slot]) {
        let ids = slots.compactMap { slot -> String? in
            if case .app(let id) = slot { return id }
            return nil
        }
        guard !ids.isEmpty else { return }
        let folder = FolderItem(id: UUID(), name: nextFolderName(), appIDs: ids, createdAt: Date())
        folders.append(folder)
        rebuildIndexes()
        for id in ids { _ = removeSlot("a:\(id)") }
        let placed = Slot.folder(folder.id)
        if pages.isEmpty { pages = [Page()] }
        if pages[pages.count - 1].slots.count >= settings.pageCapacity {
            pages.append(Page(slots: [placed]))
        } else {
            pages[pages.count - 1].slots.append(placed)
        }
        selection = []
        persist()
    }

    func ungroup(_ id: UUID) {
        guard let folder = folder(id) else { return }
        guard let pageIndex = pages.firstIndex(where: { $0.slots.contains(.folder(id)) }),
              let slotIndex = pages[pageIndex].slots.firstIndex(of: .folder(id)) else { return }
        pages[pageIndex].slots.remove(at: slotIndex)
        var insertAt = slotIndex
        for appID in folder.appIDs where apps.contains(where: { $0.id == appID }) {
            pages[pageIndex].slots.insert(.app(appID), at: min(insertAt, pages[pageIndex].slots.count))
            insertAt += 1
        }
        reflow()
        folders.removeAll { $0.id == id }
        rebuildIndexes()
        if openFolderID == id { openFolderID = nil }
        persist()
    }

    func canUninstall(_ app: AppItem) -> Bool {
        app.bundleID != Bundle.main.bundleIdentifier && !app.path.hasPrefix("/System")
    }

    func promptUninstall(_ app: AppItem) {
        if app.bundleID == Bundle.main.bundleIdentifier { 
            notice = "不能移除正在运行的 Pinchpad。"
            return
        }
        if app.path.hasPrefix("/System") {
            notice = "系统应用留在原地，Pinchpad 不会移除它。"
            return
        }
        let alias = RelatedFiles.isAlias(app.path)
        let related = alias ? [] : RelatedFiles.candidates(for: app)
        let alert = NSAlert()
        alert.messageText = alias ? "移除替身？" : "把「\(app.effectiveName)」移到废纸篓？"
        if related.isEmpty {
            alert.informativeText = alias
                ? "只会移除替身，原应用还在。"
                : "应用包会移到废纸篓。没有发现同名的支持文件。"
        } else {
            let lines = related.prefix(12).map(\.path).joined(separator: "\n")
            alert.informativeText = "同时把这些相关文件移到废纸篓：\n\(lines)"
            if related.count > 12 {
                alert.informativeText += "\n以及另外 \(related.count - 12) 项"
            }
        }
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        presentAlert(alert) { response in
            guard response == .alertFirstButtonReturn else { return }
            var urls = [URL(fileURLWithPath: app.path)]
            urls.append(contentsOf: related)
            do {
                try Trash.move(urls)
                self.removeAppCompletely(app.id)
                self.notice = "已移到废纸篓。"
            } catch {
                self.notice = "没能移走：\(error.localizedDescription)"
            }
        }
    }

    /// 菜单栏收纳面板里钉住的应用，钉不到的（已被扫描移除的）自动过滤掉。
    var pinnedApps: [AppItem] {
        pinnedAppIDs.compactMap { app($0) }
    }

    /// 收纳面板先显示缓存，再异步刷新菜单栏图标，按屏幕上的左右顺序排列。
    @Published var runningApps: [RunningApp] = []
    private var runningAppsRefreshTask: Task<Void, Never>?
    private var runningAppsRefreshGeneration = 0

    /// 托盘「菜单栏」区只收真正在菜单栏有图标的应用——读进程的
    /// AXExtrasMenuBar，第一个子项就是它的图标；顺路拿回图标元素
    /// 和屏幕上 x 坐标：x 用来按菜单栏真实左右顺序排，元素留下来
    /// 给点按时直接 press 真图标。
    private nonisolated static func menuBarItem(processID: pid_t) -> (item: AXUIElement, x: CGFloat)? {
        let ax = AXUIElementCreateApplication(processID)
        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, "AXExtrasMenuBar" as CFString, &extras) == .success,
              let bar = extras else { return nil }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, "AXChildren" as CFString, &children) == .success,
              let items = children as? [AXUIElement], let item = items.first else { return nil }
        var x = CGFloat.greatestFiniteMagnitude
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(item, "AXPosition" as CFString, &value) == .success,
           let position = value {
            var point = CGPoint.zero
            if AXValueGetValue(position as! AXValue, .cgPoint, &point) { x = point.x }
        }
        return (item, x)
    }

    private func userFacing(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated, let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              app.activationPolicy != .prohibited,
              app.localizedName != nil,
              app.bundleURL?.path.hasPrefix("/System") == false else { return false }
        // 在全屏面板里被用户隐藏过的应用，托盘里也不显示。
        if let catalog = catalogApp(bundleID: bundleID), catalog.hidden { return false }
        return true
    }

    func refreshRunningApps() {
        runningAppsRefreshGeneration &+= 1
        var seen = Set<String>()
        let candidates = NSWorkspace.shared.runningApplications.filter {
            userFacing($0) && seen.insert($0.bundleIdentifier!).inserted
        }
        let validPIDs = Set(candidates.map(\.processIdentifier))
        let cached = runningApps.filter { validPIDs.contains($0.application.processIdentifier) }
        if cached.count != runningApps.count { runningApps = cached }

        // AX 跨进程查询可能很慢；只把 PID 交给后台，应用对象始终留在主线程。
        // 启动/退出或再次打开只合并一次待刷新请求，不并行堆积 AX 查询。
        guard runningAppsRefreshTask == nil else { return }
        let generation = runningAppsRefreshGeneration
        let processIDs = candidates.map(\.processIdentifier)
        runningAppsRefreshTask = Task { @MainActor in
            let items = await Task.detached(priority: .userInitiated) {
                processIDs.compactMap { processID -> (pid: pid_t, item: AXUIElement, x: CGFloat)? in
                    guard let (item, x) = Self.menuBarItem(processID: processID) else { return nil }
                    return (processID, item, x)
                }.sorted { $0.x < $1.x }
            }.value
            self.runningAppsRefreshTask = nil
            guard generation == self.runningAppsRefreshGeneration else {
                self.refreshRunningApps()
                return
            }
            let applications = Dictionary(uniqueKeysWithValues: candidates.map { ($0.processIdentifier, $0) })
            self.runningApps = items.compactMap { item in
                guard let app = applications[item.pid], self.userFacing(app) else { return nil }
                return RunningApp(application: app, menuBarItem: item.item, menuBarX: item.x)
            }
        }
    }

    /// 钉选应用是否正在运行——托盘在图标角上画小圆点。
    /// 查的是全部在跑进程，不是菜单栏区那张缩过的表。
    func isRunning(_ app: AppItem) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }
    }

    /// 运行中应用想收进菜单栏时，先回扫描目录里找对应的 AppItem；
    /// 目录里没有（不在扫描路径上的应用）返回 nil，托盘就不给钉选入口。
    func catalogApp(bundleID: String) -> AppItem? {
        appsByID.values.first { $0.bundleID == bundleID }
    }

    func isPinned(_ app: AppItem) -> Bool {
        pinnedAppIDs.contains(app.id)
    }

    func togglePin(_ app: AppItem) {
        if let index = pinnedAppIDs.firstIndex(of: app.id) {
            pinnedAppIDs.remove(at: index)
        } else {
            pinnedAppIDs.append(app.id)
        }
        persist()
    }

    func pinToDock(_ app: AppItem) {
        let alert = NSAlert()
        alert.messageText = "固定到 Dock？"
        alert.informativeText = "这会改写 Dock 的列表并重新启动 Dock。"
        alert.addButton(withTitle: "固定")
        alert.addButton(withTitle: "取消")
        presentAlert(alert) { response in
            guard response == .alertFirstButtonReturn else { return }
            do {
                try DockPin.add(app: app)
                self.notice = "已固定到 Dock。"
            } catch {
                self.notice = "没能固定：\(error.localizedDescription)"
            }
        }
    }

    func reorganizeNow() {
        let options = settings.reorganize
        var pool: [Slot]
        if options.allPages {
            pool = pages.flatMap(\.slots)
        } else {
            pool = pages[clampedPage].slots
        }
        pool = pool.filter(isVisible)
        if options.sortInsideFolders {
            for index in folders.indices {
                folders[index].appIDs = sortAppIDs(folders[index].appIDs, by: options.sortBy, ascending: options.ascending)
            }
        }
        let ranked = pool.sorted { lhs, rhs in
            rankedLess(lhs, rhs, options: options)
        }
        if options.allPages {
            pages = paginate(ranked)
            currentPage = 0
        } else {
            pages[clampedPage].slots = ranked
        }
        settings.sortBy = .custom
        persist()
    }

    func importSystemLayout() {
        switch SystemLayoutImport.load() {
        case .failure(let error):
            notice = error.message
        case .success(let layout):
            var used = Set<String>()
            var newFolders: [FolderItem] = []
            var slots: [Slot] = []
            for entry in layout.folders {
                let ids = entry.bundleIDs.compactMap { bundle in
                    apps.first { $0.bundleID == bundle }?.id
                }
                guard !ids.isEmpty else { continue }
                let folder = FolderItem(id: UUID(), name: entry.name, appIDs: ids, createdAt: Date())
                newFolders.append(folder)
                slots.append(.folder(folder.id))
                used.formUnion(ids)
            }
            for bundle in layout.looseBundleIDs {
                guard let id = apps.first(where: { $0.bundleID == bundle })?.id, !used.contains(id) else { continue }
                slots.append(.app(id))
                used.insert(id)
            }
            for app in apps where !app.hidden && !used.contains(app.id) {
                slots.append(.app(app.id))
            }
            folders = newFolders
            pages = paginate(slots)
            currentPage = 0
            persist()
            notice = "已按系统应用的顺序重新摆放能对应上的应用。"
        }
    }

    func addSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "添加"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.sources.append(AppSource(id: UUID(), path: url.path, enabled: true, custom: true))
    }

    func removeSource(_ id: UUID) {
        settings.sources.removeAll { $0.id == id && $0.custom }
    }

    func setGrid(columns: Int, rows: Int) {
        settings.columns = columns
        settings.rows = rows
        reflow()
        persist()
    }

    private func merge(_ found: [AppScanner.Found]) {
        let existingByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        var next: [AppItem] = []
        var seen = Set<String>()
        for item in found {
            let id = item.bundleID ?? item.path
            guard seen.insert(id).inserted else { continue }
            if var old = existingByID[id] {
                old.path = item.path
                old.name = item.name
                old.bundleID = item.bundleID
                old.sourcePath = item.sourcePath
                next.append(old)
            } else {
                next.append(AppItem(
                    id: id, path: item.path, bundleID: item.bundleID, name: item.name,
                    customName: nil, hidden: false, addedAt: Date(), lastOpenedAt: nil,
                    sourcePath: item.sourcePath
                ))
            }
        }
        guard next != apps else {
            isScanning = false
            prefetchIcons()
            onContentReady?()
            return
        }
        let kept = Set(next.map(\.id))
        let pruned = pinnedAppIDs.filter { kept.contains($0) }
        if pruned != pinnedAppIDs { pinnedAppIDs = pruned }
        let nextPaths = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0.path) })
        iconCache = iconCache.filter { id, _ in
            guard let path = nextPaths[id] else { return false }
            return path == existingByID[id]?.path
        }
        apps = next
        let updatedFolders = folders.compactMap { folder -> FolderItem? in
            var copy = folder
            copy.appIDs = folder.appIDs.filter { kept.contains($0) }
            return copy.appIDs.isEmpty ? nil : copy
        }
        if updatedFolders != folders { folders = updatedFolders }
        let folderIDs = Set(folders.map(\.id))
        if let openFolderID, !folderIDs.contains(openFolderID) {
            self.openFolderID = nil
        }
        let validSelection = Set(kept.map { Slot.app($0).id } + folderIDs.map { Slot.folder($0).id })
        let nextSelection = selection.intersection(validSelection)
        if nextSelection != selection { selection = nextSelection }
        for index in pages.indices {
            pages[index].slots.removeAll { slot in
                switch slot {
                case .app(let id): return !kept.contains(id)
                case .folder(let id): return !folderIDs.contains(id)
                }
            }
        }
        let placed = Set(pages.flatMap(\.slots).compactMap { slot -> String? in
            if case .app(let id) = slot { return id }
            return nil
        })
        let inFolders = Set(folders.flatMap(\.appIDs))
        for app in apps where !app.hidden && !placed.contains(app.id) && !inFolders.contains(app.id) {
            append(.app(app.id))
        }
        if pages.isEmpty { pages = [Page()] }
        reflow()
        currentPage = min(currentPage, pages.count - 1)
        isScanning = false
        prefetchIcons()
        persist()
        onContentReady?()
    }

    private func searchSlots() -> [Slot] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchedApps = apps.filter { app in
            if app.hidden && !settings.showHiddenInSearch { return false }
            return app.effectiveName.localizedCaseInsensitiveContains(needle)
                || (app.bundleID?.localizedCaseInsensitiveContains(needle) ?? false)
        }.map { Slot.app($0.id) }
        let matchedFolders = folders.filter { $0.name.localizedCaseInsensitiveContains(needle) }.map { Slot.folder($0.id) }
        return matchedFolders + matchedApps
    }

    private func isVisible(_ slot: Slot) -> Bool {
        switch slot {
        case .app(let id):
            guard let app = app(id) else { return false }
            return !app.hidden
        case .folder(let id):
            return folder(id)?.appIDs.isEmpty == false
        }
    }

    private func append(_ slot: Slot) {
        if pages.isEmpty { pages = [Page()] }
        if pages[pages.count - 1].slots.count >= settings.pageCapacity {
            pages.append(Page(slots: [slot]))
        } else {
            pages[pages.count - 1].slots.append(slot)
        }
    }

    private func reflow() {
        let slots = pages.flatMap(\.slots)
        let oldIDs = pages.map(\.id)
        var result = paginate(slots)
        for index in result.indices where index < oldIDs.count {
            result[index].id = oldIDs[index]
        }
        pages = result
    }

    private func paginate(_ slots: [Slot]) -> [Page] {
        let capacity = settings.pageCapacity
        if slots.isEmpty { return [Page()] }
        var result: [Page] = []
        var buffer: [Slot] = []
        for slot in slots {
            buffer.append(slot)
            if buffer.count == capacity {
                result.append(Page(slots: buffer))
                buffer = []
            }
        }
        if !buffer.isEmpty { result.append(Page(slots: buffer)) }
        return result.isEmpty ? [Page()] : result
    }

    private func removeSlot(_ id: String) -> Slot? {
        for pageIndex in pages.indices {
            if let slotIndex = pages[pageIndex].slots.firstIndex(where: { $0.id == id }) {
                return pages[pageIndex].slots.remove(at: slotIndex)
            }
        }
        return nil
    }

    private func trackPointerDrag() {
        guard isOpen, draggingID != nil else { return }
        if NSEvent.pressedMouseButtons & 1 == 0 {
            endDrag()
            return
        }
        moveDragImage()
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Pinchpad" }),
              let content = window.contentView else { return }
        let local = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = CGPoint(x: local.x, y: content.bounds.height - local.y)
        updateDrag(at: point, width: content.bounds.width, now: Date())
    }

    /// Pointer events and dwell ticks share the same state transition. Keeping
    /// the geometry/time boundary here also lets synthetic trajectories exercise
    /// reordering without a window, cursor polling or an event monitor.
    private func updateDrag(at point: CGPoint, width: CGFloat, now: Date) {
        guard let id = draggingID else { return }
        if point.x < Self.edgeDragThreshold || point.x > width - Self.edgeDragThreshold {
            pendingHoverID = nil
            hoverMark = nil
            pendingGap = nil
            pendingGapMark = nil
            previewAnchorPoint = nil
            if folderHoverID != nil { folderHoverID = nil }
            nudgeDragEdge(point.x < Self.edgeDragThreshold ? -1 : 1)
            return
        }
        edgeArmed = nil
        // A preview can move a neighboring icon underneath the stationary
        // pointer. Do not reinterpret that layout motion as a new folder hover.
        if let anchor = previewAnchorPoint {
            guard hypot(point.x - anchor.x, point.y - anchor.y) >= 6 else { return }
            previewAnchorPoint = nil
        }
        if let icon = iconUnderPointer(point), icon != id {
            pendingGap = nil
            pendingGapMark = nil
            if pendingHoverID != icon {
                pendingHoverID = icon
                hoverMark = now
                if folderHoverID != nil { folderHoverID = nil }
                return
            }
            if let mark = hoverMark, now.timeIntervalSince(mark) >= Self.folderHoverDelay,
               folderHoverID != icon {
                folderHoverID = icon
            }
            // Crossing an icon must not undo the preview and snap every shifted
            // cell back. A deliberate dwell arms folder creation only on drop.
            return
        }
        pendingHoverID = nil
        hoverMark = nil
        if folderHoverID != nil { folderHoverID = nil }
        guard let destination = gapInsertionIndex(at: point, dragging: id) else { return }
        guard destination != previewIndex else {
            pendingGap = nil
            return
        }
        if destination != pendingGap {
            pendingGap = destination
            pendingGapMark = now
            return
        }
        guard let mark = pendingGapMark, now.timeIntervalSince(mark) >= Self.gapSettleDelay else { return }
        pendingGap = nil
        previewIndex = destination
        previewGap(id, at: destination)
        previewAnchorPoint = point
    }

    private func nudgeDragEdge(_ delta: Int) {
        if edgeArmed == nil {
            edgeArmed = Date()
            return
        }
        guard let armed = edgeArmed, Date().timeIntervalSince(armed) > Self.edgeNudgeDelay else { return }
        guard Date().timeIntervalSince(lastEdgeTurn) > Self.edgeTurnDelay else { return }
        guard let id = draggingID else { return }
        let before = clampedPage
        turnPage(delta)
        guard clampedPage != before else { return }
        lastEdgeTurn = Date()
        edgeArmed = Date()
        let capacity = max(1, settings.pageCapacity)
        let destination = delta > 0
            ? clampedPage * capacity
            : min(max(0, flatSlotCount() - 1), (clampedPage + 1) * capacity - 1)
        moveDuringDrag(id, toFlatIndex: destination)
        orderAtDragStart = pages.flatMap(\.slots)
        previewIndex = nil
        previewAnchorPoint = nil
        pendingGap = nil
        pendingGapMark = nil
        pendingHoverID = nil
        hoverMark = nil
        folderHoverID = nil
    }

    private func iconUnderPointer(_ point: CGPoint) -> String? {
        var best: (String, CGFloat)?
        for (id, frame) in slotFrames where id != draggingID {
            let icon = CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                              height: min(frame.width, frame.height))
                .insetBy(dx: frame.width * 0.12, dy: frame.width * 0.12)
            guard icon.contains(point) else { continue }
            let distance = hypot(frame.midX - point.x, frame.midY - point.y)
            if best == nil || distance < best!.1 { best = (id, distance) }
        }
        return best?.0
    }

    private func gapInsertionIndex(at point: CGPoint, dragging id: String) -> Int? {
        guard pages.indices.contains(clampedPage) else { return nil }
        let icons = pages[clampedPage].slots.filter { isVisible($0) && $0.id != id }.compactMap { slot -> (String, CGRect)? in
            guard let frame = slotFrames[slot.id] else { return nil }
            return (slot.id, frame)
        }
        guard !icons.isEmpty else { return nil }
        let sorted = icons.sorted { lhs, rhs in
            abs(lhs.1.midY - rhs.1.midY) > 8 ? lhs.1.midY < rhs.1.midY : lhs.1.minX < rhs.1.minX
        }
        var rows: [[(String, CGRect)]] = []
        for item in sorted {
            if let last = rows.last?.last, abs(item.1.midY - last.1.midY) < 8 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        for row in rows {
            let top = row.map(\.1.minY).min() ?? 0
            let bottom = row.map(\.1.maxY).max() ?? 0
            guard point.y >= top, point.y <= bottom else { continue }
            let line = row.sorted { $0.1.minX < $1.1.minX }
            if point.x < line[0].1.minX {
                return orderAtDragStart.firstIndex { $0.id == line[0].0 }
            }
            for index in 0..<(line.count - 1) {
                let left = line[index].1
                let right = line[index + 1].1
                if point.x >= left.maxX, point.x <= right.minX {
                    return orderAtDragStart.firstIndex { $0.id == line[index + 1].0 }
                }
            }
            if point.x > line[line.count - 1].1.maxX, let index = orderAtDragStart.firstIndex(where: { $0.id == line[line.count - 1].0 }) {
                return index + 1
            }
        }
        return nil
    }

    private func previewGap(_ id: String, at destination: Int) {
        var all = orderAtDragStart
        guard let from = all.firstIndex(where: { $0.id == id }) else { return }
        let item = all.remove(at: from)
        var index = destination
        if from < destination { index -= 1 }
        index = min(max(0, index), all.count)
        all.insert(item, at: index)
        writeBack(all)
        dragDirty = true
    }

    private func insertionFlatIndex(at point: CGPoint, dragging id: String) -> Int? {
        let columns = max(settings.columns, 1)
        let page = clampedPage
        guard pages.indices.contains(page) else { return nil }
        let frames = pages[page].slots.filter(isVisible).compactMap { slotFrames[$0.id] }
        guard let pitch = gridPitch(frames) else { return nil }
        let col = min(max(Int(round((point.x - pitch.originX) / pitch.x)), 0), columns - 1)
        let row = min(max(Int(round((point.y - pitch.originY) / pitch.y)), 0), max(settings.rows, 1) - 1)
        let pageStart = pages.prefix(page).reduce(0) { $0 + $1.slots.filter(isVisible).count }
        let visibleIndex = min(pageStart + row * columns + col, visibleSlotCount())
        return flatIndex(forVisible: visibleIndex)
    }

    private func gridPitch(_ frames: [CGRect]) -> (originX: CGFloat, originY: CGFloat, x: CGFloat, y: CGFloat)? {
        guard let sample = frames.min(by: { lhs, rhs in
            lhs.minY == rhs.minY ? lhs.minX < rhs.minX : lhs.minY < rhs.minY
        }) else { return nil }
        let xs = Array(Set(frames.map { $0.midX.rounded() })).sorted()
        let ys = Array(Set(frames.map { $0.midY.rounded() })).sorted()
        let pitchX = xs.count >= 2 ? xs[1] - xs[0] : sample.width + 36
        let pitchY = ys.count >= 2 ? ys[1] - ys[0] : sample.height + 12
        return (xs.first ?? sample.midX, ys.first ?? sample.midY, max(pitchX, 1), max(pitchY, 1))
    }

    private func visibleSlotCount() -> Int {
        pages.reduce(0) { $0 + $1.slots.filter(isVisible).count }
    }

    private func flatIndex(forVisible visibleIndex: Int) -> Int {
        var seen = 0
        var flat = 0
        for page in pages {
            for slot in page.slots {
                if isVisible(slot) {
                    if seen == visibleIndex { return flat }
                    seen += 1
                }
                flat += 1
            }
        }
        return flat
    }

    private func moveDuringDrag(_ id: String, toFlatIndex destination: Int) {
        guard let from = flatIndex(of: id) else { return }
        var all = pages.flatMap(\.slots)
        guard all.indices.contains(from) else { return }
        let item = all.remove(at: from)
        let index = min(max(0, destination), all.count)
        all.insert(item, at: index)
        guard index != from else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            writeBack(all)
        }
        dragDirty = true
    }

    private func flatSlotCount() -> Int {
        pages.reduce(0) { $0 + $1.slots.count }
    }

    private func writeBack(_ slots: [Slot]) {
        let capacity = max(1, settings.pageCapacity)
        var chunks: [[Slot]] = []
        var buffer: [Slot] = []
        for slot in slots {
            buffer.append(slot)
            if buffer.count == capacity {
                chunks.append(buffer)
                buffer = []
            }
        }
        if !buffer.isEmpty { chunks.append(buffer) }
        if chunks.isEmpty { chunks = [[]] }
        var updated = pages
        while updated.count < chunks.count { updated.append(Page()) }
        if updated.count > chunks.count {
            updated.removeLast(updated.count - chunks.count)
        }
        for index in updated.indices where updated[index].slots != chunks[index] {
            updated[index].slots = chunks[index]
        }
        if updated != pages { pages = updated }
    }

    private func showDragImage(for id: String, iconWidth: CGFloat? = nil) {
        let image: NSImage
        if case .app(let appID) = slot(id), let app = app(appID) {
            image = icon(for: app)
        } else {
            image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage()
        }
        // 切页回弹中的旧页可能已暂停坐标收集，优先使用手势所在格子的实际尺寸。
        let side = max(iconWidth ?? slotFrames[id]?.width ?? 108, 72)
        let panel = dragPanel ?? makeDragPanel()
        dragPanel = panel
        let view = panel.contentView as? NSImageView
        view?.image = image
        let location = NSEvent.mouseLocation
        panel.setFrame(NSRect(x: location.x - side / 2, y: location.y - side / 2, width: side, height: side), display: false)
        panel.orderFrontRegardless()
    }

    private func makeDragPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 108, height: 108),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSImageView(frame: panel.contentLayoutRect)
        view.autoresizingMask = [.width, .height]
        view.imageScaling = .scaleProportionallyUpOrDown
        panel.contentView = view
        return panel
    }

    private func moveDragImage() {
        guard let dragPanel, dragPanel.isVisible else { return }
        let location = NSEvent.mouseLocation
        let side = dragPanel.frame.width
        let origin = NSPoint(x: location.x - side / 2, y: location.y - side / 2)
        guard dragPanel.frame.origin != origin else { return }
        dragPanel.setFrameOrigin(origin)
    }

    private func hideDragImage() {
        dragPanel?.orderOut(nil)
    }

    private func adoptCustomOrder() {
        if settings.sortBy != .custom {
            settings.sortBy = .custom
        }
    }

    private func absorb(_ sourceID: String, into targetID: String) {
        guard sourceID != targetID, query.isEmpty else { return }
        adoptCustomOrder()
        guard case .app(let appID) = slot(sourceID) else {
            move(sourceID, onto: targetID)
            return
        }
        switch slot(targetID) {
        case .folder(let folderID):
            guard removeSlot(sourceID) != nil else { return }
            if let index = folders.firstIndex(where: { $0.id == folderID }),
               !folders[index].appIDs.contains(appID) {
                folders[index].appIDs.append(appID)
            }
            reflow()
            persist()
        case .app(let targetAppID):
            let folder = FolderItem(id: UUID(), name: nextFolderName(), appIDs: [targetAppID, appID], createdAt: Date())
            folders.append(folder)
            rebuildIndexes()
            _ = removeSlot(sourceID)
            replace(targetID, with: .folder(folder.id))
            reflow()
            persist()
        default:
            move(sourceID, onto: targetID)
        }
    }

    private func flatIndex(of id: String) -> Int? {
        var index = 0
        for page in pages {
            for slot in page.slots {
                if slot.id == id { return index }
                index += 1
            }
        }
        return nil
    }

    private func slot(_ id: String) -> Slot? {
        pages.lazy.flatMap(\.slots).first { $0.id == id }
    }

    private func replace(_ id: String, with slot: Slot) {
        for pageIndex in pages.indices {
            if let index = pages[pageIndex].slots.firstIndex(where: { $0.id == id }) {
                pages[pageIndex].slots[index] = slot
                return
            }
        }
    }

    private func insert(_ slot: Slot, after targetID: String) {
        for pageIndex in pages.indices {
            if let slotIndex = pages[pageIndex].slots.firstIndex(where: { $0.id == targetID }) {
                pages[pageIndex].slots.insert(slot, at: slotIndex + 1)
                reflow()
                return
            }
        }
        append(slot)
    }

    private func insert(_ slot: Slot, before targetID: String) {
        for pageIndex in pages.indices {
            if let slotIndex = pages[pageIndex].slots.firstIndex(where: { $0.id == targetID }) {
                pages[pageIndex].slots.insert(slot, at: slotIndex)
                reflow()
                return
            }
        }
        append(slot)
    }

    private func removeAppCompletely(_ id: String) {
        apps.removeAll { $0.id == id }
        rebuildIndexes()
        iconCache[id] = nil
        pinnedAppIDs.removeAll { $0 == id }
        for index in folders.indices {
            folders[index].appIDs.removeAll { $0 == id }
        }
        folders.removeAll { $0.appIDs.isEmpty }
        rebuildIndexes()
        for index in pages.indices {
            pages[index].slots.removeAll { slot in
                if case .app(let appID) = slot { return appID == id }
                if case .folder(let folderID) = slot { return folder(folderID) == nil }
                return false
            }
        }
        if pages.allSatisfy(\.slots.isEmpty) { pages = [Page()] }
        selection = []
        persist()
    }

    private func nextFolderName() -> String {
        let existing = Set(folders.map(\.name))
        if !existing.contains("文件夹") { return "文件夹" }
        var number = 2
        while existing.contains("文件夹 \(number)") { number += 1 }
        return "文件夹 \(number)"
    }

    private func sortAppIDs(_ ids: [String], by key: SortKey, ascending: Bool) -> [String] {
        ids.sorted { lhs, rhs in
            guard let a = app(lhs), let b = app(rhs) else { return lhs < rhs }
            return appLess(a, b, by: key, ascending: ascending)
        }
    }

    private func rankedLess(_ lhs: Slot, _ rhs: Slot, options: ReorganizeOptions) -> Bool {
        let left = rank(lhs)
        let right = rank(rhs)
        if options.folders != .mixed, left.isFolder != right.isFolder {
            return options.folders == .before ? left.isFolder : right.isFolder
        }
        if options.appleApps != .mixed, left.isApple != right.isApple {
            return options.appleApps == .before ? left.isApple : right.isApple
        }
        return appLess(left, right, by: options.sortBy, ascending: options.ascending)
    }

    private struct Rank {
        var name: String
        var added: Date
        var opened: Date
        var isFolder: Bool
        var isApple: Bool
        var tie: String
    }

    private func rank(_ slot: Slot) -> Rank {
        switch slot {
        case .app(let id):
            let app = app(id)
            return Rank(
                name: app?.effectiveName ?? id,
                added: app?.addedAt ?? .distantPast,
                opened: app?.lastOpenedAt ?? .distantPast,
                isFolder: false,
                isApple: app?.isApple ?? false,
                tie: id
            )
        case .folder(let id):
            let folder = folder(id)
            return Rank(
                name: folder?.name ?? "文件夹",
                added: folder?.createdAt ?? .distantPast,
                opened: .distantPast,
                isFolder: true,
                isApple: false,
                tie: id.uuidString
            )
        }
    }

    private func appLess(_ lhs: Rank, _ rhs: Rank, by key: SortKey, ascending: Bool) -> Bool {
        let order: ComparisonResult
        switch key {
        case .name, .custom:
            order = lhs.name.localizedStandardCompare(rhs.name)
        case .added:
            order = lhs.added == rhs.added ? .orderedSame : (lhs.added < rhs.added ? .orderedAscending : .orderedDescending)
        case .opened:
            order = lhs.opened == rhs.opened ? .orderedSame : (lhs.opened < rhs.opened ? .orderedAscending : .orderedDescending)
        }
        if order == .orderedSame { return lhs.tie < rhs.tie }
        let isAscending = order == .orderedAscending
        return ascending ? isAscending : !isAscending
    }

    private func appLess(_ lhs: AppItem, _ rhs: AppItem, by key: SortKey, ascending: Bool) -> Bool {
        appLess(
            Rank(name: lhs.effectiveName, added: lhs.addedAt, opened: lhs.lastOpenedAt ?? .distantPast, isFolder: false, isApple: lhs.isApple, tie: lhs.id),
            Rank(name: rhs.effectiveName, added: rhs.addedAt, opened: rhs.lastOpenedAt ?? .distantPast, isFolder: false, isApple: rhs.isApple, tie: rhs.id),
            by: key, ascending: ascending
        )
    }

    private func presentAlert(
        _ alert: NSAlert,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        let parent = AppDelegate.current?.alertParentWindow ?? NSApp.keyWindow
        PanelAlertPresenter.present(alert, over: parent, completion: completion)
    }

    private func promptText(_ title: String, value: String, completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        presentAlert(alert) { response in
            guard response == .alertFirstButtonReturn else { completion(nil); return }
            completion(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func persist() {
        let snapshot = LibrarySnapshot(
            settings: settings, apps: apps, folders: folders, pages: pages, currentPage: currentPage,
            pinnedAppIDs: pinnedAppIDs
        )
        let fileURL = fileURL
        persistQueue.async {
            let failure: String?
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
                failure = nil
            } catch {
                failure = "保存失败：\(error.localizedDescription)"
            }
            guard let failure else { return }
            DispatchQueue.main.async { AppModel.shared.notice = failure }
        }
    }

    private func wireMonitors() {
        CornerMonitor.shared.onFire = { AppModel.shared.toggle() }
        PinchMonitor.shared.bindPanels(
            openTray: { AppDelegate.current?.openTrayFromPinch() },
            closeTray: { AppDelegate.current?.dismissTray() },
            openLauncher: { AppModel.shared.openFromPinch() },
            closeLauncher: { AppModel.shared.close() }
        )
        PinchMonitor.shared.onUnavailable = { AppModel.shared.notice = $0 }
    }

    func keepOutOfDock() {
        let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private func applyChrome() {
        let failures = [registerHotKey(), registerTerminalHotKey()].compactMap { $0 }
        notice = failures.isEmpty ? nil : failures.joined(separator: " ")
        CornerMonitor.shared.apply(settings.hotCorner)
        PinchMonitor.shared.apply(counts: settings.pinchCounts,
                                  threeSensitivity: settings.pinchThreeSensitivity,
                                  fourSensitivity: settings.pinchFourSensitivity)
        keepOutOfDock()
    }

    func start() {
        applyChrome()
        if dragPanel == nil { dragPanel = makeDragPanel() }
        if settings.launchAtLogin {
            applyLaunchAtLogin()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in AppModel.shared.refreshRunningApps() }
            }
        }
        refreshRunningApps()
    }

    func applyLaunchAtLogin() {
        notice = LoginItem.apply(settings.launchAtLogin)
    }
}

/// 菜单栏区的运行中应用。普通点击通过 Launch Services 打开应用，
/// AX 元素只用于右键菜单中的「打开菜单」。不参与持久化。
struct RunningApp: Identifiable, Equatable {
    let application: NSRunningApplication
    let menuBarItem: AXUIElement
    /// 图标在菜单栏里的 x 坐标，用来按真实左右顺序排；取不到的排最后。
    let menuBarX: CGFloat

    var id: String {
        "\(application.bundleIdentifier ?? "app")-\(application.processIdentifier)"
    }
    var name: String { application.localizedName ?? "应用" }
    var icon: NSImage? { application.icon }
    var bundleID: String? { application.bundleIdentifier }
    var isFrontmost: Bool { application.isActive }

    /// 触发它真正的菜单栏图标（弹出应用自己的菜单）。
    /// AX 元素失效时返回 false，调用方退回打开应用。
    func pressMenuBarItem() -> Bool {
        AXUIElementPerformAction(menuBarItem, kAXPressAction as CFString) == .success
    }

    func open() {
        guard let url = application.bundleURL else {
            activate()
            return
        }
        // Reopen through Launch Services: activate alone cannot restore a
        // closed main window or bring an accessory app's UI back.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in
                    AppModel.shared.notice = "没能打开应用：\(error.localizedDescription)"
                }
            }
        }
    }

    func activate() {
        application.activate(options: [.activateAllWindows])
    }

    func terminate() {
        application.terminate()
    }

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.application == rhs.application && lhs.menuBarX == rhs.menuBarX
    }
}
