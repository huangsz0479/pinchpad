import SwiftUI

extension CardNavigationShortcuts {
    static func code(from event: NSEvent) -> UInt16? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        if event.type == .systemDefined, event.subtype.rawValue == 8 {
            let type = (event.data1 >> 16) & 0xffff, state = (event.data1 >> 8) & 0xff
            let code = UInt16(clamping: 256 + type)
            return state == 0x0a && accepts(code) ? code : nil
        }
        guard event.type == .keyDown || event.type == .flagsChanged, accepts(event.keyCode) else { return nil }
        if event.type == .keyDown { return event.keyCode }
        guard event.type == .flagsChanged else { return nil }
        if event.keyCode == 57 { return event.keyCode }
        // Device-specific bits distinguish a release while the other Shift is held.
        let sideMask: UInt = event.keyCode == 56 ? 0x02 : 0x04
        if [56, 60].contains(event.keyCode), event.modifierFlags.rawValue & sideMask != 0 { return event.keyCode }
        return nil
    }

    static func label(_ code: UInt16) -> String {
        if code >= 256 {
            let names = [0: "音量 +", 1: "音量 −", 2: "亮度 +", 3: "亮度 −", 7: "静音", 10: "Num Lock",
                         11: "对比度 +", 12: "对比度 −", 13: "启动面板", 14: "推出", 15: "屏幕镜像",
                         16: "播放 / 暂停", 17: "下一曲", 18: "上一曲", 19: "快进", 20: "快退",
                         21: "键盘背光 +", 22: "键盘背光 −", 23: "键盘背光", 25: "菜单"]
            return names[Int(code) - 256] ?? "媒体键"
        }
        switch code {
        case 48: return "Tab ⇥"
        case 50: return "~ / `"
        case 56: return "左 Shift ⇧"
        case 60: return "右 Shift ⇧"
        case 57: return "Caps Lock ⇪"
        default: return HotKeyCenter.title(keyCode: UInt32(code), modifiers: 0)
        }
    }
}

struct CardKeyEditor: View {
    let title: String
    let code: UInt16
    var onRecord: (UInt16) -> Void
    @State private var monitor: Any?
    @State private var identity = UUID()
    private static let began = Notification.Name("PinchpadShortcutRecordingBegan")

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(monitor == nil ? CardNavigationShortcuts.label(code) : "请按一个键")
                    .foregroundStyle(monitor == nil ? Color.primary : Color.accentColor)
                Button(monitor == nil ? "录制更改" : "取消") {
                    if monitor == nil { begin() } else { stop() }
                }
                .accessibilityLabel("\(title)快捷键：\(monitor == nil ? "录制更改" : "取消")")
            }
        }
        .frame(minHeight: 28)
        .onReceive(NotificationCenter.default.publisher(for: Self.began)) { notification in
            if notification.object as? UUID != identity { stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
        .onDisappear(perform: stop)
    }

    private func begin() {
        NotificationCenter.default.post(name: Self.began, object: identity)
        HotKeyCenter.shared.recordCardKey = { code in
            stop()
            onRecord(code)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .systemDefined]) { event in
            if let code = CardNavigationShortcuts.code(from: event) {
                stop()
                onRecord(code)
            }
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            HotKeyCenter.shared.recordCardKey = nil
        }
        monitor = nil
    }
}
