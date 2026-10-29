"""Replay the real reveal completion without opening a window."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/AppMain.swift').read_text()
start = source.index('private func finishReveal(token: Int)')
opening = source.index('{', start)
depth, end = 1, opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
method = source[start:end]
harness = r'''
import Foundation
@MainActor final class AppModel {
    static let shared = AppModel()
    var isOpen = true
    var interactionReady = false
}
@MainActor final class Driver {
    var visibilityToken = 1
    var interactionReadyAt = ProcessInfo.processInfo.systemUptime + 0.05
    func finish(_ token: Int) { finishReveal(token: token) }
''' + method + r'''
}
@main struct PanelInteractionProbe {
    @MainActor static func main() {
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        let model = AppModel.shared
        let driver = Driver()
        driver.finish(1)
        require(!model.interactionReady, "Hover scale starts before the icon entrance has finished")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        require(model.interactionReady, "Hover was not restored after the entrance settled")
        model.interactionReady = false
        driver.interactionReadyAt = ProcessInfo.processInfo.systemUptime + 0.04
        driver.finish(1)
        driver.visibilityToken = 2
        model.isOpen = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        require(!model.interactionReady, "An old completion restored hover on a closed panel")
        if !failures.isEmpty {
            failures.forEach { fputs("FAIL: \($0)\n", stderr) }
            exit(1)
        }
        print("PASS: hover waits for the icon wave; stale completion cannot restore interaction")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-interaction-') as directory:
    swift = Path(directory) / 'Probe.swift'
    swift.write_text(harness)
    binary = Path(directory) / 'probe'
    subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', '/tmp/pinchpad-build-module-cache', str(swift), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
