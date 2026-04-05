import Foundation

struct FileSystemService {
    private let fileManager = FileManager.default

    func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func clearDirectory(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let items = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for item in items {
            try fileManager.removeItem(at: item)
        }
    }

    func copyProjectContents(from sourceURL: URL, to destinationURL: URL, excludingRootNames: Set<String>) throws {
        try ensureDirectory(destinationURL)
        let rootItems = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
        for item in rootItems {
            if excludingRootNames.contains(item.lastPathComponent) {
                continue
            }
            let destination = destinationURL.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: item, to: destination)
        }
    }

    func contentsExcluding(_ rootURL: URL, excludingRootNames: Set<String>) throws -> [URL] {
        let items = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        return items.filter { !excludingRootNames.contains($0.lastPathComponent) }
    }

    func removeContents(of rootURL: URL, excludingRootNames: Set<String>) throws {
        let targets = try contentsExcluding(rootURL, excludingRootNames: excludingRootNames)
        for item in targets {
            try fileManager.removeItem(at: item)
        }
    }

    func appendLine(_ line: String, to fileURL: URL) throws {
        let payload = (line + "\n").data(using: .utf8) ?? Data()
        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: fileURL, options: .atomic)
        }
    }
}

struct ProjectMemoryService {
    private let fm = FileManager.default

    func fileURL(for type: MemoryFileType, projectURL: URL) -> URL {
        switch type {
        case .summary:
            return ProjectLayout(projectURL: projectURL).projectSummaryURL
        case .bugs:
            return ProjectLayout(projectURL: projectURL).bugsURL
        case .ideas:
            return ProjectLayout(projectURL: projectURL).ideasURL
        case .todo:
            return ProjectLayout(projectURL: projectURL).todoURL
        case .park:
            return ProjectLayout(projectURL: projectURL).parkURL
        }
    }

    func read(type: MemoryFileType, projectURL: URL) throws -> String {
        let url = fileURL(for: type, projectURL: projectURL)
        guard fm.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func write(type: MemoryFileType, projectURL: URL, content: String) throws {
        let url = fileURL(for: type, projectURL: projectURL)
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    @discardableResult
    func appendEntry(
        type: MemoryFileType,
        projectURL: URL,
        title: String,
        details: String,
        linkedSnapshotID: String?,
        linkedMemoryIDs: [String]
    ) throws -> String {
        let url = fileURL(for: type, projectURL: projectURL)
        let id = makeEntryID(prefix: type.idPrefix)
        let nowISO = DateFormatters.iso8601.string(from: Date())
        let linkedSnapshot = (linkedSnapshotID?.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? "-"
        let linkedIDs = linkedMemoryIDs.map(\.trimmed).filter { !$0.isEmpty }
        let linkedIDsText = linkedIDs.isEmpty ? "-" : linkedIDs.joined(separator: ", ")
        let titleText = title.trimmedOr("Untitled")
        let bodyText = details.trimmedOr("-")

        let entry = """

        ## \(id)
        - Title: \(titleText)
        - Created: \(nowISO)
        - Linked Snapshot: \(linkedSnapshot)
        - Linked Memory IDs: \(linkedIDsText)
        - Status: Open

        ### Notes
        \(bodyText)
        """

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let separator = existing.hasSuffix("\n") ? "" : "\n"
        let updated = existing + separator + entry + "\n"
        try updated.data(using: .utf8)?.write(to: url, options: .atomic)
        return id
    }

    private func makeEntryID(prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(prefix)-\(formatter.string(from: Date()))"
    }
}
