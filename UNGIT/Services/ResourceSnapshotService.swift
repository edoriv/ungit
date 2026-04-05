import Foundation

struct ResourceSnapshotService {
    private let processRunner = ProcessRunner()

    func captureObservedSnapshot() -> ResourceSnapshot? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let nowISO = DateFormatters.iso8601.string(from: Date())

        do {
            let result = try processRunner.runCapturing(
                "/bin/ps",
                ["-p", "\(pid)", "-o", "%cpu=", "-o", "rss=" ]
            )
            let parts = result.output
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)

            let cpu = parts.first.flatMap(Double.init)
            let rssKB = parts.dropFirst().first.flatMap(Double.init)
            let memoryMB = rssKB.map { $0 / 1024.0 }

            return ResourceSnapshot(
                capturedAt: nowISO,
                cpuPercentObserved: cpu,
                memoryMBObserved: memoryMB,
                energyImpactObserved: nil,
                diskKbpsObserved: nil,
                networkKbpsObserved: nil,
                captureContext: "Observed estimate from current UNGIT process at snapshot save time; not a benchmark."
            )
        } catch {
            return nil
        }
    }
}
