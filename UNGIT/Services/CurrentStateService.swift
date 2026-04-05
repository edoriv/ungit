import Foundation

struct CurrentStateService {
    func evaluate(projectURL: URL, timeline: [TimelineEntry]) throws -> CurrentStateStatus {
        guard let latestSnapshot = timeline.sorted(by: { $0.createdAtISO8601 > $1.createdAtISO8601 }).first else {
            return .noSnapshotsYet
        }

        let latestChange = try latestProjectFileModificationDate(projectURL: projectURL)
        guard let latestChange else {
            return .matchesLatestSnapshot
        }

        // Small tolerance for filesystem timestamp granularity.
        let toleranceSeconds: TimeInterval = 1
        if latestChange.timeIntervalSince(latestSnapshot.createdAt) > toleranceSeconds {
            return .notSavedSinceLastSnapshot
        }
        return .matchesLatestSnapshot
    }

    private func latestProjectFileModificationDate(projectURL: URL) throws -> Date? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }

        var latestDate: Date?

        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains(".ungit") {
                continue
            }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true, let modified = values.contentModificationDate else {
                continue
            }

            if let current = latestDate {
                if modified > current {
                    latestDate = modified
                }
            } else {
                latestDate = modified
            }
        }

        return latestDate
    }
}
