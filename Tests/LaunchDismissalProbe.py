"""Exercise production launch/close ordering without opening windows or applications.

Launch Services is replaced by a deliberately slow recorder; the actual model
methods are compiled unchanged so the check catches dismissal after a blocking
open call, an animated launch dismissal, and work before the next main-loop turn.
Run: python3 Tests/LaunchDismissalProbe.py
"""

from pathlib import Path
import subprocess
import tempfile


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


root = Path(__file__).resolve().parents[1]
model = (root / "Sources/AppModel.swift").read_text()
callback = next(line.strip() for line in model.splitlines() if "var onOpenChange:" in line)
animated_callback = "(Bool)" in callback
callback_body = "{ animated in" if animated_callback else "{ let animated = true"
close_call = "model.close(animated: true)" if "func close(animated:" in model else "model.close()"

source = r'''import Foundation

struct AppItem {
    var id: String
    var path: String
    var lastOpenedAt: Date?
}

@MainActor
enum Probe {
    static var events: [String] = []
    static var panelVisible = true
    static var openedWhileVisible = false
    static var requestCount = 0
    static var openedURL: URL?
    static var activates = false
    static var completion: ((Any?, Error?) -> Void)?
}

@MainActor
final class NSWorkspace {
    static let shared = NSWorkspace()
    final class OpenConfiguration { var activates = false }
    func open(_ url: URL) {
        record(url, activates: true)
    }
    func openApplication(at url: URL, configuration: OpenConfiguration,
                         completionHandler: @escaping (Any?, Error?) -> Void) {
        Probe.completion = completionHandler
        record(url, activates: configuration.activates)
    }
    private func record(_ url: URL, activates: Bool) {
        Probe.events.append("open")
        Probe.openedWhileVisible = Probe.panelVisible
        Probe.openedURL = url
        Probe.activates = activates
        Probe.requestCount += 1
        // Simulate synchronous Launch Services work even for the async API.
        Thread.sleep(forTimeInterval: 0.06)
    }
}

@MainActor
final class AppModel {
    static let shared = AppModel()
    struct Paging { var offset: CGFloat = 0; var isSwiping = false }
    var paging = Paging()
    var apps = [AppItem(id: "fixture", path: "/fixture/Example.app")]
    var isOpen = true
    var draggingID: String?
    var notice: String?
''' + callback + "\n" + r'''
    func persist() { Probe.events.append("persist") }
    func endDrag() { draggingID = nil }
''' + block(model, "func launch(_ app: AppItem)") + "\n" + block(model, "func close(") + r'''
}

@main
struct LaunchDismissalProbe {
    @MainActor
    static func main() {
        let model = AppModel.shared
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        model.onOpenChange = ''' + callback_body + r'''
            Probe.events.append(animated ? "dismiss-animated" : "dismiss-immediate")
            if !animated { Probe.panelVisible = false }
        }
        let start = ProcessInfo.processInfo.systemUptime
        model.launch(model.apps[0])
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        print(String(format: "launch callback returned in %.3f ms; immediate events: %@",
                     elapsed, Probe.events.description))
        require(!model.isOpen && !Probe.panelVisible, "Launch must dismiss the panel immediately")
        require(Probe.events == ["dismiss-immediate"],
                "Dismissal must be the only work before yielding to the main loop")
        require(elapsed < 20, "Launch callback blocked on the 60 ms Launch Services fixture")
        let deadline = Date(timeIntervalSinceNow: 1)
        while Probe.requestCount == 0 && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        require(Probe.requestCount == 1, "Exactly one launch request must follow dismissal")
        require(!Probe.openedWhileVisible, "Application open was requested while the panel was still visible")
        require(Probe.openedURL?.path == "/fixture/Example.app" && Probe.activates,
                "Launch request lost its target or foreground activation")
        require(model.apps[0].lastOpenedAt != nil && Probe.events.filter { $0 == "persist" }.count == 1,
                "Launch history must still be saved exactly once")
        print("after main-loop turn: \(Probe.events)")
        Probe.events = []
        model.isOpen = true
        ''' + close_call + r'''
        require(Probe.events == ["dismiss-animated"], "Normal close must retain its animation")
        Probe.panelVisible = true  // The ordinary fade has not completed yet.
        Probe.events = []
        model.launch(model.apps[0])
        require(!Probe.panelVisible && Probe.events == ["dismiss-immediate"],
                "Launch during a pending ordinary close must finish dismissal immediately")
        let secondDeadline = Date(timeIntervalSinceNow: 1)
        while Probe.requestCount < 2 && Date() < secondDeadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        Probe.completion?(nil, NSError(domain: "fixture", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "launch failed"]))
        let failureDeadline = Date(timeIntervalSinceNow: 1)
        while model.notice == nil && Date() < failureDeadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        require(model.notice?.contains("launch failed") == true && !model.isOpen,
                "Failed launch must retain its error without reopening the dismissed panel")
        if failures.isEmpty {
            print("PASS: immediate dismissal, deferred launch, one history update, interrupted close and launch failure")
            print("PASS: normal close animation retained")
        } else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="pinchpad-launch-dismissal-") as directory:
    directory = Path(directory)
    swift = directory / "LaunchDismissalProbe.swift"
    swift.write_text(source)
    binary = directory / "probe"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library", "-O", "-module-cache-path", "/tmp/pinchpad-build-module-cache",
        str(swift), "-o", str(binary),
    ], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
