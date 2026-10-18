import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case gestures = "手势"
    case appearance = "外观"
    case sources = "应用"
    case about = "关于"

    var id: String { rawValue }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab: SettingsTab = .general
    @State private var showReorganize = false

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(model: model)
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            GesturesTab(model: model)
                .tabItem { Label("手势与按键", systemImage: "hand.tap") }
                .tag(SettingsTab.gestures)

            AppearanceTab(model: model, showReorganize: $showReorganize)
                .tabItem { Label("外观与网格", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.appearance)

            SourcesTab(model: model)
                .tabItem { Label("应用与来源", systemImage: "app.badge") }
                .tag(SettingsTab.sources)

            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 520, height: 480)
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(notice)
                        .font(.callout)
                    Spacer()
                    Button("知道了") { model.notice = nil }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .padding(14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.2), value: model.notice)
        .sheet(isPresented: $showReorganize) {
            ReorganizeSheet(model: model, isPresented: $showReorganize)
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("系统集成") {
                Toggle("菜单栏托盘图标", isOn: $model.settings.showMenuBar)
                Toggle("在程序坞显示 Pinchpad", isOn: $model.settings.showDockIcon)
                Toggle("打开时临时隐藏程序坞", isOn: $model.settings.hideDockWhileOpen)
                Toggle("登录时自动启动", isOn: $model.settings.launchAtLogin)
            }
            Section("运行方式") {
                Text("Pinchpad 是本机独立的应用启动面板，平时在后台静默运行，几乎不占用 CPU。随时可通过快捷键、触控板手势或菜单栏呼出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(4)
    }
}

private struct GesturesTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("快捷键") {
                Toggle("启用快捷键打开", isOn: $model.settings.f4Enabled)
                HotKeyEditor(model: model)
            }
            Section("触控板手势") {
                Toggle("三指捏合打开菜单栏收纳", isOn: $model.settings.pinchThree)
                Toggle("四指捏合打开全屏面板", isOn: $model.settings.pinchFour)
                Text("支持内置触控板与外接 Magic Trackpad。Pinchpad 只接管向内捏合；四指张开仍保留系统「显示桌面」功能。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("屏幕热角") {
                Picker("将指针移入角落呼出", selection: $model.settings.hotCorner) {
                    ForEach(HotCorner.allCases) { corner in
                        Text(corner.title).tag(corner)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(4)
    }
}

private struct AppearanceTab: View {
    @ObservedObject var model: AppModel
    @Binding var showReorganize: Bool

    var body: some View {
        Form {
            Section("网格与排版") {
                Picker("网格密度", selection: gridSelection) {
                    ForEach(GridPreset.allCases) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                Picker("浏览方式", selection: $model.settings.browsing) {
                    ForEach(Browsing.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("出现在屏幕", selection: $model.settings.showOn) {
                    ForEach(ShowOn.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Toggle("每次打开从第一页开始", isOn: $model.settings.returnToFirstPage)
                Toggle("隐藏应用名称", isOn: $model.settings.hideNames)
            }
            Section("视觉风格") {
                Picker("背景样式", selection: $model.settings.backdrop) {
                    ForEach(BackdropKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }
            Section("交互与管理") {
                Toggle("按住 Option 点击时卸载", isOn: $model.settings.optionClickUninstall)
                Text("按住 Option 键进入抖动管理模式，可快速点击移除第三方应用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("整理应用布局…") { showReorganize = true }
            }
        }
        .formStyle(.grouped)
        .padding(4)
    }

    private var gridSelection: Binding<String> {
        Binding {
            "\(model.settings.columns)x\(model.settings.rows)"
        } set: { id in
            guard let preset = GridPreset.allCases.first(where: { $0.id == id }) else { return }
            model.setGrid(columns: preset.columns, rows: preset.rows)
        }
    }
}

private struct SourcesTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("应用扫描目录") {
                ForEach($model.settings.sources) { $source in
                    HStack {
                        Toggle(source.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"), isOn: $source.enabled)
                            .lineLimit(1)
                            .help(source.path)
                        if source.custom {
                            Button("移除") { model.removeSource(source.id) }
                                .buttonStyle(.borderless)
                                .help("仅移除扫描目录，不会删除文件夹")
                        }
                    }
                }
                HStack {
                    Button("添加文件夹…") { model.addSource() }
                    Spacer()
                    Button(model.isScanning ? "正在扫描…" : "重新扫描") { model.rescan() }
                        .disabled(model.isScanning)
                }
                Button("导入系统应用顺序") { model.importSystemLayout() }
            }
            Section("已隐藏的应用") {
                let hidden = model.apps.filter(\.hidden)
                if hidden.isEmpty {
                    Text("没有隐藏的应用")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hidden) { app in
                        HStack {
                            Text(app.effectiveName)
                            Spacer()
                            Button("取消隐藏") { model.unhide(app.id) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(4)
    }
}

private struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 68, height: 68)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            }
            VStack(spacing: 3) {
                Text("Pinchpad")
                    .font(.title2.weight(.bold))
                Text("版本 \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("本机独立应用启动面板，从菜单栏、快捷键、热角或触控板捏合随心打开。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Divider().frame(width: 240)

            VStack(alignment: .leading, spacing: 6) {
                hint("command", "⌘ + 点击应用：进入多选模式")
                hint("option", "按住 Option：进入抖动卸载管理")
                hint("arrow.left.and.right", "方向键 ← / → 或点击两侧箭头：翻页浏览")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("全部功能直接可用，无许可证、订阅或许可限制。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16, alignment: .center)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ReorganizeSheet: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.arrow.down.square.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("整理应用布局")
                    .font(.title2.weight(.semibold))
            }
            Toggle("跨页整体排序", isOn: $model.settings.reorganize.allPages)
            Picker("排序依据", selection: $model.settings.reorganize.sortBy) {
                ForEach(SortKey.allCases.filter { $0 != .custom }) { key in
                    Text(key.title).tag(key)
                }
            }
            Toggle("升序排列", isOn: $model.settings.reorganize.ascending)
            Picker("文件夹位置", selection: $model.settings.reorganize.folders) {
                ForEach(EndPlacement.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            Picker("系统自带应用", selection: $model.settings.reorganize.appleApps) {
                ForEach(EndPlacement.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            Toggle("同时整理文件夹内部应用", isOn: $model.settings.reorganize.sortInsideFolders)
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                Button("开始整理") {
                    model.reorganizeNow()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct HotKeyEditor: View {
    @ObservedObject var model: AppModel
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent("全局快捷键") {
            HStack(spacing: 8) {
                Text(recording ? "请按下组合键，Esc 取消" : model.hotKeyLabel)
                    .foregroundStyle(recording ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Button(recording ? "取消" : "录制更改") {
                    if recording { stop() } else { begin() }
                }
            }
        }
        .onDisappear { stop() }
    }

    private func begin() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { stop() }
                return nil
            }
            let modifiersOnly: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]
            if modifiersOnly.contains(event.keyCode) { return nil }
            let modifiers = HotKeyCenter.carbonModifiers(event.modifierFlags)
            let code = UInt32(event.keyCode)
            DispatchQueue.main.async {
                var next = model.settings
                next.hotKeyCode = code
                next.hotKeyModifiers = modifiers
                next.f4Enabled = true
                model.settings = next
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        recording = false
    }
}
