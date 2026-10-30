import SwiftUI

struct GeneralSettingsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "系统集成") {
                SettingsToggle(title: "菜单栏图标", detail: "点击图标，打开常用应用收纳", isOn: $model.settings.showMenuBar)
                Divider()
                SettingsToggle(title: "在程序坞显示 Pinchpad", isOn: $model.settings.showDockIcon)
                Divider()
                SettingsToggle(title: "登录时自动启动", isOn: $model.settings.launchAtLogin)
            }
            SettingsCard(title: "打开面板时") {
                SettingsToggle(title: "临时隐藏程序坞", detail: "关闭面板后恢复原来的状态", isOn: $model.settings.hideDockWhileOpen)
            }
            SettingsHint(text: "Pinchpad 平时在后台运行，可通过快捷键、触控板手势、热角或菜单栏随时呼出。")
        }
    }
}

struct AppearanceSettingsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "启动面板背景") {
                HStack(spacing: 10) {
                    ForEach(BackdropKind.allCases) { backdrop in
                        backdropOption(backdrop)
                    }
                }
            }
            SettingsCard(title: "应用名称") {
                SettingsToggle(title: "隐藏应用名称", detail: "仅在启动面板中显示应用图标", isOn: $model.settings.hideNames)
            }
            SettingsHint(text: "三指捏合展开全屏晾衣绳，应用卡片挂落后轻晃停稳。点击菜单栏图标仍打开收纳窗口；两处共用每个应用的小、中、大设置。")
        }
    }

    private func backdropOption(_ backdrop: BackdropKind) -> some View {
        let selected = model.settings.backdrop == backdrop
        return Button { model.settings.backdrop = backdrop } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: previewColors(backdrop), startPoint: .topLeading, endPoint: .bottomTrailing))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 7), count: 3), spacing: 7) {
                        ForEach(0..<6) { index in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(index.isMultiple(of: 2) ? 0.85 : 0.4))
                                .frame(width: 16, height: 16)
                        }
                    }
                }
                .frame(height: 78)
                HStack(spacing: 5) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Text(backdrop.title).foregroundStyle(.primary)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(backdrop.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func previewColors(_ backdrop: BackdropKind) -> [Color] {
        switch backdrop {
        case .blur: return [Color(red: 0.34, green: 0.47, blue: 0.66), Color(red: 0.64, green: 0.56, blue: 0.7)]
        case .dim: return [Color(red: 0.18, green: 0.23, blue: 0.32), Color(red: 0.3, green: 0.27, blue: 0.35)]
        case .plain: return [Color(white: 0.12), Color(white: 0.12)]
        }
    }
}

struct LayoutSettingsPage: View {
    @ObservedObject var model: AppModel
    @Binding var showReorganize: Bool

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "网格与浏览") {
                SettingsRow(title: "网格密度") {
                    SettingsPicker(title: "网格密度", selection: gridSelection,
                                   options: GridPreset.allCases.map { ($0.id, $0.title) })
                }
                Divider()
                SettingsRow(title: "浏览方式") {
                    SettingsPicker(title: "浏览方式", selection: $model.settings.browsing,
                                   options: Browsing.allCases.map { ($0, $0.title) })
                }
                Divider()
                SettingsRow(title: "出现在屏幕") {
                    SettingsPicker(title: "出现在屏幕", selection: $model.settings.showOn,
                                   options: ShowOn.allCases.map { ($0, $0.title) })
                }
                Divider()
                SettingsToggle(title: "每次打开从第一页开始", isOn: $model.settings.returnToFirstPage)
            }
            SettingsCard(title: "应用整理") {
                SettingsToggle(title: "按住 Option 点击时卸载", isOn: $model.settings.optionClickUninstall)
                Divider()
                SettingsRow(title: "重新排列应用", detail: "按名称、添加时间或最近打开排序") {
                    Button("整理布局…") { showReorganize = true }
                }
            }
        }
    }

    private var gridSelection: Binding<String> {
        Binding { "\(model.settings.columns)x\(model.settings.rows)" } set: { id in
            guard let preset = GridPreset.allCases.first(where: { $0.id == id }) else { return }
            model.setGrid(columns: preset.columns, rows: preset.rows)
        }
    }
}

struct AboutSettingsPage: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 76, height: 76)
                }
                Text("Pinchpad").font(.title2.weight(.bold))
                Text("版本 \(version)").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            SettingsCard(title: "顺手的小技巧") {
                Label("⌘ + 点击应用，进入多选模式", systemImage: "command")
                Label("按住 Option，进入抖动管理模式", systemImage: "option")
                Label("使用左右方向键或两侧箭头翻页", systemImage: "arrow.left.and.right")
            }
            .font(.callout)
            Text("全部功能直接可用，无许可证、订阅或许可限制。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
