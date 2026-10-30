import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, gestures, shortcuts, terminal, appearance, layout, sources, hidden, about

    var id: Self { self }
    var title: String {
        switch self {
        case .general: return "通用"
        case .gestures: return "触控板手势"
        case .shortcuts: return "快捷键与热角"
        case .terminal: return "终端"
        case .appearance: return "外观"
        case .layout: return "布局与整理"
        case .sources: return "应用来源"
        case .hidden: return "隐藏应用"
        case .about: return "关于"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .gestures: return "hand.draw"
        case .shortcuts: return "keyboard"
        case .terminal: return "terminal"
        case .appearance: return "circle.lefthalf.filled"
        case .layout: return "square.grid.2x2"
        case .sources: return "folder"
        case .hidden: return "eye.slash"
        case .about: return "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "让 Pinchpad 按你的习惯运行。"
        case .gestures: return "两种捏合，分别调整到顺手的程度。"
        case .shortcuts: return "用一个按键，或轻移指针打开启动面板。"
        case .terminal: return "用专属快捷键，在指定目录打开终端。"
        case .appearance: return "调整背景与文字，让应用一目了然。"
        case .layout: return "选择浏览方式，安排应用的位置。"
        case .sources: return "选择 Pinchpad 从哪些文件夹发现应用。"
        case .hidden: return "管理暂时不在启动面板中显示的应用。"
        case .about: return "轻轻一捏，应用就在手边。"
        }
    }
}

struct SettingsView: View {
    static let windowSize = CGSize(width: 780, height: 600)
    @ObservedObject var model: AppModel
    @State private var selectedTab: SettingsTab = .general
    @State private var showReorganize = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedTab.title).font(.system(size: 24, weight: .bold))
                    Text(selectedTab.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                status
            }
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showReorganize) {
            ReorganizeSheet(model: model, isPresented: $showReorganize)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                }
                Text("Pinchpad").font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            navigationGroup("偏好设置", tabs: [.general, .gestures, .shortcuts, .terminal])
            navigationGroup("启动面板", tabs: [.appearance, .layout])
            navigationGroup("应用管理", tabs: [.sources, .hidden])
            Spacer(minLength: 0)
            navigationButton(.about)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 22)
        .frame(width: 176)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }

    private func navigationGroup(_ title: String, tabs: [SettingsTab]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .padding(.bottom, 3)
            ForEach(tabs) { navigationButton($0) }
        }
    }

    private func navigationButton(_ tab: SettingsTab) -> some View {
        Button { selectedTab = tab } label: {
            Label {
                Text(tab.title).font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
            } icon: {
                Image(systemName: tab.symbol).frame(width: 18)
            }
            .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(selectedTab == tab ? Color.accentColor : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    @ViewBuilder private var page: some View {
        switch selectedTab {
        case .general: GeneralSettingsPage(model: model)
        case .gestures: GestureSettingsPage(model: model)
        case .shortcuts: ShortcutSettingsPage(model: model)
        case .terminal: TerminalSettingsPage(model: model)
        case .appearance: AppearanceSettingsPage(model: model)
        case .layout: LayoutSettingsPage(model: model, showReorganize: $showReorganize)
        case .sources: SourceSettingsPage(model: model)
        case .hidden: HiddenAppsSettingsPage(model: model)
        case .about: AboutSettingsPage()
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            Image(systemName: model.notice == nil ? "checkmark.circle" : "info.circle")
                .foregroundStyle(model.notice == nil ? Color.secondary : Color.accentColor)
            Text(model.notice ?? "更改会自动保存并立即生效")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(model.notice ?? "更改会自动保存并立即生效")
            Spacer(minLength: 0)
            if model.notice != nil {
                Button { model.notice = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("关闭提示")
            }
        }
        .frame(height: 34)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1) }
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            content
        }
        .frame(minHeight: 30)
    }
}

struct SettingsToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct SettingsHint: View {
    let text: String
    var symbol = "info.circle"

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}
