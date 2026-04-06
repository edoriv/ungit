import Foundation
import Combine

enum PromptCommandExecutionResult {
    case notACommand
    case info(report: String)
    case quickSaved(snapshotID: String, title: String)
    case verification(report: String)
    case handoffRequested
    case reviewDraft(SnapshotDraft)
    case memoryAdded(type: MemoryFileType, entryID: String)
    case restoreRequested(snapshotID: String, title: String)
    case preflight(report: String)
    case prune(report: String)
    case failed
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projectURL: URL?
    @Published var project: ProjectMetadata?
    @Published var timeline: [TimelineEntry] = []
    @Published var selectedEntry: TimelineEntry? {
        didSet {
            Task { await loadSelectedManifest() }
        }
    }
    @Published var selectedManifest: SnapshotManifest?
    @Published var isBusy = false
    @Published var statusMessage: String = "Choose a project folder to begin."
    @Published var errorMessage: String?
    @Published var currentStateStatus: CurrentStateStatus = .unknown
    @Published var snapshotsStorageBytes: Int64 = 0
    @Published var recentProjects: [RecentProjectItem] = []
    @Published var criticalLessonSuggestion: String?
    @Published var shouldPromptForProjectSummary: Bool = false
    @Published var projectSummaryDraft: String = ""
    @Published var checkpointReminderMessage: String?
    @Published var latestPublishPreflight: RemotePublishPreflight?

    private let initializer = ProjectInitializer()
    private let snapshotService = SnapshotService()
    private let restoreService = RestoreSafetyService()
    private let notesDraftService = NotesDraftService()
    private let currentStateService = CurrentStateService()
    private let memoryService = ProjectMemoryService()
    private let archiveService = ArchiveService()
    private let extractedProjectValidator = ExtractedProjectValidator()
    private let manifestsWatcher = DirectoryChangeWatcher()
    private let projectWatcher = DirectoryChangeWatcher()
    private var watcherReloadTask: Task<Void, Never>?
    private var stateReloadTask: Task<Void, Never>?
    private var lastRestoreAt: Date?
    private var lastSuggestedEntryID: String?
    private var projectChangeEventCount: Int = 0
    private var lastCheckpointReminderSnapshotID: String?
    private static let recentProjectsKey = "ungit.recentProjects"
    private let checkpointReminderEventThreshold = 24
    private let checkpointReminderRecentSnapshotGrace: TimeInterval = 15 * 60

    init() {
        recentProjects = Self.loadRecentProjects()
    }

    func openProject(at url: URL) async {
        await runOperation {
            let wasAlreadyInitialized = FileManager.default.fileExists(
                atPath: ProjectLayout(projectURL: url).projectMetadataURL.path
            )
            let metadata = try initializer.initializeProjectIfNeeded(at: url)
            projectURL = url
            project = metadata
            addRecentProject(url.path)
            statusMessage = "Project ready: \(metadata.name)"
            try reloadTimelineInternal()
            try verifyLatestProofOnOpen(projectURL: url)
            startManifestWatcher(for: url)
            startProjectStateWatcher(for: url)
            projectChangeEventCount = 0
            lastCheckpointReminderSnapshotID = nil
            checkpointReminderMessage = nil

            if !wasAlreadyInitialized {
                projectSummaryDraft = buildInitialProjectSummaryTemplate(projectName: metadata.name)
                shouldPromptForProjectSummary = true
                statusMessage = "Project ready: \(metadata.name). Add Project Summary / Goals to set the home base."
            } else {
                shouldPromptForProjectSummary = false
            }
        }
    }

    func openRecentProject(path: String) async {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        await openProject(at: url)
    }

