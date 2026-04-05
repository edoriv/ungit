import Foundation

struct ProjectInitializer {
    private let fileSystem = FileSystemService()
    private let jsonStore = JSONFileStore()
    private let ungitStartMarker = "<!-- UNGIT:START -->"
    private let ungitEndMarker = "<!-- UNGIT:END -->"

    func initializeProjectIfNeeded(at projectURL: URL) throws -> ProjectMetadata {
        let layout = ProjectLayout(projectURL: projectURL)
        try fileSystem.ensureDirectory(layout.ungitURL)
        try fileSystem.ensureDirectory(layout.snapshotsURL)
        try fileSystem.ensureDirectory(layout.manifestsURL)
        try fileSystem.ensureDirectory(layout.exportsURL)
        try fileSystem.ensureDirectory(layout.restoresURL)
        try fileSystem.ensureDirectory(layout.tempURL)

        if jsonStore.exists(layout.projectMetadataURL) {
            try ensureMemoryFiles(for: layout)
            try ensureAgentsFile(in: projectURL)
            return try jsonStore.read(ProjectMetadata.self, from: layout.projectMetadataURL)
        }

        let now = Date()
        let rootPath = ProjectPath(
            id: UUID().uuidString,
            name: "main",
            createdAt: now,
            createdAtISO8601: DateFormatters.iso8601.string(from: now),
            sourceSnapshotID: nil
        )

        let metadata = ProjectMetadata(
            id: UUID().uuidString,
            name: projectURL.lastPathComponent,
            rootPath: projectURL.path,
            createdAt: now,
            createdAtISO8601: DateFormatters.iso8601.string(from: now),
            currentPathName: rootPath.name,
            paths: [rootPath]
        )

        try jsonStore.write(metadata, to: layout.projectMetadataURL)

        if !jsonStore.exists(layout.projectLogJSONURL) {
            try jsonStore.write(ProjectLog(entries: []), to: layout.projectLogJSONURL)
        }

        if !FileManager.default.fileExists(atPath: layout.projectLogMarkdownURL.path) {
            let header = "# UNGIT Project Log\n\nProject: \(metadata.name)\nCreated: \(metadata.createdAtISO8601)\n\n"
            try header.data(using: .utf8)?.write(to: layout.projectLogMarkdownURL, options: .atomic)
        }

        try ensureMemoryFiles(for: layout)
        try ensureAgentsFile(in: projectURL)

        return metadata
    }

    func loadProject(at projectURL: URL) throws -> ProjectMetadata {
        let layout = ProjectLayout(projectURL: projectURL)
        guard jsonStore.exists(layout.projectMetadataURL) else {
            throw AppError.projectNotInitialized
        }
        return try jsonStore.read(ProjectMetadata.self, from: layout.projectMetadataURL)
    }

