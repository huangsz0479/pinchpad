import Foundation

enum Browsing: String, Codable, CaseIterable, Identifiable {
    case paged, scroll, window
    var id: String { rawValue }
    var title: String {
        switch self {
        case .paged: return "分页"
        case .scroll: return "纵向滚动"
        case .window: return "窗口"
        }
    }
}

enum HotCorner: String, Codable, CaseIterable, Identifiable {
    case off, topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "关闭"
        case .topLeft: return "左上"
        case .topRight: return "右上"
        case .bottomLeft: return "左下"
        case .bottomRight: return "右下"
        }
    }
}

enum ShowOn: String, Codable, CaseIterable, Identifiable {
    case main, cursor, active
    var id: String { rawValue }
    var title: String {
        switch self {
        case .main: return "主屏幕"
        case .cursor: return "指针所在屏幕"
        case .active: return "当前屏幕"
        }
    }
}

enum SortKey: String, Codable, CaseIterable, Identifiable {
    case custom, name, added, opened
    var id: String { rawValue }
    var title: String {
        switch self {
        case .custom: return "当前顺序"
        case .name: return "名称"
        case .added: return "添加日期"
        case .opened: return "最近打开"
        }
    }
}

enum EndPlacement: String, Codable, CaseIterable, Identifiable {
    case before, after, mixed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .before: return "排在前面"
        case .after: return "排在后面"
        case .mixed: return "混在一起"
        }
    }
}

enum BackdropKind: String, Codable, CaseIterable, Identifiable {
    case blur, dim, plain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blur: return "墙纸模糊"
        case .dim: return "压暗"
        case .plain: return "深色"
        }
    }
}

struct AppSource: Codable, Identifiable, Hashable {
    var id: UUID
    var path: String
    var enabled: Bool
    var custom: Bool

    static var defaults: [AppSource] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            AppSource(id: UUID(), path: "/Applications", enabled: true, custom: false),
            AppSource(id: UUID(), path: "/System/Applications", enabled: true, custom: false),
            AppSource(id: UUID(), path: "/System/Applications/Utilities", enabled: true, custom: false),
            AppSource(id: UUID(), path: home + "/Applications", enabled: true, custom: false)
        ]
    }
}

struct ReorganizeOptions: Codable, Hashable {
    var allPages: Bool = true
    var sortBy: SortKey = .name
    var ascending: Bool = true
    var folders: EndPlacement = .mixed
    var appleApps: EndPlacement = .mixed
    var sortInsideFolders: Bool = true
}





struct Preferences: Codable, Equatable {
    var columns: Int = 7
    var rows: Int = 5
    var browsing: Browsing = .paged
    var showMenuBar: Bool = true
    var showDockIcon: Bool = false
    var hideDockWhileOpen: Bool = true
    var hotCorner: HotCorner = .off
    var pinchThree: Bool = true
    var pinchFour: Bool = true
    var pinchThreeSensitivity: PinchSensitivity = .standard
    var pinchFourSensitivity: PinchSensitivity = .standard
    /// 是否启用全局快捷键。名字沿用最初的字段，避免旧的设置文件读不出来。
    var f4Enabled: Bool = true
    /// F4，不带修饰键。
    var hotKeyCode: UInt32 = 118
    var hotKeyModifiers: UInt32 = 0
    /// 「打开终端」全局快捷键，默认关闭；默认 ⌃⌥T（17 = T，0x1800 = control | option）。
    var terminalHotKeyEnabled: Bool = false
    var terminalHotKeyCode: UInt32 = 17
    var terminalHotKeyModifiers: UInt32 = 0x1800
    /// 终端新窗口的工作目录；留空表示用户主目录。
    var terminalDirectory: String = ""
    /// 终端应用路径；留空表示系统自带 Terminal.app。
    var terminalAppPath: String = ""
    var showOn: ShowOn = .cursor
    var returnToFirstPage: Bool = false
    var sortBy: SortKey = .custom
    var sortAscending: Bool = true
    var hideNames: Bool = false
    var showHiddenInSearch: Bool = true
    var optionClickUninstall: Bool = true
    var backdrop: BackdropKind = .blur
    var sources: [AppSource] = AppSource.defaults
    var launchAtLogin: Bool = false
    var reorganize: ReorganizeOptions = ReorganizeOptions()

