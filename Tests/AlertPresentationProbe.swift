import AppKit

// Runs native alerts with cancel-only test actions. No files or apps are removed.
// swiftc -swift-version 5 Sources/PanelAlertPresenter.swift \
//   Tests/AlertPresentationProbe.swift -o /tmp/AlertPresentationProbe \
//   && /tmp/AlertPresentationProbe
@main
struct AlertPresentationProbe {
    final class ProbePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        do {
            try check(style: [.borderless],
                      level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1),
                      name: "full-screen launcher")
            try check(style: [.titled, .closable], level: .floating, name: "windowed launcher")
            print("PASS: native confirmation sheets stay above their launcher")
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    static func check(style: NSWindow.StyleMask, level: NSWindow.Level, name: String) throws {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 900, height: 600)
        let parent = ProbePanel(contentRect: frame.insetBy(dx: 80, dy: 80),
                                styleMask: style, backing: .buffered, defer: false)
        parent.level = level
        parent.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        parent.backgroundColor = .windowBackgroundColor
        parent.isReleasedWhenClosed = false
        parent.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { parent.orderOut(nil) }

        let alert = NSAlert()
        alert.messageText = "Pinchpad confirmation layering test"
        alert.informativeText = "This test only cancels; no destructive action is performed."
        alert.addButton(withTitle: "Confirm (never clicked)")
        alert.addButton(withTitle: "Cancel")
        var response: NSApplication.ModalResponse?
        var failure: String?
        var inspected = false
        let inspect = Timer(timeInterval: 0.5, repeats: false) { _ in
            MainActor.assumeIsolated {
                inspected = true
                let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                let order = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
                let alertIndex = order.firstIndex(of: alert.window.windowNumber)
                let parentIndex = order.firstIndex(of: parent.windowNumber)
                if let alertIndex, let parentIndex, alertIndex < parentIndex {
                    print("PASS: \(name): alert is ahead of launcher in WindowServer order")
                } else {
                    failure = "\(name): confirmation is behind the launcher (alert level \(alert.window.level.rawValue), launcher level \(parent.level.rawValue))"
                }
                if parent.attachedSheet !== alert.window || alert.window.sheetParent !== parent {
                    failure = failure ?? "\(name): confirmation is not attached to its launcher"
                }
                // Only cancel, even if the alert is incorrectly hidden.
                alert.buttons.last?.performClick(nil)
            }
        }
        RunLoop.main.add(inspect, forMode: .default)
        RunLoop.main.add(inspect, forMode: .modalPanel)
        defer { inspect.invalidate() }

        PanelAlertPresenter.present(alert, over: parent) { result in response = result }
        let deadline = Date().addingTimeInterval(4)
        while response == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        if response == nil {
            if let sheet = parent.attachedSheet { parent.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
            failure = failure ?? "\(name): cancel did not finish the confirmation"
        }
        if !inspected { failure = failure ?? "\(name): window ordering was not inspected" }
        if response != .alertSecondButtonReturn { failure = failure ?? "\(name): cancellation was not preserved" }
        if !parent.isVisible { failure = failure ?? "\(name): cancelling hid the launcher" }
        if let failure {
            throw NSError(domain: "AlertPresentationProbe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: failure])
        }
    }
}
