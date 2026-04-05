import Foundation

struct ProjectPath: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Date
    var createdAtISO8601: String
    var sourceSnapshotID: String?
}

struct ProjectMetadata: Codable {
    var id: String
    var name: String
    var rootPath: String
    var createdAt: Date
    var createdAtISO8601: String
    var currentPathName: String
    var paths: [ProjectPath]
}

struct ProjectLog: Codable {
    var entries: [TimelineEntry]
}

struct RecentProjectItem: Identifiable, Hashable {
    let path: String

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

enum CurrentStateStatus {
    case matchesLatestSnapshot
    case notSavedSinceLastSnapshot
    case noSnapshotsYet
    case unknown
}

enum MemoryFileType: String, CaseIterable, Identifiable {
    case summary
    case bugs
    case ideas
    case todo
    case park

    var id: String { rawValue }

    var fileName: String {
        switch self {
        case .summary: return "PROJECT_SUMMARY.md"
        case .bugs: return "BUGS.md"
        case .ideas: return "IDEAS.md"
        case .todo: return "TODO.md"
        case .park: return "PARK.md"
        }
    }

    var title: String {
        switch self {
        case .summary: return "Summary"
        case .bugs: return "Bugs"
        case .ideas: return "Ideas"
        case .todo: return "TODO"
        case .park: return "Park"
        }
    }

    var idPrefix: String {
        switch self {
        case .summary: return "SUMMARY"
        case .bugs: return "BUG"
        case .ideas: return "IDEA"
        case .todo: return "TODO"
        case .park: return "PARK"
        }
    }
}

enum RestoreApprovalState: String, Codable {
    case requested = "Requested"
    case approved = "Approved"
    case consumed = "Consumed"
    case canceled = "Canceled"
}

struct RestoreApprovalGate: Codable {
    var snapshotID: String
    var snapshotTitle: String
    var state: RestoreApprovalState
    var requestedAt: Date
    var requestedAtISO8601: String
    var approvedAt: Date?
    var approvedAtISO8601: String?
    var expiresAt: Date?
    var expiresAtISO8601: String?
    var token: String?
    var lastUpdatedBy: String
}
