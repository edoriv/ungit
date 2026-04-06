import Foundation

struct SnapshotArchivePruneResult {
    var dryRun: Bool
    var keepRecentNonMajor: Int
    var totalArchivesBefore: Int
    var totalBytesBefore: Int64
    var prunedArchives: Int
    var failedArchives: Int
    var reclaimedBytes: Int64
    var totalArchivesAfter: Int
    var totalBytesAfter: Int64
    var prunedSnapshotIDs: [String]
    var failedSnapshotIDs: [String]
}

struct SnapshotSingleArchivePruneResult {
    var dryRun: Bool
    var snapshotID: String
    var title: String
    var snapshotType: SnapshotType
    var archiveWasPresent: Bool
    var pruned: Bool
    var reclaimedBytes: Int64
    var totalBytesBefore: Int64
    var totalBytesAfter: Int64
    var note: String
}

enum TimelineExportMode: String, CaseIterable, Identifiable {
    case patchList = "Patch List"
    case bulletList = "Bullet List"
    case detailedSummary = "Detailed Summary"
    case continuityReview = "Continuity Review"
    case projectHandoff = "Project Handoff"

    var id: String { rawValue }

    var fileToken: String {
        switch self {
        case .patchList: return "patch-list"
        case .bulletList: return "bullet-list"
        case .detailedSummary: return "detailed-summary"
        case .continuityReview: return "continuity-review"
        case .projectHandoff: return "project-handoff"
        }
    }
}

struct TimelineExportResult {
    var mode: TimelineExportMode
    var entriesExported: Int
    var fileURL: URL
}

