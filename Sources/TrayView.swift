import AppKit
import SwiftUI

/// Control Center reference: independent glass capsules with desktop-visible gaps.
/// https://support.apple.com/zh-sg/guide/mac-help/mchl50f94f8f/mac
/// 「菜单栏」是菜单栏上有图标的在跑应用，「已收纳」是手动钉选的常用应用。
/// 点图标即启动/前置并收起；Esc 和点击外部关闭由 TrayPanel/AppDelegate 处理。
struct TrayView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void
    var onLaunch: () -> Void
    var onHeightChange: (CGFloat, Bool) -> Void = { _, _ in }
    @State private var adding = false
    @State private var query = ""
    @State private var layoutWidth = Self.contentWidth
    @FocusState private var searchFocused: Bool

    static let contentWidth: CGFloat = 360
    static let cornerRadius: CGFloat = 30
    private static let cardSpacing: CGFloat = 12
    private static let edgePadding: CGFloat = 12
    static let cellHeight: CGFloat = 60

    /// Natural panel height, capped before long app lists become a sidebar.
    /// Reserve useful space for adding apps when the collection is empty.
    static func preferredHeight(menuCount: Int, pinnedCount: Int) -> CGFloat {
        preferredHeight(menuSizes: Array(repeating: .medium, count: menuCount),
                        pinnedSizes: Array(repeating: .medium, count: pinnedCount))
    }

    static func preferredHeight(menuSizes: [TrayAppSize], pinnedSizes: [TrayAppSize],
                                width: CGFloat = contentWidth) -> CGFloat {
        func moduleHeight(_ sizes: [TrayAppSize]) -> CGFloat {
            let grid = TrayGridMetrics(sizes: sizes, width: max(1, width - 2 * edgePadding))
            return 28 + 8 + (sizes.isEmpty ? cellHeight : grid.height)
        }
        let menu = menuSizes.isEmpty ? 0 : moduleHeight(menuSizes) + cardSpacing
        return min(600, 2 * edgePadding + menu + moduleHeight(pinnedSizes) + cardSpacing + cellHeight)
    }

    private var preferredHeight: CGFloat {
        let height = Self.preferredHeight(menuSizes: model.runningApps.map { model.traySize(for: $0) },
                                          pinnedSizes: model.pinnedApps.map { model.traySize(for: $0) },
                                          width: layoutWidth)
        return adding ? max(420, height) : height
    }

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                // Batch the glass rendering without merging neighbouring controls.
                GlassEffectContainer(spacing: 0) { panelContent }
            } else {
                panelContent
            }
        }
        .onChange(of: adding) { _, on in
            if on {
                query = ""
                searchFocused = true
            }
            onHeightChange(preferredHeight, on)
        }
        .onChange(of: preferredHeight) { _, height in onHeightChange(height, adding) }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { layoutWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in layoutWidth = width }
            }
        }
    }

    private var panelContent: some View {
        VStack(spacing: Self.cardSpacing) {
            if adding {
                addMode
            } else {
                content
            }
            footer
        }
        .padding(Self.edgePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Independent application controls

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Self.cardSpacing) {
                if !model.runningApps.isEmpty {
                    section("菜单栏", count: model.runningApps.count) {
                        grid {
                            ForEach(model.runningApps) { app in
                                RunningCell(app: app, model: model, onClose: onLaunch)
                                    .traySize(model.traySize(for: app))
                            }
                        }
                    }
                }
                section("已收纳", count: model.pinnedApps.count) {
                    if model.pinnedApps.isEmpty {
                        Button { adding = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                                Text("添加应用").font(.system(size: 13, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.cellHeight)
                            .modifier(TrayModuleSurface())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(TrayIconButtonStyle())
                    } else {
                        grid {
                            ForEach(model.pinnedApps) { app in
                                PinnedCell(app: app, model: model, onClose: onLaunch)
                                    .traySize(model.traySize(for: app))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid<Content: View>(@ViewBuilder _ cells: () -> Content) -> some View {
        TrayGridLayout(spacing: Self.cardSpacing) { cells() }
    }

    private func section<Content: View>(_ title: String, count: Int,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if count > 0 {
                    Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .modifier(TrayModuleSurface(cornerRadius: 14, interactive: false))
            content()
        }
    }

    // MARK: - Add applications in the same panel

    private var candidates: [AppItem] {
        model.apps
            .filter { !$0.hidden && !model.isPinned($0) }
            .filter { query.isEmpty || $0.effectiveName.localizedCaseInsensitiveContains(query) }
            .sorted { $0.effectiveName.localizedCaseInsensitiveCompare($1.effectiveName) == .orderedAscending }
    }

    private var addMode: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("搜索应用", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .modifier(TrayModuleSurface(cornerRadius: 22, interactive: false))
            if candidates.isEmpty {
                VStack {
                    Text("没有匹配的应用")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.cellHeight)
                        .modifier(TrayModuleSurface(interactive: false))
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    grid {
                        ForEach(candidates) { app in
                            CandidateCell(app: app, model: model)
                                .traySize(model.traySize(for: app))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: Self.cardSpacing) {
            if adding {
                Button { adding = false } label: {
                    Label("完成", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.cellHeight)
                        .modifier(TrayModuleSurface())
                        .contentShape(Capsule())
                }
            } else {
                Button {
                    onClose()
                    model.open()
                } label: {
                    Label("全部应用", systemImage: "square.grid.3x3.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.cellHeight)
                        .modifier(TrayModuleSurface())
                        .contentShape(Capsule())
                }
                Button { adding = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .medium))
                        .frame(width: Self.cellHeight, height: Self.cellHeight)
                        .modifier(TrayModuleSurface())
                        .contentShape(Circle())
                }
                .accessibilityLabel("添加应用")
                .help("添加应用")
            }
            Button {
                onClose()
                SettingsOpener.open()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: Self.cellHeight, height: Self.cellHeight)
                    .modifier(TrayModuleSurface())
                    .contentShape(Circle())
            }
            .accessibilityLabel("设置")
            .help("Pinchpad 设置")
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(TrayIconButtonStyle())
        .frame(height: Self.cellHeight)
    }
}

private struct TrayModuleSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var cornerRadius: CGFloat = TrayView.cornerRadius
    var interactive = true
    var capsule = true
    var hanging = false

    func body(content: Content) -> some View {
        if capsule {
            outlined(content, shape: Capsule())
        } else {
            outlined(content, shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private func outlined<S: InsettableShape>(_ content: Content, shape: S) -> some View {
        surface(content, shape: shape)
            // The dark outer edge survives a light desktop; the light inner
            // edge survives a dark one, including when the glass matches it.
            .overlay {
                ZStack {
                    shape.strokeBorder(.black.opacity(hanging ? 0.3 : 0.85), lineWidth: 1.5)
                    shape.inset(by: 1.5).strokeBorder(.white.opacity(0.95), lineWidth: 1)
                }
                .clipShape(shape)
            }
            .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 3)
    }

    @ViewBuilder
    private func surface<S: InsettableShape>(_ content: Content, shape: S) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular
                .tint(Color(nsColor: .windowBackgroundColor).opacity(0.3))
                .interactive(interactive), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// 图标的公共外形：图标 + 名字，hover 提亮、按下回弹，右键菜单由子视图提供。
private struct CellChrome<Menu: View>: View {
    let icon: NSImage?
    let name: String
    var size: TrayAppSize = .medium
    var running = false
    var hanging = false
    var action: () -> Void
    @ViewBuilder var menu: () -> Menu
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(TrayIconButtonStyle(rigid: hanging))
        .focusable(!hanging)
        .onHover { hovering = $0 }
        .contextMenu { menu() }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovering)
        .accessibilityLabel(name)
        .help(name)
    }

    @ViewBuilder private var label: some View {
        if hanging {
            // Keep the icon outside the native glass content layer. That layer
            // can detach foreground content when the card rotates around its
            // corner hole; the background and centred overlay share one frame.
            Color.clear
                .modifier(TrayModuleSurface(cornerRadius: 10, interactive: false, capsule: false, hanging: true))
                .overlay(alignment: .center) { appIcon }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        } else {
            organizerLabel
        }
    }

    private var organizerLabel: some View {
        Group {
            switch size {
            case .small:
                appIcon
            case .medium:
                HStack(spacing: 10) {
                    appIcon
                    appName.font(.system(size: hanging ? 15 : 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
            case .large:
                VStack(spacing: 12) {
                    appIcon
                    appName.font(.system(size: hanging ? 16 : 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(TrayModuleSurface(capsule: !hanging && size != .large, hanging: hanging))
        .contentShape(size == .large || hanging
            ? AnyShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            : AnyShape(Capsule()))
    }

    private var appName: some View {
        Text(name)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.tail)
    }

    private var appIcon: some View {
        Image(nsImage: icon ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: iconSide, height: iconSide)
                .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 2)
                .scaleEffect(hovering ? 1.04 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if running {
                        Circle()
                            .fill(Color(nsColor: .systemGreen))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(.regularMaterial, lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }
    }

    private var iconSide: CGFloat { hanging ? ClotheslineLayout.iconSide : (size == .large ? 52 : 32) }
}

private struct TraySizeMenu: View {
    let selection: TrayAppSize
    var onSelect: (TrayAppSize) -> Void

    var body: some View {
        Picker("大小", selection: Binding(get: { selection }, set: onSelect)) {
            ForEach(TrayAppSize.allCases) { size in
                Text(size.title).tag(size)
            }
        }
    }
}

private struct TrayIconButtonStyle: ButtonStyle {
    var rigid = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !rigid ? 0.96 : 1)
    }
}

/// 已收纳格：点击启动，右键可打开/访达显示/取消收纳；运行中的应用在角上带小绿点。
private struct PinnedCell: View {
    let app: AppItem
    @ObservedObject var model: AppModel
    var onClose: () -> Void

    var body: some View {
        CellChrome(icon: model.icon(for: app), name: app.effectiveName,
                   size: model.traySize(for: app), running: model.isRunning(app)) {
            onClose()
            model.launch(app)
        } menu: {
            TraySizeMenu(selection: model.traySize(for: app)) { model.setTraySize($0, for: app) }
            Divider()
            Button {
                onClose()
                model.launch(app)
            } label: {
                Label("打开", systemImage: "arrow.up.forward.app")
            }
            Button {
                model.reveal(app)
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }
            Divider()
            Button {
                model.togglePin(app)
            } label: {
                Label("取消收纳", systemImage: "menubar.arrow.up.rectangle")
            }
        }
    }
}

/// 普通点击打开应用；只有明确选择「打开菜单」时才 press 菜单栏图标。
struct RunningCell: View {
    let app: RunningApp
    @ObservedObject var model: AppModel
    var onClose: () -> Void
    var hanging = false
    var canOpen: () -> Bool = { true }

    private var catalogApp: AppItem? {
        app.bundleID.flatMap { model.catalogApp(bundleID: $0) }
    }

    private func openApplication() {
        guard canOpen() else { return }
        onClose()
        DispatchQueue.main.async { app.open() }
    }

    var body: some View {
        CellChrome(icon: app.icon, name: app.name, size: model.traySize(for: app),
                   running: app.isFrontmost, hanging: hanging, action: openApplication) {
            if !hanging {
                TraySizeMenu(selection: model.traySize(for: app)) { model.setTraySize($0, for: app) }
                Divider()
            }
            Button(action: openApplication) {
                Label("打开应用", systemImage: "arrow.up.forward.app")
            }
            Button {
                guard canOpen() else { return }
                onClose()
                DispatchQueue.main.async {
                    if !app.pressMenuBarItem() { app.open() }
                }
            } label: {
                Label("打开菜单", systemImage: "menubar.rectangle")
            }
            Button {
                guard canOpen() else { return }
                onClose()
                DispatchQueue.main.async { app.activate() }
            } label: {
                Label("前置", systemImage: "macwindow.on.rectangle")
            }
            if !hanging, let catalogApp {
                Divider()
                Button {
                    model.togglePin(catalogApp)
                } label: {
                    Label(
                        model.isPinned(catalogApp) ? "从菜单栏移除" : "收进菜单栏",
                        systemImage: model.isPinned(catalogApp) ? "menubar.arrow.up.rectangle" : "menubar.arrow.down.rectangle"
                    )
                }
            }
            Divider()
            Button {
                app.terminate()
            } label: {
                Label("退出", systemImage: "xmark.circle")
            }
        }
    }
}

/// 添加模式里的候选格：点击即收进菜单栏（可连续选多个）。
private struct CandidateCell: View {
    let app: AppItem
    @ObservedObject var model: AppModel

    var body: some View {
        CellChrome(icon: model.icon(for: app), name: app.effectiveName, size: model.traySize(for: app)) {
            model.togglePin(app)
        } menu: {
            TraySizeMenu(selection: model.traySize(for: app)) { model.setTraySize($0, for: app) }
            Divider()
            Button {
                model.togglePin(app)
            } label: {
                Label("收进菜单栏", systemImage: "menubar.arrow.down.rectangle")
            }
        }
    }
}
