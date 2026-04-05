import Foundation

struct RestoreSafetyService {
    private let fileSystem = FileSystemService()
    private let archiveService = ArchiveService()
    private let validator = ExtractedProjectValidator()
    private let jsonStore = JSONFileStore()

    func restoreSnapshot(
        projectURL: URL,
        entry: TimelineEntry,
        project: ProjectMetadata,
        snapshotService: SnapshotService
    ) throws {
        let layout = ProjectLayout(projectURL: projectURL)
        let archiveURL = layout.ungitURL.appendingPathComponent(entry.archiveRelativePath, isDirectory: false)

        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            appendRestoreDrillEntry(
                layout: layout,
                snapshotID: entry.id,
                snapshotTitle: entry.title,
                outcome: "Failed",
                notes: "Archive missing at \(entry.archiveRelativePath)."
            )
            throw AppError.cannotFindArchive
        }

        let safetyNotes = SnapshotNotes(
            title: "Automatic Safety Snapshot Before Restore",
            summary: "Saved automatically before restoring \(entry.title).",
            whatChanged: "Automatic safety save before restore.",
            why: "Restore protection",
            importantFilesTouched: [],
            gotchas: "",
            tags: ["automatic", "safety", "restore"],
            status: .rollbackPoint,
            snapshotType: .trustedRollback,
            pathName: project.currentPathName,
            proofCommand: "",
            linkedMemoryIDs: []
        )

        _ = try snapshotService.saveSnapshot(
            projectURL: projectURL,
            project: project,
            notes: safetyNotes,
            isAutomaticSafetySnapshot: true
        )

        let operationID = UUID().uuidString
        let extractionTemp = layout.tempURL.appendingPathComponent("restore-extract-\(operationID)", isDirectory: true)
        let recoveryRoot = layout.restoresURL.appendingPathComponent("recovery-\(operationID)", isDirectory: true)
        let originalBackup = recoveryRoot.appendingPathComponent("original", isDirectory: true)

        try fileSystem.ensureDirectory(extractionTemp)
        try fileSystem.ensureDirectory(recoveryRoot)
        try fileSystem.ensureDirectory(originalBackup)

        defer { try? FileManager.default.removeItem(at: extractionTemp) }

        let extractedProjectRoot = try archiveService.extractSnapshotArchive(archiveURL: archiveURL, destinationURL: extractionTemp)
        try validator.validateProjectTree(at: extractedProjectRoot)

        // Backup must complete before any live project mutation.
        try fileSystem.copyProjectContents(
            from: projectURL,
            to: originalBackup,
            excludingRootNames: [".ungit"]
        )

