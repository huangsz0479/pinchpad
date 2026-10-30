"""Exercise production panel lifecycle routing without opening any windows.

The panel and animation scheduler are fakes; sync/finishConceal are copied from
AppMain. This checks immediate launch dismissal and stale animation completion,
not on-screen frame rate. Run: python3 Tests/PanelLifecycleProbe.py
"""

from pathlib import Path
import subprocess
import tempfile


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


root = Path(__file__).resolve().parents[1]
source = (root / "Sources/AppMain.swift").read_text()
sync = block(source, "private func sync(")
# The baseline accepts but ignores the new policy so it fails behaviorally.
sync = sync.replace("private func sync()", "private func sync(animated: Bool = true)")
finish = block(source, "private func finishConceal(token: Int)")
harness = r'''
import AppKit

@MainActor final class AppModel {
    static let shared = AppModel()
    struct Settings { var hideDockWhileOpen = true }
    var settings = Settings()
    var isOpen = true
    var interactionReady = true
    var isOptionPressed = false
    var cleanupCount = 0
    var preparationCount = 0
    func keepOutOfDock() {}
    func completeClose() { cleanupCount += 1 }
    func prepareEntrance() { preparationCount += 1 }
}

@MainActor final class ProbeContentView {
    var layoutCount = 0
    func layoutSubtreeIfNeeded() { layoutCount += 1 }
}

@MainActor final class ProbePanel {
    var contentView: ProbeContentView? = ProbeContentView()
    var displayCount = 0
    func displayIfNeeded() { displayCount += 1 }
    var isVisible = true
    var isKeyWindow = true
    var ignoresMouseEvents = false
    var attachedSheet: Int?
    func endSheet(_ sheet: Int, returnCode: NSApplication.ModalResponse) { attachedSheet = nil }
    func resignKey() { isKeyWindow = false }
}

@MainActor enum LauncherPanelVisibility {
    static func suspend(_ panel: ProbePanel) {
        panel.ignoresMouseEvents = true
        panel.isVisible = false
    }
}

@MainActor final class CompanionSurface {
    var isShown = true
    func dismiss(animated: Bool = true) { isShown = false }
}

@MainActor final class Lifecycle {
    let clothesline = CompanionSurface()
    var panel: ProbePanel? = ProbePanel()
    var auroraView: NSView?
    var visibilityToken = 0
    var panelRevealed = true
    var outsideMonitor = true
    var dockHidden = true
    var pending: [Int] = []
    func dismissTray() {}
    func ensurePanel() -> Bool {
        guard panel == nil else { return false }
        panel = ProbePanel()
        return true
    }
    func layout() {}
    func setDockHidden(_ value: Bool) { dockHidden = value }
    func installOutsideMonitor() { outsideMonitor = true }
    func removeOutsideMonitor() { outsideMonitor = false }
    func reveal() { panelRevealed = true; panel?.isVisible = true }
    func conceal(token: Int) { pending.append(token) }
    func change(open: Bool, animated: Bool = true) {
        AppModel.shared.isOpen = open
        sync(animated: animated)
    }
    func complete(_ token: Int) { finishConceal(token: token) }
''' + sync + "\n" + finish + r'''
}

@main struct PanelLifecycleProbe {
    @MainActor static func main() {
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        let model = AppModel.shared
        let driver = Lifecycle()
        driver.panel?.attachedSheet = 1
        driver.change(open: false, animated: false)
        require(driver.panel?.isVisible == false, "Launching an app leaves the panel visible until a fade finishes")
        require(driver.pending.isEmpty, "Immediate dismissal queued a closing animation")
        require(driver.panel?.isKeyWindow == false && driver.panel?.ignoresMouseEvents == true,
                "Immediate dismissal retained keyboard or pointer capture")
        require(driver.panel?.attachedSheet == nil && !driver.outsideMonitor && !driver.dockHidden,
                "Immediate dismissal failed to clear sheet, monitor, or Dock state")
        require(model.cleanupCount == 1 && model.preparationCount == 1,
                "Immediate dismissal skipped cleanup or the next icon wave preparation")

        driver.change(open: true)
        require(!driver.clothesline.isShown, "Opening the full launcher must dismiss the clothesline")
        let revealToken = driver.visibilityToken
        driver.change(open: true)
        require(driver.visibilityToken == revealToken,
                "A layout-only sync invalidated the pending reveal completion without replacing it")
        driver.change(open: false)
        require(driver.panel?.isVisible == true && driver.pending.count == 1,
                "Ordinary close no longer retains its fade animation")
        let oldToken = driver.visibilityToken
        driver.change(open: true)
        let count = model.cleanupCount
        driver.complete(oldToken)
        require(driver.panel?.isVisible == true && model.cleanupCount == count,
                "An old closing animation hid a reopened panel")
        driver.change(open: false, animated: false)
        driver.complete(oldToken)
        require(driver.panel?.isVisible == false && model.cleanupCount == count + 1,
                "Immediate close during an interrupted fade did not settle exactly once")

        driver.panel = nil
        let beforeCreation = model.preparationCount
        driver.change(open: true)
        require(model.preparationCount == beforeCreation + 1
                && driver.panel?.contentView?.layoutCount == 2 && driver.panel?.displayCount == 1,
                "A new host did not mount and prepare before revealing")
        driver.change(open: true)
        require(model.preparationCount == beforeCreation + 1,
                "Synchronizing a reused host reset its entrance")
        driver.panel = nil
        driver.change(open: false, animated: false)
        require(!driver.dockHidden, "Closing without a panel left the Dock hidden")
        if !failures.isEmpty {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
        print("PASS: immediate launch dismissal, normal animated close, stale completions, sheet/focus/Dock cleanup")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="pinchpad-panel-lifecycle-") as directory:
    directory = Path(directory)
    probe = directory / "Probe.swift"
    probe.write_text(harness)
    binary = directory / "probe"
    subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", "/tmp/pinchpad-build-module-cache",
                    str(probe), "-o", str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
