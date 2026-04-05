import Foundation

public struct WriteVerificationResult {
    public var manifestExists: Bool
    public var archiveExists: Bool
    public var manifestDecoded: Bool
    public var idMatchesManifest: Bool
    public var archiveReferenceMatches: Bool

    public var allPassed: Bool {
        manifestExists && archiveExists && manifestDecoded && idMatchesManifest && archiveReferenceMatches
    }

    public func asJSON() -> JSONValue {
        .object([
            "manifest_exists": .bool(manifestExists),
            "archive_exists": .bool(archiveExists),
            "manifest_decodes": .bool(manifestDecoded),
            "id_matches_manifest": .bool(idMatchesManifest),
            "archive_reference_matches": .bool(archiveReferenceMatches)
        ])
    }
}

struct RestorePreflightResult {
    var canProceed: Bool
    var snapshotID: String?
    var archiveExists: Bool
    var archiveValid: Bool
    var manifestIssueCount: Int
    var manifestIssues: [ManifestLoadIssue]
    var notes: [String]

    func asJSON() -> JSONValue {
        .object([
            "can_proceed": .bool(canProceed),
            "snapshot_id": snapshotID.map(JSONValue.string) ?? .null,
            "archive_exists": .bool(archiveExists),
            "archive_valid": .bool(archiveValid),
            "manifest_issue_count": .number(Double(manifestIssueCount)),
            "manifest_issues": .array(manifestIssues.map {
                .object([
                    "file": .string($0.fileName),
                    "reason": .string($0.reason)
                ])
            }),
            "notes": .array(notes.map(JSONValue.string))
        ])
    }
}

public final class UngitToolRouter {
    private let initializer = ProjectInitializer()
    private let snapshotService = SnapshotService()
    private let restoreService = RestoreSafetyService()
    private let notesDraftService = NotesDraftService()
    private let jsonStore = JSONFileStore()
    private let archiveService = ArchiveService()
    private let validator = ExtractedProjectValidator()

    public init() {}

    public func toolDefinitions() -> [MCPToolDefinition] {
        [
            tool(name: "ungit_quick_save", description: "Execute a fast snapshot save.", required: ["project_path", "kind"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "kind": schemaString(
                    enumValues: ["save", "pre_change", "feature_works", "trusted_rollback", "milestone", "release_candidate", "release"],
                    description: "Quick save kind."
                ),
                "title": schemaString(description: "Optional title override."),
                "notes_hint": schemaString(description: "Optional short notes hint.")
            ]),
            tool(name: "ungit_review_save", description: "Draft or execute review-style snapshot save.", required: ["project_path"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "mode": schemaString(enumValues: ["draft", "execute"], description: "Draft or execute."),
                "title": schemaString(description: "Optional title override."),
                "instruction": schemaString(description: "Optional save instruction."),
                "capture_critical_lesson": schemaBoolean(description: "When true, uses critical lesson format.", defaultValue: false)
            ]),
            tool(name: "ungit_restore_snapshot", description: "Restore snapshot with safety snapshot flow. Requires explicit restore approval token.", required: ["project_path", "snapshot_id", "confirm_restore", "restore_approval_token"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "snapshot_id": schemaString(description: "Snapshot ID to restore."),
                "confirm_restore": schemaBoolean(description: "Must be true to proceed."),
                "restore_approval_token": schemaString(description: "One-time restore approval token.")
            ]),
            tool(name: "ungit_get_timeline", description: "Get timeline entries from manifests.", required: ["project_path"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "limit": schemaInteger(description: "Maximum entries to return.", minimum: 1, defaultValue: 50)
            ]),
            tool(name: "ungit_review_timeline", description: "Get continuity-focused timeline review with intent/risk/outcome and restore drill evidence.", required: ["project_path"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "from_snapshot_id": schemaString(description: "Optional starting snapshot ID."),
                "to_snapshot_id": schemaString(description: "Optional ending snapshot ID."),
                "focus": schemaString(enumValues: ["summary", "drift", "regression", "restore"], description: "Optional review focus.")
            ]),
            tool(name: "ungit_get_snapshot", description: "Get full snapshot manifest by ID.", required: ["project_path", "snapshot_id"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "snapshot_id": schemaString(description: "Snapshot ID.")
            ]),
            tool(name: "ungit_get_recent_lessons", description: "Get recent critical lessons for memory recovery.", required: ["project_path"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "limit": schemaInteger(description: "Maximum lessons to return.", minimum: 1, defaultValue: 5)
            ]),
            tool(name: "ungit_get_project_summary", description: "Get lightweight project summary from timeline/manifests.", required: ["project_path"], properties: [
                "project_path": schemaString(description: "Absolute project path.")
            ]),
            tool(name: "ungit_export_timeline", description: "Export timeline report to a markdown file.", required: ["project_path", "mode"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "mode": schemaString(
                    enumValues: ["patch_list", "bullet_list", "detailed_summary", "continuity_review", "project_handoff"],
                    description: "Export report mode."
                ),
                "destination_path": schemaString(description: "Optional absolute destination file path.")
            ]),
            tool(name: "ungit_checkpoint_advisor", description: "Recommend snapshot checkpoint action before code changes.", required: ["project_path", "planned_change_scope", "files_touched_estimate"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "planned_change_scope": schemaString(enumValues: ["small", "medium", "large"], description: "Planned change scope."),
                "files_touched_estimate": schemaInteger(description: "Estimated touched file count.", minimum: 0, defaultValue: 1),
                "change_type": schemaString(enumValues: ["ui", "refactor", "restore", "bugfix", "architecture"], description: "Optional change type.")
            ]),
            tool(name: "ungit_verify_snapshot_proof", description: "Run proof checks for a snapshot using lightweight or archive mode.", required: ["project_path", "snapshot_id"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "snapshot_id": schemaString(description: "Snapshot ID."),
                "mode": schemaString(enumValues: ["lightweight", "archive"], description: "Optional proof mode override.")
            ]),
            tool(name: "ungit_restore_preflight", description: "Run a non-destructive restore health check before restore.", required: ["project_path"], properties: [
                "project_path": schemaString(description: "Absolute project path."),
                "snapshot_id": schemaString(description: "Optional snapshot ID.")
            ])
        ]
    }

