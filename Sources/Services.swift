import AppKit
import ApplicationServices
import Carbon
import Darwin
import Foundation
import SQLite3
import ServiceManagement

enum AppScanner {
    struct Found: Hashable {
        var path: String
        var bundleID: String?
        var name: String
        var sourcePath: String
    }

    static func scan(paths: [String]) -> [Found] {
        var seen = Set<String>()
        var found: [Found] = []
        let fileManager = FileManager.default
        for root in paths {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                let path = url.path
                guard seen.insert(path).inserted else { continue }
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let bundleID = bundle?.bundleIdentifier
                let identity = bundleID ?? path
                if found.contains(where: { ($0.bundleID ?? $0.path) == identity }) { continue }
                found.append(Found(path: path, bundleID: bundleID, name: name, sourcePath: root))
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum RelatedFiles {
    static func candidates(for app: AppItem) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        var paths: [URL] = []
        let name = app.name
        let bundle = app.bundleID
        func add(_ url: URL) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                paths.append(url)
            }
        }
        add(library.appendingPathComponent("Application Support/\(name)"))
        if let bundle {
            add(library.appendingPathComponent("Application Support/\(bundle)"))
            add(library.appendingPathComponent("Caches/\(bundle)"))
            add(library.appendingPathComponent("Preferences/\(bundle).plist"))
            add(library.appendingPathComponent("Containers/\(bundle)"))
            add(library.appendingPathComponent("Saved Application State/\(bundle).savedState"))
            add(library.appendingPathComponent("WebKit/\(bundle)"))
            add(library.appendingPathComponent("HTTPStorages/\(bundle)"))
            add(library.appendingPathComponent("Application Scripts/\(bundle)"))
            let groups = library.appendingPathComponent("Group Containers")
            if let names = try? FileManager.default.contentsOfDirectory(atPath: groups.path) {
                for entry in names where entry.contains(bundle) {
                    add(groups.appendingPathComponent(entry))
                }
            }
        }
        add(library.appendingPathComponent("Logs/\(name)"))
        return paths
    }

    static func isAlias(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
        return values?.isSymbolicLink == true || values?.isAliasFile == true
    }
}

enum Trash {
    static func move(_ urls: [URL]) throws {
        guard !urls.isEmpty else { return }
        try FileManager.default.trashItem(at: urls[0], resultingItemURL: nil)
        if urls.count == 1 { return }
        for url in urls.dropFirst() {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }
}

enum DockPin {
    static func add(app: AppItem) throws {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
        let data = try Data(contentsOf: plistURL)
        guard var root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var apps = root["persistent-apps"] as? [[String: Any]] ?? []
        if apps.contains(where: { tile in
            let tileData = tile["tile-data"] as? [String: Any]
            let fileData = tileData?["file-data"] as? [String: Any]
            return (fileData?["_CFURLString"] as? String) == app.path
        }) {
            return
        }
        let tile: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": [
                "file-label": app.effectiveName,
                "file-data": [
                    "_CFURLString": app.path,
                    "_CFURLStringType": 0
                ]
            ]
        ]
        apps.append(tile)
        root["persistent-apps"] = apps
        let out = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try out.write(to: plistURL, options: .atomic)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try task.run()
    }
}

struct ImportFailure: Error {
    var message: String
    init(_ message: String) { self.message = message }
}

enum SystemLayoutImport {
    struct Layout {
        var folders: [(name: String, bundleIDs: [String])]
        var looseBundleIDs: [String]
    }