    private func ensureAgentsFile(in projectURL: URL) throws {
        let agentsURL = projectURL.appendingPathComponent("AGENTS.md", isDirectory: false)
        let workflowBlock = """
        ## UNGIT Workflow (Managed by UNGIT)

        This project uses UNGIT workflow rules.

        ### UNGIT Operating Rules

        - Single active project only.
        - Use project-local `.ungit` only.
        - Use UNGIT terms only in user-facing language:
          - Project, Snapshot, Path, Timeline, Restore, Milestone, Notes
        - Do not use Git UI concepts or Git jargon for snapshots.

        ### Command Workflow

        UNGIT commands are executable operations, not conversational summaries.
        They must trigger real snapshot logic when issued.

        - `UNGIT quick save`
        - `UNGIT quick pre-change`
        - `UNGIT quick feature works`
        - `UNGIT quick trusted rollback`
        - `UNGIT quick milestone`
        - `UNGIT quick release candidate`
        - `UNGIT quick release`
        - `UNGIT review save`
        - `UNGIT review save: capture critical lesson`
        - Keep `PROJECT_SUMMARY.md` current with project goals and scope; this is the continuity home base for long-running work.
        - `UNGIT add bug: <title>`
        - `UNGIT add idea: <title>`
        - `UNGIT add todo: <title>`
        - `UNGIT park: <note>`
        - `UNGIT update park: <note>`
        - `UNGIT fork point`
        - `UNGIT fork path` (alias of `fork point`)
        - `UNGIT prune snapshots`
        - `UNGIT prune snapshots: confirm`
        - `UNGIT prune snapshot <snapshot-id>`
        - `UNGIT prune snapshot <snapshot-id>: confirm`
        - `UNGIT handoff`
        - `UNGIT verify snapshot <snapshot-id>`
        - `UNGIT verify snapshot <snapshot-id> archive`
        - `UNGIT verify latest milestone`
        - `UNGIT verify latest trusted rollback`
        - `UNGIT verify latest release candidate`
        - `UNGIT verify latest release`
        - `UNGIT preflight restore`

        ### Command Routing (MCP Only)

        `UNGIT ...` is not a shell binary command.
        Treat every `UNGIT ...` instruction as an MCP-routed workflow command.

        - Never execute `UNGIT ...` through terminal shell (`zsh`, `bash`, etc.).
        - Always map `UNGIT ...` commands to UNGIT MCP tools first.
        - If shell reports `command not found: UNGIT`, that is a routing failure, not command failure.
        - In that case, retry via MCP tool mapping and then verify disk state.

        Required MCP mapping examples:
        - `UNGIT quick save` -> `ungit_quick_save(kind=save)`
        - `UNGIT quick pre-change` -> `ungit_quick_save(kind=pre_change)`
        - `UNGIT quick feature works` -> `ungit_quick_save(kind=feature_works)`
        - `UNGIT quick trusted rollback` -> `ungit_quick_save(kind=trusted_rollback)`
        - `UNGIT quick milestone` -> `ungit_quick_save(kind=milestone)`
        - `UNGIT quick release candidate` -> `ungit_quick_save(kind=release_candidate)`
        - `UNGIT quick release` -> `ungit_quick_save(kind=release)`
        - `UNGIT save milestone` -> `ungit_quick_save(kind=milestone)`
        - `UNGIT show timeline` -> `ungit_get_timeline(...)`
        - `UNGIT show snapshot <snapshot-id>` -> `ungit_get_snapshot(snapshot_id=<id>)`
        - `UNGIT verify snapshot <snapshot-id>` -> `ungit_verify_snapshot_proof(snapshot_id=<id>)`
        - `UNGIT verify snapshot <snapshot-id> archive` -> `ungit_verify_snapshot_proof(snapshot_id=<id>, mode=archive)`
        - `UNGIT verify latest milestone` -> `ungit_get_timeline(...)` resolve latest milestone ID, then `ungit_verify_snapshot_proof(...)`
        - `UNGIT verify latest trusted rollback` -> `ungit_get_timeline(...)` resolve latest trusted rollback ID, then `ungit_verify_snapshot_proof(...)`
        - `UNGIT verify latest release candidate` -> `ungit_get_timeline(...)` resolve latest release candidate ID, then `ungit_verify_snapshot_proof(...)`
        - `UNGIT verify latest release` -> `ungit_get_timeline(...)` resolve latest release ID, then `ungit_verify_snapshot_proof(...)`
        - `UNGIT handoff` -> `ungit_export_timeline(mode=project_handoff)`
        - Timeline review requests -> `ungit_review_timeline(...)`

        ### Quick Save Behavior

        - If user omits a title, auto-generate the best title and draft notes from context.
        - Generate title ONLY from current context.
        - Do not reuse stale or unrelated previous titles.
        - If user gives a concrete title, use it as-is.
        - `quick` commands draft notes automatically and execute.
        - `review save` drafts notes first and waits for confirmation.
        - `UNGIT review save: capture critical lesson` should create a focused learning snapshot using:
          - tags: `critical-lesson`, `regression-risk`
          - title: `Critical Lesson` (unless user overrides)
          - structure:
            - Problem: What was broken?
            - Fix: What exact change fixed it?
            - Why it works: Why this fix works.
            - Do not change: What must not be changed later.
            - Proof: One code or command example that actually worked.

        ### Checkpoint Discipline

        - Before any code-changing batch, checkpoint advice is required.
        - Before substantial edits, call MCP tool `ungit_checkpoint_advisor` and surface its recommendation once.
        - Small/local changes should suggest `UNGIT quick save`.
        - Structural/risky/multi-file changes should suggest `UNGIT quick pre-change`.
        - If no snapshot exists in the current work block, explicitly prompt once before substantial edits.
        - After each substantial batch, suggest follow-up `UNGIT quick save`.
        - Do not silently stack risky edits without a checkpoint recommendation.

        ### Command Success Verification

        UNGIT command success is defined only by verified disk state.

        For any UNGIT save command, success means all of the following:
        1. Snapshot was executed through UNGIT core logic.
        2. Manifest file exists in `.ungit/manifests`.
        3. Archive file exists in `.ungit/snapshots`.
        4. Return manifest ID, final title, type/status.

        Verification must occur immediately after execution and before responding.

        If those checks do not pass, do not imply success.
        Report failure clearly.

        On failure, return:
        - Which step failed (execution / manifest / archive / return data).
        - Reason (if known).
        - No partial success messaging.

        ### Proof States and Modes

        Proof state must be explicit and stored per snapshot.

        - Allowed proof states:
          - `Verified`
          - `Unverified`
          - `Broken`
        - Default new snapshots to `Unverified` unless explicit proof is captured.
        - Allowed proof verification modes:
          - `Lightweight Proof`
          - `Archive Proof`
        - Store proof mode and proof checked timestamp in snapshot data.
        - Show proof state and proof mode clearly in timeline and inspector.
        - Trusted Rollback should strongly prefer snapshots verified with `Archive Proof`.

        ### Continuity Metadata

        Track lightweight continuity metadata in snapshots to reduce drift:

        - `Change Intent`: one-line statement of what this change is trying to achieve.
        - `Risk Level`: `Low` / `Medium` / `High`.
        - `Outcome`: `Worked` / `Partial` / `Reverted` (when known).
        - Maintain a `RESTORE_DRILLS.md` log with restore drill outcomes and notes.

        ### Archive Proof Guardrails

        `Archive Proof` must be safe, isolated, and non-destructive.

        - Extract archived snapshot only into an isolated temp workspace.
        - Never mutate the archived snapshot artifact during proof.
        - Never mutate the live project during proof.
        - Clean temp workspace after proof when appropriate.
        - Clearly label proof results as archived snapshot replay proof.

        ### Restore Safety

        Before every restore, always:
        1. Create a safety snapshot first.
        2. Then replace live project files with the selected snapshot.

        Restore is Xcode-aware:
        1. Detect whether Xcode (`com.apple.dt.Xcode`) is running before restore.
        2. If running, offer:
           - Quit Xcode and Restore
           - Restore Anyway
           - Cancel
        3. If user chooses Quit Xcode and Restore:
           - request graceful app termination first
           - wait until Xcode is fully closed before any live restore mutation
           - if Xcode does not close in time, offer:
             - Keep Waiting
             - Cancel Restore
             - Force Quit and Restore
           - do not force quit without explicit user approval
        4. After successful restore, if UNGIT closed Xcode, optionally offer to reopen the restored project.
        5. Prefer opening `.xcworkspace` if present, otherwise `.xcodeproj`.

        Restore requires explicit approval:
        1. Restore commands must first create a pending restore request.
        2. Live restore mutation is allowed only after explicit in-app approval.
        3. Approval must issue a short-lived, one-time token bound to the selected snapshot ID.
        4. Restore execution must reject missing, mismatched, reused, or expired tokens.
        5. Do not perform restore mutation without that explicit approval path.

        ### Snapshot Archive Pruning

        Pruning is archive-only and must preserve timeline history.

        - Pruning removes only snapshot archive files from `.ungit/snapshots`.
        - Manifests and project log history must remain intact.
        - Keep all `Milestone`, `Release Candidate`, `Release`, and `Trusted Rollback` archives.
        - Keep the latest 10 non-major snapshot archives.
        - Never prune the newest snapshot archive.
        - `UNGIT prune snapshots` = dry-run preview only.
        - `UNGIT prune snapshots: confirm` = apply prune policy.
        - `UNGIT prune snapshot <snapshot-id>` = dry-run preview for one snapshot archive.
        - `UNGIT prune snapshot <snapshot-id>: confirm` = apply prune for one snapshot archive.
        - Pruned snapshots remain visible in timeline/inspector and must be labeled as not restorable.

        ### Sacred Landmark Protection

        - `Release Candidate` and `Release` snapshot archives are protected by UNGIT policy.
        - They are never pruned by default and are treated as sacred restore anchors.

        ### Timeline Recovery Prompts

        UNGIT timeline is the authoritative memory source for past decisions.
        When context is unclear, review timeline before acting.

        - Use MCP tool `ungit_review_timeline` first for continuity-focused reviews.
        - Do not summarize snapshots by title alone when continuity metadata exists.
        - Include `Change Intent`, `Risk Level`, `Outcome`, and relevant restore drill evidence.
        - When analyzing drift/regression:
          - prioritize `High` risk snapshots
          - highlight `Partial` and `Reverted` outcomes
          - check restore reliability evidence in `RESTORE_DRILLS.md`
        - Review the UNGIT timeline from the last trusted rollback to now.
        - Look at the milestone where trash first worked, then compare the later fixes and tell me where intent drift probably happened.
        - We lost the plot. Read the recent UNGIT snapshots and summarize what we were trying to do.
        """
        let managedSection = "\(ungitStartMarker)\n\(workflowBlock)\n\(ungitEndMarker)"

        if FileManager.default.fileExists(atPath: agentsURL.path) {
            let existing = (try? String(contentsOf: agentsURL, encoding: .utf8)) ?? ""

            if let startRange = existing.range(of: ungitStartMarker),
               let endRange = existing.range(of: ungitEndMarker),
               startRange.lowerBound < endRange.lowerBound {
                let replaceRange = startRange.upperBound..<endRange.lowerBound
                let replacement = "\n\(workflowBlock)\n"
                let updated = existing.replacingCharacters(in: replaceRange, with: replacement)
                try updated.data(using: .utf8)?.write(to: agentsURL, options: .atomic)
                return
            }

            if existing.contains(ungitStartMarker) || existing.contains(ungitEndMarker) {
                return
            }

            let separator = existing.hasSuffix("\n") ? "\n" : "\n\n"
            let appended = existing + separator + managedSection + "\n"
            try appended.data(using: .utf8)?.write(to: agentsURL, options: .atomic)
            return
        }

        let content = "# AGENTS.md\n\n" + managedSection + "\n"
        try content.data(using: .utf8)?.write(to: agentsURL, options: .atomic)
    }

