import Foundation

struct ManifestLoadIssue: Equatable {
    let fileName: String
    let reason: String
}

struct ManifestStore {
    private let jsonStore = JSONFileStore()

    func save(_ manifest: SnapshotManifest, at layout: ProjectLayout) throws -> String {
        let fileName = "\(manifest.id).json"
        let url = layout.manifestsURL.appendingPathComponent(fileName, isDirectory: false)
        try jsonStore.write(manifest, to: url)
        return "manifests/\(fileName)"
    }

    func loadManifest(projectURL: URL, relativePath: String) throws -> SnapshotManifest {
        let url = projectURL.appendingPathComponent(".ungit", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: false)
        return try jsonStore.read(SnapshotManifest.self, from: url)
    }

    func loadAllManifests(at layout: ProjectLayout) throws -> [SnapshotManifest] {
        try loadAllManifestsWithIssues(at: layout).manifests
    }

    func loadAllManifestsWithIssues(at layout: ProjectLayout) throws -> (manifests: [SnapshotManifest], issues: [ManifestLoadIssue]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: layout.manifestsURL.path) else { return ([], []) }

        let files = try fm.contentsOfDirectory(at: layout.manifestsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }

        var manifests: [SnapshotManifest] = []
        var issues: [ManifestLoadIssue] = []
        for file in files {
            do {
                let manifest = try jsonStore.read(SnapshotManifest.self, from: file)
                let expectedName = "\(manifest.id).json"
                guard file.lastPathComponent == expectedName else {
                    issues.append(
                        ManifestLoadIssue(
                            fileName: file.lastPathComponent,
                            reason: "File name does not match manifest id \(manifest.id)."
                        )
                    )
                    continue
                }
                manifests.append(manifest)
            } catch {
                issues.append(
                    ManifestLoadIssue(
                        fileName: file.lastPathComponent,
                        reason: "Could not decode manifest JSON."
                    )
                )
            }
        }

        return (
            manifests.sorted { $0.createdAtISO8601 > $1.createdAtISO8601 },
            issues.sorted { $0.fileName < $1.fileName }
        )
    }
}
