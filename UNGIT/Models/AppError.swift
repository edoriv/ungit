import Foundation

enum AppError: LocalizedError {
    case invalidProjectPath
    case projectNotInitialized
    case snapshotNotFound
    case cannotFindArchive
    case manifestIntegrity(String)
    case archiveValidationFailed(String)
    case commandFailed(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectPath:
            return "The selected folder is not valid for this operation."
        case .projectNotInitialized:
            return "UNGIT is not initialized in this project."
        case .snapshotNotFound:
            return "The selected snapshot could not be found."
        case .cannotFindArchive:
            return "The snapshot archive file is missing."
        case .manifestIntegrity(let details):
            return "Snapshot manifest issue: \(details)"
        case .archiveValidationFailed(let details):
            return "Snapshot archive failed safety validation: \(details)"
        case .commandFailed(let details):
            return "A file operation failed: \(details)"
        case .restoreFailed(let details):
            return "Restore did not complete safely: \(details)"
        }
    }
}
