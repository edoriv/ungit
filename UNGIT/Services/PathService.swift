import Foundation

struct PathService {
    func createPathFromSnapshot(
        projectURL: URL,
        project: ProjectMetadata,
        snapshotEntry: TimelineEntry,
        pathName: String,
        destinationFolderURL: URL
    ) throws -> ProjectMetadata {
        _ = projectURL
        _ = project
        _ = snapshotEntry
        _ = pathName
        _ = destinationFolderURL
        throw AppError.commandFailed("Fork path folder cloning is deprecated. Use `UNGIT fork point` to save a semantic divergence marker.")
    }
}
