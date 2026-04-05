import Foundation

struct ExtractedProjectValidator {
    func validateProjectTree(at projectRoot: URL) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: projectRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppError.archiveValidationFailed("Extracted project root is missing.")
        }

        let rootPath = projectRoot.standardizedFileURL.path
        guard let enumerator = fm.enumerator(at: projectRoot, includingPropertiesForKeys: [.isSymbolicLinkKey, .isAliasFileKey, .isRegularFileKey, .isDirectoryKey], options: [], errorHandler: { _, _ in true }) else {
            throw AppError.archiveValidationFailed("Unable to read extracted files.")
        }

        for case let itemURL as URL in enumerator {
            let standardized = itemURL.standardizedFileURL.path
            guard standardized == rootPath || standardized.hasPrefix(rootPath + "/") else {
                throw AppError.archiveValidationFailed("Found file outside extracted root: \(itemURL.lastPathComponent)")
            }

            let relativePath: String
            if standardized == rootPath {
                relativePath = ""
            } else {
                relativePath = String(standardized.dropFirst(rootPath.count + 1))
            }

            if !relativePath.isEmpty && relativePath.split(separator: "/").contains(".ungit") {
                throw AppError.archiveValidationFailed("Extracted snapshot contains unexpected .ungit content.")
            }

            let values = try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
            if values.isSymbolicLink == true {
                throw AppError.archiveValidationFailed("Symlinks are not allowed in restore snapshots: \(itemURL.lastPathComponent)")
            }
            if values.isAliasFile == true {
                throw AppError.archiveValidationFailed("Aliases are not allowed in restore snapshots: \(itemURL.lastPathComponent)")
            }

            let attrs = try fm.attributesOfItem(atPath: itemURL.path)
            let type = attrs[.type] as? FileAttributeType
            if type != .typeRegular && type != .typeDirectory {
                throw AppError.archiveValidationFailed("Unsupported file type in snapshot: \(itemURL.lastPathComponent)")
            }
        }
    }
}
