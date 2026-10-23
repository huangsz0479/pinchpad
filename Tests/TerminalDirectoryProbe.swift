import AppKit
import Foundation

// Verifies the terminal-shortcut launch path: handing a folder to a terminal
// app through Launch Services (the same NSWorkspace call `openTerminal` uses)
// must produce a new interactive shell whose cwd is that folder.
// Polls the process table for a newly spawned login shell and checks its cwd.
// Usage: swift Tests/TerminalDirectoryProbe.swift <directory> [terminal.app-path]
guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: TerminalDirectoryProbe <directory> [terminal.app-path]\n", stderr)
    exit(2)
}
let directory = (CommandLine.arguments[1] as NSString).expandingTildeInPath
let appPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "/System/Applications/Utilities/Terminal.app"

func shells() -> [pid_t: String] {
    // lsof prints `p<pid>` / `n<path>` pairs for each shell's cwd descriptor.
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    task.arguments = ["-a", "-d", "cwd", "-Fn", "-c", "zsh", "-c", "bash"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    guard let _ = try? task.run() else { return [:] }
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    task.waitUntilExit()
    var result: [pid_t: String] = [:]
    var current: pid_t?
    for line in output.split(separator: "\n") {
        if line.hasPrefix("p"), let pid = pid_t(line.dropFirst()) {
            current = pid
        } else if line.hasPrefix("n"), let pid = current {
            result[pid] = String(line.dropFirst())
        }
    }
    return result
}

var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
    fputs("FAIL: directory does not exist: \(directory)\n", stderr)
    exit(1)
}
guard FileManager.default.fileExists(atPath: appPath) else {
    fputs("FAIL: terminal app does not exist: \(appPath)\n", stderr)
    exit(1)
}

let before = shells()
let expected = URL(fileURLWithPath: directory).resolvingSymlinksInPath().path
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
var opened = false
let semaphore = DispatchSemaphore(value: 0)
NSWorkspace.shared.open(
    [URL(fileURLWithPath: directory, isDirectory: true)],
    withApplicationAt: URL(fileURLWithPath: appPath), configuration: configuration
) { _, error in
    if let error { fputs("FAIL: open failed: \(error.localizedDescription)\n", stderr) }
    else { opened = true }
    semaphore.signal()
}
_ = semaphore.wait(timeout: .now() + 10)
guard opened else { exit(1) }

let deadline = Date().addingTimeInterval(15)
while Date() < deadline {
    for (pid, cwd) in shells() where before[pid] == nil {
        let resolved = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path
        if resolved == expected {
            print("PASS: new shell pid \(pid) opened with cwd \(resolved)")
            exit(0)
        }
    }
    usleep(250_000)
}
fputs("FAIL: no new shell appeared with cwd \(expected)\n", stderr)
exit(1)