    static func load() -> Result<Layout, ImportFailure> {
        guard let url = findDatabase() else {
            return .failure(ImportFailure("没有找到系统应用布局数据库。这台 Mac 上可能已经没有它。"))
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return .failure(ImportFailure("打不开 \(url.path)"))
        }
        defer { sqlite3_close(db) }
        guard tableExists("apps", db), tableExists("items", db) else {
            return .failure(ImportFailure("这个数据库不是系统应用布局。"))
        }
        var apps: [Int64: String] = [:]
        if let rows = query(db, "SELECT item_id, bundleid FROM apps") {
            for row in rows {
                if row.count >= 2, let id = Int64(row[0]), !row[1].isEmpty {
                    apps[id] = row[1]
                }
            }
        }
        var groups: [Int64: String] = [:]
        if tableExists("groups", db), let rows = query(db, "SELECT item_id, title FROM groups") {
            for row in rows where row.count >= 2 {
                if let id = Int64(row[0]) { groups[id] = row[1] }
            }
        }
        struct Item {
            var id: Int64
            var parent: Int64
            var ordering: Int
        }
        var items: [Item] = []
        let sql = "SELECT rowid, parent_id, ordering FROM items ORDER BY parent_id, ordering"
        if let rows = query(db, sql) {
            for row in rows where row.count >= 3 {
                if let id = Int64(row[0]), let parent = Int64(row[1]), let ordering = Int(row[2]) {
                    items.append(Item(id: id, parent: parent, ordering: ordering))
                }
            }
        }
        var children: [Int64: [Item]] = [:]
        for item in items {
            children[item.parent, default: []].append(item)
        }
        var folderBundleIDs: Set<String> = []
        var folders: [(String, [String])] = []
        for (id, title) in groups.sorted(by: { $0.key < $1.key }) {
            let kids = (children[id] ?? []).sorted { $0.ordering < $1.ordering }
            let bundles = kids.compactMap { apps[$0.id] }
            guard !bundles.isEmpty else { continue }
            let name = title.isEmpty ? "文件夹" : title
            folders.append((name, bundles))
            folderBundleIDs.formUnion(bundles)
        }
        let loose = items
            .filter { apps[$0.id] != nil && !folderBundleIDs.contains(apps[$0.id]!) }
            .sorted { $0.ordering < $1.ordering }
            .compactMap { apps[$0.id] }
        if folders.isEmpty && loose.isEmpty {
            return .failure(ImportFailure("数据库里没有可以对应的应用。"))
        }
        return .success(Layout(folders: folders, looseBundleIDs: loose))
    }

    private static func findDatabase() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/Application Support/Dock"),
            home.appendingPathComponent("Library/Application Support")
        ]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            var depth = 0
            for case let url as URL in enumerator {
                if depth > 600 { break }
                depth += 1
                let name = url.lastPathComponent
                if name == "db" || name.hasSuffix(".db") {
                    if name.contains("desktoppicture") { continue }
                    return url
                }
            }
        }
        return nil
    }

    private static func tableExists(_ name: String, _ db: OpaquePointer) -> Bool {
        let rows = query(db, "SELECT name FROM sqlite_master WHERE type='table' AND name=?1", params: [name])
        return rows?.isEmpty == false
    }

    private static func query(_ db: OpaquePointer, _ sql: String, params: [String] = []) -> [[String]]? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        for (index, param) in params.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), (param as NSString).utf8String, -1, nil) == SQLITE_OK else {
                return nil
            }
        }

        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String] = []
            let count = sqlite3_column_count(statement)
            for index in 0..<count {
                if let cString = sqlite3_column_text(statement, index) {
                    row.append(String(cString: cString))
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }
        return rows
    }
}

enum LoginItem {
    static func apply(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    /// EventHotKeyID.id：面板快捷键用 1，终端快捷键用 2。Carbon 回调按它分发。
    static let launcherID: UInt32 = 1
    static let terminalID: UInt32 = 2
    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    func handle(_ id: UInt32) {
        handlers[id]?()
    }

    @discardableResult
    func apply(id: UInt32, enabled: Bool, keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) -> String? {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), pinchpadHotKeyHandler, 1, &spec, nil, nil)
            installed = true
        }
        if let hotKey = hotKeys[id] {
            UnregisterEventHotKey(hotKey)
            hotKeys[id] = nil
        }
        handlers[id] = onPress
        guard enabled else { return nil }
        var hotKey: EventHotKeyRef?
        let identity = EventHotKeyID(signature: 0x4750_4144, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, identity, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            return "快捷键没有生效，可能已被系统或其他应用占用。"
        }
        hotKeys[id] = hotKey
        return nil
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    static func title(keyCode: UInt32, modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName(keyCode)
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        let named: [UInt32: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        if let name = named[keyCode] { return name }
        if let translated = translate(keyCode) { return translated }
        if let ansi = ansiKeys[keyCode] { return ansi }
        return "键\(keyCode)"
    }

    /// 当前输入源若是中文输入法，就没有 UnicodeKeyLayoutData，翻译会失败——
    /// 先拿「键盘布局」源（始终有布局数据），再退回当前输入源。
    private static func keyboardLayoutData() -> Data? {
        for copy in [TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentKeyboardInputSource] {
            if let source = copy()?.takeRetainedValue(),
               let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            }
        }
        return nil
    }

    private static func translate(_ keyCode: UInt32) -> String? {
        guard let data = keyboardLayoutData() else { return nil }
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    /// ANSI 物理键位兜底表：布局数据拿不到时，字母/数字/符号仍显示真实字符。
    private static let ansiKeys: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        65: "小键盘.", 67: "小键盘*", 69: "小键盘+", 75: "小键盘/", 76: "小键盘↩",
        78: "小键盘-", 81: "小键盘=", 82: "小键盘0", 83: "小键盘1", 84: "小键盘2",
        85: "小键盘3", 86: "小键盘4", 87: "小键盘5", 88: "小键盘6", 89: "小键盘7",
        91: "小键盘8", 92: "小键盘9"
    ]
}

