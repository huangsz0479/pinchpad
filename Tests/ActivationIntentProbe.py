"""Replay the real icon activation gate, without a window or system input."""
from pathlib import Path
import subprocess
import tempfile


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


root = Path(__file__).resolve().parents[1]
model = (root / 'Sources/AppModel.swift').read_text()
methods = '\n'.join(block(model, marker) for marker in (
    'private var pointerGuarded:', 'func beginPointerSession()',
    'func recordPointerDown(at timestamp:', 'func activate(_ slot:',
))
source = r'''
import Foundation
struct AppItem { let id: String }
enum Slot { case app(String), folder(Int) }
enum NSEvent {
    struct Flags: OptionSet { let rawValue: Int; static let option = Flags(rawValue: 1) }
    static var modifierFlags: Flags = []
}
final class PinchMonitor {
    static let shared = PinchMonitor()
    var deadline = Date.distantFuture
    func pinchPointerGuardUntil() -> Date { deadline }
}
final class AppModel {
    struct Settings { var optionClickUninstall = true }
    var settings = Settings()
    var isOpen = true
    var draggingID: String?
    var openFolderID: Int?
    var selection: Set<String> = []
    private var ignorePointerUntil = Date.distantPast
    private var pointerSessionBegan: TimeInterval = 0
    private var pointerPressBegan: TimeInterval?
    var launches = 0
    var uninstallPrompts = 0
    func app(_ id: String) -> AppItem? { AppItem(id: id) }
    func launch(_ app: AppItem) { launches += 1; isOpen = false }
    func promptUninstall(_ app: AppItem) { uninstallPrompts += 1 }
''' + methods + r'''
}
@main struct ActivationIntentProbe {
    static func main() {
        var failures: [String] = []
        func require(_ value: Bool, _ message: String) { if !value { failures.append(message) } }
        let model = AppModel()
        model.beginPointerSession()
        model.activate(.app("target"))
        require(model.launches == 0 && model.isOpen, "A pinch-tail release without a new press must not launch")
        model.recordPointerDown(at: ProcessInfo.processInfo.systemUptime)
        model.activate(.app("target"))
        require(model.launches == 1 && !model.isOpen,
                "A fresh icon click after opening is swallowed by the pinch tail instead of dismissing immediately")
        model.isOpen = true
        model.beginPointerSession()
        model.recordPointerDown(at: 0)
        model.activate(.app("target"))
        require(model.launches == 1, "An input queued before the panel opened must not authorize a launch")
        model.recordPointerDown(at: ProcessInfo.processInfo.systemUptime)
        model.activate(.folder(4))
        require(model.openFolderID == 4, "A fresh folder click is swallowed by the pinch tail")
        model.activate(.app("target"))
        require(model.launches == 1, "A consumed fresh press must not authorize another activation")
        NSEvent.modifierFlags = .option
        model.recordPointerDown(at: ProcessInfo.processInfo.systemUptime)
        model.activate(.app("target"))
        require(model.uninstallPrompts == 1 && model.launches == 1, "Option-click lost its uninstall confirmation")
        NSEvent.modifierFlags = []
        model.beginPointerSession()
        model.draggingID = "dragged"
        model.recordPointerDown(at: ProcessInfo.processInfo.systemUptime)
        model.activate(.app("target"))
        require(model.launches == 1, "Dragging must not authorize an app activation")
        if !failures.isEmpty {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
        print("PASS: fresh app/folder clicks bypass pinch tails; stale releases and dragging remain guarded")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-activation-intent-') as directory:
    source_path = Path(directory) / 'Probe.swift'
    source_path.write_text(source)
    binary = Path(directory) / 'probe'
    subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', '/tmp/pinchpad-build-module-cache', str(source_path), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