    public func execute(tool name: String, arguments: [String: JSONValue]) -> ToolEnvelope {
        switch name {
        case "ungit_get_timeline":
            return getTimeline(arguments: arguments)
        case "ungit_review_timeline":
            return reviewTimeline(arguments: arguments)
        case "ungit_get_snapshot":
            return getSnapshot(arguments: arguments)
        case "ungit_get_recent_lessons":
            return getRecentLessons(arguments: arguments)
        case "ungit_get_project_summary":
            return getProjectSummary(arguments: arguments)
        case "ungit_export_timeline":
            return exportTimeline(arguments: arguments)
        case "ungit_checkpoint_advisor":
            return checkpointAdvisor(arguments: arguments)
        case "ungit_quick_save":
            return quickSave(arguments: arguments)
        case "ungit_restore_snapshot":
            return restoreSnapshot(arguments: arguments)
        case "ungit_review_save":
            return reviewSave(arguments: arguments)
        case "ungit_verify_snapshot_proof":
            return verifySnapshotProof(arguments: arguments)
        case "ungit_restore_preflight":
            return restorePreflight(arguments: arguments)
        default:
            return .failure(tool: name, step: "validation", reason: "Unknown tool")
        }
    }

    public func verifyWrite(projectURL: URL, returnedID: String) -> WriteVerificationResult {
        let layout = ProjectLayout(projectURL: projectURL)
        let manifestURL = layout.manifestsURL.appendingPathComponent("\(returnedID).json", isDirectory: false)
        let manifestExists = FileManager.default.fileExists(atPath: manifestURL.path)

        var manifestDecoded = false
        var idMatches = false
        var archiveReferenceMatches = false
        var archiveExists = false

        if manifestExists, let manifest = try? jsonStore.read(SnapshotManifest.self, from: manifestURL) {
            manifestDecoded = true
            idMatches = manifest.id == returnedID
            let expectedArchiveRef = "snapshots/\(returnedID).zip"
            archiveReferenceMatches = manifest.archiveRelativePath == expectedArchiveRef
            let archiveURL = layout.ungitURL.appendingPathComponent(manifest.archiveRelativePath, isDirectory: false)
            archiveExists = FileManager.default.fileExists(atPath: archiveURL.path)
        }

        return WriteVerificationResult(
            manifestExists: manifestExists,
            archiveExists: archiveExists,
            manifestDecoded: manifestDecoded,
            idMatchesManifest: idMatches,
            archiveReferenceMatches: archiveReferenceMatches
        )
    }

