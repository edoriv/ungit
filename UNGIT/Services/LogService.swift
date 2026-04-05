import Foundation

struct LogService {
    private let jsonStore = JSONFileStore()
    private let markdownHeader = "# UNGIT Project Log\n\nThis file is generated from manifests and reflects snapshot history.\n\n"

    func loadTimeline(for layout: ProjectLayout) throws -> [TimelineEntry] {
        if !jsonStore.exists(layout.projectLogJSONURL) {
            return []
        }
        let log = try jsonStore.read(ProjectLog.self, from: layout.projectLogJSONURL)
        return log.entries.sorted { $0.createdAtISO8601 > $1.createdAtISO8601 }
    }

    func replaceProjection(entries: [TimelineEntry], for layout: ProjectLayout) throws {
        try jsonStore.write(ProjectLog(entries: entries), to: layout.projectLogJSONURL)
        let markdownLines = entries.map {
            let proof = $0.proofVerificationStatus.rawValue
            let archive = $0.archiveAvailable ? "Available" : "Pruned"
            return "- [\($0.createdAtISO8601)] \($0.title) | \($0.snapshotType.rawValue) | \($0.status.rawValue) | proof: \(proof) | archive: \(archive) | path: \($0.pathName)"
        }
        let markdown = markdownHeader + markdownLines.joined(separator: "\n") + "\n"
        try markdown.data(using: .utf8)?.write(to: layout.projectLogMarkdownURL, options: .atomic)
    }
}