    private func ensureMemoryFiles(for layout: ProjectLayout) throws {
        try ensureMemoryFile(
            at: layout.projectSummaryURL,
            title: "PROJECT SUMMARY",
            description: """
            Home base for project intent and goals. Keep this current so long-running work stays aligned.

            ## Project Summary Entry
            - What this project is:
            - Primary user outcome:
            - Current goals:
            - Constraints / non-goals:
            - Definition of done:
            """
        )
        try ensureMemoryFile(
            at: layout.bugsURL,
            title: "BUGS",
            description: "Project-local bug notes for regressions, failures, and reproducible issues."
        )
        try ensureMemoryFile(
            at: layout.ideasURL,
            title: "IDEAS",
            description: "Project-local idea backlog for experiments, options, and future directions."
        )
        try ensureMemoryFile(
            at: layout.todoURL,
            title: "TODO",
            description: "Project-local actionable tasks and follow-ups."
        )
        try ensureMemoryFile(
            at: layout.parkURL,
            title: "PARK",
            description: "Where work was left off so pickup is fast and clear."
        )
        try ensureMemoryFile(
            at: layout.restoreDrillsURL,
            title: "RESTORE_DRILLS",
            description: "Restore drill history with outcomes, notes, and follow-up issues."
        )
    }

    private func ensureMemoryFile(at url: URL, title: String, description: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let content = """
        # \(title)

        \(description)

        """
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
