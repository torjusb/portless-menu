import CoreServices
import Foundation
import Observation
import PortlessCore

@MainActor
@Observable
final class StateStore {
    private(set) var snapshot: Snapshot = .proxyDown
    @ObservationIgnored private var watchedDir: URL?
    @ObservationIgnored private var stream: FSEventStreamRef?
    @ObservationIgnored private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let dir = StateReader.resolveStateDir(
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser,
            probe: systemPidProbe
        )
        if dir != watchedDir { watch(dir) }
        let next = StateReader.snapshot(stateDir: dir, probe: systemPidProbe)
        if next != snapshot { snapshot = next }
    }

    // FSEvents with file-level events, because portless rewrites routes.json in place,
    // which a directory vnode source would not report.
    private func watch(_ dir: URL) {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        watchedDir = dir
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        stream = FSEventStreamCreate(
            nil,
            { _, info, _, paths, _, _ in
                guard let info else { return }
                let store = Unmanaged<StateStore>.fromOpaque(info).takeUnretainedValue()
                let names = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
                MainActor.assumeIsolated { store.handle(changedPaths: names) }
            },
            &context,
            [dir.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(flags)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    private func handle(changedPaths: [String]) {
        let relevant = changedPaths.contains { StateReader.watchedFiles.contains(URL(fileURLWithPath: $0).lastPathComponent) }
        if relevant { refresh() }
    }
}