    private func quickSave(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_quick_save"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }
        guard let kindRaw = arguments["kind"]?.stringValue, let kind = quickKind(from: kindRaw) else {
            return .failure(tool: tool, step: "validation", reason: "kind is required: save|pre_change|feature_works|trusted_rollback|milestone|release_candidate|release")
        }

        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        do {
            let project = try initializer.loadProject(at: projectURL)
            let providedTitle = arguments["title"]?.stringValue?.trimmed
            let titleWasGenerated = (providedTitle == nil || providedTitle?.isEmpty == true)

            var draft = notesDraftService.buildQuickDraft(
                kind: kind,
                providedTitle: providedTitle,
                pathName: project.currentPathName
            )
            if let hint = arguments["notes_hint"]?.stringValue?.trimmed, !hint.isEmpty {
                draft.whatChanged = hint
                draft.summary = draft.title
            }

            let notes = draft.toNotes(defaultTitle: "Snapshot")
            let entry = try snapshotService.saveSnapshot(projectURL: projectURL, project: project, notes: notes)
            let verification = verifyWrite(projectURL: projectURL, returnedID: entry.id)
            guard verification.allPassed else {
                return .failure(tool: tool, step: "verification", reason: encodeVerificationFailure(verification))
            }

            return .success(tool: tool, data: .object([
                "snapshot": .object([
                    "id": .string(entry.id),
                    "title": .string(entry.title),
                    "type": .string(entry.snapshotType.rawValue),
                    "status": .string(entry.status.rawValue)
                ]),
                "title_was_generated": .bool(titleWasGenerated),
                "verification": verification.asJSON()
            ]))
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func restoreSnapshot(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_restore_snapshot"
        guard let confirm = arguments["confirm_restore"]?.boolValue, confirm else {
            return .failure(tool: tool, step: "validation", reason: "confirm_restore must be true")
        }
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }
        guard let snapshotID = arguments["snapshot_id"]?.stringValue, !snapshotID.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "snapshot_id is required")
        }
        guard let approvalToken = arguments["restore_approval_token"]?.stringValue?.trimmed, !approvalToken.isEmpty else {
            return .failure(tool: tool, step: "approval", reason: "restore_approval_token is required. Approve restore in the UNGIT app first.")
        }

        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        do {
            let project = try initializer.loadProject(at: projectURL)
            let timeline = try snapshotService.loadTimeline(projectURL: projectURL)
            guard let entry = timeline.first(where: { $0.id == snapshotID }) else {
                return .failure(tool: tool, step: "validation", reason: "snapshot_id not found")
            }

            try restoreService.consumeRestoreApproval(
                projectURL: projectURL,
                snapshotID: snapshotID,
                token: approvalToken,
                consumedBy: "mcp"
            )

            let beforeManifests = try ManifestStore().loadAllManifests(at: ProjectLayout(projectURL: projectURL))
            try restoreService.restoreSnapshot(projectURL: projectURL, entry: entry, project: project, snapshotService: snapshotService)
            let afterManifests = try ManifestStore().loadAllManifests(at: ProjectLayout(projectURL: projectURL))
            let beforeIDs = Set(beforeManifests.map(\.id))
            let safety = afterManifests.first(where: { $0.isAutomaticSafetySnapshot && !beforeIDs.contains($0.id) })

            var data: [String: JSONValue] = [
                "restored_snapshot_id": .string(snapshotID)
            ]

            if let safety {
                let verification = verifyWrite(projectURL: projectURL, returnedID: safety.id)
                guard verification.allPassed else {
                    return .failure(tool: tool, step: "verification", reason: encodeVerificationFailure(verification))
                }
                data["safety_snapshot"] = .object([
                    "id": .string(safety.id),
                    "title": .string(safety.notes.title),
                    "type": .string(safety.notes.snapshotType.rawValue),
                    "status": .string(safety.notes.status.rawValue)
                ])
                data["verification"] = verification.asJSON()
            }

            return .success(tool: tool, data: .object(data))
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func reviewSave(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_review_save"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }

        let mode = arguments["mode"]?.stringValue?.lowercased() ?? "draft"
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        do {
            let project = try initializer.loadProject(at: projectURL)
            let instruction = arguments["instruction"]?.stringValue?.trimmed ?? ""
            let title = arguments["title"]?.stringValue?.trimmed ?? ""
            let captureLesson = arguments["capture_critical_lesson"]?.boolValue ?? false

            var draftInput = instruction
            if captureLesson {
                draftInput = "UNGIT review save: capture critical lesson"
            } else if draftInput.isEmpty {
                draftInput = title
            }

            var draft = notesDraftService.buildDraft(from: draftInput, pathName: project.currentPathName)
            if !title.isEmpty { draft.title = title; draft.summary = title }

            if mode == "draft" {
                return .success(tool: tool, data: .object([
                    "mode": .string("draft"),
                    "draft": .object([
                        "title": .string(draft.title),
                        "summary": .string(draft.summary),
                        "type": .string(draft.snapshotType.rawValue),
                        "status": .string(draft.status.rawValue),
                        "what_changed": .string(draft.whatChanged),
                        "why": .string(draft.why),
                        "tags": .string(draft.tagsText)
                    ])
                ]))
            }

            if mode != "execute" {
                return .failure(tool: tool, step: "validation", reason: "mode must be draft or execute")
            }

            let notes = draft.toNotes(defaultTitle: "Snapshot")
            let entry = try snapshotService.saveSnapshot(projectURL: projectURL, project: project, notes: notes)
            let verification = verifyWrite(projectURL: projectURL, returnedID: entry.id)
            guard verification.allPassed else {
                return .failure(tool: tool, step: "verification", reason: encodeVerificationFailure(verification))
            }

            return .success(tool: tool, data: .object([
                "mode": .string("execute"),
                "snapshot": .object([
                    "id": .string(entry.id),
                    "title": .string(entry.title),
                    "type": .string(entry.snapshotType.rawValue),
                    "status": .string(entry.status.rawValue)
                ]),
                "verification": verification.asJSON()
            ]))
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func getTimeline(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_get_timeline"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }

        let limit = arguments["limit"]?.intValue ?? 50
        do {
            let timeline = try snapshotService.loadTimeline(projectURL: URL(fileURLWithPath: projectPath, isDirectory: true))
            let slice = Array(timeline.prefix(max(1, limit)))
            let rows = slice.map { entry in
                JSONValue.object([
                    "id": .string(entry.id),
                    "created_at": .string(entry.createdAtISO8601),
                    "title": .string(entry.title),
                    "summary": .string(entry.summary),
                    "type": .string(entry.snapshotType.rawValue),
                    "status": .string(entry.status.rawValue),
                    "path": .string(entry.pathName)
                ])
            }
            return .success(tool: tool, data: .object(["entries": .array(rows)]))
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func getSnapshot(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_get_snapshot"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }
        guard let snapshotID = arguments["snapshot_id"]?.stringValue, !snapshotID.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "snapshot_id is required")
        }

        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        do {
            let timeline = try snapshotService.loadTimeline(projectURL: projectURL)
            guard let entry = timeline.first(where: { $0.id == snapshotID }) else {
                return .failure(tool: tool, step: "validation", reason: "snapshot_id not found")
            }
            let manifest = try snapshotService.loadManifest(projectURL: projectURL, entry: entry)
            let payload = try encodeEncodable(manifest)
            return .success(tool: tool, data: payload)
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func reviewTimeline(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_review_timeline"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }

        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        let focus = (arguments["focus"]?.stringValue?.lowercased().trimmed).flatMap { raw -> String? in
            switch raw {
            case "summary", "drift", "regression", "restore":
                return raw
            case "":
                return nil
            default:
                return nil
            }
        } ?? "summary"

        do {
            let timeline = try snapshotService.loadTimeline(projectURL: projectURL)
            let selected = try timelineSlice(
                timeline: timeline,
                fromSnapshotID: arguments["from_snapshot_id"]?.stringValue?.trimmed,
                toSnapshotID: arguments["to_snapshot_id"]?.stringValue?.trimmed
            )
            let selectedIDs = Set(selected.map(\.id))
            let manifests = try ManifestStore().loadAllManifests(at: ProjectLayout(projectURL: projectURL))
            let manifestMap = Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0) })

            let rows = selected.map { entry -> JSONValue in
                let manifest = manifestMap[entry.id]
                return .object([
                    "id": .string(entry.id),
                    "created_at": .string(entry.createdAtISO8601),
                    "title": .string(entry.title),
                    "summary": .string(entry.summary),
                    "type": .string(entry.snapshotType.rawValue),
                    "status": .string(entry.status.rawValue),
                    "path": .string(entry.pathName),
                    "change_intent": .string(manifest?.notes.changeIntent ?? ""),
                    "risk_level": .string((manifest?.notes.riskLevel.rawValue) ?? "Medium"),
                    "outcome": manifest?.notes.outcome.map { .string($0.rawValue) } ?? .null,
                    "proof_state": .string((manifest?.proofVerificationStatus.rawValue) ?? entry.proofVerificationStatus.rawValue),
                    "proof_mode": manifest?.proofVerificationMode.map { .string($0.rawValue) } ?? .null,
                    "proof_checked_at": manifest?.proofCheckedAtISO8601.map { .string($0) } ?? .null,
                    "archive_available": .bool(entry.archiveAvailable),
                    "archive_locked": .bool((manifest?.archiveLocked) ?? false),
                    "archive_prune_reason": manifest?.archivePruneReason.map { .string($0) } ?? .null
                ])
            }

            let drills = parseRestoreDrills(at: ProjectLayout(projectURL: projectURL).restoreDrillsURL)
            let matchingDrills = drills
                .filter { selectedIDs.contains($0.snapshotID) }
                .map { drill in
                    JSONValue.object([
                        "timestamp": .string(drill.timestamp),
                        "snapshot_id": .string(drill.snapshotID),
                        "snapshot_title": .string(drill.snapshotTitle),
                        "outcome": .string(drill.outcome),
                        "notes": .string(drill.notes)
                    ])
                }

            let highRiskIDs = selected.compactMap { entry -> JSONValue? in
                guard manifestMap[entry.id]?.notes.riskLevel == .high else { return nil }
                return .string(entry.id)
            }
            let partialOrRevertedIDs = selected.compactMap { entry -> JSONValue? in
                guard let outcome = manifestMap[entry.id]?.notes.outcome else { return nil }
                guard outcome == .partial || outcome == .reverted else { return nil }
                return .string(entry.id)
            }
            let restoreDrillSnapshotIDs = Set(drills.map(\.snapshotID))
            let withoutDrillIDs = selected
                .filter { entry in
                    let risk = manifestMap[entry.id]?.notes.riskLevel ?? .medium
                    return risk == .high && !restoreDrillSnapshotIDs.contains(entry.id)
                }
                .map { JSONValue.string($0.id) }

            return .success(tool: tool, data: .object([
                "focus": .string(focus),
                "from_snapshot_id": arguments["from_snapshot_id"]?.stringValue.map(JSONValue.string) ?? .null,
                "to_snapshot_id": arguments["to_snapshot_id"]?.stringValue.map(JSONValue.string) ?? .null,
                "snapshot_count": .number(Double(selected.count)),
                "snapshots": .array(rows),
                "restore_drills": .array(matchingDrills),
                "high_risk_snapshot_ids": .array(highRiskIDs),
                "partial_or_reverted_snapshot_ids": .array(partialOrRevertedIDs),
                "high_risk_without_restore_drill_ids": .array(withoutDrillIDs)
            ]))
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func getRecentLessons(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_get_recent_lessons"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }

        let limit = arguments["limit"]?.intValue ?? 5
        do {
            let manifests = try ManifestStore().loadAllManifests(at: ProjectLayout(projectURL: URL(fileURLWithPath: projectPath, isDirectory: true)))
            let lessons = manifests.filter { manifest in
                let tags = Set(manifest.notes.tags.map { $0.lowercased() })
                return tags.contains("critical-lesson") || tags.contains("regression-risk") || manifest.notes.title.lowercased().contains("critical lesson")
            }
            .prefix(max(1, limit))

            let rows = lessons.map { manifest in
                JSONValue.object([
                    "id": .string(manifest.id),
                    "created_at": .string(manifest.createdAtISO8601),
                    "title": .string(manifest.notes.title),
                    "summary": .string(manifest.notes.summary),
                    "tags": .array(manifest.notes.tags.map(JSONValue.string))
                ])
            }
            return .success(tool: tool, data: .object(["lessons": .array(Array(rows))]))
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func getProjectSummary(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_get_project_summary"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }

        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        do {
            let project = try initializer.loadProject(at: projectURL)
            let timeline = try snapshotService.loadTimeline(projectURL: projectURL)
            let milestones = timeline.filter { $0.snapshotType == .milestone }.count
            let rollbacks = timeline.filter { $0.snapshotType == .trustedRollback }.count

            var data: [String: JSONValue] = [
                "project_name": .string(project.name),
                "project_path": .string(project.rootPath),
                "current_path": .string(project.currentPathName),
                "total_snapshots": .number(Double(timeline.count)),
                "milestone_count": .number(Double(milestones)),
                "trusted_rollback_count": .number(Double(rollbacks))
            ]
            if let latest = timeline.first {
                data["latest_snapshot"] = .object([
                    "id": .string(latest.id),
                    "title": .string(latest.title),
                    "created_at": .string(latest.createdAtISO8601),
                    "type": .string(latest.snapshotType.rawValue),
                    "status": .string(latest.status.rawValue)
                ])
            }
            return .success(tool: tool, data: .object(data))
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func exportTimeline(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_export_timeline"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }
        guard let modeRaw = arguments["mode"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !modeRaw.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "mode is required")
        }

        let modeLookup: [String: TimelineExportMode] = [
            "patch_list": .patchList,
            "bullet_list": .bulletList,
            "detailed_summary": .detailedSummary,
            "continuity_review": .continuityReview,
            "project_handoff": .projectHandoff
        ]
        guard let mode = modeLookup[modeRaw.lowercased()] else {
            return .failure(tool: tool, step: "validation", reason: "mode must be one of: patch_list|bullet_list|detailed_summary|continuity_review|project_handoff")
        }

        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        let destinationURL: URL?
        if let destinationPath = arguments["destination_path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !destinationPath.isEmpty {
            destinationURL = URL(fileURLWithPath: destinationPath, isDirectory: false)
        } else {
            destinationURL = nil
        }

        do {
            let result = try snapshotService.exportTimeline(
                projectURL: projectURL,
                mode: mode,
                destinationURL: destinationURL
            )
            return .success(tool: tool, data: .object([
                "mode": .string(result.mode.rawValue),
                "entries_exported": .number(Double(result.entriesExported)),
                "file_path": .string(result.fileURL.path)
            ]))
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func verifySnapshotProof(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_verify_snapshot_proof"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }
        guard let snapshotID = arguments["snapshot_id"]?.stringValue, !snapshotID.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "snapshot_id is required")
        }

        let modeRaw = arguments["mode"]?.stringValue?.lowercased().trimmed
        let mode: ProofVerificationMode
        switch modeRaw {
        case nil, "":
            mode = .lightweight
        case "lightweight":
            mode = .lightweight
        case "archive":
            mode = .archive
        default:
            return .failure(tool: tool, step: "validation", reason: "mode must be lightweight or archive")
        }

        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        do {
            let executed = try snapshotService.verifyProof(projectURL: projectURL, entryID: snapshotID, mode: mode)
            guard executed else {
                return .failure(tool: tool, step: "execution", reason: "No proof checks were runnable for this snapshot.")
            }

            let manifests = try ManifestStore().loadAllManifests(at: ProjectLayout(projectURL: projectURL))
            guard let manifest = manifests.first(where: { $0.id == snapshotID }) else {
                return .failure(tool: tool, step: "execution", reason: "Snapshot not found after proof verification.")
            }

            return .success(tool: tool, data: .object([
                "snapshot_id": .string(snapshotID),
                "proof_state": .string(manifest.proofVerificationStatus.rawValue),
                "proof_mode": .string(manifest.proofVerificationMode?.rawValue ?? "Not Recorded"),
                "proof_checked_at": .string(manifest.proofCheckedAtISO8601 ?? "")
            ]))
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func checkpointAdvisor(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_checkpoint_advisor"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            return .failure(tool: tool, step: "validation", reason: "project_path does not exist")
        }

        guard let scopeRaw = arguments["planned_change_scope"]?.stringValue?.lowercased().trimmed else {
            return .failure(tool: tool, step: "validation", reason: "planned_change_scope is required: small|medium|large")
        }
        guard ["small", "medium", "large"].contains(scopeRaw) else {
            return .failure(tool: tool, step: "validation", reason: "planned_change_scope must be one of: small|medium|large")
        }
        guard let filesEstimate = arguments["files_touched_estimate"]?.intValue, filesEstimate >= 0 else {
            return .failure(tool: tool, step: "validation", reason: "files_touched_estimate is required and must be >= 0")
        }

        let changeType = arguments["change_type"]?.stringValue?.lowercased().trimmed
        let allowedChangeTypes = Set(["ui", "refactor", "restore", "bugfix", "architecture"])
        if let changeType, !changeType.isEmpty, !allowedChangeTypes.contains(changeType) {
            return .failure(tool: tool, step: "validation", reason: "change_type must be one of: ui|refactor|restore|bugfix|architecture")
        }

        let highRiskType = (changeType == "refactor" || changeType == "restore" || changeType == "architecture")
        let mediumRiskType = (changeType == "bugfix")

        let recommendation: String
        let reason: String
        let riskLevel: String

        if filesEstimate == 0 {
            recommendation = "none"
            reason = "No files are expected to change, so no pre-edit checkpoint is required."
            riskLevel = "Low"
        } else if scopeRaw == "large" || filesEstimate >= 6 || highRiskType {
            recommendation = "pre_change"
            reason = "Planned changes are structural/risky or touch many files; capture a safer rewind point first."
            riskLevel = "High"
        } else if scopeRaw == "medium" || filesEstimate >= 2 || mediumRiskType {
            recommendation = "quick_save"
            reason = "Planned changes are meaningful but not full-structural; create a checkpoint before editing."
            riskLevel = "Medium"
        } else {
            recommendation = "quick_save"
            reason = "Small/local change still benefits from lightweight checkpoint discipline."
            riskLevel = "Low"
        }

        return .success(tool: tool, data: .object([
            "recommendation": .string(recommendation),
            "reason": .string(reason),
            "risk_level": .string(riskLevel)
        ]))
    }

    private func restorePreflight(arguments: [String: JSONValue]) -> ToolEnvelope {
        let tool = "ungit_restore_preflight"
        guard let projectPath = arguments["project_path"]?.stringValue, !projectPath.isEmpty else {
            return .failure(tool: tool, step: "validation", reason: "project_path is required")
        }

        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        do {
            let snapshotID = arguments["snapshot_id"]?.stringValue?.trimmed
            let report = try runRestorePreflight(projectURL: projectURL, snapshotID: snapshotID)
            return .success(tool: tool, data: report.asJSON())
        } catch {
            return .failure(tool: tool, step: "execution", reason: error.localizedDescription)
        }
    }

    private func quickKind(from raw: String) -> UngitQuickCommandKind? {
        switch raw.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "save":
            return .save
        case "pre_change", "prechange":
            return .preChange
        case "feature_works", "featureworks":
            return .featureWorks
        case "trusted_rollback", "trustedrollback":
            return .trustedRollback
        case "milestone":
            return .milestone
        case "release_candidate", "releasecandidate", "rc":
            return .releaseCandidate
        case "release":
            return .release
        default:
            return nil
        }
    }

    private func runRestorePreflight(projectURL: URL, snapshotID: String?) throws -> RestorePreflightResult {
        let layout = ProjectLayout(projectURL: projectURL)
        let loaded = try ManifestStore().loadAllManifestsWithIssues(at: layout)
        let issues = loaded.issues
        let timeline = try snapshotService.loadTimeline(projectURL: projectURL)

        let targetEntry: TimelineEntry?
        if let snapshotID, !snapshotID.isEmpty {
            targetEntry = timeline.first(where: { $0.id == snapshotID })
        } else {
            targetEntry = timeline.first(where: { $0.snapshotType == .trustedRollback }) ?? timeline.first
        }

        guard let entry = targetEntry else {
            return RestorePreflightResult(
                canProceed: false,
                snapshotID: nil,
                archiveExists: false,
                archiveValid: false,
                manifestIssueCount: issues.count,
                manifestIssues: issues,
                notes: ["No snapshots available for restore preflight."]
            )
        }

        let archiveURL = layout.ungitURL.appendingPathComponent(entry.archiveRelativePath, isDirectory: false)
        let archiveExists = FileManager.default.fileExists(atPath: archiveURL.path)
        var archiveValid = false
        var notes: [String] = []

        if archiveExists {
            let tempURL = layout.tempURL.appendingPathComponent("restore-preflight-\(UUID().uuidString)", isDirectory: true)
            do {
                let extractedRoot = try archiveService.extractSnapshotArchive(archiveURL: archiveURL, destinationURL: tempURL)
                try validator.validateProjectTree(at: extractedRoot)
                archiveValid = true
                notes.append("Archive extracted and validated in isolated temp workspace.")
            } catch {
                archiveValid = false
                notes.append("Archive validation failed: \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: tempURL)
        } else {
            notes.append("Archive file missing for selected snapshot.")
        }

        let canProceed = archiveExists && archiveValid
        if !issues.isEmpty {
            notes.append("Manifest issues detected: \(issues.count).")
        }

        return RestorePreflightResult(
            canProceed: canProceed,
            snapshotID: entry.id,
            archiveExists: archiveExists,
            archiveValid: archiveValid,
            manifestIssueCount: issues.count,
            manifestIssues: issues,
            notes: notes
        )
    }

    private func timelineSlice(
        timeline: [TimelineEntry],
        fromSnapshotID: String?,
        toSnapshotID: String?
    ) throws -> [TimelineEntry] {
        guard !timeline.isEmpty else { return [] }

        let normalizedFrom = fromSnapshotID?.uppercased()
        let normalizedTo = toSnapshotID?.uppercased()

        if normalizedFrom == nil, normalizedTo == nil {
            return timeline
        }

        var fromIndex: Int?
        var toIndex: Int?
        if let normalizedFrom {
            fromIndex = timeline.firstIndex(where: { $0.id.uppercased() == normalizedFrom })
            if fromIndex == nil {
                throw AppError.restoreFailed("from_snapshot_id not found: \(normalizedFrom)")
            }
        }
        if let normalizedTo {
            toIndex = timeline.firstIndex(where: { $0.id.uppercased() == normalizedTo })
            if toIndex == nil {
                throw AppError.restoreFailed("to_snapshot_id not found: \(normalizedTo)")
            }
        }

        switch (fromIndex, toIndex) {
        case let (.some(from), .some(to)):
            let lower = min(from, to)
            let upper = max(from, to)
            return Array(timeline[lower...upper])
        case let (.some(from), .none):
            return Array(timeline[0...from])
        case let (.none, .some(to)):
            return Array(timeline[0...to])
        case (.none, .none):
            return timeline
        }
    }

    private struct RestoreDrillRecord {
        let timestamp: String
        let snapshotID: String
        let snapshotTitle: String
        let outcome: String
        let notes: String
    }

    private func parseRestoreDrills(at url: URL) -> [RestoreDrillRecord] {
        guard let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty else {
            return []
        }

        struct Draft {
            var timestamp: String = ""
            var snapshotID: String = ""
            var snapshotTitle: String = ""
            var outcome: String = ""
            var notes: String = ""
        }

        var records: [RestoreDrillRecord] = []
        var current: Draft?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("## Restore Drill ") {
                if let current, !current.snapshotID.isEmpty {
                    records.append(
                        RestoreDrillRecord(
                            timestamp: current.timestamp,
                            snapshotID: current.snapshotID,
                            snapshotTitle: current.snapshotTitle,
                            outcome: current.outcome,
                            notes: current.notes
                        )
                    )
                }
                let timestamp = String(line.dropFirst("## Restore Drill ".count)).trimmed
                current = Draft(timestamp: timestamp)
                continue
            }

            guard var working = current else { continue }
            if line.hasPrefix("- Snapshot ID:") {
                working.snapshotID = String(line.dropFirst("- Snapshot ID:".count)).trimmed
                current = working
            } else if line.hasPrefix("- Snapshot Title:") {
                working.snapshotTitle = String(line.dropFirst("- Snapshot Title:".count)).trimmed
                current = working
            } else if line.hasPrefix("- Outcome:") {
                working.outcome = String(line.dropFirst("- Outcome:".count)).trimmed
                current = working
            } else if line.hasPrefix("- Notes:") {
                working.notes = String(line.dropFirst("- Notes:".count)).trimmed
                current = working
            }
        }

        if let current, !current.snapshotID.isEmpty {
            records.append(
                RestoreDrillRecord(
                    timestamp: current.timestamp,
                    snapshotID: current.snapshotID,
                    snapshotTitle: current.snapshotTitle,
                    outcome: current.outcome,
                    notes: current.notes
                )
            )
        }

        return records
    }

    private func encodeVerificationFailure(_ verification: WriteVerificationResult) -> String {
        var failures: [String] = []
        if !verification.manifestExists { failures.append("manifest missing") }
        if !verification.archiveExists { failures.append("archive missing") }
        if !verification.manifestDecoded { failures.append("manifest decode failed") }
        if !verification.idMatchesManifest { failures.append("returned ID mismatch") }
        if !verification.archiveReferenceMatches { failures.append("manifest archive reference mismatch") }
        return failures.joined(separator: ", ")
    }

    private func encodeEncodable<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return JSONValue.fromAny(object)
    }

    private func tool(name: String, description: String, required: [String], properties: [String: JSONValue]) -> MCPToolDefinition {
        MCPToolDefinition(
            name: name,
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "required": .array(required.map(JSONValue.string)),
                "properties": .object(properties),
                "additionalProperties": .bool(false)
            ])
        )
    }

    private func schemaString(enumValues: [String]? = nil, description: String? = nil) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("string")
        ]
        if let enumValues, !enumValues.isEmpty {
            object["enum"] = .array(enumValues.map(JSONValue.string))
        }
        if let description, !description.isEmpty {
            object["description"] = .string(description)
        }
        return .object(object)
    }

    private func schemaBoolean(description: String? = nil, defaultValue: Bool? = nil) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("boolean")
        ]
        if let description, !description.isEmpty {
            object["description"] = .string(description)
        }
        if let defaultValue {
            object["default"] = .bool(defaultValue)
        }
        return .object(object)
    }

    private func schemaInteger(description: String? = nil, minimum: Int? = nil, defaultValue: Int? = nil) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("integer")
        ]
        if let description, !description.isEmpty {
            object["description"] = .string(description)
        }
        if let minimum {
            object["minimum"] = .number(Double(minimum))
        }
        if let defaultValue {
            object["default"] = .number(Double(defaultValue))
        }
        return .object(object)
    }
}