    private enum CodingKeys: String, CodingKey {
        case columns, rows, browsing, showMenuBar, showDockIcon, hideDockWhileOpen
        case hotCorner, pinchToOpen, pinchFingers, pinchThree, pinchFour, f4Enabled, hotKeyCode, hotKeyModifiers
        case terminalHotKeyEnabled, terminalHotKeyCode, terminalHotKeyModifiers, terminalDirectory, terminalAppPath
        case pinchSensitivity, pinchThreeSensitivity, pinchFourSensitivity
        case showOn, returnToFirstPage, sortBy, sortAscending, hideNames
        case showHiddenInSearch, optionClickUninstall, backdrop, sources, launchAtLogin, reorganize
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? columns
        rows = try container.decodeIfPresent(Int.self, forKey: .rows) ?? rows
        browsing = try container.decodeIfPresent(Browsing.self, forKey: .browsing) ?? browsing
        showMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showMenuBar) ?? showMenuBar
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? showDockIcon
        hideDockWhileOpen = try container.decodeIfPresent(Bool.self, forKey: .hideDockWhileOpen) ?? hideDockWhileOpen
        hotCorner = try container.decodeIfPresent(HotCorner.self, forKey: .hotCorner) ?? hotCorner
        if container.contains(.pinchThree) || container.contains(.pinchFour) {
            pinchThree = try container.decodeIfPresent(Bool.self, forKey: .pinchThree) ?? pinchThree
            pinchFour = try container.decodeIfPresent(Bool.self, forKey: .pinchFour) ?? pinchFour
        } else {
            let legacyOpen = try container.decodeIfPresent(Bool.self, forKey: .pinchToOpen) ?? true
            pinchThree = legacyOpen
            pinchFour = legacyOpen
        }
        // Preserve the previous shared level for both gestures on first upgrade.
        let legacySensitivity = try container.decodeIfPresent(Int.self, forKey: .pinchSensitivity)
        let threeLevel = try container.decodeIfPresent(Int.self, forKey: .pinchThreeSensitivity) ?? legacySensitivity
        let fourLevel = try container.decodeIfPresent(Int.self, forKey: .pinchFourSensitivity) ?? legacySensitivity
        pinchThreeSensitivity = threeLevel.flatMap(PinchSensitivity.init(rawValue:)) ?? .standard
        pinchFourSensitivity = fourLevel.flatMap(PinchSensitivity.init(rawValue:)) ?? .standard
        f4Enabled = try container.decodeIfPresent(Bool.self, forKey: .f4Enabled) ?? f4Enabled
        hotKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotKeyCode) ?? hotKeyCode
        hotKeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers) ?? hotKeyModifiers
        terminalHotKeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .terminalHotKeyEnabled) ?? terminalHotKeyEnabled
        terminalHotKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .terminalHotKeyCode) ?? terminalHotKeyCode
        terminalHotKeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .terminalHotKeyModifiers) ?? terminalHotKeyModifiers
        terminalDirectory = try container.decodeIfPresent(String.self, forKey: .terminalDirectory) ?? terminalDirectory
        terminalAppPath = try container.decodeIfPresent(String.self, forKey: .terminalAppPath) ?? terminalAppPath
        showOn = try container.decodeIfPresent(ShowOn.self, forKey: .showOn) ?? showOn
        returnToFirstPage = try container.decodeIfPresent(Bool.self, forKey: .returnToFirstPage) ?? returnToFirstPage
        sortBy = try container.decodeIfPresent(SortKey.self, forKey: .sortBy) ?? sortBy
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? sortAscending
        hideNames = try container.decodeIfPresent(Bool.self, forKey: .hideNames) ?? hideNames
        showHiddenInSearch = try container.decodeIfPresent(Bool.self, forKey: .showHiddenInSearch) ?? showHiddenInSearch
        optionClickUninstall = try container.decodeIfPresent(Bool.self, forKey: .optionClickUninstall) ?? optionClickUninstall
        backdrop = try container.decodeIfPresent(BackdropKind.self, forKey: .backdrop) ?? backdrop
        sources = try container.decodeIfPresent([AppSource].self, forKey: .sources) ?? sources
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        reorganize = try container.decodeIfPresent(ReorganizeOptions.self, forKey: .reorganize) ?? reorganize
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columns, forKey: .columns)
        try container.encode(rows, forKey: .rows)
        try container.encode(browsing, forKey: .browsing)
        try container.encode(showMenuBar, forKey: .showMenuBar)
        try container.encode(showDockIcon, forKey: .showDockIcon)
        try container.encode(hideDockWhileOpen, forKey: .hideDockWhileOpen)
        try container.encode(hotCorner, forKey: .hotCorner)
        try container.encode(pinchThree, forKey: .pinchThree)
        try container.encode(pinchFour, forKey: .pinchFour)
        try container.encode(pinchThreeSensitivity, forKey: .pinchThreeSensitivity)
        try container.encode(pinchFourSensitivity, forKey: .pinchFourSensitivity)
        try container.encode(f4Enabled, forKey: .f4Enabled)
        try container.encode(hotKeyCode, forKey: .hotKeyCode)
        try container.encode(hotKeyModifiers, forKey: .hotKeyModifiers)
        try container.encode(terminalHotKeyEnabled, forKey: .terminalHotKeyEnabled)
        try container.encode(terminalHotKeyCode, forKey: .terminalHotKeyCode)
        try container.encode(terminalHotKeyModifiers, forKey: .terminalHotKeyModifiers)
        try container.encode(terminalDirectory, forKey: .terminalDirectory)
        try container.encode(terminalAppPath, forKey: .terminalAppPath)
        try container.encode(showOn, forKey: .showOn)
        try container.encode(returnToFirstPage, forKey: .returnToFirstPage)
        try container.encode(sortBy, forKey: .sortBy)
        try container.encode(sortAscending, forKey: .sortAscending)
        try container.encode(hideNames, forKey: .hideNames)
        try container.encode(showHiddenInSearch, forKey: .showHiddenInSearch)
        try container.encode(optionClickUninstall, forKey: .optionClickUninstall)
        try container.encode(backdrop, forKey: .backdrop)
        try container.encode(sources, forKey: .sources)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(reorganize, forKey: .reorganize)
    }





    var pinchCounts: Set<Int> {
        var counts: Set<Int> = []
        if pinchThree { counts.insert(3) }
        if pinchFour { counts.insert(4) }
        return counts
    }

    var pageCapacity: Int { max(1, columns * rows) }

    var gridTitle: String { "\(columns)×\(rows)" }
}

