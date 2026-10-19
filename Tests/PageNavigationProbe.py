"""Replay the production monitor and SwiftUI handlers without windows or system input.

The app singleton loads the user's library and installs device monitors, so this
probe compiles only the relevant production methods with an in-memory event source.
Run: python3 Tests/PageNavigationProbe.py
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
app = (root / "Sources/AppMain.swift").read_text()
model = (root / "Sources/AppModel.swift").read_text()
view = (root / "Sources/PinchpadView.swift").read_text()
fallbacks = []
for key in ("leftArrow", "rightArrow"):
    handler = block(view, ".onKeyPress(." + key)
    body = handler[handler.index("{") + 1:handler.rindex("}")]
    if "_ in" in body:
        body = body.split("_ in", 1)[1]
    fallbacks.append(body)

source = r"""import Swift
struct NSEvent {
    struct Mask: OptionSet {
        let rawValue: Int
        static let keyDown = Mask(rawValue: 1)
        static let scrollWheel = Mask(rawValue: 2)
        static let leftMouseDown = Mask(rawValue: 4)
        static let leftMouseUp = Mask(rawValue: 8)
        static let flagsChanged = Mask(rawValue: 16)
    }
    let direction: Int
    static var callback: ((NSEvent) -> NSEvent?)?
    static func addLocalMonitorForEvents(matching: Mask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        callback = handler
        return 0
    }
}
enum Browsing { case paged, scroll }
struct Settings { var browsing = Browsing.paged }
final class Model {
    var settings = Settings()
    var query = ""
    var openFolderID: Int?
    var draggingID: String?
    var pages = [0, 1, 2]
    var currentPage = 0
    var pageDirection = 1
    var changes = 0
    func persist() { changes += 1 }
""" + block(model, "var clampedPage: Int") + "\n" + block(model, "func turnPage(_ delta: Int)") + r"""
}
final class Probe {
    var inputMonitor: Any?
    let model = Model()
    var fallbackCalls = 0
    var replacement: NSEvent?
""" + block(app, "private func installInputMonitor()") + r"""
    func install() { installInputMonitor() }
    func handleInput(_ event: NSEvent) -> NSEvent? {
        if let replacement { return replacement }
        guard event.direction != 0 else { return event }
        model.turnPage(event.direction)
        return nil
    }
    enum Result { case ignored, handled }
    func fallback(_ event: NSEvent) -> Result {
        fallbackCalls += 1
        if event.direction < 0 {
""" + fallbacks[0] + r"""
        } else {
""" + fallbacks[1] + r"""
        }
    }
    func dispatch(_ event: NSEvent) {
        if let delivered = NSEvent.callback?(event) { _ = fallback(delivered) }
    }
}
var failures: [String] = []
func require(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

// Three pages reproduce the original jump directly from one end to the other.
// More pages, every starting position, and the boundaries exercise the same route.
for count in 2...6 {
    for start in 0..<count {
        for direction in [-1, 1] {
            let probe = Probe()
            probe.model.pages = Array(0..<count)
            probe.model.currentPage = start
            probe.install()
            probe.dispatch(NSEvent(direction: direction))
            let expected = min(max(0, start + direction), count - 1)
            require(probe.model.currentPage == expected,
                    "\(count) pages, page \(start + 1), direction \(direction): reached page \(probe.model.currentPage + 1), expected \(expected + 1)")
            require(probe.fallbackCalls == 0, "Handled arrow reached the SwiftUI handler again")
            require(probe.model.changes == (start == expected ? 0 : 1), "Arrow changed the page more than once")
        }
    }
}

for direction in [-1, 1] {
    let probe = Probe()
    probe.model.pages = Array(0..<8)
    let start = direction < 0 ? 7 : 0
    probe.model.currentPage = start
    probe.install()
    for press in 1...3 {
        probe.dispatch(NSEvent(direction: direction))
        require(probe.model.currentPage == start + press * direction,
                "Consecutive arrow events must advance one page per event")
    }
}

do {
    let probe = Probe()
    probe.install()
    let ignored = NSEvent(direction: 0)
    require(NSEvent.callback?(ignored)?.direction == 0, "Unhandled input must pass through")
    probe.replacement = NSEvent(direction: 42)
    require(NSEvent.callback?(ignored)?.direction == 42, "Replacement input must pass through")
}

do {
    var probe: Probe? = Probe()
    let ownerReleased = { [weak probe] in probe == nil }
    probe?.install()
    let monitor = NSEvent.callback!
    probe = nil
    require(ownerReleased(), "The input monitor must not retain its owner")
    require(monitor(NSEvent(direction: 1))?.direction == 1,
            "Input must pass through after the monitor owner is released")
}

if failures.isEmpty {
    print("PASS: left/right arrows advance once, including boundaries and consecutive events")
    print("PASS: handled input is consumed; unhandled/replacement input passes through")
    print("PASS: released monitor owners leave input untouched")
} else {
    for failure in failures { print("FAIL: \(failure)") }
}
"""

with tempfile.TemporaryDirectory(prefix="pinchpad-page-navigation-") as directory:
    directory = Path(directory)
    swift = directory / "main.swift"
    swift.write_text(source)
    binary = directory / "probe"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-module-cache-path",
        str(directory / "module-cache"), str(swift), "-o", str(binary),
    ], check=True)
    result = subprocess.run([str(binary)], text=True, capture_output=True)
    print(result.stdout, end="")
    print(result.stderr, end="")
    raise SystemExit(result.returncode or (1 if "FAIL:" in result.stdout else 0))
