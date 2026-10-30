import SwiftUI

struct GestureSettingsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            PinchSettingsCard(title: "三指捏合", destination: "展开菜单栏应用晾衣绳", symbol: "menubar.rectangle",
                              enabled: $model.settings.pinchThree, sensitivity: $model.settings.pinchThreeSensitivity)
            PinchSettingsCard(title: "四指捏合", destination: "打开应用启动面板", symbol: "square.grid.3x3",
                              enabled: $model.settings.pinchFour, sensitivity: $model.settings.pinchFourSensitivity)
            SettingsHint(text: "三指将菜单栏应用挂在全屏晾衣绳上，轻晃后停稳；拖动卡片可自由摆放，松手重新系绳。点击菜单栏图标打开设置。灵敏度越高，所需收拢幅度越小。四指张开仍保留系统「显示桌面」功能。")
        }
    }
}

private struct PinchSettingsCard: View {
    let title: String
    let destination: String
    let symbol: String
    @Binding var enabled: Bool
    @Binding var sensitivity: PinchSensitivity

    var body: some View {
        SettingsCard(title: destination) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Toggle(title, isOn: $enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Divider()
            VStack(spacing: 8) {
                HStack {
                    Text("灵敏度").font(.system(size: 12))
                    Spacer()
                    Text(sensitivity.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.08), in: Capsule())
                }
                HStack(spacing: 12) {
                    Text("低").font(.caption).foregroundStyle(.secondary)
                    Slider(value: level, in: 1...5, step: 1)
                        .accessibilityLabel("\(title)灵敏度")
                        .accessibilityValue(sensitivity.title)
                    Text("高").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
        }
    }

    private var level: Binding<Double> {
        Binding { Double(sensitivity.rawValue) } set: { value in
            sensitivity = PinchSensitivity(rawValue: Int(value.rounded())) ?? .standard
        }
    }
}

struct ShortcutSettingsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "应用启动面板") {
                SettingsToggle(title: "启用全局快捷键", isOn: $model.settings.f4Enabled)
                Divider()
                HotKeyEditor(title: "打开面板", label: model.hotKeyLabel) { code, modifiers in
                    var next = model.settings
                    next.hotKeyCode = code
                    next.hotKeyModifiers = modifiers
                    next.f4Enabled = true
                    model.settings = next
                }
                .frame(minHeight: 30)
            }
            SettingsCard(title: "屏幕热角") {
                SettingsRow(title: "将指针移入角落呼出") {
                    Picker("屏幕热角", selection: $model.settings.hotCorner) {
                        ForEach(HotCorner.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 140)
                }
            }
        }
    }
}

struct TerminalSettingsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "终端快捷键") {
                SettingsToggle(title: "启用快捷键打开终端", isOn: $model.settings.terminalHotKeyEnabled)
                Divider()
                HotKeyEditor(title: "打开新窗口", label: model.terminalHotKeyLabel) { code, modifiers in
                    var next = model.settings
                    next.terminalHotKeyCode = code
                    next.terminalHotKeyModifiers = modifiers
                    next.terminalHotKeyEnabled = true
                    model.settings = next
                }
                .frame(minHeight: 30)
            }
            SettingsCard(title: "启动配置") {
                SettingsRow(title: "终端应用") {
                    Text(model.terminalAppLabel).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary).help(model.terminalAppLabel)
                    Button("选择…") { model.chooseTerminalApp() }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("启动目录").font(.system(size: 13))
                    HStack(spacing: 8) {
                        TextField("留空使用主目录", text: $model.settings.terminalDirectory)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("终端启动目录")
                            .help(model.settings.terminalDirectory)
                        Button("选择…") { model.chooseTerminalDirectory() }
                    }
                    Text("每次使用快捷键，都会在此目录打开一个新窗口。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