struct AppItem: Codable, Identifiable, Hashable {
    var id: String
    var path: String
    var bundleID: String?
    var name: String
    var customName: String?
    var hidden: Bool
    var addedAt: Date
    var lastOpenedAt: Date?
    var sourcePath: String

    var effectiveName: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? name : trimmed
    }

    var isApple: Bool { bundleID?.hasPrefix("com.apple.") == true }
}

struct FolderItem: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var appIDs: [String]
    var createdAt: Date
}

enum Slot: Codable, Hashable, Identifiable {
    case app(String)
    case folder(UUID)

    var id: String {
        switch self {
        case .app(let id): return "a:" + id
        case .folder(let id): return "f:" + id.uuidString
        }
    }
}

struct Page: Codable, Identifiable, Hashable {
    var id: UUID
    var slots: [Slot]

    init(id: UUID = UUID(), slots: [Slot] = []) {
        self.id = id
        self.slots = slots
    }
}

struct LibrarySnapshot: Codable {
    var version: Int = 1
    var settings: Preferences
    var apps: [AppItem]
    var folders: [FolderItem]
    var pages: [Page]
    var currentPage: Int
    /// 可选字段：旧版本快照里没有这个 key，合成 Codable 会对可选字段用
    /// decodeIfPresent，旧文件读出来是 nil 而不是整个库解析失败。
    var pinnedAppIDs: [String]?
}

enum GridPreset: CaseIterable, Identifiable {
    case c7r5, c8r5, c9r5, c10r5, c7r6, c8r6, c9r6, c10r6
    var id: String { "\(columns)x\(rows)" }
    var columns: Int {
        switch self {
        case .c7r5, .c7r6: return 7
        case .c8r5, .c8r6: return 8
        case .c9r5, .c9r6: return 9
        case .c10r5, .c10r6: return 10
        }
    }
    var rows: Int {
        switch self {
        case .c7r5, .c8r5, .c9r5, .c10r5: return 5
        case .c7r6, .c8r6, .c9r6, .c10r6: return 6
        }
    }
    var title: String { "\(columns)×\(rows)" }
}