        var didMutateLiveProject = false
        do {
            try fileSystem.removeContents(of: projectURL, excludingRootNames: [".ungit"])
            didMutateLiveProject = true

            try fileSystem.copyProjectContents(
                from: extractedProjectRoot,
                to: projectURL,
                excludingRootNames: [".ungit"]
            )

            let doneMarker = recoveryRoot.appendingPathComponent("restore-complete.txt", isDirectory: false)
            try "restore completed".data(using: .utf8)?.write(to: doneMarker, options: .atomic)
            appendRestoreDrillEntry(
                layout: layout,
                snapshotID: entry.id,
                snapshotTitle: entry.title,
                outcome: "Success",
                notes: "Restore completed with safety snapshot + staged replacement."
            )
        } catch {
            guard didMutateLiveProject else {
                appendRestoreDrillEntry(
                    layout: layout,
                    snapshotID: entry.id,
                    snapshotTitle: entry.title,
                    outcome: "Failed",
                    notes: "Restore failed before live project mutation."
                )
                throw AppError.restoreFailed("Restore failed before project files were replaced.")
            }

            do {
                try fileSystem.removeContents(of: projectURL, excludingRootNames: [".ungit"])
                try fileSystem.copyProjectContents(from: originalBackup, to: projectURL, excludingRootNames: [])
            } catch {
                appendRestoreDrillEntry(
                    layout: layout,
                    snapshotID: entry.id,
                    snapshotTitle: entry.title,
                    outcome: "Failed",
                    notes: "Restore failed and automatic rollback failed. Recovery copy exists at \(originalBackup.path)."
                )
                throw AppError.restoreFailed("Restore failed and automatic rollback also failed. Recovery copy exists at \(originalBackup.path)")
            }

            appendRestoreDrillEntry(
                layout: layout,
                snapshotID: entry.id,
                snapshotTitle: entry.title,
                outcome: "Recovered",
                notes: "Restore failed but project was reverted to pre-restore files."
            )
            throw AppError.restoreFailed("Restore failed. Project reverted to pre-restore files.")
        }
    }

    func requestRestoreApproval(projectURL: URL, entry: TimelineEntry, requestedBy: String) throws -> RestoreApprovalGate {
        let layout = ProjectLayout(projectURL: projectURL)
        let now = Date()
        let gate = RestoreApprovalGate(
            snapshotID: entry.id,
            snapshotTitle: entry.title,
            state: .requested,
            requestedAt: now,
            requestedAtISO8601: DateFormatters.iso8601.string(from: now),
            approvedAt: nil,
            approvedAtISO8601: nil,
            expiresAt: nil,
            expiresAtISO8601: nil,
            token: nil,
            lastUpdatedBy: requestedBy
        )
        try jsonStore.write(gate, to: layout.restoreApprovalURL)
        appendRestoreApprovalLog(layout: layout, event: "REQUESTED", details: "snapshot=\(entry.id) by=\(requestedBy)")
        return gate
    }

    func approveRestore(projectURL: URL, snapshotID: String, approvedBy: String, validForSeconds: TimeInterval = 180) throws -> RestoreApprovalGate {
        let layout = ProjectLayout(projectURL: projectURL)
        guard var gate = try loadRestoreApproval(projectURL: projectURL) else {
            throw AppError.commandFailed("Restore approval failed: no pending restore request.")
        }
        guard gate.snapshotID == snapshotID else {
            throw AppError.commandFailed("Restore approval failed: pending request is for \(gate.snapshotID), not \(snapshotID).")
        }

        let now = Date()
        let expiresAt = now.addingTimeInterval(validForSeconds)
        gate.state = .approved
        gate.approvedAt = now
        gate.approvedAtISO8601 = DateFormatters.iso8601.string(from: now)
        gate.expiresAt = expiresAt
        gate.expiresAtISO8601 = DateFormatters.iso8601.string(from: expiresAt)
        gate.token = UUID().uuidString.uppercased()
        gate.lastUpdatedBy = approvedBy

        try jsonStore.write(gate, to: layout.restoreApprovalURL)
        appendRestoreApprovalLog(layout: layout, event: "APPROVED", details: "snapshot=\(snapshotID) by=\(approvedBy) expires=\(gate.expiresAtISO8601 ?? "-")")
        return gate
    }

    func consumeRestoreApproval(projectURL: URL, snapshotID: String, token: String, consumedBy: String) throws {
        let layout = ProjectLayout(projectURL: projectURL)
        guard var gate = try loadRestoreApproval(projectURL: projectURL) else {
            throw AppError.commandFailed("Restore blocked: no restore approval exists.")
        }
        guard gate.snapshotID == snapshotID else {
            throw AppError.commandFailed("Restore blocked: approval is for \(gate.snapshotID), not \(snapshotID).")
        }
        guard gate.state == .approved else {
            throw AppError.commandFailed("Restore blocked: approval state is \(gate.state.rawValue).")
        }
        guard let gateToken = gate.token, !gateToken.isEmpty else {
            throw AppError.commandFailed("Restore blocked: approval token is missing.")
        }
        guard gateToken == token.uppercased() else {
            throw AppError.commandFailed("Restore blocked: approval token mismatch.")
        }
        if let expiresAt = gate.expiresAt, Date() > expiresAt {
            gate.state = .canceled
            gate.token = nil
            gate.lastUpdatedBy = "system-expired"
            try jsonStore.write(gate, to: layout.restoreApprovalURL)
            appendRestoreApprovalLog(layout: layout, event: "EXPIRED", details: "snapshot=\(snapshotID)")
            throw AppError.commandFailed("Restore blocked: approval token expired.")
        }

        gate.state = .consumed
        gate.token = nil
        gate.lastUpdatedBy = consumedBy
        try jsonStore.write(gate, to: layout.restoreApprovalURL)
        appendRestoreApprovalLog(layout: layout, event: "CONSUMED", details: "snapshot=\(snapshotID) by=\(consumedBy)")
    }

    func cancelRestoreApproval(projectURL: URL, canceledBy: String) throws {
        let layout = ProjectLayout(projectURL: projectURL)
        guard var gate = try loadRestoreApproval(projectURL: projectURL) else { return }
        gate.state = .canceled
        gate.token = nil
        gate.lastUpdatedBy = canceledBy
        try jsonStore.write(gate, to: layout.restoreApprovalURL)
        appendRestoreApprovalLog(layout: layout, event: "CANCELED", details: "snapshot=\(gate.snapshotID) by=\(canceledBy)")
    }

    func loadRestoreApproval(projectURL: URL) throws -> RestoreApprovalGate? {
        let layout = ProjectLayout(projectURL: projectURL)
        guard jsonStore.exists(layout.restoreApprovalURL) else { return nil }
        return try jsonStore.read(RestoreApprovalGate.self, from: layout.restoreApprovalURL)
    }

    private func appendRestoreDrillEntry(
        layout: ProjectLayout,
        snapshotID: String,
        snapshotTitle: String,
        outcome: String,
        notes: String
    ) {
        let timestamp = DateFormatters.iso8601.string(from: Date())
        let lines = [
            "",
            "## Restore Drill \(timestamp)",
            "- Snapshot ID: \(snapshotID)",
            "- Snapshot Title: \(snapshotTitle)",
            "- Outcome: \(outcome)",
            "- Notes: \(notes)"
        ]
        let payload = lines.joined(separator: "\n") + "\n"

        do {
            if FileManager.default.fileExists(atPath: layout.restoreDrillsURL.path) {
                let existing = (try? String(contentsOf: layout.restoreDrillsURL, encoding: .utf8)) ?? ""
                let updated = existing + payload
                try updated.data(using: .utf8)?.write(to: layout.restoreDrillsURL, options: .atomic)
            } else {
                let header = "# RESTORE_DRILLS\n\nRestore drill history with outcomes, notes, and follow-up issues.\n"
                let content = header + payload
                try content.data(using: .utf8)?.write(to: layout.restoreDrillsURL, options: .atomic)
            }
        } catch {
            // Restore logging should never block restore execution.
        }
    }

    private func appendRestoreApprovalLog(layout: ProjectLayout, event: String, details: String) {
        let timestamp = DateFormatters.iso8601.string(from: Date())
        let line = "\(timestamp) [\(event)] \(details)\n"
        do {
            if FileManager.default.fileExists(atPath: layout.restoreApprovalLogURL.path) {
                let existing = (try? String(contentsOf: layout.restoreApprovalLogURL, encoding: .utf8)) ?? ""
                let updated = existing + line
                try updated.data(using: .utf8)?.write(to: layout.restoreApprovalLogURL, options: .atomic)
            } else {
                try line.data(using: .utf8)?.write(to: layout.restoreApprovalLogURL, options: .atomic)
            }
        } catch {
            // Approval logging should never block restore execution.
        }
    }
}
