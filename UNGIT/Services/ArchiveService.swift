import Foundation

struct ArchiveService {
    private let fileSystem = FileSystemService()
    private let processRunner = ProcessRunner()
    private let excludedRootNames: Set<String> = [
        ".ungit", ".build", "build", "DerivedData", "deriveddata", "dist", "out", "output", "release", "debug"
    ]

    func createSnapshotArchive(projectURL: URL, archiveURL: URL, tempRootURL: URL) throws {
        let stagingRoot = tempRootURL.appendingPathComponent("archive-staging-\(UUID().uuidString)", isDirectory: true)
        let stagingProjectContents = stagingRoot.appendingPathComponent("project", isDirectory: true)

        try fileSystem.ensureDirectory(stagingRoot)
        try fileSystem.ensureDirectory(stagingProjectContents)
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        try fileSystem.copyProjectContents(
            from: projectURL,
            to: stagingProjectContents,
            excludingRootNames: excludedRootNames
        )

        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }

        try processRunner.run(
            "/usr/bin/ditto",
            ["-c", "-k", "--sequesterRsrc", "--keepParent", stagingProjectContents.path, archiveURL.path]
        )
    }

    func extractSnapshotArchive(archiveURL: URL, destinationURL: URL) throws -> URL {
        let fileSystem = FileSystemService()
        try fileSystem.ensureDirectory(destinationURL)
        try fileSystem.clearDirectory(destinationURL)

        try processRunner.run(
            "/usr/bin/ditto",
            ["-x", "-k", archiveURL.path, destinationURL.path]
        )

        let projectFolder = destinationURL.appendingPathComponent("project", isDirectory: true)
        guard FileManager.default.fileExists(atPath: projectFolder.path) else {
            throw AppError.restoreFailed("Archive is invalid: expected top-level 'project' folder.")
        }

        return projectFolder
    }
}