struct SnapshotService {
    private let manifestStore = ManifestStore()
    private let logService = LogService()
    private let archiveService = ArchiveService()
    private let processRunner = ProcessRunner()
    private let resourceSnapshotService = ResourceSnapshotService()
    private let currentStateService = CurrentStateService()
    private let maxProofDetailsLength = 2200
    private let excludedDirectoryNames: Set<String> = [
        ".ungit", "build", ".build", "deriveddata", "dist", "out", "output", "release", "debug"
    ]
    private let codeFileExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx",
        "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "java", "kt", "kts", "cs",
        "php", "lua", "sh", "bash", "zsh", "fish", "sql", "css", "scss", "sass",
        "html", "xml", "json", "yaml", "yml", "toml"
    ]
    private let maxCodeFileSizeBytes = 2_000_000

    func saveSnapshot(
        projectURL: URL,
        project: ProjectMetadata,
        notes: SnapshotNotes,
        isAutomaticSafetySnapshot: Bool = false
    ) throws -> TimelineEntry {
        let layout = ProjectLayout(projectURL: projectURL)
        let id = UUID().uuidString
        let now = Date()
        let isoTime = DateFormatters.iso8601.string(from: now)

        let manifests = try manifestStore.loadAllManifests(at: layout)
        let previousInPath = manifests.first(where: { $0.notes.pathName == notes.pathName })
        let autoTouched = try detectAutoFilesTouched(projectURL: projectURL, since: previousInPath?.createdAt)
        let mergedFiles = Array(Set(notes.importantFilesTouched + autoTouched)).sorted()
        var mergedNotes = notes
        mergedNotes.importantFilesTouched = mergedFiles

        let archiveFile = "\(id).zip"
        let archiveURL = layout.snapshotsURL.appendingPathComponent(archiveFile, isDirectory: false)
        try archiveService.createSnapshotArchive(projectURL: projectURL, archiveURL: archiveURL, tempRootURL: layout.tempURL)
        let archiveLocked: Bool
        do {
            archiveLocked = try lockArchiveIfNeeded(archiveURL: archiveURL, snapshotType: notes.snapshotType)
        } catch {
            // Prevent orphan archives when lock step fails.
            try? FileManager.default.removeItem(at: archiveURL)
            throw error
        }
        let sizeMetrics = try captureProjectSizeMetrics(projectURL: projectURL)
        let resourceSnapshot = resourceSnapshotService.captureObservedSnapshot()

        let manifest = SnapshotManifest(
            id: id,
            projectID: project.id,
            createdAt: now,
            createdAtISO8601: isoTime,
            projectPath: projectURL.path,
            archiveRelativePath: "snapshots/\(archiveFile)",
            notes: mergedNotes,
            isAutomaticSafetySnapshot: isAutomaticSafetySnapshot,
            projectSizeMetrics: sizeMetrics,
            resourceSnapshot: resourceSnapshot,
            proofVerificationStatus: .unverified,
            proofVerificationMode: nil,
            proofCheckedAt: nil,
            proofCheckedAtISO8601: nil,
            proofDetails: nil,
            archivePrunedAt: nil,
            archivePrunedAtISO8601: nil,
            archivePruneReason: nil,
            archiveLocked: archiveLocked,
            remoteMetadata: SnapshotRemoteMetadata()
        )

        let manifestRelativePath = try manifestStore.save(manifest, at: layout)

        let timelineEntry = TimelineEntry(
            id: id,
            createdAt: now,
            createdAtISO8601: isoTime,
            manifestRelativePath: manifestRelativePath,
            archiveRelativePath: manifest.archiveRelativePath,
            title: mergedNotes.title,
            summary: mergedNotes.summary,
            snapshotType: mergedNotes.snapshotType,
            status: mergedNotes.status,
            pathName: mergedNotes.pathName,
            tags: mergedNotes.tags,
            isAutomaticSafetySnapshot: isAutomaticSafetySnapshot,
            projectFileCount: sizeMetrics.fileCount,
            codeSizeApproxLines: sizeMetrics.codeSizeApproxLines,
            proofVerificationStatus: .unverified,
            proofVerificationMode: nil,
            remotePublishState: .notPublished,
            archiveAvailable: true
        )

        _ = try reconcileLogsFromManifests(projectURL: projectURL)
        return timelineEntry
    }

    func loadTimeline(projectURL: URL) throws -> [TimelineEntry] {
        try reconcileLogsFromManifests(projectURL: projectURL)
    }

    func loadManifest(projectURL: URL, entry: TimelineEntry) throws -> SnapshotManifest {
        try manifestStore.loadManifest(projectURL: projectURL, relativePath: entry.manifestRelativePath)
    }

    func snapshotArchiveStorageBytes(projectURL: URL) -> Int64 {
        let snapshotsURL = ProjectLayout(projectURL: projectURL).snapshotsURL
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: snapshotsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let itemURL as URL in enumerator {
            guard itemURL.pathExtension.lowercased() == "zip" else { continue }
            let values = try? itemURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    func exportTimeline(projectURL: URL, mode: TimelineExportMode, destinationURL: URL? = nil) throws -> TimelineExportResult {
        let layout = ProjectLayout(projectURL: projectURL)
        let manifests = try manifestStore.loadAllManifests(at: layout)
        let content = renderedTimelineExport(projectURL: projectURL, manifests: manifests, mode: mode)

        let destination: URL
        if let destinationURL {
            destination = destinationURL
        } else {
            try FileSystemService().ensureDirectory(layout.exportsURL)
            destination = layout.exportsURL.appendingPathComponent(defaultExportFileName(for: mode), isDirectory: false)
        }

        try content.data(using: .utf8)?.write(to: destination, options: .atomic)

        return TimelineExportResult(
            mode: mode,
            entriesExported: manifests.count,
            fileURL: destination
        )
    }

    func defaultExportFileName(for mode: TimelineExportMode) -> String {
        let stamp = DateFormatters.fileSafeTimestamp.string(from: Date())
        return "timeline-\(mode.fileToken)-\(stamp).md"
    }

    func pruneSnapshotArchives(
        projectURL: URL,
        keepRecentNonMajor: Int = 10,
        apply: Bool
    ) throws -> SnapshotArchivePruneResult {
        let safeKeepCount = max(0, keepRecentNonMajor)
        let layout = ProjectLayout(projectURL: projectURL)
        let manifests = try manifestStore.loadAllManifests(at: layout)
        let newestManifestID = manifests.first?.id

        var keptNonMajor = 0
        var pruneCandidates: [(manifest: SnapshotManifest, archiveURL: URL, bytes: Int64, reason: String)] = []

        for manifest in manifests {
            let archiveURL = layout.ungitURL.appendingPathComponent(manifest.archiveRelativePath, isDirectory: false)
            guard FileManager.default.fileExists(atPath: archiveURL.path) else { continue }

            if manifest.id == newestManifestID {
                continue
            }

            if manifest.notes.snapshotType.isSacredLandmark {
                continue
            }

            if keptNonMajor < safeKeepCount {
                keptNonMajor += 1
                continue
            }

            let fileValues = try? archiveURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard fileValues?.isRegularFile == true else { continue }
            let bytes = Int64(fileValues?.fileSize ?? 0)
            let reason = derivePruneReason(for: manifest, in: manifests)
            pruneCandidates.append((manifest: manifest, archiveURL: archiveURL, bytes: bytes, reason: reason))
        }

        let bytesBefore = snapshotArchiveStorageBytes(projectURL: projectURL)
        let countBefore = existingArchiveCount(at: layout.snapshotsURL)

        var reclaimed: Int64 = 0
        var prunedIDs: [String] = []
        var failedIDs: [String] = []
        if apply {
            for candidate in pruneCandidates {
                let archiveProtected = candidate.manifest.archiveLocked ?? false
                if archiveProtected {
                    failedIDs.append(candidate.manifest.id)
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: candidate.archiveURL)
                    reclaimed += candidate.bytes
                    var updated = candidate.manifest
                    let now = Date()
                    updated.archivePrunedAt = now
                    updated.archivePrunedAtISO8601 = DateFormatters.iso8601.string(from: now)
                    updated.archivePruneReason = candidate.reason
                    updated.archiveLocked = false
                    _ = try manifestStore.save(updated, at: layout)
                    prunedIDs.append(candidate.manifest.id)
                } catch {
                    failedIDs.append(candidate.manifest.id)
                }
            }
        } else {
            reclaimed = pruneCandidates.reduce(0) { $0 + $1.bytes }
            prunedIDs = pruneCandidates.map { $0.manifest.id }
        }

        let bytesAfter = apply ? snapshotArchiveStorageBytes(projectURL: projectURL) : max(0, bytesBefore - reclaimed)
        let countAfter = apply ? existingArchiveCount(at: layout.snapshotsURL) : max(0, countBefore - pruneCandidates.count)

        _ = try reconcileLogsFromManifests(projectURL: projectURL)

        return SnapshotArchivePruneResult(
            dryRun: !apply,
            keepRecentNonMajor: safeKeepCount,
            totalArchivesBefore: countBefore,
            totalBytesBefore: bytesBefore,
            prunedArchives: apply ? prunedIDs.count : pruneCandidates.count,
            failedArchives: apply ? failedIDs.count : 0,
            reclaimedBytes: reclaimed,
            totalArchivesAfter: countAfter,
            totalBytesAfter: bytesAfter,
            prunedSnapshotIDs: prunedIDs,
            failedSnapshotIDs: failedIDs
        )
    }

    func pruneSnapshotArchive(
        projectURL: URL,
        snapshotID: String,
        apply: Bool
    ) throws -> SnapshotSingleArchivePruneResult {
        let layout = ProjectLayout(projectURL: projectURL)
        let manifests = try manifestStore.loadAllManifests(at: layout)
        guard let manifest = manifests.first(where: { $0.id == snapshotID }) else {
            throw AppError.commandFailed("Snapshot \(snapshotID) was not found.")
        }

        let archiveURL = layout.ungitURL.appendingPathComponent(manifest.archiveRelativePath, isDirectory: false)
        let archiveExists = FileManager.default.fileExists(atPath: archiveURL.path)
        let bytesBefore = snapshotArchiveStorageBytes(projectURL: projectURL)
        let reason = derivePruneReason(for: manifest, in: manifests)

        guard archiveExists else {
            _ = try reconcileLogsFromManifests(projectURL: projectURL)
            return SnapshotSingleArchivePruneResult(
                dryRun: !apply,
                snapshotID: manifest.id,
                title: manifest.notes.title,
                snapshotType: manifest.notes.snapshotType,
                archiveWasPresent: false,
                pruned: false,
                reclaimedBytes: 0,
                totalBytesBefore: bytesBefore,
                totalBytesAfter: bytesBefore,
                note: "Archive already pruned."
            )
        }

        if manifest.archiveLocked ?? false {
            _ = try reconcileLogsFromManifests(projectURL: projectURL)
            return SnapshotSingleArchivePruneResult(
                dryRun: !apply,
                snapshotID: manifest.id,
                title: manifest.notes.title,
                snapshotType: manifest.notes.snapshotType,
                archiveWasPresent: true,
                pruned: false,
                reclaimedBytes: 0,
                totalBytesBefore: bytesBefore,
                totalBytesAfter: bytesBefore,
                note: "Archive is protected and cannot be pruned."
            )
        }

        let newestManifestID = manifests.first?.id
        if manifest.id == newestManifestID {
            _ = try reconcileLogsFromManifests(projectURL: projectURL)
            return SnapshotSingleArchivePruneResult(
                dryRun: !apply,
                snapshotID: manifest.id,
                title: manifest.notes.title,
                snapshotType: manifest.notes.snapshotType,
                archiveWasPresent: true,
                pruned: false,
                reclaimedBytes: 0,
                totalBytesBefore: bytesBefore,
                totalBytesAfter: bytesBefore,
                note: "Newest snapshot archive is protected and cannot be pruned."
            )
        }

        let fileValues = try? archiveURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let archiveBytes = Int64(fileValues?.fileSize ?? 0)
        let pruned: Bool
        if apply {
            try FileManager.default.removeItem(at: archiveURL)
            var updated = manifest
            let now = Date()
            updated.archivePrunedAt = now
            updated.archivePrunedAtISO8601 = DateFormatters.iso8601.string(from: now)
            updated.archivePruneReason = reason
            updated.archiveLocked = false
            _ = try manifestStore.save(updated, at: layout)
            pruned = true
        } else {
            pruned = false
        }

        let bytesAfter = apply ? snapshotArchiveStorageBytes(projectURL: projectURL) : max(0, bytesBefore - archiveBytes)
        _ = try reconcileLogsFromManifests(projectURL: projectURL)

        return SnapshotSingleArchivePruneResult(
            dryRun: !apply,
            snapshotID: manifest.id,
            title: manifest.notes.title,
            snapshotType: manifest.notes.snapshotType,
            archiveWasPresent: true,
            pruned: pruned,
            reclaimedBytes: archiveBytes,
            totalBytesBefore: bytesBefore,
            totalBytesAfter: bytesAfter,
            note: apply ? "Archive pruned: \(reason)" : "Preview only: \(reason)"
        )
    }

    @discardableResult
    func verifyProofIfAvailable(projectURL: URL, entryID: String) throws -> Bool {
        let layout = ProjectLayout(projectURL: projectURL)
        let manifests = try manifestStore.loadAllManifests(at: layout)
        guard let manifest = manifests.first(where: { $0.id == entryID }) else { return false }
        let preferredMode: ProofVerificationMode = manifest.notes.snapshotType.prefersArchiveProof ? .archive : .lightweight
        return try verifyProof(projectURL: projectURL, entryID: entryID, mode: preferredMode)
    }

    @discardableResult
    func verifyProof(projectURL: URL, entryID: String, mode: ProofVerificationMode) throws -> Bool {
        let layout = ProjectLayout(projectURL: projectURL)
        let manifests = try manifestStore.loadAllManifests(at: layout)
        guard let index = manifests.firstIndex(where: { $0.id == entryID }) else { return false }
        var manifest = manifests[index]
        let verification = try runProofChecks(projectURL: projectURL, manifest: manifest, mode: mode)
        guard verification.executedChecks else { return false }

        let now = Date()
        manifest.proofCheckedAt = now
        manifest.proofCheckedAtISO8601 = DateFormatters.iso8601.string(from: now)
        manifest.proofVerificationStatus = verification.success ? .verified : .broken
        manifest.proofVerificationMode = mode
        manifest.proofDetails = String(verification.details.prefix(maxProofDetailsLength))

        _ = try manifestStore.save(manifest, at: layout)
        _ = try reconcileLogsFromManifests(projectURL: projectURL)
        return true
    }

    func publishPreflight(projectURL: URL, snapshotID: String) throws -> RemotePublishPreflight {
        let layout = ProjectLayout(projectURL: projectURL)
        let manifests = try manifestStore.loadAllManifests(at: layout)
        guard let manifest = manifests.first(where: { $0.id == snapshotID }) else {
            throw AppError.commandFailed("Snapshot \(snapshotID) was not found.")
        }

        let timeline = try reconcileLogsFromManifests(projectURL: projectURL)
        let isGitRepository = gitCommandSucceeds(["rev-parse", "--is-inside-work-tree"], projectURL: projectURL)
        let currentBranch = isGitRepository
            ? try? trimmedGitOutput(["branch", "--show-current"], projectURL: projectURL)
            : nil
        let originRemoteURL = isGitRepository
            ? try? trimmedGitOutput(["remote", "get-url", "origin"], projectURL: projectURL)
            : nil
        let gitStatus = isGitRepository
            ? try processRunner.runCapturing("/usr/bin/env", ["git", "status", "--porcelain=1", "--ignored"], currentDirectoryURL: projectURL)
            : CommandResult(exitCode: 1, output: "")
        let parsedStatus = parseGitStatus(gitStatus.output)
        let latestSnapshotID = timeline.first?.id
        let snapshotIsLatest = latestSnapshotID == snapshotID
        let currentState = try currentStateService.evaluate(projectURL: projectURL, timeline: timeline)
        let workingTreeDrifted = !snapshotIsLatest || currentState != .matchesLatestSnapshot

        var blockers: [String] = []
        if manifest.notes.snapshotType != .milestone {
            blockers.append("Remote publish may only operate on a saved milestone snapshot.")
        }
        let archiveURL = layout.ungitURL.appendingPathComponent(manifest.archiveRelativePath, isDirectory: false)
        if !FileManager.default.fileExists(atPath: archiveURL.path) {
            blockers.append("Milestone archive is missing.")
        }
        if !isGitRepository {
            blockers.append("Project is not inside a Git repository.")
        }
        if (originRemoteURL?.isEmpty ?? true) {
            blockers.append("Origin remote is missing.")
        }
        if (currentBranch?.isEmpty ?? true) {
            blockers.append("Current branch is unavailable.")
        }
        if manifest.remoteMetadata.publishState == .published {
            blockers.append("This milestone is already published.")
        }

        return RemotePublishPreflight(
            snapshotID: manifest.id,
            snapshotTitle: manifest.notes.title,
            snapshotType: manifest.notes.snapshotType,
            isGitRepository: isGitRepository,
            originRemoteURL: originRemoteURL,
            currentBranch: currentBranch,
            snapshotIsLatest: snapshotIsLatest,
            workingTreeDriftedSinceSnapshot: workingTreeDrifted,
            stagedChangesPresent: parsedStatus.stagedChangesPresent,
            unstagedChangesPresent: parsedStatus.unstagedChangesPresent,
            untrackedFilesPresent: parsedStatus.untrackedFilesPresent,
            ignoredFilesPresent: parsedStatus.ignoredFilesPresent,
            publishAllowed: blockers.isEmpty,
            blockingReasons: blockers
        )
    }

    func createRemoteCorrectionReview(
        projectURL: URL,
        milestoneSnapshotID: String,
        requestedBy: String,
        selectedAction: RemoteCorrectionSelectedAction = .inspectOnly,
        codexRecommendation: String? = nil
    ) throws -> TimelineEntry {
        let layout = ProjectLayout(projectURL: projectURL)
        let manifests = try manifestStore.loadAllManifests(at: layout)
        guard let milestoneManifest = manifests.first(where: { $0.id == milestoneSnapshotID }) else {
            throw AppError.commandFailed("Snapshot \(milestoneSnapshotID) was not found.")
        }
        guard milestoneManifest.notes.snapshotType == .milestone else {
            throw AppError.commandFailed("Remote Correction Review can only be created for a milestone snapshot.")
        }

        let remotePath = remotePublishPath(for: milestoneManifest).trimmedOr("origin/unknown")
        let reason = classifyRemotePublishFailure(
            message: milestoneManifest.remoteMetadata.lastPublishError,
            preflight: milestoneManifest.remoteMetadata.latestPreflight
        )

        let tempRoot = layout.tempURL.appendingPathComponent("remote-correction-review-\(milestoneSnapshotID)-\(UUID().uuidString)", isDirectory: true)
        let localExtractURL = tempRoot.appendingPathComponent("local-milestone", isDirectory: true)
        let remoteCloneURL = tempRoot.appendingPathComponent("remote-path", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileSystemService().ensureDirectory(tempRoot)

        let archiveURL = layout.ungitURL.appendingPathComponent(milestoneManifest.archiveRelativePath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw AppError.commandFailed("Milestone archive is missing. Remote Correction Review needs the saved milestone snapshot.")
        }

        let localReviewRoot = try archiveService.extractSnapshotArchive(archiveURL: archiveURL, destinationURL: localExtractURL)
        let remoteReviewRoot = try importRemotePathForReview(projectURL: projectURL, remoteURL: milestoneManifest.remoteMetadata.latestPreflight?.originRemoteURL, branchName: milestoneManifest.remoteMetadata.branchName, destinationURL: remoteCloneURL)
        let changedFiles = try compareProjectTrees(localURL: localReviewRoot, remoteURL: remoteReviewRoot)
        let summary = summarizeRemoteCorrection(changedFiles: changedFiles, remotePath: remotePath)
        let recommendationLevel = recommendationLevel(for: changedFiles, reason: reason)

        var reviewNotes = SnapshotNotes(
            title: "Remote Correction Review",
            summary: "Review remote divergence safely for milestone \(milestoneManifest.id).",
            whatChanged: summary,
            why: "Blocked publish needs safe inspection before any correction decision.",
            importantFilesTouched: changedFiles.map(\.path),
            gotchas: "This review imported remote changes into an isolated inspection space. No live project files were modified.",
            tags: ["remote-correction-review", "publish-blocked", "remote-review"],
            status: .working,
            snapshotType: .remoteCorrectionReview,
            pathName: milestoneManifest.notes.pathName,
            proofCommand: "",
            linkedMemoryIDs: [milestoneManifest.id],
            changeIntent: "Inspect remote divergence without changing live local truth.",
            riskLevel: recommendationLevel == .risky ? .high : (recommendationLevel == .caution ? .medium : .low),
            outcome: nil
        )
        reviewNotes.summary = summary

        let projectMetadata = try JSONFileStore().read(ProjectMetadata.self, from: layout.projectMetadataURL)
        let entry = try saveSnapshot(
            projectURL: projectURL,
            project: projectMetadata,
            notes: reviewNotes,
            isAutomaticSafetySnapshot: false
        )

        var savedManifest = try manifestStore.loadManifest(projectURL: projectURL, relativePath: entry.manifestRelativePath)
        let reviewedAt = Date()
        savedManifest.remoteCorrectionReview = RemoteCorrectionReviewRecord(
            linkedMilestoneSnapshotID: milestoneManifest.id,
            reasonForReview: reason,
            remotePath: remotePath,
            changedFiles: changedFiles,
            summaryOfRemoteChanges: summary,
            codexRecommendation: codexRecommendation ?? defaultCodexRecommendation(for: changedFiles, reason: reason, remotePath: remotePath),
            recommendationLevel: recommendationLevel,
            humanSelectedNextAction: selectedAction,
            reviewedAt: reviewedAt,
            reviewedAtISO8601: DateFormatters.iso8601.string(from: reviewedAt)
        )
        _ = try manifestStore.save(savedManifest, at: layout)
        _ = try reconcileLogsFromManifests(projectURL: projectURL)
        return entry
    }

    @discardableResult
    func publishMilestone(
        projectURL: URL,
        snapshotID: String,
        requestedBy: String,
        approvedBy: String,
        executedBy: String = "UNGIT"
    ) throws -> SnapshotRemoteMetadata {
        let layout = ProjectLayout(projectURL: projectURL)
        let manifests = try manifestStore.loadAllManifests(at: layout)
        guard let manifestIndex = manifests.firstIndex(where: { $0.id == snapshotID }) else {
            throw AppError.commandFailed("Snapshot \(snapshotID) was not found.")
        }

        let preflight = try publishPreflight(projectURL: projectURL, snapshotID: snapshotID)
        var manifest = manifests[manifestIndex]
        let attemptAt = Date()
        let attemptISO = DateFormatters.iso8601.string(from: attemptAt)
        let branchName = preflight.currentBranch?.trimmed

        manifest.remoteMetadata.latestPreflight = preflight
        manifest.remoteMetadata.lastPublishAttemptAt = attemptAt
        manifest.remoteMetadata.lastPublishAttemptAtISO8601 = attemptISO
        manifest.remoteMetadata.requestedBy = requestedBy
        manifest.remoteMetadata.approvedBy = approvedBy
        manifest.remoteMetadata.executedBy = executedBy
        manifest.remoteMetadata.branchName = branchName

        guard preflight.publishAllowed else {
            manifest.remoteMetadata.publishState = .publishFailed
            manifest.remoteMetadata.lastPublishError = preflight.blockingReasons.joined(separator: " ")
            _ = try manifestStore.save(manifest, at: layout)
            _ = try reconcileLogsFromManifests(projectURL: projectURL)
            throw AppError.commandFailed(manifest.remoteMetadata.lastPublishError ?? "Publish preflight failed.")
        }

        let publicationWindow = try buildPublicationWindow(targetSnapshotID: snapshotID, manifests: manifests)

        manifest.remoteMetadata.publishState = .publishing
        manifest.remoteMetadata.publicationWindow = publicationWindow
        manifest.remoteMetadata.lastPublishError = nil
        _ = try manifestStore.save(manifest, at: layout)

        do {
            let subject = "Milestone: \(manifest.notes.title)"
            let body = commitBody(for: manifest, publicationWindow: publicationWindow)
            let archiveURL = layout.ungitURL.appendingPathComponent(manifest.archiveRelativePath, isDirectory: false)
            guard let remoteURL = preflight.originRemoteURL?.trimmed, !remoteURL.isEmpty else {
                throw AppError.commandFailed("Origin remote is missing.")
            }
            guard let branchName, !branchName.isEmpty else {
                throw AppError.commandFailed("Current branch is unavailable.")
            }

            let commitSHA = try publishSnapshotArchive(
                projectURL: projectURL,
                archiveURL: archiveURL,
                remoteURL: remoteURL,
                branchName: branchName,
                commitSubject: subject,
                commitBody: body
            )
            let publishedAt = Date()
            manifest.remoteMetadata.publishState = .published
            manifest.remoteMetadata.commitSHA = commitSHA
            manifest.remoteMetadata.publishedAt = publishedAt
            manifest.remoteMetadata.publishedAtISO8601 = DateFormatters.iso8601.string(from: publishedAt)
            manifest.remoteMetadata.lastPublishError = nil
            _ = try manifestStore.save(manifest, at: layout)
            _ = try reconcileLogsFromManifests(projectURL: projectURL)
            return manifest.remoteMetadata
        } catch {
            manifest.remoteMetadata.publishState = .publishFailed
            manifest.remoteMetadata.lastPublishError = error.localizedDescription
            _ = try manifestStore.save(manifest, at: layout)
            _ = try reconcileLogsFromManifests(projectURL: projectURL)
            throw error
        }
    }

    @discardableResult
    func reconcileLogsFromManifests(projectURL: URL) throws -> [TimelineEntry] {
        let layout = ProjectLayout(projectURL: projectURL)
        let manifests = try manifestStore.loadAllManifests(at: layout)
        let normalizedManifests = try migrateArchiveProtectionModel(layout: layout, manifests: manifests)
        let entries = try normalizedManifests.map { manifest in
            try timelineEntry(from: manifest, layout: layout)
        }
        try logService.replaceProjection(entries: entries, for: layout)
        return entries
    }

    private func timelineEntry(from manifest: SnapshotManifest, layout: ProjectLayout) throws -> TimelineEntry {
        let archiveURL = layout.ungitURL.appendingPathComponent(manifest.archiveRelativePath, isDirectory: false)
        let archiveAvailable = FileManager.default.fileExists(atPath: archiveURL.path)
        let normalizedTitle = normalizedForkPointTextIfNeeded(manifest.notes.title, tags: manifest.notes.tags)
        let normalizedSummary = normalizedForkPointTextIfNeeded(manifest.notes.summary, tags: manifest.notes.tags)

        return TimelineEntry(
            id: manifest.id,
            createdAt: manifest.createdAt,
            createdAtISO8601: manifest.createdAtISO8601,
            manifestRelativePath: "manifests/\(manifest.id).json",
            archiveRelativePath: manifest.archiveRelativePath,
            title: normalizedTitle,
            summary: normalizedSummary,
            snapshotType: manifest.notes.snapshotType,
            status: manifest.notes.status,
            pathName: manifest.notes.pathName,
            tags: manifest.notes.tags,
            isAutomaticSafetySnapshot: manifest.isAutomaticSafetySnapshot,
            projectFileCount: manifest.projectSizeMetrics?.fileCount,
            codeSizeApproxLines: manifest.projectSizeMetrics?.codeSizeApproxLines,
            proofVerificationStatus: manifest.proofVerificationStatus,
            proofVerificationMode: manifest.proofVerificationMode,
            remotePublishState: manifest.remoteMetadata.publishState,
            archiveAvailable: archiveAvailable
        )
    }

    private func buildPublicationWindow(
        targetSnapshotID: String,
        manifests: [SnapshotManifest]
    ) throws -> MilestonePublicationWindow {
        let ordered = manifests.sorted { $0.createdAt < $1.createdAt }
        guard let targetIndex = ordered.firstIndex(where: { $0.id == targetSnapshotID }) else {
            throw AppError.commandFailed("Publication window could not find snapshot \(targetSnapshotID).")
        }

        let previousPublishedIndex = ordered[..<targetIndex].lastIndex(where: {
            $0.notes.snapshotType == .milestone && $0.remoteMetadata.publishState == .published
        })
        let startIndex = (previousPublishedIndex ?? -1) + 1
        let included = ordered[startIndex...targetIndex]
            .filter { !$0.isAutomaticSafetySnapshot }

        let previousPublishedMilestoneID = previousPublishedIndex.map { ordered[$0].id }
        let firstIncludedSnapshotID = included.first?.id
        let lastIncludedSnapshotID = included.last?.id
        let includedSnapshotIDs = included.map(\.id)
        let compiledChangelog = renderCompiledChangelog(from: included)

        return MilestonePublicationWindow(
            previousPublishedMilestoneID: previousPublishedMilestoneID,
            firstIncludedSnapshotID: firstIncludedSnapshotID,
            lastIncludedSnapshotID: lastIncludedSnapshotID,
            includedSnapshotIDs: includedSnapshotIDs,
            compiledChangelog: compiledChangelog
        )
    }

    private func publishSnapshotArchive(
        projectURL: URL,
        archiveURL: URL,
        remoteURL: String,
        branchName: String,
        commitSubject: String,
        commitBody: String
    ) throws -> String {
        let layout = ProjectLayout(projectURL: projectURL)
        let publishRoot = layout.tempURL.appendingPathComponent("publish-\(UUID().uuidString)", isDirectory: true)
        let extractedArchiveURL = publishRoot.appendingPathComponent("milestone-archive", isDirectory: true)
        let remoteCloneURL = publishRoot.appendingPathComponent("remote-clone", isDirectory: true)
        let fileSystem = FileSystemService()

        defer { try? FileManager.default.removeItem(at: publishRoot) }
        try fileSystem.ensureDirectory(publishRoot)

        let archiveProjectRoot = try archiveService.extractSnapshotArchive(archiveURL: archiveURL, destinationURL: extractedArchiveURL)
        try cloneRemoteForPublish(
            projectURL: projectURL,
            remoteURL: remoteURL,
            branchName: branchName,
            destinationURL: remoteCloneURL
        )
        try synchronizePublishedContents(
            sourceRootURL: archiveProjectRoot,
            destinationRootURL: remoteCloneURL
        )
        try configureGitIdentityForPublish(sourceProjectURL: projectURL, publishCloneURL: remoteCloneURL)
        try processRunner.run("/usr/bin/env", ["git", "add", "-A"], currentDirectoryURL: remoteCloneURL)
        let stagedStatus = try processRunner.runCapturing("/usr/bin/env", ["git", "status", "--porcelain=1"], currentDirectoryURL: remoteCloneURL)
        if stagedStatus.output.trimmed.isEmpty {
            return try trimmedGitOutput(["rev-parse", "HEAD"], projectURL: remoteCloneURL)
        }
        try processRunner.run("/usr/bin/env", ["git", "commit", "-m", commitSubject, "-m", commitBody], currentDirectoryURL: remoteCloneURL)
        try processRunner.run("/usr/bin/env", ["git", "push", "origin", branchName], currentDirectoryURL: remoteCloneURL)
        return try trimmedGitOutput(["rev-parse", "HEAD"], projectURL: remoteCloneURL)
    }

    private func cloneRemoteForPublish(
        projectURL: URL,
        remoteURL: String,
        branchName: String,
        destinationURL: URL
    ) throws {
        let fileSystem = FileSystemService()
        try fileSystem.ensureDirectory(destinationURL)
        try fileSystem.clearDirectory(destinationURL)
        try processRunner.run("/usr/bin/env", ["git", "clone", "--depth", "1", remoteURL, destinationURL.path], currentDirectoryURL: projectURL)

        if gitCommandSucceeds(["rev-parse", "--verify", "origin/\(branchName)"], projectURL: destinationURL) {
            try processRunner.run("/usr/bin/env", ["git", "checkout", "-B", branchName, "origin/\(branchName)"], currentDirectoryURL: destinationURL)
        } else {
            try processRunner.run("/usr/bin/env", ["git", "checkout", "-B", branchName], currentDirectoryURL: destinationURL)
        }
    }

    private func synchronizePublishedContents(
        sourceRootURL: URL,
        destinationRootURL: URL
    ) throws {
        let fileSystem = FileSystemService()
        try fileSystem.removeContents(of: destinationRootURL, excludingRootNames: [".git"])
        try fileSystem.copyProjectContents(
            from: sourceRootURL,
            to: destinationRootURL,
            excludingRootNames: [".git", ".ungit"]
        )
    }

    private func configureGitIdentityForPublish(
        sourceProjectURL: URL,
        publishCloneURL: URL
    ) throws {
        let userName = (try? trimmedGitOutput(["config", "user.name"], projectURL: sourceProjectURL)).flatMap { $0.trimmed.isEmpty ? nil : $0 } ?? "UNGIT"
        let userEmail = (try? trimmedGitOutput(["config", "user.email"], projectURL: sourceProjectURL)).flatMap { $0.trimmed.isEmpty ? nil : $0 } ?? "ungit@local.invalid"
        try processRunner.run("/usr/bin/env", ["git", "config", "user.name", userName], currentDirectoryURL: publishCloneURL)
        try processRunner.run("/usr/bin/env", ["git", "config", "user.email", userEmail], currentDirectoryURL: publishCloneURL)
    }

    private func importRemotePathForReview(
        projectURL: URL,
        remoteURL: String?,
        branchName: String?,
        destinationURL: URL
    ) throws -> URL {
        guard let remoteURL, !remoteURL.trimmed.isEmpty else {
            throw AppError.commandFailed("Remote Correction Review could not locate the selected remote path.")
        }
        guard let branchName, !branchName.trimmed.isEmpty else {
            throw AppError.commandFailed("Remote Correction Review could not determine the selected remote path branch.")
        }

        try FileSystemService().ensureDirectory(destinationURL)
        try FileSystemService().clearDirectory(destinationURL)
        try processRunner.run(
            "/usr/bin/env",
            ["git", "clone", "--depth", "1", "--branch", branchName, remoteURL, destinationURL.path],
            currentDirectoryURL: projectURL
        )
        return destinationURL
    }

    private func compareProjectTrees(localURL: URL, remoteURL: URL) throws -> [RemoteCorrectionChangedFile] {
        let localFiles = try relativeFileMap(rootURL: localURL, excludingRootNames: [".git", ".ungit"])
        let remoteFiles = try relativeFileMap(rootURL: remoteURL, excludingRootNames: [".git", ".ungit"])
        let allPaths = Set(localFiles.keys).union(remoteFiles.keys).sorted()

        return try allPaths.compactMap { path in
            let local = localFiles[path]
            let remote = remoteFiles[path]

            switch (local, remote) {
            case (nil, .some):
                return RemoteCorrectionChangedFile(path: path, status: .added)
            case (.some, nil):
                return RemoteCorrectionChangedFile(path: path, status: .deleted)
            case let (.some(localURL), .some(remoteURL)):
                let localData = try Data(contentsOf: localURL)
                let remoteData = try Data(contentsOf: remoteURL)
                guard localData != remoteData else { return nil }
                return RemoteCorrectionChangedFile(path: path, status: .modified)
            default:
                return nil
            }
        }
    }

    private func relativeFileMap(rootURL: URL, excludingRootNames: Set<String>) throws -> [String: URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return [:]
        }

        var results: [String: URL] = [:]
        for case let itemURL as URL in enumerator {
            let relativePath = itemURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            if itemURL.pathComponents.contains(where: { excludingRootNames.contains($0) }) {
                continue
            }
            let values = try itemURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            results[relativePath] = itemURL
        }
        return results
    }

    private func summarizeRemoteCorrection(changedFiles: [RemoteCorrectionChangedFile], remotePath: String) -> String {
        let added = changedFiles.filter { $0.status == .added }.count
        let modified = changedFiles.filter { $0.status == .modified }.count
        let deleted = changedFiles.filter { $0.status == .deleted }.count
        let sample = changedFiles.prefix(8).map { "\($0.status.rawValue): \($0.path)" }.joined(separator: "; ")
        let sampleText = sample.isEmpty ? "No file-level delta was detected." : sample
        return "Remote path \(remotePath) differs from the saved milestone snapshot. Added \(added), modified \(modified), deleted \(deleted). Sample: \(sampleText)"
    }

    private func recommendationLevel(
        for changedFiles: [RemoteCorrectionChangedFile],
        reason: RemotePublishFailureReason
    ) -> RemoteCorrectionRecommendationLevel {
        if reason == .remotePathDiverged {
            return changedFiles.count > 12 ? .risky : .caution
        }
        return changedFiles.count > 20 ? .risky : .caution
    }

    private func defaultCodexRecommendation(
        for changedFiles: [RemoteCorrectionChangedFile],
        reason: RemotePublishFailureReason,
        remotePath: String
    ) -> String {
        switch reason {
        case .remotePathDiverged:
            return "Remote change can block distribution without invalidating local truth. Review the imported delta from \(remotePath), then prefer publishing this milestone to a new path unless the remote correction clearly matches your intended milestone story."
        default:
            return "Inspect the imported remote delta first. Keep local milestone truth unchanged until a human chooses whether to ignore it, adopt it later, or publish to a new path."
        }
    }

    private func remotePublishPath(for manifest: SnapshotManifest) -> String {
        let branch = manifest.remoteMetadata.branchName?.trimmed
        if let branch, !branch.isEmpty {
            return "origin/\(branch)"
        }
        if let branch = manifest.remoteMetadata.latestPreflight?.currentBranch?.trimmed, !branch.isEmpty {
            return "origin/\(branch)"
        }
        return manifest.remoteMetadata.latestPreflight?.originRemoteURL?.trimmedOr("origin/unknown") ?? "origin/unknown"
    }

    private func classifyRemotePublishFailure(
        message: String?,
        preflight: RemotePublishPreflight?
    ) -> RemotePublishFailureReason {
        let lower = message?.lowercased() ?? ""

        if let preflight {
            if !preflight.isGitRepository {
                return .noGitRepository
            }
            if !preflight.publishAllowed {
                if preflight.workingTreeDriftedSinceSnapshot {
                    return .workspaceDriftDetected
                }
                if preflight.originRemoteURL?.isEmpty ?? true {
                    return .remoteMissing
                }
            }
        }

        if lower.contains("non-fast-forward") || lower.contains("tip of your current branch is behind") {
            return .remotePathDiverged
        }
        if lower.contains("authentication failed") || lower.contains("could not read username") || lower.contains("permission denied") {
            return .remoteAuthFailed
        }
        if lower.contains("remote") && lower.contains("not found") {
            return .remoteMissing
        }
        if lower.contains("drifted") {
            return .workspaceDriftDetected
        }
        if !lower.isEmpty {
            return .publishBlocked
        }
        return .unknown
    }

    private func renderCompiledChangelog(from manifests: [SnapshotManifest]) -> String {
        guard !manifests.isEmpty else { return "No milestone notes were available to compile." }

        var lines: [String] = []
        lines.append("Compiled from UNGIT snapshot notes since the previous published milestone.")
        lines.append("")

        for manifest in manifests {
            let notes = manifest.notes
            lines.append("[\(notes.snapshotType.rawValue)] \(notes.title) (\(manifest.id))")
            if !notes.summary.trimmed.isEmpty {
                lines.append("Summary: \(notes.summary.trimmed)")
            }
            if !notes.whatChanged.trimmed.isEmpty {
                lines.append("What Changed: \(notes.whatChanged.trimmed)")
            }
            if !notes.why.trimmed.isEmpty {
                lines.append("Why: \(notes.why.trimmed)")
            }
            if !notes.changeIntent.trimmed.isEmpty {
                lines.append("Change Intent: \(notes.changeIntent.trimmed)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmed
    }

    private func commitBody(for manifest: SnapshotManifest, publicationWindow: MilestonePublicationWindow) -> String {
        var lines: [String] = []
        lines.append("UNGIT Milestone Snapshot: \(manifest.id)")
        lines.append("Publication Window:")
        lines.append("- Previous Published Milestone ID: \(publicationWindow.previousPublishedMilestoneID ?? "-")")
        lines.append("- First Included Snapshot ID: \(publicationWindow.firstIncludedSnapshotID ?? "-")")
        lines.append("- Last Included Snapshot ID: \(publicationWindow.lastIncludedSnapshotID ?? "-")")
        lines.append("- Included Snapshot IDs: \(publicationWindow.includedSnapshotIDs.joined(separator: ", "))")
        lines.append("")
        lines.append(publicationWindow.compiledChangelog)
        return lines.joined(separator: "\n")
    }

    private func trimmedGitOutput(_ arguments: [String], projectURL: URL) throws -> String {
        let result = try processRunner.runCapturing("/usr/bin/env", ["git"] + arguments, currentDirectoryURL: projectURL)
        guard result.exitCode == 0 else {
            throw AppError.commandFailed(result.output.trimmedOr("git \(arguments.joined(separator: " ")) failed"))
        }
        return result.output.trimmed
    }

    private func gitCommandSucceeds(_ arguments: [String], projectURL: URL) -> Bool {
        guard let result = try? processRunner.runCapturing("/usr/bin/env", ["git"] + arguments, currentDirectoryURL: projectURL) else {
            return false
        }
        return result.exitCode == 0
    }

    private func parseGitStatus(_ output: String) -> (
        stagedChangesPresent: Bool,
        unstagedChangesPresent: Bool,
        untrackedFilesPresent: Bool,
        ignoredFilesPresent: Bool
    ) {
        var staged = false
        var unstaged = false
        var untracked = false
        var ignored = false

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.count >= 2 else { continue }
            let x = line[line.startIndex]
            let y = line[line.index(after: line.startIndex)]
            if x == "?" && y == "?" {
                untracked = true
                continue
            }
            if x == "!" && y == "!" {
                ignored = true
                continue
            }
            if x != " " {
                staged = true
            }
            if y != " " {
                unstaged = true
            }
        }

        return (staged, unstaged, untracked, ignored)
    }

    private func normalizedForkPointTextIfNeeded(_ text: String, tags: [String]) -> String {
        let hasForkPointTag = tags.contains { $0.lowercased() == "fork-point" }
        guard hasForkPointTag else { return text }
        return text.replacingOccurrences(of: "Fork Path", with: "Fork Point")
    }

    private func existingArchiveCount(at snapshotsURL: URL) -> Int {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: snapshotsURL, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "zip" }.count
    }

    private func renderedTimelineExport(projectURL: URL, manifests: [SnapshotManifest], mode: TimelineExportMode) -> String {
        let ordered = manifests.sorted(by: { $0.createdAt > $1.createdAt })
        let title: String
        switch mode {
        case .patchList: title = "UNGIT Timeline Export: Patch List"
        case .bulletList: title = "UNGIT Timeline Export: Bullet List"
        case .detailedSummary: title = "UNGIT Timeline Export: Detailed Summary"
        case .continuityReview: title = "UNGIT Timeline Export: Continuity Review"
        case .projectHandoff: title = "UNGIT Timeline Export: Project Handoff"
        }

        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        lines.append("- Project: \(projectURL.lastPathComponent)")
        lines.append("- Exported: \(DateFormatters.displayWithSeconds.string(from: Date()))")
        lines.append("- Entries: \(ordered.count)")
        lines.append("")

        switch mode {
        case .bulletList:
            lines.append(contentsOf: renderBulletList(ordered))
        case .patchList:
            lines.append(contentsOf: renderPatchList(ordered))
        case .detailedSummary:
            lines.append(contentsOf: renderDetailedSummary(ordered))
        case .continuityReview:
            lines.append(contentsOf: renderContinuityReview(ordered))
        case .projectHandoff:
            lines.append(contentsOf: renderProjectHandoff(projectURL: projectURL, manifests: ordered))
        }

        return lines.joined(separator: "\n")
    }

    private func renderBulletList(_ manifests: [SnapshotManifest]) -> [String] {
        var lines: [String] = []
        for manifest in manifests {
            let notes = manifest.notes
            let archiveState = manifest.archivePrunedAt == nil ? "restorable" : "archive removed"
            lines.append("- [\(notes.snapshotType.rawValue)] \(notes.title) (\(manifest.id)) — \(notes.status.rawValue), \(notes.pathName), \(archiveState)")
        }
        return lines
    }

    private func renderPatchList(_ manifests: [SnapshotManifest]) -> [String] {
        var lines: [String] = []
        for manifest in manifests {
            let notes = manifest.notes
            lines.append("## \(notes.title) — \(manifest.id)")
            lines.append("- Type/Status: \(notes.snapshotType.rawValue) / \(notes.status.rawValue)")
            lines.append("- Captured: \(DateFormatters.display.string(from: manifest.createdAt))")
            lines.append("- Path: \(notes.pathName)")
            lines.append("- Change Intent: \(safeText(notes.changeIntent, fallback: "-"))")
            lines.append("- What Changed: \(safeText(notes.whatChanged, fallback: "-"))")
            lines.append("- Important Files: \(notes.importantFilesTouched.isEmpty ? "-" : notes.importantFilesTouched.joined(separator: ", "))")
            lines.append("- Proof: \(manifest.proofVerificationStatus.rawValue)\(manifest.proofVerificationMode.map { " (\($0.rawValue))" } ?? "")")
            lines.append("")
        }
        return lines
    }

    private func renderDetailedSummary(_ manifests: [SnapshotManifest]) -> [String] {
        var lines: [String] = []
        for manifest in manifests {
            let notes = manifest.notes
            lines.append("## \(notes.title) (\(manifest.id))")
            lines.append("- Type: \(notes.snapshotType.rawValue)")
            lines.append("- Status: \(notes.status.rawValue)")
            lines.append("- Risk: \(notes.riskLevel.rawValue)")
            lines.append("- Outcome: \(notes.outcome?.rawValue ?? "-")")
            lines.append("- Captured: \(DateFormatters.display.string(from: manifest.createdAt))")
            lines.append("- Path: \(notes.pathName)")
            lines.append("- Tags: \(notes.tags.isEmpty ? "-" : notes.tags.joined(separator: ", "))")
            lines.append("- Proof State: \(manifest.proofVerificationStatus.rawValue)")
            lines.append("- Proof Mode: \(manifest.proofVerificationMode?.rawValue ?? "-")")
            lines.append("- Proof Checked: \(manifest.proofCheckedAt.map { DateFormatters.display.string(from: $0) } ?? "-")")
            lines.append("- Archive: \(manifest.archivePrunedAt == nil ? "Available" : "Archive removed (history preserved)")")
            if let reason = manifest.archivePruneReason, !reason.isEmpty {
                lines.append("- Pruned Reason: \(reason)")
            }
            lines.append("")
            lines.append("### Summary")
            lines.append(safeText(notes.summary, fallback: "-"))
            lines.append("")
            lines.append("### What Changed")
            lines.append(safeText(notes.whatChanged, fallback: "-"))
            lines.append("")
            lines.append("### Why")
            lines.append(safeText(notes.why, fallback: "-"))
            lines.append("")
            lines.append("### Gotchas")
            lines.append(safeText(notes.gotchas, fallback: "-"))
            lines.append("")
        }
        return lines
    }

    private func renderContinuityReview(_ manifests: [SnapshotManifest]) -> [String] {
        var lines: [String] = []
        for manifest in manifests {
            let notes = manifest.notes
            lines.append("## \(notes.title) (\(manifest.id))")
            lines.append("- Change Intent: \(safeText(notes.changeIntent, fallback: "-"))")
            lines.append("- Risk: \(notes.riskLevel.rawValue)")
            lines.append("- Outcome: \(notes.outcome?.rawValue ?? "-")")
            lines.append("- Proof: \(manifest.proofVerificationStatus.rawValue)\(manifest.proofVerificationMode.map { " (\($0.rawValue))" } ?? "")")
            lines.append("- Snapshot Type: \(notes.snapshotType.rawValue)")
            lines.append("- Captured: \(DateFormatters.display.string(from: manifest.createdAt))")
            lines.append("")
        }
        return lines
    }

    private func renderProjectHandoff(projectURL: URL, manifests: [SnapshotManifest]) -> [String] {
        var lines: [String] = []
        let layout = ProjectLayout(projectURL: projectURL)
        let latestNonAutomatic = manifests.filter { !$0.isAutomaticSafetySnapshot }.prefix(6)
        let continuity = continuityWindow(from: manifests)
        let continuityHasTrustedRollbackAnchor = manifests.contains { $0.notes.snapshotType == .trustedRollback }
        let risks = manifests.filter { manifest in
            manifest.notes.riskLevel == .high ||
            manifest.proofVerificationStatus != .verified ||
            manifest.archivePrunedAt != nil
        }.prefix(12)
        let topRegressions = Array(likelyRegressionPoints(in: continuity).prefix(3))
        let rollbackCandidate = safestRollbackCandidate(in: manifests)
        let projectSummaryText = readTextFile(at: layout.projectSummaryURL)
        let hasFilledProjectSummary = !projectSummaryText.isEmpty && !appearsToBeUnfilledProjectSummaryTemplate(projectSummaryText)
        let nextActions = handoffNextActions(
            manifests: manifests,
            risks: Array(risks),
            hasFilledProjectSummary: hasFilledProjectSummary
        )

        lines.append("## Operator Handoff Summary")
        lines.append(operatorSummary(
            projectName: projectURL.lastPathComponent,
            manifests: manifests,
            continuityHasTrustedRollbackAnchor: continuityHasTrustedRollbackAnchor
        ))
        lines.append("")

        lines.append("## Recent Work Story (Latest First)")
        if latestNonAutomatic.isEmpty {
            lines.append("- No recent snapshots found.")
        } else {
            for manifest in latestNonAutomatic {
                let notes = manifest.notes
                let proof = manifest.proofVerificationStatus.rawValue
                let outcome = notes.outcome?.rawValue ?? "Not Set"
                lines.append("- \(notes.title) (\(manifest.id)) — \(notes.snapshotType.rawValue), \(notes.status.rawValue), proof \(proof), outcome \(outcome)")
            }
        }
        lines.append("")

        lines.append("## Human Handoff")
        if let candidate = rollbackCandidate {
            lines.append("- Resume point: use **\(candidate.notes.title)** (\(candidate.id)) as the safest known rollback today.")
        } else {
            lines.append("- Resume point: no clear rollback candidate is established yet.")
        }
        if topRegressions.isEmpty {
            lines.append("- Drift watch: no major regression signal in continuity metadata.")
        } else {
            let riskNames = topRegressions.map { "\"\($0.notes.title)\"" }.joined(separator: ", ")
            lines.append("- Drift watch: re-check \(riskNames) first if behavior looks off.")
        }
        if let firstAction = nextActions.first {
            lines.append("- First move next session: \(firstAction)")
        }
        lines.append("- Operator note: this handoff favors concrete next steps; detailed audit data remains below as reference.")
        lines.append("")

        lines.append("## Project Goals / Home Base")
        if projectSummaryText.isEmpty {
            lines.append("_No PROJECT_SUMMARY.md content found._")
        } else if appearsToBeUnfilledProjectSummaryTemplate(projectSummaryText) {
            lines.append("_PROJECT_SUMMARY.md is still template-level and should be filled with concrete goals/outcomes._")
            lines.append("")
            lines.append(projectSummaryText)
        } else {
            lines.append(projectSummaryText)
        }
        lines.append("")

        lines.append("## Current Safe Rollback Candidate")
        if let candidate = rollbackCandidate {
            lines.append("- Snapshot: \(candidate.notes.title) (\(candidate.id))")
            lines.append("- Type/Status: \(candidate.notes.snapshotType.rawValue) / \(candidate.notes.status.rawValue)")
            lines.append("- Proof: \(candidate.proofVerificationStatus.rawValue)\(candidate.proofVerificationMode.map { " (\($0.rawValue))" } ?? "")")
            lines.append("- Captured: \(DateFormatters.display.string(from: candidate.createdAt))")
            lines.append("- Archive: \(candidate.archivePrunedAt == nil ? "Available" : "Archive removed (history preserved)")")
            lines.append("- Reason: \(rollbackCandidateReason(for: candidate))")
        } else {
            lines.append("- No safe rollback candidate found.")
        }
        lines.append("")

        lines.append("## Sacred Landmarks (Recent)")
        let landmarks = manifests.filter { $0.notes.snapshotType.isSacredLandmark }.prefix(5)
        if landmarks.isEmpty {
            lines.append("- None yet.")
        } else {
            for manifest in landmarks {
                lines.append("- [\(manifest.notes.snapshotType.rawValue)] \(manifest.notes.title) (\(manifest.id)) — \(manifest.proofVerificationStatus.rawValue), \(DateFormatters.display.string(from: manifest.createdAt))")
            }
        }
        lines.append("")

        lines.append("## Open Risks")
        let prioritizedRisks = Array(risks.prefix(6))
        if prioritizedRisks.isEmpty {
            lines.append("- No open high-signal risks detected.")
        } else {
            for manifest in prioritizedRisks {
                var flags: [String] = []
                if manifest.notes.riskLevel == .high { flags.append("High Risk") }
                if manifest.proofVerificationStatus != .verified { flags.append("Proof \(manifest.proofVerificationStatus.rawValue)") }
                if manifest.archivePrunedAt != nil { flags.append("Archive removed") }
                lines.append("- \(manifest.notes.title) (\(manifest.id)): \(flags.joined(separator: ", "))")
            }
        }
        lines.append("")

        lines.append("## Continuity (Last Trusted Rollback -> Now)")
        if !continuityHasTrustedRollbackAnchor {
            lines.append("- Trusted Rollback anchor not found; continuity window uses latest 12 entries.")
        }
        let intents = continuity.map { safeText($0.notes.changeIntent, fallback: "") }.filter { !$0.isEmpty }
        let uniqueIntents = Array(NSOrderedSet(array: intents).array as? [String] ?? []).prefix(5)
        lines.append("- Window Entries: \(continuity.count)")
        lines.append("- Change Intent: \(uniqueIntents.isEmpty ? "-" : uniqueIntents.joined(separator: " | "))")
        let low = continuity.filter { $0.notes.riskLevel == .low }.count
        let medium = continuity.filter { $0.notes.riskLevel == .medium }.count
        let high = continuity.filter { $0.notes.riskLevel == .high }.count
        lines.append("- Risk Profile: Low \(low), Medium \(medium), High \(high)")
        let worked = continuity.filter { $0.notes.outcome == .worked }.count
        let partial = continuity.filter { $0.notes.outcome == .partial }.count
        let reverted = continuity.filter { $0.notes.outcome == .reverted }.count
        let notSet = continuity.filter { $0.notes.outcome == nil }.count
        lines.append("- Outcome Profile: Worked \(worked), Partial \(partial), Reverted \(reverted), Not Set \(notSet)")

        if topRegressions.isEmpty {
            lines.append("- Likely Regression Points: none obvious from continuity metadata.")
        } else {
            lines.append("- Likely Regression Points:")
            for manifest in topRegressions {
                lines.append("- \(manifest.notes.title) (\(manifest.id)) — \(manifest.notes.riskLevel.rawValue), \(manifest.proofVerificationStatus.rawValue), outcome \(manifest.notes.outcome?.rawValue ?? "Not Set")")
            }
        }
        lines.append("")

        lines.append("## Restore Readiness")
        let drills = readTextFile(at: layout.restoreDrillsURL)
        if drills.isEmpty {
            lines.append("- Restore drill evidence: none recorded in RESTORE_DRILLS.md")
        } else {
            let evidence = latestRestoreDrillEvidence(in: drills, maxCount: 3)
            if evidence.isEmpty {
                lines.append("- Restore drill evidence: none recorded in RESTORE_DRILLS.md")
            } else {
                lines.append("- Restore drill evidence found (latest):")
                for line in evidence {
                    lines.append("- \(line)")
                }
            }
        }
        if let candidate = rollbackCandidate {
            let restoreReady = candidate.proofVerificationStatus == .verified &&
                candidate.proofVerificationMode == .archive &&
                candidate.archivePrunedAt == nil
            lines.append("- Rollback Readiness: \(restoreReady ? "Strong" : "Needs confirmation")")
        } else {
            lines.append("- Rollback Readiness: No candidate available")
        }
        lines.append("")

        lines.append("## Next Actions (Suggested)")
        for action in nextActions {
            lines.append("- \(action)")
        }

        return lines
    }

    private func safeText(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmed
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func readTextFile(at url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text.trimmed
    }

    private func appearsToBeUnfilledProjectSummaryTemplate(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("- what this project is:") &&
            lower.contains("- primary user outcome:") &&
            lower.contains("- current goals:") &&
            lower.contains("- constraints / non-goals:") &&
            lower.contains("- definition of done:")
    }

    private func operatorSummary(
        projectName: String,
        manifests: [SnapshotManifest],
        continuityHasTrustedRollbackAnchor: Bool
    ) -> String {
        let total = manifests.count
        let verified = manifests.filter { $0.proofVerificationStatus == .verified }.count
        let unverified = manifests.filter { $0.proofVerificationStatus == .unverified }.count
        let broken = manifests.filter { $0.proofVerificationStatus == .broken }.count
        let highRisk = manifests.filter { $0.notes.riskLevel == .high }.count
        let latest = manifests.first
        let latestTitle = latest?.notes.title ?? "Unknown"
        let anchorNote = continuityHasTrustedRollbackAnchor
            ? "Trusted Rollback anchor exists."
            : "No Trusted Rollback anchor is present yet."

        return """
        \(projectName) currently has \(total) timeline entries. Proof posture is \(verified) Verified / \(unverified) Unverified / \(broken) Broken, with \(highRisk) high-risk snapshots. Latest activity is "\(latestTitle)". \(anchorNote) Treat verified sacred landmarks as primary rollback safety and avoid relying on unverified quick saves for recovery decisions.
        """
    }

    private func safestRollbackCandidate(in manifests: [SnapshotManifest]) -> SnapshotManifest? {
        let archived = manifests.filter { $0.archivePrunedAt == nil }

        if let trusted = archived.first(where: {
            $0.notes.snapshotType == .trustedRollback &&
            $0.proofVerificationStatus == .verified &&
            $0.proofVerificationMode == .archive
        }) {
            return trusted
        }

        if let sacred = archived.first(where: {
            $0.notes.snapshotType.isSacredLandmark &&
            $0.proofVerificationStatus == .verified
        }) {
            return sacred
        }

        return archived.first
    }

    private func rollbackCandidateReason(for manifest: SnapshotManifest) -> String {
        if manifest.notes.snapshotType == .trustedRollback &&
            manifest.proofVerificationStatus == .verified &&
            manifest.proofVerificationMode == .archive {
            return "Trusted Rollback with Verified Archive Proof."
        }
        if manifest.notes.snapshotType.isSacredLandmark && manifest.proofVerificationStatus == .verified {
            return "Verified sacred landmark fallback."
        }
        return "Most recent archive-available snapshot fallback."
    }

    private func continuityWindow(from manifests: [SnapshotManifest]) -> [SnapshotManifest] {
        guard let rollbackIndex = manifests.firstIndex(where: { $0.notes.snapshotType == .trustedRollback }) else {
            return Array(manifests.prefix(12))
        }
        return Array(manifests.prefix(rollbackIndex + 1))
    }

    private func likelyRegressionPoints(in manifests: [SnapshotManifest]) -> [SnapshotManifest] {
        manifests
            .filter { manifest in
                let risky = manifest.notes.riskLevel == .high
                let weakOutcome = manifest.notes.outcome == .partial || manifest.notes.outcome == .reverted
                let weakProof = manifest.proofVerificationStatus == .broken || manifest.proofVerificationStatus == .unverified
                return risky || weakOutcome || weakProof
            }
            .sorted { lhs, rhs in
                regressionScore(lhs) > regressionScore(rhs)
            }
    }

    private func regressionScore(_ manifest: SnapshotManifest) -> Int {
        var score = 0
        if manifest.notes.riskLevel == .high { score += 5 }
        if manifest.proofVerificationStatus == .broken { score += 4 }
        if manifest.proofVerificationStatus == .unverified { score += 2 }
        if manifest.notes.outcome == .reverted { score += 4 }
        if manifest.notes.outcome == .partial { score += 3 }
        if manifest.notes.snapshotType.isSacredLandmark { score += 2 }
        return score
    }

    private func latestRestoreDrillEvidence(in text: String, maxCount: Int) -> [String] {
        let excluded = [
            "# restore_drills",
            "restore drill history with outcomes, notes, and follow-up issues."
        ]

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
            .filter { line in
                !excluded.contains(where: { line.lowercased() == $0 })
            }
            .filter { $0.hasPrefix("-") }
            .map { String($0.dropFirst()).trimmed }

        let evidence = lines.suffix(maxCount)
        return Array(evidence.reversed())
    }

    private func handoffNextActions(
        manifests: [SnapshotManifest],
        risks: [SnapshotManifest],
        hasFilledProjectSummary: Bool
    ) -> [String] {
        var actions: [String] = []

        if !hasFilledProjectSummary {
            actions.append("Fill PROJECT_SUMMARY.md with concrete goals, user outcome, and definition of done before next major changes.")
        }

        if manifests.contains(where: { $0.notes.snapshotType == .trustedRollback }) == false {
            actions.append("Capture a Trusted Rollback snapshot and verify it with Archive Proof to establish a real continuity anchor.")
        }

        if risks.contains(where: { $0.proofVerificationStatus == .unverified || $0.proofVerificationStatus == .broken }) {
            actions.append("Verify the most recent high-signal landmarks (Milestone/RC/Release) so restore decisions rely on Verified proof.")
        }

        actions.append("Run and log a restore drill against the current rollback candidate, then confirm recovery steps still match real workflow.")
        return Array(actions.prefix(3))
    }

    private func latestNonEmptyLines(in text: String, maxCount: Int) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
            .suffix(maxCount)
            .reversed()
    }

    private func derivePruneReason(for manifest: SnapshotManifest, in manifests: [SnapshotManifest]) -> String {
        if manifest.notes.snapshotType == .preChange {
            return "Pre-change noise"
        }

        let hasNewerVerifiedMilestone = manifests.contains { other in
            other.id != manifest.id &&
            other.createdAt > manifest.createdAt &&
            other.notes.snapshotType.isSacredLandmark &&
            other.proofVerificationStatus == .verified
        }
        if hasNewerVerifiedMilestone {
            return "Superseded by Verified landmark"
        }

        if manifest.proofVerificationStatus != .verified {
            return "Low importance + Unverified"
        }

        return "Superseded by newer snapshots"
    }

    private func lockArchiveIfNeeded(archiveURL: URL, snapshotType: SnapshotType) throws -> Bool {
        _ = archiveURL
        return snapshotType == .releaseCandidate || snapshotType == .release
    }

    private func isArchiveImmutableOnDisk(_ archiveURL: URL) -> Bool {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: archiveURL.path)) ?? [:]
        if let immutable = attrs[.immutable] as? Bool {
            return immutable
        }
        if let immutable = attrs[.immutable] as? NSNumber {
            return immutable.boolValue
        }
        return false
    }

    private func migrateArchiveProtectionModel(layout: ProjectLayout, manifests: [SnapshotManifest]) throws -> [SnapshotManifest] {
        var normalized = manifests
        for index in normalized.indices {
            var manifest = normalized[index]
            let archiveURL = layout.ungitURL.appendingPathComponent(manifest.archiveRelativePath, isDirectory: false)

            if isArchiveImmutableOnDisk(archiveURL) {
                try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: archiveURL.path)
            }

            let shouldBeProtected = manifest.notes.snapshotType == .releaseCandidate || manifest.notes.snapshotType == .release
            if (manifest.archiveLocked ?? false) != shouldBeProtected {
                manifest.archiveLocked = shouldBeProtected
                _ = try manifestStore.save(manifest, at: layout)
            }

            normalized[index] = manifest
        }
        return normalized
    }

    private func captureProjectSizeMetrics(projectURL: URL) throws -> ProjectSizeMetrics {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            return ProjectSizeMetrics(fileCount: 0, codeSizeApproxLines: 0)
        }

        var fileCount = 0
        var codeLineCount = 0

        for case let itemURL as URL in enumerator {
            let relative = itemURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
            if shouldExclude(relativePath: relative) {
                enumerator.skipDescendants()
                continue
            }

            let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            if values.isDirectory == true {
                continue
            }

            guard values.isRegularFile == true else { continue }
            fileCount += 1

            let ext = itemURL.pathExtension.lowercased()
            guard codeFileExtensions.contains(ext) else { continue }
            if let size = values.fileSize, size > maxCodeFileSizeBytes { continue }

            if let data = try? Data(contentsOf: itemURL),
               let text = String(data: data, encoding: .utf8) {
                codeLineCount += text.split(whereSeparator: \.isNewline).count
            }
        }

        return ProjectSizeMetrics(fileCount: fileCount, codeSizeApproxLines: codeLineCount)
    }

    private func shouldExclude(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map { $0.lowercased() }
        return components.contains(where: { excludedDirectoryNames.contains($0) })
    }

    private func runProofChecks(projectURL: URL, manifest: SnapshotManifest, mode: ProofVerificationMode) throws -> (executedChecks: Bool, success: Bool, details: String) {
        switch mode {
        case .lightweight:
            return try runLightweightProofChecks(projectURL: projectURL, manifest: manifest)
        case .archive:
            return try runArchiveProofChecks(projectURL: projectURL, manifest: manifest)
        }
    }

    private func runLightweightProofChecks(projectURL: URL, manifest: SnapshotManifest) throws -> (executedChecks: Bool, success: Bool, details: String) {
        let command = manifest.notes.proofCommand.trimmed
        var checkResults: [(name: String, result: CommandResult)] = []

        if !command.isEmpty {
            let result = try processRunner.runCapturing("/bin/zsh", ["-lc", command], currentDirectoryURL: projectURL)
            checkResults.append(("proof_command", result))
        } else {
            let packageURL = projectURL.appendingPathComponent("Package.swift", isDirectory: false)
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                return (false, false, "No proof command or Package.swift found for lightweight proof.")
            }
            let result = try processRunner.runCapturing("/bin/zsh", ["-lc", "swift build"], currentDirectoryURL: projectURL)
            checkResults.append(("swift_build", result))
        }

        let success = checkResults.allSatisfy { $0.result.exitCode == 0 }
        let details = renderProofDetails(
            mode: .lightweight,
            context: "Proof executed against current project state at \(projectURL.path).",
            checks: checkResults
        )
        return (!checkResults.isEmpty, success, details)
    }

    private func runArchiveProofChecks(projectURL: URL, manifest: SnapshotManifest) throws -> (executedChecks: Bool, success: Bool, details: String) {
        let layout = ProjectLayout(projectURL: projectURL)
        let archiveURL = layout.ungitURL.appendingPathComponent(manifest.archiveRelativePath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            return (false, false, "Archive Proof failed: snapshot archive is missing at \(manifest.archiveRelativePath).")
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ungit-proof-archive-\(manifest.id)-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let replayProjectURL = try archiveService.extractSnapshotArchive(archiveURL: archiveURL, destinationURL: tempRoot)
        let command = manifest.notes.proofCommand.trimmed
        var checkResults: [(name: String, result: CommandResult)] = []

        let packageURL = replayProjectURL.appendingPathComponent("Package.swift", isDirectory: false)
        if FileManager.default.fileExists(atPath: packageURL.path) {
            let buildResult = try processRunner.runCapturing("/bin/zsh", ["-lc", "swift build"], currentDirectoryURL: replayProjectURL)
            checkResults.append(("swift_build", buildResult))

            let testResult = try processRunner.runCapturing("/bin/zsh", ["-lc", "swift test"], currentDirectoryURL: replayProjectURL)
            checkResults.append(("swift_test", testResult))
        }

        if !command.isEmpty {
            let cmdResult = try processRunner.runCapturing("/bin/zsh", ["-lc", command], currentDirectoryURL: replayProjectURL)
            checkResults.append(("proof_command", cmdResult))
        }

        guard !checkResults.isEmpty else {
            return (false, false, "Archive Proof found no runnable checks (no Package.swift and no proof command).")
        }

        let success = checkResults.allSatisfy { $0.result.exitCode == 0 }
        let details = renderProofDetails(
            mode: .archive,
            context: "Proof executed by archived snapshot replay in isolated temp workspace: \(replayProjectURL.path). Archive and live project were not modified.",
            checks: checkResults
        )
        return (true, success, details)
    }

    private func renderProofDetails(
        mode: ProofVerificationMode,
        context: String,
        checks: [(name: String, result: CommandResult)]
    ) -> String {
        var lines: [String] = [
            "Proof Mode: \(mode.rawValue)",
            context
        ]

        for item in checks {
            let statusText = item.result.exitCode == 0 ? "PASS" : "FAIL(\(item.result.exitCode))"
            lines.append("[\(statusText)] \(item.name)")
            if !item.result.output.trimmed.isEmpty {
                lines.append(item.result.output.trimmed)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func detectAutoFilesTouched(projectURL: URL, since date: Date?) throws -> [String] {
        guard let date else { return [] }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var touched: [String] = []
        let ungitPrefix = projectURL.appendingPathComponent(".ungit", isDirectory: true).path + "/"

        for case let fileURL as URL in enumerator {
            if fileURL.path.hasPrefix(ungitPrefix) {
                enumerator.skipDescendants()
                continue
            }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true, let modifiedAt = values.contentModificationDate else { continue }
            guard modifiedAt >= date else { continue }

            let relative = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
            touched.append(relative)
        }

        return touched.sorted()
    }
}