private func pinchpadHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ user: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    DispatchQueue.main.async { HotKeyCenter.shared.handle(id) }
    return noErr
}

final class CornerMonitor {
    static let shared = CornerMonitor()
    var onFire: (() -> Void)?
    private var timer: Timer?
    private var corner: HotCorner = .off
    private var armed = true
    private var enteredAt: Date?

    private static let timerInterval: TimeInterval = 0.12
    private static let cornerInset: CGFloat = 6
    private static let activationDelay: TimeInterval = 0.12

    deinit {
        timer?.invalidate()
        timer = nil
    }

    func apply(_ corner: HotCorner) {
        self.corner = corner
        timer?.invalidate()
        timer = nil
        guard corner != .off else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.timerInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard corner != .off, let screen = screen(containing: NSEvent.mouseLocation) else { return }
        let point = NSEvent.mouseLocation
        let frame = screen.frame
        let hit: Bool
        switch corner {
        case .off: hit = false
        case .topLeft: hit = point.x <= frame.minX + Self.cornerInset && point.y >= frame.maxY - Self.cornerInset
        case .topRight: hit = point.x >= frame.maxX - Self.cornerInset && point.y >= frame.maxY - Self.cornerInset
        case .bottomLeft: hit = point.x <= frame.minX + Self.cornerInset && point.y <= frame.minY + Self.cornerInset
        case .bottomRight: hit = point.x >= frame.maxX - Self.cornerInset && point.y <= frame.minY + Self.cornerInset
        }
        if !hit {
            armed = true
            enteredAt = nil
            return
        }
        if enteredAt == nil { enteredAt = Date() }
        guard armed, let enteredAt, Date().timeIntervalSince(enteredAt) > Self.activationDelay else { return }
        armed = false
        onFire?()
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

private struct MTPoint { var x: Float; var y: Float }
private struct MTReadout { var position: MTPoint; var velocity: MTPoint }
private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var foo3: Int32
    var foo4: Int32
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTReadout
    var zero2a: Int32
    var zero2b: Int32
    var unk2: Float
}

private typealias MTFrameCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Void
private typealias MTRegisterFn = @convention(c) (UnsafeMutableRawPointer?, MTFrameCallback?) -> Void
private typealias MTDeviceFn = @convention(c) () -> UnsafeMutableRawPointer?
private typealias MTDeviceListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTStartFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void

private let pinchEventCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = PinchMonitor.shared.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    if PinchMonitor.shared.shouldSwallow(type: type, event: event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}

private let multitouchCallback: MTFrameCallback = { device, touches, count, _, _ in
    PinchMonitor.shared.handleTouches(touches, count: Int(count), deviceID: UInt(bitPattern: device))
}

// Owns the lifetime of the source that handles filtered gesture events.
final class EventTapRunLoop {
    private final class State {
        let source: CFRunLoopSource
        private let lock = NSLock()
        private var runLoop: CFRunLoop?
        private var stopped = false

        init(source: CFRunLoopSource) { self.source = source }

