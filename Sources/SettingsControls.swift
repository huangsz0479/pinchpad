import SwiftUI

/// A native dropdown whose visible button fills the settings control column.
/// A frame around SwiftUI's menu Picker only reserves space; its button still
/// shrinks to the longest option, leaving different widths and centered edges.
struct SettingsPicker<Selection: Equatable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Selection
    let options: [(value: Selection, title: String)]

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let titles = options.map(\.title)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        button.selectItem(at: options.firstIndex { $0.value == selection } ?? -1)
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(title)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: 170, height: 26)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: SettingsPicker
        init(_ parent: SettingsPicker) { self.parent = parent }

        @objc func select(_ sender: NSPopUpButton) {
            guard parent.options.indices.contains(sender.indexOfSelectedItem) else { return }
            parent.selection = parent.options[sender.indexOfSelectedItem].value
        }
    }
}

struct ReorganizeSheet: View {
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
            SettingsRow(title: "排序依据") {
                SettingsPicker(title: "排序依据", selection: $model.settings.reorganize.sortBy,
                               options: SortKey.allCases.filter { $0 != .custom }.map { ($0, $0.title) })
            }
            Toggle("升序排列", isOn: $model.settings.reorganize.ascending)
            SettingsRow(title: "文件夹位置") {
                SettingsPicker(title: "文件夹位置", selection: $model.settings.reorganize.folders,
                               options: EndPlacement.allCases.map { ($0, $0.title) })
            }
            SettingsRow(title: "系统自带应用") {
                SettingsPicker(title: "系统自带应用", selection: $model.settings.reorganize.appleApps,
                               options: EndPlacement.allCases.map { ($0, $0.title) })
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

struct HotKeyEditor: View {
    var title: String
    var label: String
    var onRecord: (UInt32, UInt32) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(recording ? "请按下组合键，Esc 取消" : label)
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
                onRecord(code, modifiers)
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
