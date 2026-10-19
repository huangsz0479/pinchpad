import AppKit

@MainActor
enum LauncherPanelVisibility {
    static func suspend(_ panel: NSPanel) {
        panel.ignoresMouseEvents = true
        // Retain the panel and its content, but remove its surface from desktop compositing.
        panel.orderOut(nil)
        panel.alphaValue = 1
        (panel.contentView as? NSVisualEffectView)?.state = .inactive
        if let layer = panel.contentView?.layer {
            layer.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
        }
    }
}