        func run() {
            let current = CFRunLoopGetCurrent()!
            lock.lock()
            guard !stopped else { lock.unlock(); return }
            runLoop = current
            CFRunLoopAddSource(current, source, .commonModes)
            lock.unlock()

            CFRunLoopRun()

            CFRunLoopRemoveSource(current, source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            lock.lock()
            runLoop = nil
            stopped = true
            lock.unlock()
        }

        func stop() {
            lock.lock()
            guard !stopped else { lock.unlock(); return }
            stopped = true
            let current = runLoop
            lock.unlock()
            guard let current else {
                CFRunLoopSourceInvalidate(source)
                return
            }
            // Queue shutdown as well as waking the loop: stop may race its first run.
            CFRunLoopPerformBlock(current, CFRunLoopMode.commonModes.rawValue) { [source] in
                CFRunLoopSourceInvalidate(source)
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(current)
        }
    }

    private let state: State

    init(source: CFRunLoopSource) {
        let state = State(source: source)
        self.state = state
        // Capture state rather than the owner, so deinit can stop a running worker.
        let thread = Thread { state.run() }
        thread.name = "app.local.pinchpad.gestures"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() { state.stop() }
    deinit { stop() }
}

final class PinchMonitor {
    static let shared = PinchMonitor()
    var onOpen: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onUnavailable: ((String) -> Void)?

    func bindPanels(
        openTray: @escaping () -> Void,
        closeTray: @escaping () -> Void,
        openLauncher: @escaping () -> Void,
        closeLauncher: @escaping () -> Void
    ) {
        onOpen = { fingers in
            if fingers == 3 { openTray() } else { openLauncher() }
        }
        onClose = { _ in
            // Finger count selects the opening surface, not the closing target.
            // Both close actions are idempotent; an outward gesture dismisses
            // whichever panel is currently visible.
            closeTray()
            closeLauncher()
        }
    }

    fileprivate var eventTap: CFMachPort?
    private var tapRunLoop: EventTapRunLoop?
    private var devices: [UnsafeMutableRawPointer] = []
    private var devicesList: [AnyObject] = []
    private let stateLock = NSLock()
    private var openCounts: Set<Int> = [3, 4]
    private var classifier = PinchClassifier()
    /// 当前这次系统 Dock 手势（从 began 到 ended）是否整段拦下；nil 表示还没定。
    private var swallowingDock: Bool?
    private var activeDeviceID: UInt?
    private var activeDeviceLastFrameAt: TimeInterval?
    private var touchGuardUntil = Date.distantPast
    private static let touchTail: TimeInterval = 0.2
    private static let deviceHandoffDelay: TimeInterval = 0.2

    private static let gestureHIDTypeField = CGEventField(rawValue: 110)!
    private static let swipeMotionField = CGEventField(rawValue: 123)!
    private static let gesturePhaseField = CGEventField(rawValue: 132)!
    private static let dockSwipeHIDType: Int64 = 23
    private static let motionHorizontal: Int64 = 1
    private static let motionVertical: Int64 = 2
    private static let motionPinch: Int64 = 3
    private static let phaseBegan: Int64 = 1
    private static let phaseEnded: Int64 = 4
    private static let phaseCancelled: Int64 = 8

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tapRunLoop?.stop()
    }

    func apply(counts: Set<Int>, threeSensitivity: PinchSensitivity = .standard, fourSensitivity: PinchSensitivity = .standard) {
        stateLock.lock()
        openCounts = counts
        classifier = PinchClassifier(threeFingerSensitivity: threeSensitivity, fourFingerSensitivity: fourSensitivity)
        activeDeviceID = nil
        activeDeviceLastFrameAt = nil
        swallowingDock = nil
        stateLock.unlock()
        if !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
            DispatchQueue.main.async {
                self.onUnavailable?("捏合要在「系统设置 → 隐私与安全性 → 辅助功能」里允许 Pinchpad。允许这一次之后，重新打开不用再授权。")
            }
        }
        startDevice()
        startTap()
    }

    /// 更新识别门槛即可，无需重启设备监听或重新请求辅助功能授权。
    func setSensitivities(three: PinchSensitivity, four: PinchSensitivity) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard classifier.threeFingerSensitivity != three || classifier.fourFingerSensitivity != four else { return }
        classifier = PinchClassifier(threeFingerSensitivity: three, fourFingerSensitivity: four)
        activeDeviceID = nil
        activeDeviceLastFrameAt = nil
        swallowingDock = nil
    }

    func shouldSwallow(type: CGEventType, event: CGEvent) -> Bool {
        let raw = type.rawValue
        guard raw == 29 || raw == 30 else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        let fingersTracked = classifier.fingers > 0 && openCounts.contains(classifier.peak)
        let recognizedOpening = classifier.fingers > 0 && classifier.signal == .open
        guard raw == 30, event.getIntegerValueField(Self.gestureHIDTypeField) == Self.dockSwipeHIDType else {
            return recognizedOpening
                || (swallowingDock == true && classifier.fingers > 0 && classifier.signal != .close)
        }
        // Only replace the system's app-launcher pinch. Show Desktop and other
        // Dock motions must not fall back to swallowing every classified pinch.
        let phase = event.getIntegerValueField(Self.gesturePhaseField)
        let motion = event.getIntegerValueField(Self.swipeMotionField)
        if phase == Self.phaseBegan { swallowingDock = nil }
        if motion != Self.motionPinch {
            if motion == Self.motionHorizontal || motion == Self.motionVertical {
                classifier.markSwipe()
            }
            swallowingDock = false
        } else if classifier.signal == .close {
            swallowingDock = false
        } else if swallowingDock == nil {
            swallowingDock = fingersTracked || recognizedOpening
        }
        let swallow = swallowingDock ?? recognizedOpening
        if phase == Self.phaseEnded || phase == Self.phaseCancelled { swallowingDock = nil }
        return swallow
    }

