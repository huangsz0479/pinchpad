import AppKit

@MainActor
enum PanelAlertPresenter {
    static func present(
        _ alert: NSAlert,
        over parent: NSWindow?,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        guard let parent else {
            completion(alert.runModal())
            return
        }
        // runModal resets NSAlert to modalPanel level, below the full-screen
        // launcher. A native sheet inherits its parent's Space and stacking.
        alert.beginSheetModal(for: parent, completionHandler: completion)
    }
}
