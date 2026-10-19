import AppKit
import SwiftUI

/// 菜单栏收纳面板的内容：对照控制中心的形态——毛玻璃面板里叠模块卡片，
/// 「菜单栏」是菜单栏上有图标的在跑应用，「已收纳」是手动钉选的常用应用。
/// 点图标即启动/前置并收起；Esc 和点击外部关闭由 TrayPanel/AppDelegate 处理。
struct TrayView: View {
    @ObservedObject var model: AppModel
    /// 外层用液态玻璃时为 true：玻璃自带折射边缘，不再叠加 SwiftUI 描边。
    var liquidGlass = false
    /// 需要收起面板时调用（启动应用、跳全屏面板等）。
    var onClose: () -> Void
    @State private var adding = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    static let contentWidth: CGFloat = 460
    private static let columns = 5
    private static let cardPadding: CGFloat = 10
    private static let cardSpacing: CGFloat = 8
    private static let edgePadding: CGFloat = 10
    private static let footerHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            if adding {
                addMode
            } else {
                content
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if !liquidGlass {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
        }
        .onChange(of: adding) { _, on in
            if on {
                query = ""
                searchFocused = true
            }
        }
    }

    // MARK: - 正常模式：菜单栏 + 已收纳两张模块卡

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Self.cardSpacing) {
                if !model.runningApps.isEmpty {
                    card("菜单栏") {
                        grid {
                            ForEach(model.runningApps) { app in
                                RunningCell(app: app, model: model, onClose: onClose)
                            }
                        }
                    }
                }
                card("已收纳") {
                    grid {
                        ForEach(model.pinnedApps) { app in
                            PinnedCell(app: app, model: model, onClose: onClose)
                        }
                        AddCell { adding = true }
                    }
                }
            }
            .padding(Self.edgePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid<Content: View>(@ViewBuilder _ cells: () -> Content) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.columns),
            spacing: 4
        ) { cells() }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
        .padding(Self.cardPadding)
        .modifier(TrayModuleSurface())
    }

    // MARK: - 添加模式：面板内直接挑选要收纳的应用

    private var candidates: [AppItem] {
        model.apps
            .filter { !$0.hidden && !model.isPinned($0) }
            .filter { query.isEmpty || $0.effectiveName.localizedCaseInsensitiveContains(query) }
            .sorted { $0.effectiveName.localizedCaseInsensitiveCompare($1.effectiveName) == .orderedAscending }
    }

    private var addMode: some View {
        VStack(spacing: 8) {
            HStack {
                Text("添加应用")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("完成") { adding = false }
                    .buttonStyle(TrayPill())
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索应用", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            if candidates.isEmpty {
                Text("没有匹配的应用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    grid {
                        ForEach(candidates) { app in
                            CandidateCell(app: app, model: model)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(Self.edgePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底栏

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
            HStack(spacing: 10) {
                Button {
                    onClose()
                    model.open()
                } label: {
                    Label("全部应用", systemImage: "square.grid.3x3.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(TrayPill())
                Spacer()
                Button {
                    onClose()
                    SettingsOpener.open()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(TrayPill())
                .accessibilityLabel("设置")
                .help("Pinchpad 设置")
            }
            .padding(.horizontal, 14)
            .frame(height: Self.footerHeight - 1)
        }
        .frame(height: Self.footerHeight)
    }
}

private struct TrayModuleSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

/// 图标的公共外形：图标 + 名字，hover 提亮、按下回弹，右键菜单由子视图提供。
private struct CellChrome<Menu: View>: View {
    let icon: NSImage?
    let name: String
    var running = false
    var action: () -> Void
    @ViewBuilder var menu: () -> Menu
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(TrayIconButtonStyle())
        .onHover { hovering = $0 }
        .contextMenu { menu() }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovering)
        .accessibilityLabel(name)
    }

    private var label: some View {
        VStack(spacing: 4) {
            Image(nsImage: icon ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .shadow(color: .black.opacity(hovering ? 0.28 : 0.16), radius: hovering ? 8 : 4, x: 0, y: hovering ? 3 : 2)
                .scaleEffect(hovering ? 1.05 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if running {
                        Circle()
                            .fill(Color(nsColor: .systemGreen))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(.regularMaterial, lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .help(name)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0))
        }
        .contentShape(Rectangle())
    }
}

private struct TrayIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

/// 已收纳格：点击启动，右键可打开/访达显示/取消收纳；运行中的应用在角上带小绿点。
private struct PinnedCell: View {
    let app: AppItem
    @ObservedObject var model: AppModel
    var onClose: () -> Void

    var body: some View {
        CellChrome(icon: model.icon(for: app), name: app.effectiveName, running: model.isRunning(app)) {
            onClose()
            model.launch(app)
        } menu: {
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
private struct RunningCell: View {
    let app: RunningApp
    @ObservedObject var model: AppModel
    var onClose: () -> Void

    private var catalogApp: AppItem? {
        app.bundleID.flatMap { model.catalogApp(bundleID: $0) }
    }

    private func openApplication() {
        onClose()
        app.open()
    }

    var body: some View {
        CellChrome(icon: app.icon, name: app.name, running: app.isFrontmost, action: openApplication) {
            Button(action: openApplication) {
                Label("打开应用", systemImage: "arrow.up.forward.app")
            }
            Button {
                onClose()
                DispatchQueue.main.async {
                    if !app.pressMenuBarItem() { app.open() }
                }
            } label: {
                Label("打开菜单", systemImage: "menubar.rectangle")
            }
            Button {
                onClose()
                app.activate()
            } label: {
                Label("前置", systemImage: "macwindow.on.rectangle")
            }
            if let catalogApp {
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

/// 「已收纳」卡片尾部的添加格：虚线底，点击切到添加模式。
private struct AddCell: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(TrayIconButtonStyle())
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
        .accessibilityLabel("添加应用")
        .help("把常用应用收进菜单栏")
    }

    private var label: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
            Text("添加")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.primary.opacity(hovering ? 0.4 : 0.22))
        }
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0))
        }
        .contentShape(Rectangle())
    }
}

/// 添加模式里的候选格：点击即收进菜单栏（可连续选多个）。
private struct CandidateCell: View {
    let app: AppItem
    @ObservedObject var model: AppModel

    var body: some View {
        CellChrome(icon: model.icon(for: app), name: app.effectiveName) {
            model.togglePin(app)
        } menu: {
            Button {
                model.togglePin(app)
            } label: {
                Label("收进菜单栏", systemImage: "menubar.arrow.down.rectangle")
            }
        }
    }
}

/// 面板底栏的小按钮：圆角药丸底，hover 提亮。
private struct TrayPill: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary.opacity(hovering ? 1 : 0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(hovering ? 0.1 : 0), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .onHover { hovering = $0 }
            .animation(.smooth(duration: 0.15), value: hovering)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}