    fileprivate func handleTouches(_ raw: UnsafeMutableRawPointer?, count: Int, deviceID: UInt) {
        var samples: [TouchSample] = []
        if let raw, count > 0 {
            samples.reserveCapacity(count)
            let touches = raw.assumingMemoryBound(to: MTTouch.self)
            for index in 0..<count {
                let touch = touches[index]
                let point = touch.normalized.position
                samples.append(TouchSample(id: touch.identifier, state: touch.state, x: point.x, y: point.y))
            }
        }
        handle(samples: samples, deviceID: deviceID)
    }

    func handle(samples: [TouchSample], at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime,
                deviceID: UInt = 0) {
        stateLock.lock()
        let hasContacts = samples.contains(where: \.isDown)
        if let activeDeviceID, activeDeviceID != deviceID {
            // An idle second trackpad emits empty frames too. It must not reset
            // an in-progress gesture from the device actually being touched.
            let previousDeviceStalled = timestamp - (activeDeviceLastFrameAt ?? timestamp) > Self.deviceHandoffDelay
            guard hasContacts, classifier.fingers < 2 || previousDeviceStalled else { stateLock.unlock(); return }
            classifier.reset()
            swallowingDock = nil
            self.activeDeviceID = deviceID
        } else if hasContacts {
            activeDeviceID = deviceID
        }
        activeDeviceLastFrameAt = timestamp
        let counts = openCounts
        let generation = classifier.resetGeneration
        let signal = classifier.feed(samples, at: timestamp) { counts.contains($0) }
        if classifier.resetGeneration != generation { swallowingDock = nil }
        let fingers = classifier.peak
        // 只有被判定为捏合（或被整段拦下的 Dock 手势）的触点序列才算手势尾巴，
        // 普通点按本身也会产生按下触点，不能误伤。
        if classifier.fingers >= 2, classifier.kind == .pinch || swallowingDock == true {
            touchGuardUntil = Date().addingTimeInterval(Self.touchTail)
        }
        stateLock.unlock()
        if let signal { claim(open: signal == .open, fingers: fingers) }
    }

    /// 捏合手势进行期间（及抬手后 0.2s 内）的指针点击多半是手势尾巴，应被忽略。
    /// 只在至少两指仍在的已识别手势中续期；最后一指停留和普通点击不会无限延长窗口。
    func pinchPointerGuardUntil() -> Date {
        stateLock.lock()
        defer { stateLock.unlock() }
        return touchGuardUntil
    }

    private func claim(open: Bool, fingers: Int) {
        // The classifier fires once per continuous contact sequence. A global
        // cooldown would discard a separate, deliberately repeated gesture.
        DispatchQueue.main.async {
            if open { self.onOpen?(fingers) } else { self.onClose?(fingers) }
        }
    }

    private func startTap() {
        if eventTap != nil { return }
        var mask = CGEventMask(1) << CGEventMask(29)
        mask |= CGEventMask(1) << CGEventMask(30)
        let locations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        for location in locations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: pinchEventCallback,
                userInfo: nil
            ) {
                guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                    CFMachPortInvalidate(tap)
                    continue
                }
                eventTap = tap
                tapRunLoop = EventTapRunLoop(source: source)
                CGEvent.tapEnable(tap: tap, enable: true)
                return
            }
        }
        DispatchQueue.main.async {
            self.onUnavailable?("系统没有允许 Pinchpad 拦截触控板手势。请到「辅助功能」里打开 Pinchpad。")
        }
    }

    private func startDevice() {
        if !devices.isEmpty { return }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY),
              let registerRaw = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startRaw = dlsym(handle, "MTDeviceStart") else { return }
        let register = unsafeBitCast(registerRaw, to: MTRegisterFn.self)
        let start = unsafeBitCast(startRaw, to: MTStartFn.self)
        // 内置触控板和外接 Magic Trackpad 都监听，只拿默认设备会漏掉外接的那块。
        var found: [UnsafeMutableRawPointer] = []
        if let listRaw = dlsym(handle, "MTDeviceCreateList"),
           let list = unsafeBitCast(listRaw, to: MTDeviceListFn.self)()?.takeRetainedValue() as? [AnyObject] {
            found = list.map { Unmanaged.passUnretained($0).toOpaque() }
            devicesList = list
        }
        if found.isEmpty, let createRaw = dlsym(handle, "MTDeviceCreateDefault"),
           let created = unsafeBitCast(createRaw, to: MTDeviceFn.self)() {
            found = [created]
        }
        for device in found {
            register(device, multitouchCallback)
            start(device, 0)
        }
        devices = found
    }
}