    func openMostRecentProjectIfAvailable() async {
        guard projectURL == nil else { return }
        guard let path = recentProjects.first?.path else { return }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            removeRecentProject(path)
            return
        }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        await openProject(at: url)
    }

    func reloadTimeline() async {
        await runOperation {
            try reloadTimelineInternal()
        }
    }

    func draftFromShortInput(_ text: String) -> SnapshotDraft {
        notesDraftService.buildDraft(from: text, pathName: project?.currentPathName ?? "main")
    }

    func executePromptCommandIfPresent(_ input: String) async -> PromptCommandExecutionResult {
        guard let command = notesDraftService.parseCommand(from: input) else {
            return .notACommand
        }

        switch command {
        case .inspectRemoteChanges(let id):
            var report = ""

            await runOperation {
                guard let projectURL else { throw AppError.invalidProjectPath }
                guard let entry = timeline.first(where: { $0.id.uppercased() == id.uppercased() }) else {
                    throw AppError.commandFailed("Snapshot \(id) was not found.")
                }

                let review = try snapshotService.createRemoteCorrectionReview(
                    projectURL: projectURL,
                    milestoneSnapshotID: entry.id,
                    requestedBy: "Codex"
                )
                try reloadTimelineInternal()
                selectedEntry = timeline.first(where: { $0.id == review.id }) ?? selectedEntry
                report = "Remote Correction Review created: \(review.id) linked to milestone \(entry.id)."
                statusMessage = report
            }

            if !report.isEmpty {
                return .info(report: report)
            }
            return .failed
        case .publishMilestone(let id):
            var report = ""

            await runOperation {
                guard let projectURL else { throw AppError.invalidProjectPath }
                guard let entry = timeline.first(where: { $0.id.uppercased() == id.uppercased() }) else {
                    throw AppError.commandFailed("Snapshot \(id) was not found.")
                }

                latestPublishPreflight = try snapshotService.publishPreflight(projectURL: projectURL, snapshotID: entry.id)
                let remote = try snapshotService.publishMilestone(
                    projectURL: projectURL,
                    snapshotID: entry.id,
                    requestedBy: "Codex",
                    approvedBy: "human"
                )
                try reloadTimelineInternal()
                guard let updated = timeline.first(where: { $0.id == entry.id }) else {
                    throw AppError.commandFailed("Published milestone \(entry.id), but timeline refresh could not find the updated entry.")
                }
                selectedEntry = updated
                report = "Milestone published: \(updated.id) on \(remote.branchName ?? "unknown-branch") @ \(remote.commitSHA?.prefix(7) ?? "no-sha")."
                statusMessage = report
            }

            if !report.isEmpty {
                return .info(report: report)
            }
            return .failed
        case .showRemoteStatus(let id):
            guard let entry = timeline.first(where: { $0.id.uppercased() == id.uppercased() }) else {
                errorMessage = "Snapshot \(id) was not found."
                return .failed
            }
            selectedEntry = entry
            let remote = selectedManifest?.remoteMetadata
            let state = remote?.publishState.rawValue ?? entry.remotePublishState.rawValue
            let branch = remote?.branchName ?? "Not Recorded"
            let sha = remote?.commitSHA ?? "Not Recorded"
            let report = "Remote status for \(entry.id): \(state). Branch: \(branch). Commit: \(sha)."
            statusMessage = report
            return .info(report: report)
        case .showTimeline:
            do {
                try reloadTimelineInternal()
                guard let latest = timeline.first else {
                    let report = "Timeline is empty."
                    statusMessage = report
                    return .info(report: report)
                }
                let report = "Timeline entries: \(timeline.count). Latest: \(latest.id) — \(latest.title)."
                statusMessage = report
                return .info(report: report)
            } catch {
                errorMessage = error.localizedDescription
                return .failed
            }
        case .showSnapshot(let id):
            guard let entry = timeline.first(where: { $0.id.uppercased() == id.uppercased() }) else {
                errorMessage = "Snapshot \(id) was not found."
                return .failed
            }
            selectedEntry = entry
            let report = "Showing snapshot \(entry.id): \(entry.title) [\(entry.snapshotType.rawValue) / \(entry.status.rawValue)]."
            statusMessage = report
            return .info(report: report)
        case .verifySnapshot(let id, let requestedMode):
            var report = ""

            await runOperation {
                guard let projectURL else { throw AppError.invalidProjectPath }
                guard let entry = timeline.first(where: { $0.id.uppercased() == id.uppercased() }) else {
                    throw AppError.commandFailed("Snapshot \(id) was not found.")
                }

                let mode = requestedMode ?? (entry.snapshotType.prefersArchiveProof ? .archive : .lightweight)
                let executed = try snapshotService.verifyProof(projectURL: projectURL, entryID: entry.id, mode: mode)
                guard executed else {
                    throw AppError.commandFailed("Proof did not execute for snapshot \(entry.id).")
                }

                try reloadTimelineInternal()
                guard let updated = timeline.first(where: { $0.id == entry.id }) else {
                    throw AppError.commandFailed("Verified snapshot \(entry.id), but timeline refresh could not find the updated entry.")
                }
                selectedEntry = updated
                let state = selectedManifest?.proofVerificationStatus.rawValue ?? updated.proofVerificationStatus.rawValue
                report = "Proof completed for \(updated.id): \(state) (\(mode.rawValue))."
                statusMessage = report
            }

            if !report.isEmpty {
                return .verification(report: report)
            }
            return .failed
        case .verifyLatest(let kind, let requestedMode):
            var report = ""

            await runOperation {
                guard let projectURL else { throw AppError.invalidProjectPath }
                guard let entry = latestEntryForVerification(kind: kind) else {
                    throw AppError.commandFailed("No matching snapshot found to verify.")
                }

                let mode = requestedMode ?? (entry.snapshotType.prefersArchiveProof ? .archive : .lightweight)
                let executed = try snapshotService.verifyProof(projectURL: projectURL, entryID: entry.id, mode: mode)
                guard executed else {
                    throw AppError.commandFailed("Proof did not execute for snapshot \(entry.id).")
                }

                try reloadTimelineInternal()
                guard let updated = timeline.first(where: { $0.id == entry.id }) else {
                    throw AppError.commandFailed("Verified snapshot \(entry.id), but timeline refresh could not find the updated entry.")
                }
                selectedEntry = updated
                let state = selectedManifest?.proofVerificationStatus.rawValue ?? updated.proofVerificationStatus.rawValue
                report = "Proof completed for latest \(verificationKindLabel(kind)): \(updated.id) \(state) (\(mode.rawValue))."
                statusMessage = report
            }

            if !report.isEmpty {
                return .verification(report: report)
            }
            return .failed
        case .handoff:
            statusMessage = "Handoff requested. Choose a save location to export."
            return .handoffRequested
        case .restoreLatestTrustedRollback:
            guard let entry = timeline.first(where: { $0.snapshotType == .trustedRollback }) else {
                errorMessage = "No Trusted Rollback snapshot found."
                return .failed
            }
            selectedEntry = entry
            if let projectURL {
                do {
                    _ = try restoreService.requestRestoreApproval(projectURL: projectURL, entry: entry, requestedBy: "prompt-command")
                } catch {
                    errorMessage = error.localizedDescription
                    return .failed
                }
            }
            statusMessage = "Restore requested for \(entry.id). Approval required before execution."
            return .restoreRequested(snapshotID: entry.id, title: entry.title)
        case .restoreSnapshot(let id):
            guard let entry = timeline.first(where: { $0.id.uppercased() == id.uppercased() }) else {
                errorMessage = "Snapshot \(id) was not found."
                return .failed
            }
            selectedEntry = entry
            if let projectURL {
                do {
                    _ = try restoreService.requestRestoreApproval(projectURL: projectURL, entry: entry, requestedBy: "prompt-command")
                } catch {
                    errorMessage = error.localizedDescription
                    return .failed
                }
            }
            statusMessage = "Restore requested for \(entry.id). Approval required before execution."
            return .restoreRequested(snapshotID: entry.id, title: entry.title)
        case .reviewCriticalLesson:
            return .reviewDraft(draftCriticalLesson())
        case .review(let title):
            let raw = title?.trimmed ?? "Review Save"
            let draft = notesDraftService.buildDraft(from: raw, pathName: project?.currentPathName ?? "main")
            return .reviewDraft(draft)
        case .forkPoint(let title):
            var savedID = ""
            var savedTitle = ""

            await runOperation {
                guard let projectURL, let project else { throw AppError.invalidProjectPath }
                let draft = notesDraftService.buildForkPointDraft(
                    providedTitle: title,
                    pathName: project.currentPathName
                )
                let entry = try persistSnapshot(draft: draft, projectURL: projectURL, project: project, automatic: false)
                savedID = entry.id
                savedTitle = entry.title
                statusMessage = "Fork Point saved: \(entry.id) — \(entry.title)"
            }

            if !savedID.isEmpty {
                return .quickSaved(snapshotID: savedID, title: savedTitle)
            }
            return .failed
        case .pruneSnapshots(let apply):
            var report = ""

            await runOperation {
                guard let projectURL else { throw AppError.invalidProjectPath }
                let result = try snapshotService.pruneSnapshotArchives(
                    projectURL: projectURL,
                    keepRecentNonMajor: 10,
                    apply: apply
                )

                snapshotsStorageBytes = result.totalBytesAfter
                let modeText = result.dryRun ? "Prune Preview" : "Prune Complete"
                let failuresText = result.failedArchives > 0
                    ? " \(result.failedArchives) archive(s) could not be pruned."
                    : ""
                report = "\(modeText): \(result.prunedArchives) archive(s), reclaimed \(formatBytes(result.reclaimedBytes)). Size \(formatBytes(result.totalBytesBefore)) → \(formatBytes(result.totalBytesAfter)). Kept all sacred landmarks/rollbacks and latest \(result.keepRecentNonMajor) non-major snapshots.\(failuresText)"
                statusMessage = report
                try reloadTimelineInternal()
            }

            if !report.isEmpty {
                return .prune(report: report)
            }
            return .failed
        case .pruneSnapshot(let id, let apply):
            var report = ""

            await runOperation {
                guard let projectURL else { throw AppError.invalidProjectPath }
                let result = try snapshotService.pruneSnapshotArchive(
                    projectURL: projectURL,
                    snapshotID: id,
                    apply: apply
                )

                snapshotsStorageBytes = result.totalBytesAfter
                let modeText = result.dryRun ? "Prune Snapshot Preview" : "Prune Snapshot Complete"
                report = "\(modeText): \(result.snapshotID) [\(result.snapshotType.rawValue)] \"\(result.title)\". \(result.note) Reclaim \(formatBytes(result.reclaimedBytes)). Size \(formatBytes(result.totalBytesBefore)) → \(formatBytes(result.totalBytesAfter))."
                statusMessage = report
                try reloadTimelineInternal()
            }

            if !report.isEmpty {
                return .prune(report: report)
            }
            return .failed
        case .preflightRestore:
            var report = ""

            await runOperation {
                guard let projectURL else { throw AppError.invalidProjectPath }
                let layout = ProjectLayout(projectURL: projectURL)
                let loaded = try ManifestStore().loadAllManifestsWithIssues(at: layout)
                let targetEntry = selectedEntry
                    ?? timeline.first(where: { $0.snapshotType == .trustedRollback })
                    ?? timeline.first

                guard let targetEntry else {
                    throw AppError.commandFailed("No snapshots available for restore preflight.")
                }

                let archiveURL = layout.ungitURL.appendingPathComponent(targetEntry.archiveRelativePath, isDirectory: false)
                let archiveExists = FileManager.default.fileExists(atPath: archiveURL.path)
                guard archiveExists else {
                    throw AppError.commandFailed("Restore preflight failed: missing archive for snapshot \(targetEntry.id).")
                }

                let tempURL = layout.tempURL.appendingPathComponent("restore-preflight-ui-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                let extractedRoot = try archiveService.extractSnapshotArchive(archiveURL: archiveURL, destinationURL: tempURL)
                try extractedProjectValidator.validateProjectTree(at: extractedRoot)

                report = "Preflight OK for \(targetEntry.id). Archive validates. Manifest issues observed: \(loaded.issues.count)."
                statusMessage = report
            }

            if !report.isEmpty {
                return .preflight(report: report)
            }
            return .failed
        case .addMemory(let type, let title):
            var createdID = ""

            await runOperation {
                guard let projectURL else { throw AppError.invalidProjectPath }
                guard let text = title?.trimmed, !text.isEmpty else {
                let label: String
                switch type {
                case .summary: label = "summary"
                case .bugs: label = "bug"
                case .ideas: label = "idea"
                case .todo: label = "todo"
                case .park: label = "park"
                }
                    throw AppError.commandFailed("Title is required. Use: UNGIT add \(label): <title>")
                }

                createdID = try memoryService.appendEntry(
                    type: type,
                    projectURL: projectURL,
                    title: text,
                    details: "Captured from UNGIT command.",
                    linkedSnapshotID: selectedEntry?.id,
                    linkedMemoryIDs: []
                )
                statusMessage = "\(type.idPrefix) entry added: \(createdID)"
            }

            if !createdID.isEmpty {
                return .memoryAdded(type: type, entryID: createdID)
            }
            return .failed
        case .parkUpdate(let text):
            var createdID = ""

            await runOperation {
                guard let projectURL else { throw AppError.invalidProjectPath }
                let noteText = text?.trimmed ?? ""
                guard !noteText.isEmpty else {
                    throw AppError.commandFailed("Park text is required. Use: UNGIT park: <note>")
                }

                createdID = try memoryService.appendEntry(
                    type: .park,
                    projectURL: projectURL,
                    title: "Park Update",
                    details: noteText,
                    linkedSnapshotID: selectedEntry?.id,
                    linkedMemoryIDs: []
                )
                statusMessage = "PARK entry added: \(createdID)"
            }

            if !createdID.isEmpty {
                return .memoryAdded(type: .park, entryID: createdID)
            }
            return .failed
        case .quick(let kind, let title):
            var savedID = ""
            var savedTitle = ""

            await runOperation {
                guard let projectURL, let project else { throw AppError.invalidProjectPath }
                let draft = notesDraftService.buildQuickDraft(
                    kind: kind,
                    providedTitle: title,
                    pathName: project.currentPathName
                )
                let entry = try persistSnapshot(draft: draft, projectURL: projectURL, project: project, automatic: false)
                savedID = entry.id
                savedTitle = entry.title
                statusMessage = "Snapshot saved: \(entry.id) — \(entry.title)"
            }

            if !savedID.isEmpty {
                return .quickSaved(snapshotID: savedID, title: savedTitle)
            }
            return .failed
        }
    }

    func saveSnapshot(draft: SnapshotDraft, automatic: Bool = false) async {
        await runOperation {
            guard let projectURL, let project else { throw AppError.invalidProjectPath }
            _ = try persistSnapshot(draft: draft, projectURL: projectURL, project: project, automatic: automatic)

            statusMessage = automatic ? "Automatic safety snapshot saved." : "Snapshot saved."
        }
    }

    func consumeCheckpointReminder() {
        checkpointReminderMessage = nil
    }

    func saveQuickSnapshot(type: SnapshotType, title: String) async {
        var draft = SnapshotDraft.empty(pathName: project?.currentPathName ?? "main")
        draft.title = title
        draft.summary = title
        draft.snapshotType = type
        draft.status = quickStatus(for: type)
        await saveSnapshot(draft: draft)
    }

    func saveQuickMilestoneAndPublish(title: String = "Milestone") async {
        await runOperation {
            guard let projectURL, let project else { throw AppError.invalidProjectPath }

            var draft = SnapshotDraft.empty(pathName: project.currentPathName)
            draft.title = title
            draft.summary = title
            draft.snapshotType = .milestone
            draft.status = .trusted
            draft.riskLevel = .low

            let entry = try persistSnapshot(draft: draft, projectURL: projectURL, project: project, automatic: false)
            do {
                latestPublishPreflight = try snapshotService.publishPreflight(projectURL: projectURL, snapshotID: entry.id)
                let remote = try snapshotService.publishMilestone(
                    projectURL: projectURL,
                    snapshotID: entry.id,
                    requestedBy: "human",
                    approvedBy: "human"
                )

                try reloadTimelineInternal()
                selectedEntry = timeline.first(where: { $0.id == entry.id }) ?? selectedEntry
                statusMessage = "Milestone saved and published: \(entry.id) — \(remote.commitSHA?.prefix(7) ?? "no-sha")"
            } catch {
                try reloadTimelineInternal()
                selectedEntry = timeline.first(where: { $0.id == entry.id }) ?? selectedEntry
                statusMessage = "Milestone saved locally, but publish failed for \(entry.id)."
                throw error
            }
        }
    }

    func publishSelectedMilestone() async {
        await runOperation {
            guard let projectURL, let entry = selectedEntry else {
                throw AppError.snapshotNotFound
            }

            do {
                latestPublishPreflight = try snapshotService.publishPreflight(projectURL: projectURL, snapshotID: entry.id)
                let remote = try snapshotService.publishMilestone(
                    projectURL: projectURL,
                    snapshotID: entry.id,
                    requestedBy: "human",
                    approvedBy: "human"
                )

                try reloadTimelineInternal()
                selectedEntry = timeline.first(where: { $0.id == entry.id }) ?? selectedEntry
                statusMessage = "Milestone published: \(entry.id) — \(remote.commitSHA?.prefix(7) ?? "no-sha")"
            } catch {
                try reloadTimelineInternal()
                selectedEntry = timeline.first(where: { $0.id == entry.id }) ?? selectedEntry
                statusMessage = "Publish failed for milestone \(entry.id)."
                throw error
            }
        }
    }

    func inspectRemoteChangesForSelectedMilestone() async {
        await runOperation {
            guard let projectURL, let entry = selectedEntry else {
                throw AppError.snapshotNotFound
            }

            let review = try snapshotService.createRemoteCorrectionReview(
                projectURL: projectURL,
                milestoneSnapshotID: entry.id,
                requestedBy: "human"
            )
            try reloadTimelineInternal()
            selectedEntry = timeline.first(where: { $0.id == review.id }) ?? selectedEntry
            statusMessage = "Remote Correction Review created: \(review.id)"
        }
    }

    func restoreSelectedSnapshot(approvalToken: String) async {
        await runOperation {
            guard let entry = selectedEntry, let projectURL, let project else {
                throw AppError.snapshotNotFound
            }

            try restoreService.consumeRestoreApproval(
                projectURL: projectURL,
                snapshotID: entry.id,
                token: approvalToken,
                consumedBy: "ui"
            )

            try restoreService.restoreSnapshot(
                projectURL: projectURL,
                entry: entry,
                project: project,
                snapshotService: snapshotService
            )

            lastRestoreAt = Date()
            statusMessage = "Restore complete: \(entry.title)"
            try reloadTimelineInternal()
            _ = try snapshotService.verifyProofIfAvailable(projectURL: projectURL, entryID: entry.id)
            try reloadTimelineInternal()
        }
    }

    func issueRestoreApprovalTokenForSelectedSnapshot(validForSeconds: TimeInterval = 180) throws -> String {
        guard let projectURL, let entry = selectedEntry else {
            throw AppError.snapshotNotFound
        }
        _ = try restoreService.requestRestoreApproval(projectURL: projectURL, entry: entry, requestedBy: "ui")
        let approved = try restoreService.approveRestore(
            projectURL: projectURL,
            snapshotID: entry.id,
            approvedBy: "ui-modal",
            validForSeconds: validForSeconds
        )
        guard let token = approved.token, !token.isEmpty else {
            throw AppError.commandFailed("Restore approval failed: token was not generated.")
        }
        return token
    }

    func cancelPendingRestoreApproval() {
        guard let projectURL else { return }
        do {
            try restoreService.cancelRestoreApproval(projectURL: projectURL, canceledBy: "ui")
            statusMessage = "Restore canceled."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportTimeline(mode: TimelineExportMode, destinationURL: URL? = nil) async {
        await runOperation {
            guard let projectURL else { throw AppError.invalidProjectPath }
            let result = try snapshotService.exportTimeline(projectURL: projectURL, mode: mode, destinationURL: destinationURL)
            statusMessage = "Timeline exported (\(result.mode.rawValue)): \(result.fileURL.path)"
        }
    }

    func defaultExportFileName(for mode: TimelineExportMode) -> String {
        snapshotService.defaultExportFileName(for: mode)
    }

    func dismissCriticalLessonSuggestion() {
        criticalLessonSuggestion = nil
    }

    func draftCriticalLesson() -> SnapshotDraft {
        notesDraftService.buildDraft(from: "UNGIT review save: capture critical lesson", pathName: project?.currentPathName ?? "main")
    }

    func loadMemoryContent(type: MemoryFileType) async -> String {
        guard let projectURL else { return "" }
        do {
            return try memoryService.read(type: type, projectURL: projectURL)
        } catch {
            errorMessage = error.localizedDescription
            return ""
        }
    }

    func saveMemoryContent(type: MemoryFileType, content: String) async {
        await runOperation {
            guard let projectURL else { throw AppError.invalidProjectPath }
            try memoryService.write(type: type, projectURL: projectURL, content: content)
            statusMessage = "\(type.title) saved."
        }
    }

    func saveProjectSummary(content: String) async {
        await runOperation {
            guard let projectURL, let project else { throw AppError.invalidProjectPath }
            let trimmed = content.trimmed
            let payload = trimmed.isEmpty
                ? buildInitialProjectSummaryTemplate(projectName: project.name)
                : trimmed + "\n"
            try memoryService.write(type: .summary, projectURL: projectURL, content: payload)

            if timeline.isEmpty {
                var baseline = SnapshotDraft.empty(pathName: project.currentPathName)
                baseline.title = "Project Summary / Goals Baseline"
                baseline.summary = "Initial project intent and goals captured for continuity."
                baseline.snapshotType = .milestone
                baseline.status = .trusted
                baseline.tagsText = "project-summary,goals,onboarding"
                baseline.whatChanged = "Captured initial PROJECT_SUMMARY.md home base for this project."
                baseline.why = "Anchor project intent early so timeline reviews can detect drift against explicit goals."
                baseline.gotchas = "Update PROJECT_SUMMARY.md when goals change to keep continuity reviews accurate."
                baseline.changeIntent = "Establish project home base and review anchor before implementation changes."
                baseline.riskLevel = .low
                _ = try persistSnapshot(draft: baseline, projectURL: projectURL, project: project, automatic: false)
            }

            shouldPromptForProjectSummary = false
            projectSummaryDraft = payload
            statusMessage = "Project Summary saved."
        }
    }

    func deferProjectSummaryPrompt() {
        shouldPromptForProjectSummary = false
        statusMessage = "Project summary prompt dismissed for now."
    }

    func addMemoryEntry(
        type: MemoryFileType,
        title: String,
        details: String,
        linkedSnapshotID: String?,
        linkedMemoryIDsText: String
    ) async {
        await runOperation {
            guard let projectURL else { throw AppError.invalidProjectPath }
            let linkedMemoryIDs = linkedMemoryIDsText
                .split(separator: ",")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty }

            let entryID = try memoryService.appendEntry(
                type: type,
                projectURL: projectURL,
                title: title,
                details: details,
                linkedSnapshotID: linkedSnapshotID,
                linkedMemoryIDs: linkedMemoryIDs
            )
            statusMessage = "\(type.idPrefix) entry added: \(entryID)"
        }
    }

    private func loadSelectedManifest() async {
        guard let entry = selectedEntry, let projectURL else {
            selectedManifest = nil
            return
        }

        do {
            selectedManifest = try snapshotService.loadManifest(projectURL: projectURL, entry: entry)
        } catch {
            selectedManifest = nil
            errorMessage = error.localizedDescription
        }
    }

    private func reloadTimelineInternal() throws {
        guard let projectURL else { throw AppError.invalidProjectPath }
        timeline = try snapshotService.loadTimeline(projectURL: projectURL)
        snapshotsStorageBytes = snapshotService.snapshotArchiveStorageBytes(projectURL: projectURL)

        if let selected = selectedEntry,
           !timeline.contains(where: { $0.id == selected.id }) {
            selectedEntry = nil
        }

        if selectedEntry == nil {
            selectedEntry = timeline.first
        }

        updateCriticalLessonSuggestion()

        refreshCurrentState()
    }

    private func runOperation(_ operation: () throws -> Void) async {
        isBusy = true
        defer { isBusy = false }

        do {
            errorMessage = nil
            try operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func quickStatus(for type: SnapshotType) -> SnapshotStatus {
        switch type {
        case .milestone, .releaseCandidate, .release:
            return .trusted
        case .trustedRollback:
            return .rollbackPoint
        case .experiment:
            return .experimental
        default:
            return .working
        }
    }

    private func persistSnapshot(
        draft: SnapshotDraft,
        projectURL: URL,
        project: ProjectMetadata,
        automatic: Bool
    ) throws -> TimelineEntry {
        let defaultTitle = automatic ? "Automatic Snapshot" : "Snapshot"
        let notes = draft.toNotes(defaultTitle: defaultTitle)
        let entry = try snapshotService.saveSnapshot(
            projectURL: projectURL,
            project: project,
            notes: notes,
            isAutomaticSafetySnapshot: automatic
        )
        projectChangeEventCount = 0
        lastCheckpointReminderSnapshotID = nil
        checkpointReminderMessage = nil
        try reloadTimelineInternal()
        return entry
    }

    private func startManifestWatcher(for projectURL: URL) {
        manifestsWatcher.stop()
        watcherReloadTask?.cancel()

        let manifestsURL = ProjectLayout(projectURL: projectURL).manifestsURL
        do {
            try manifestsWatcher.startWatching(directoryURL: manifestsURL) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.scheduleWatcherReload()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startProjectStateWatcher(for projectURL: URL) {
        projectWatcher.stop()
        stateReloadTask?.cancel()

        do {
            try projectWatcher.startWatching(directoryURL: projectURL) { [weak self] changedPaths in
                guard let self else { return }
                Task { @MainActor in
                    let relevant = changedPaths.filter { !$0.contains("/.ungit/") && !$0.hasSuffix("/.ungit") }
                    guard !relevant.isEmpty else { return }
                    self.projectChangeEventCount += relevant.count
                    self.scheduleStateReload()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleWatcherReload() {
        watcherReloadTask?.cancel()
        watcherReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.reloadTimelineFromWatcher()
        }
    }

    private func scheduleStateReload() {
        stateReloadTask?.cancel()
        stateReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.refreshCurrentStateFromWatcher()
        }
    }

    private func reloadTimelineFromWatcher() async {
        guard let projectURL else { return }
        do {
            let latestTimeline = try snapshotService.loadTimeline(projectURL: projectURL)
            timeline = latestTimeline
            snapshotsStorageBytes = snapshotService.snapshotArchiveStorageBytes(projectURL: projectURL)

            if let selected = selectedEntry,
               !timeline.contains(where: { $0.id == selected.id }) {
                selectedEntry = timeline.first
            } else if selectedEntry == nil {
                selectedEntry = timeline.first
            }

            updateCriticalLessonSuggestion()
            refreshCurrentState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCurrentStateFromWatcher() async {
        refreshCurrentState()
    }

    private func refreshCurrentState() {
        guard let projectURL else {
            currentStateStatus = .unknown
            return
        }

        do {
            currentStateStatus = try currentStateService.evaluate(projectURL: projectURL, timeline: timeline)
            evaluateCheckpointReminder()
        } catch {
            currentStateStatus = .unknown
        }
    }

    private func evaluateCheckpointReminder() {
        guard currentStateStatus == .notSavedSinceLastSnapshot else {
            if currentStateStatus == .matchesLatestSnapshot {
                projectChangeEventCount = 0
            }
            return
        }

        if let latest = timeline.first {
            let age = Date().timeIntervalSince(latest.createdAt)
            if age < checkpointReminderRecentSnapshotGrace {
                return
            }
        }

        guard projectChangeEventCount >= checkpointReminderEventThreshold else { return }

        let latestID = timeline.first?.id ?? "none"
        if lastCheckpointReminderSnapshotID == latestID {
            return
        }

        let suggestion: String
        if projectChangeEventCount >= checkpointReminderEventThreshold * 2 {
            suggestion = "Checkpoint reminder: many file changes detected (\(projectChangeEventCount) events). Consider `UNGIT quick pre-change` before continuing."
        } else {
            suggestion = "Checkpoint reminder: \(projectChangeEventCount) project changes detected since last snapshot. Consider `UNGIT quick save`."
        }

        checkpointReminderMessage = suggestion
        statusMessage = suggestion
        lastCheckpointReminderSnapshotID = latestID
    }

    deinit {
        watcherReloadTask?.cancel()
        stateReloadTask?.cancel()
    }

    private func addRecentProject(_ path: String) {
        var paths = recentProjects.map(\.path)
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > 12 {
            paths = Array(paths.prefix(12))
        }
        Self.saveRecentProjects(paths)
        recentProjects = paths.map { RecentProjectItem(path: $0) }
    }

    private static func loadRecentProjects() -> [RecentProjectItem] {
        let paths = UserDefaults.standard.stringArray(forKey: recentProjectsKey) ?? []
        return paths.map { RecentProjectItem(path: $0) }
    }

    private static func saveRecentProjects(_ paths: [String]) {
        UserDefaults.standard.set(paths, forKey: recentProjectsKey)
    }

    private func removeRecentProject(_ path: String) {
        let filtered = recentProjects.map(\.path).filter { $0 != path }
        Self.saveRecentProjects(filtered)
        recentProjects = filtered.map { RecentProjectItem(path: $0) }
    }

    private func updateCriticalLessonSuggestion() {
        guard let latest = timeline.first(where: { !$0.isAutomaticSafetySnapshot }) else {
            criticalLessonSuggestion = nil
            return
        }

        guard latest.id != lastSuggestedEntryID else { return }
        guard shouldSuggestCriticalLesson(for: latest) else { return }

        criticalLessonSuggestion = "This looks like a fix. Capture a critical lesson?"
        lastSuggestedEntryID = latest.id
    }

    private func shouldSuggestCriticalLesson(for entry: TimelineEntry) -> Bool {
        if entry.snapshotType == .fix { return true }

        let lower = "\(entry.title) \(entry.summary)".lowercased()
        if ["fixed", "resolved", "issue", "bug"].contains(where: { lower.contains($0) }) {
            return true
        }

        let rapidThreshold: TimeInterval = 10 * 60
        let recent = timeline.filter { !$0.isAutomaticSafetySnapshot }.prefix(3)
        if recent.count >= 3,
           let oldest = recent.last?.createdAt,
           let newest = recent.first?.createdAt,
           newest.timeIntervalSince(oldest) <= rapidThreshold {
            return true
        }

        if let restoreAt = lastRestoreAt,
           entry.createdAt >= restoreAt,
           entry.createdAt.timeIntervalSince(restoreAt) <= rapidThreshold {
            return true
        }

        return false
    }

    private func latestEntryForVerification(kind: UngitVerifyLatestKind) -> TimelineEntry? {
        switch kind {
        case .snapshot:
            return timeline.first(where: { !$0.isAutomaticSafetySnapshot })
        case .milestone:
            return timeline.first(where: { !$0.isAutomaticSafetySnapshot && $0.snapshotType == .milestone })
        case .trustedRollback:
            return timeline.first(where: { !$0.isAutomaticSafetySnapshot && $0.snapshotType == .trustedRollback })
        case .releaseCandidate:
            return timeline.first(where: { !$0.isAutomaticSafetySnapshot && $0.snapshotType == .releaseCandidate })
        case .release:
            return timeline.first(where: { !$0.isAutomaticSafetySnapshot && $0.snapshotType == .release })
        }
    }

    private func verificationKindLabel(_ kind: UngitVerifyLatestKind) -> String {
        switch kind {
        case .snapshot:
            return "snapshot"
        case .milestone:
            return "milestone"
        case .trustedRollback:
            return "trusted rollback"
        case .releaseCandidate:
            return "release candidate"
        case .release:
            return "release"
        }
    }

    private func verifyLatestProofOnOpen(projectURL: URL) throws {
        guard let latest = timeline.first(where: { !$0.isAutomaticSafetySnapshot }) else { return }
        _ = try snapshotService.verifyProofIfAvailable(projectURL: projectURL, entryID: latest.id)
    }

    private func buildInitialProjectSummaryTemplate(projectName: String) -> String {
        """
        # PROJECT SUMMARY

        Home base for project intent and goals.

        ## Project Summary Entry
        - Project: \(projectName)
        - What this project is:
        - Primary user outcome:
        - Current goals:
        - Constraints / non-goals:
        - Definition of done:
        """
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}
