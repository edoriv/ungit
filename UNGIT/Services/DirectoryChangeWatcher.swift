import Foundation
import CoreServices

final class DirectoryChangeWatcher {
    private var stream: FSEventStreamRef?
    private var onChange: (@Sendable ([String]) -> Void)?

    func startWatching(directoryURL: URL, onChange: @escaping @Sendable ([String]) -> Void) throws {
        stop()
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [directoryURL.path] as CFArray
        let latency: CFTimeInterval = 0.2
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, numEvents, eventPaths, _, _) in
                guard
                    let info,
                    numEvents > 0
                else {
                    return
                }

                let watcher = Unmanaged<DirectoryChangeWatcher>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                let changed = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []

                watcher.onChange?(changed)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            throw AppError.commandFailed("Unable to watch directory: \(directoryURL.path)")
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw AppError.commandFailed("Unable to start directory watcher: \(directoryURL.path)")
        }
        self.stream = stream
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        self.stream = nil
        self.onChange = nil
    }

    deinit {
        stop()
    }
}
