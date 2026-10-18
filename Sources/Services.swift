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
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var installed = false

    @discardableResult
    func apply(enabled: Bool, keyCode: UInt32, modifiers: UInt32) -> String? {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), pinchpadHotKeyHandler, 1, &spec, nil, nil)
            installed = true
        }
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard enabled else { return nil }
        let identity = EventHotKeyID(signature: 0x4750_4144, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, identity, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            self.hotKey = nil
            return "快捷键没有生效，可能已被系统或其他应用占用。"
        }
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
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "键\(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
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
        guard status == noErr, length > 0 else { return "键\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

private func pinchpadHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ user: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async { HotKeyCenter.shared.onPress?() }
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

private let multitouchCallback: MTFrameCallback = { _, touches, count, _, _ in
    PinchMonitor.shared.handleTouches(touches, count: Int(count))
}

final class PinchMonitor {
    static let shared = PinchMonitor()
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onUnavailable: ((String) -> Void)?
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var devices: [UnsafeMutableRawPointer] = []
    private var devicesList: [AnyObject] = []
    private let stateLock = NSLock()
    private var openCounts: Set<Int> = [3, 4]
    private var classifier = PinchClassifier()
    /// 当前这次系统 Dock 手势（从 began 到 ended）是否整段拦下；nil 表示还没定。
    private var swallowingDock: Bool?
    private var lastFire = Date.distantPast
    private var touchGuardUntil = Date.distantPast
    private static let touchTail: TimeInterval = 0.2

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
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    func apply(counts: Set<Int>) {
        stateLock.lock()
        openCounts = counts
        classifier.reset()
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

    fileprivate func shouldSwallow(type: CGEventType, event: CGEvent) -> Bool {
        let raw = type.rawValue
        guard raw == 29 || raw == 30 else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        let fingersTracked = openCounts.contains(classifier.peak)
        guard raw == 30, event.getIntegerValueField(Self.gestureHIDTypeField) == Self.dockSwipeHIDType else {
            return classifier.kind == .pinch || (swallowingDock == true && classifier.fingers > 0)
        }
        // 系统自己已经判好了这次 Dock 手势是左右/上下平移还是捏合，以它为准：
        // 平移一律放行并且不再当成捏合；捏合从 began 开始整段拦下，不等我们自己的判定。
        let phase = event.getIntegerValueField(Self.gesturePhaseField)
        let motion = event.getIntegerValueField(Self.swipeMotionField)
        if phase == Self.phaseBegan { swallowingDock = nil }
        if motion == Self.motionHorizontal || motion == Self.motionVertical {
            classifier.markSwipe()
            if swallowingDock == nil { swallowingDock = false }
        } else if motion == Self.motionPinch, swallowingDock == nil {
            swallowingDock = fingersTracked || classifier.kind == .pinch
        }
        let swallow = swallowingDock ?? (classifier.kind == .pinch)
        if phase == Self.phaseEnded || phase == Self.phaseCancelled { swallowingDock = nil }
        return swallow
    }

    fileprivate func handleTouches(_ raw: UnsafeMutableRawPointer?, count: Int) {
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
        stateLock.lock()
        let counts = openCounts
        let signal = classifier.feed(samples) { counts.contains($0) }
        // 只有被判定为捏合（或被整段拦下的 Dock 手势）的触点序列才算手势尾巴，
        // 普通点按本身也会产生按下触点，不能误伤。
        if samples.contains(where: \.isDown), classifier.kind == .pinch || swallowingDock == true {
            touchGuardUntil = Date().addingTimeInterval(Self.touchTail)
        }
        stateLock.unlock()
        if let signal { claim(open: signal == .open) }
    }

    /// 捏合手势进行期间（及抬手后 0.2s 内）的指针点击多半是手势尾巴，应被忽略。
    /// 普通点击产生的触点不算在内——只有被判定为捏合/被吞掉的 Dock 手势的触点序列才会延长窗口。
    func pinchPointerGuardUntil() -> Date {
        stateLock.lock()
        defer { stateLock.unlock() }
        return touchGuardUntil
    }

    private func claim(open: Bool) {
        stateLock.lock()
        let recent = Date().timeIntervalSince(lastFire) < 0.6
        if !recent { lastFire = Date() }
        stateLock.unlock()
        guard !recent else { return }
        DispatchQueue.main.async {
            if open { self.onOpen?() } else { self.onClose?() }
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
                eventTap = tap
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                runLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
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
