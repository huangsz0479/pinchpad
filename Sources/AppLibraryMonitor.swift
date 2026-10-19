import CoreServices
import Darwin
import Foundation

/// 只在扫描目录发生变化时刷新；连续复制应用文件时，等变动短暂停稳再扫描。
@MainActor
final class AppLibraryMonitor {
    private final class Callback {
        weak var monitor: AppLibraryMonitor?
        init(_ monitor: AppLibraryMonitor) { self.monitor = monitor }
    }

    private let onChange: @MainActor () -> Void
    private var paths: [String] = []
    private var watchedPaths: [String] = []
    private var stream: FSEventStreamRef?
    private var pendingChange: DispatchWorkItem?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    deinit {
        pendingChange?.cancel()
        if let stream { Self.close(stream) }
    }

    func apply(paths: [String]) {
        pendingChange?.cancel()
        pendingChange = nil
        self.paths = Array(Set(paths.map(Self.canonicalPath))).sorted()
        updateStream()
    }

    private func updateStream() {
        // ~/Applications、自定义目录可能还不存在。暂时监听最近的现存父目录，
        // 过滤无关事件；目录创建/删除后自动重新挂到正确位置。
        let manager = FileManager.default
        let candidates = Set(paths.map { path -> String in
            var url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            while !(manager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue),
                  url.path != "/" {
                url.deleteLastPathComponent()
            }
            return url.path
        })
        let roots = candidates.filter { candidate in
            !candidates.contains { $0 != candidate && Self.contains($0, candidate) }
        }.sorted()
        guard roots != watchedPaths || (stream == nil && !roots.isEmpty) else { return }
        if let stream { Self.close(stream) }
        stream = nil
        watchedPaths = roots
        guard !roots.isEmpty else { return }

        let callback = Callback(self)
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(callback).toOpaque()
        context.retain = { pointer in
            guard let pointer else { return nil }
            _ = Unmanaged<Callback>.fromOpaque(pointer).retain()
            return pointer
        }
        context.release = { pointer in
            if let pointer { Unmanaged<Callback>.fromOpaque(pointer).release() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
            | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, rawPaths, eventFlags, _ in
                guard let info else { return }
                let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
                let recoveryFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs
                    | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                    | kFSEventStreamEventFlagRootChanged)
                let needsRecovery = (0..<count).contains { eventFlags[$0] & recoveryFlags != 0 }
                MainActor.assumeIsolated {
                    callback.monitor?.changed(paths, needsRecovery: needsRecovery)
                }
            },
            &context, roots as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, .main)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
        stream = created
    }

    private func changed(_ eventPaths: [String], needsRecovery: Bool) {
        let relevant = eventPaths.contains { event in
            paths.contains { Self.contains($0, event) || Self.contains(event, $0) }
        }
        guard needsRecovery || relevant else { return }
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingChange = nil
            self.updateStream()
            self.onChange()
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private static func contains(_ root: String, _ path: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    private static func canonicalPath(_ path: String) -> String {
        var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var suffix: [String] = []
        // FSEvents 使用 /private/var 等真实路径。Foundation 对已删除路径的
        // resolvingSymlinksInPath 结果不同，因此只解析仍存在的祖先，再拼回后缀。
        while true {
            if let resolved = realpath(url.path, nil) {
                defer { free(resolved) }
                let root = String(cString: resolved)
                guard !suffix.isEmpty else { return root }
                return root + (root == "/" ? "" : "/") + suffix.reversed().joined(separator: "/")
            }
            guard url.path != "/" else { return path }
            suffix.append(url.lastPathComponent)
            url.deleteLastPathComponent()
        }
    }

    nonisolated private static func close(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
