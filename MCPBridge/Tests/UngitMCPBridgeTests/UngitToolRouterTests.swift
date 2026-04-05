import XCTest
@testable import UngitMCPBridge

final class UngitToolRouterTests: XCTestCase {
    func testQuickSaveDefaultsToFeatureWorksWithAlignedTitle() {
        let service = NotesDraftService()
        let draft = service.buildQuickDraft(
            kind: .save,
            providedTitle: nil,
            pathName: "main"
        )

        XCTAssertEqual(draft.snapshotType, .featureWorks)
        XCTAssertEqual(draft.title, "Quick Save")
    }

    func testQuickMilestoneGeneratesMilestoneTitleOnlyForMilestoneType() {
        let service = NotesDraftService()
        let draft = service.buildQuickDraft(
            kind: .milestone,
            providedTitle: nil,
            pathName: "main"
        )

        XCTAssertEqual(draft.snapshotType, .milestone)
        XCTAssertEqual(draft.title, "Milestone")
    }

    func testQuickReleaseTypesGenerateSacredLandmarkTitles() {
        let service = NotesDraftService()

        let candidate = service.buildQuickDraft(
            kind: .releaseCandidate,
            providedTitle: nil,
            pathName: "main"
        )
        XCTAssertEqual(candidate.snapshotType, .releaseCandidate)
        XCTAssertEqual(candidate.title, "Release Candidate")
        XCTAssertEqual(candidate.status, .trusted)

        let release = service.buildQuickDraft(
            kind: .release,
            providedTitle: nil,
            pathName: "main"
        )
        XCTAssertEqual(release.snapshotType, .release)
        XCTAssertEqual(release.title, "Release")
        XCTAssertEqual(release.status, .trusted)
    }

    func testParserMapsQuickCommandsToExpectedKinds() {
        let service = NotesDraftService()

        if case .quick(let kind, _) = service.parseCommand(from: "UNGIT quick save") {
            XCTAssertEqual(kind.snapshotType, .featureWorks)
        } else {
            XCTFail("Failed to parse quick save command")
        }

        if case .quick(let kind, _) = service.parseCommand(from: "UNGIT quick milestone") {
            XCTAssertEqual(kind.snapshotType, .milestone)
        } else {
            XCTFail("Failed to parse quick milestone command")
        }

        if case .quick(let kind, _) = service.parseCommand(from: "UNGIT quick release candidate") {
            XCTAssertEqual(kind.snapshotType, .releaseCandidate)
        } else {
            XCTFail("Failed to parse quick release candidate command")
        }

        if case .quick(let kind, _) = service.parseCommand(from: "UNGIT quick release") {
            XCTAssertEqual(kind.snapshotType, .release)
        } else {
            XCTFail("Failed to parse quick release command")
        }

        if case .quick(let kind, _) = service.parseCommand(from: "UNGIT quick pre-change") {
            XCTAssertEqual(kind.snapshotType, .preChange)
        } else {
            XCTFail("Failed to parse quick pre-change command")
        }

        if case .quick(let kind, _) = service.parseCommand(from: "UNGIT save milestone") {
            XCTAssertEqual(kind.snapshotType, .milestone)
        } else {
            XCTFail("Failed to parse save milestone alias")
        }
    }

    func testParserMapsMemoryCommands() {
        let service = NotesDraftService()

        if case .addMemory(let type, let title) = service.parseCommand(from: "UNGIT add bug: Crash on open") {
            XCTAssertEqual(type, .bugs)
            XCTAssertEqual(title, "Crash on open")
        } else {
            XCTFail("Failed to parse add bug command")
        }

        if case .addMemory(let type, let title) = service.parseCommand(from: "UNGIT add idea better project cards") {
            XCTAssertEqual(type, .ideas)
            XCTAssertEqual(title, "better project cards")
        } else {
            XCTFail("Failed to parse add idea command")
        }

        if case .addMemory(let type, let title) = service.parseCommand(from: "UNGIT add todo: verify restore flow") {
            XCTAssertEqual(type, .todo)
            XCTAssertEqual(title, "verify restore flow")
        } else {
            XCTFail("Failed to parse add todo command")
        }
    }

    func testParserMapsParkCommands() {
        let service = NotesDraftService()

        if case .parkUpdate(let text) = service.parseCommand(from: "UNGIT park: Left off at timeline filter bug") {
            XCTAssertEqual(text, "Left off at timeline filter bug")
        } else {
            XCTFail("Failed to parse park command")
        }

        if case .parkUpdate(let text) = service.parseCommand(from: "UNGIT update park resume with proof verification") {
            XCTAssertEqual(text, "resume with proof verification")
        } else {
            XCTFail("Failed to parse update park command")
        }

        if case .preflightRestore = service.parseCommand(from: "UNGIT preflight restore") {
            XCTAssertTrue(true)
        } else {
            XCTFail("Failed to parse preflight restore command")
        }

        if case .handoff = service.parseCommand(from: "UNGIT handoff") {
            XCTAssertTrue(true)
        } else {
            XCTFail("Failed to parse handoff command")
        }

        if case .restoreLatestTrustedRollback = service.parseCommand(from: "UNGIT restore latest trusted rollback") {
            XCTAssertTrue(true)
        } else {
            XCTFail("Failed to parse restore latest trusted rollback command")
        }

        if case .restoreSnapshot(let id) = service.parseCommand(from: "UNGIT restore snapshot c8b48257-0bc6-4936-8aaa-d3eb60df532f") {
            XCTAssertEqual(id, "C8B48257-0BC6-4936-8AAA-D3EB60DF532F")
        } else {
            XCTFail("Failed to parse restore snapshot command")
        }

        if case .forkPoint(let title) = service.parseCommand(from: "UNGIT fork point: exploration split") {
            XCTAssertEqual(title, "exploration split")
        } else {
            XCTFail("Failed to parse fork point command")
        }

        if case .forkPoint(let title) = service.parseCommand(from: "UNGIT fork path") {
            XCTAssertNil(title)
        } else {
            XCTFail("Failed to parse fork path alias")
        }

        if case .pruneSnapshots(let apply) = service.parseCommand(from: "UNGIT prune snapshots") {
            XCTAssertFalse(apply)
        } else {
            XCTFail("Failed to parse prune snapshots preview command")
        }

        if case .pruneSnapshots(let apply) = service.parseCommand(from: "UNGIT prune snapshots: confirm") {
            XCTAssertTrue(apply)
        } else {
            XCTFail("Failed to parse prune snapshots confirm command")
        }

        if case .pruneSnapshot(let id, let apply) = service.parseCommand(from: "UNGIT prune snapshot 12345678-1234-1234-1234-1234567890AB") {
            XCTAssertEqual(id, "12345678-1234-1234-1234-1234567890AB")
            XCTAssertFalse(apply)
        } else {
            XCTFail("Failed to parse prune snapshot preview command")
        }

        if case .pruneSnapshot(let id, let apply) = service.parseCommand(from: "UNGIT prune snapshot 12345678-1234-1234-1234-1234567890AB: confirm") {
            XCTAssertEqual(id, "12345678-1234-1234-1234-1234567890AB")
            XCTAssertTrue(apply)
        } else {
            XCTFail("Failed to parse prune snapshot confirm command")
        }

        if case .verifySnapshot(let id, let mode) = service.parseCommand(from: "UNGIT verify snapshot c8b48257-0bc6-4936-8aaa-d3eb60df532f archive") {
            XCTAssertEqual(id, "C8B48257-0BC6-4936-8AAA-D3EB60DF532F")
            XCTAssertEqual(mode, .archive)
        } else {
            XCTFail("Failed to parse verify snapshot command")
        }

        if case .verifyLatest(let kind, let mode) = service.parseCommand(from: "UNGIT verify latest milestone") {
            XCTAssertEqual(kind, .milestone)
            XCTAssertNil(mode)
        } else {
            XCTFail("Failed to parse verify latest milestone command")
        }

        if case .showTimeline = service.parseCommand(from: "UNGIT show timeline") {
            XCTAssertTrue(true)
        } else {
            XCTFail("Failed to parse show timeline command")
        }

        if case .showSnapshot(let id) = service.parseCommand(from: "UNGIT show snapshot c8b48257-0bc6-4936-8aaa-d3eb60df532f") {
            XCTAssertEqual(id, "C8B48257-0BC6-4936-8AAA-D3EB60DF532F")
        } else {
            XCTFail("Failed to parse show snapshot command")
        }
    }

    func testRestoreRequiresExplicitConfirmation() {
        let router = UngitToolRouter()
        let result = router.execute(tool: "ungit_restore_snapshot", arguments: [
            "project_path": .string("/tmp/example"),
            "snapshot_id": .string("abc"),
            "confirm_restore": .bool(false)
        ])

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.stepFailed, "validation")
    }

    func testRestoreRequiresApprovalToken() {
        let router = UngitToolRouter()
        let result = router.execute(tool: "ungit_restore_snapshot", arguments: [
            "project_path": .string("/tmp/example"),
            "snapshot_id": .string("abc"),
            "confirm_restore": .bool(true)
        ])

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.stepFailed, "approval")
    }

    func testQuickSaveRequiresProjectPath() {
        let router = UngitToolRouter()
        let result = router.execute(tool: "ungit_quick_save", arguments: [
            "kind": .string("save")
        ])

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.stepFailed, "validation")
    }

    func testCheckpointAdvisorRecommendsQuickSaveForSmallChanges() throws {
        let projectURL = try makeInitializedProject(named: "CheckpointSmall")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let router = UngitToolRouter()
        let result = router.execute(tool: "ungit_checkpoint_advisor", arguments: [
            "project_path": .string(projectURL.path),
            "planned_change_scope": .string("small"),
            "files_touched_estimate": .number(1)
        ])

        XCTAssertTrue(result.ok)
        let data = result.data?.objectValue
        XCTAssertEqual(data?["recommendation"]?.stringValue, "quick_save")
        XCTAssertEqual(data?["risk_level"]?.stringValue, "Low")
    }

    func testCheckpointAdvisorRecommendsPreChangeForStructuralChanges() throws {
        let projectURL = try makeInitializedProject(named: "CheckpointLarge")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let router = UngitToolRouter()
        let result = router.execute(tool: "ungit_checkpoint_advisor", arguments: [
            "project_path": .string(projectURL.path),
            "planned_change_scope": .string("medium"),
            "files_touched_estimate": .number(3),
            "change_type": .string("architecture")
        ])

        XCTAssertTrue(result.ok)
        let data = result.data?.objectValue
        XCTAssertEqual(data?["recommendation"]?.stringValue, "pre_change")
        XCTAssertEqual(data?["risk_level"]?.stringValue, "High")
    }

    func testCheckpointAdvisorRecommendsNoneWhenNoFilesPlanned() throws {
        let projectURL = try makeInitializedProject(named: "CheckpointNone")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let router = UngitToolRouter()
        let result = router.execute(tool: "ungit_checkpoint_advisor", arguments: [
            "project_path": .string(projectURL.path),
            "planned_change_scope": .string("small"),
            "files_touched_estimate": .number(0)
        ])

        XCTAssertTrue(result.ok)
        let data = result.data?.objectValue
        XCTAssertEqual(data?["recommendation"]?.stringValue, "none")
        XCTAssertEqual(data?["risk_level"]?.stringValue, "Low")
    }

    func testWriteVerificationDetectsMissingArtifacts() {
        let router = UngitToolRouter()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ungit-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = router.verifyWrite(projectURL: tmp, returnedID: "missing-id")
        XCTAssertFalse(result.manifestExists)
        XCTAssertFalse(result.archiveExists)
        XCTAssertFalse(result.allPassed)
    }

    @MainActor
    func testProjectStoreQuickSaveCommandWritesManifestAndArchive() async throws {
        let projectURL = try makeInitializedProject(named: "AppPathQuickSave")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let store = ProjectStore()
        await store.openProject(at: projectURL)
        let result = await store.executePromptCommandIfPresent("UNGIT quick save")

        guard case .quickSaved(let snapshotID, let title) = result else {
            XCTFail("Expected quickSaved result, got \(result)")
            return
        }

        XCTAssertEqual(title, "Quick Save")

        let layout = ProjectLayout(projectURL: projectURL)
        let manifestURL = layout.manifestsURL.appendingPathComponent("\(snapshotID).json", isDirectory: false)
        let archiveURL = layout.snapshotsURL.appendingPathComponent("\(snapshotID).zip", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    @MainActor
    func testProjectStoreAddMemoryCommandsAppendToFiles() async throws {
        let projectURL = try makeInitializedProject(named: "AppPathMemory")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let store = ProjectStore()
        await store.openProject(at: projectURL)

        let bugResult = await store.executePromptCommandIfPresent("UNGIT add bug: Crash in proof parser")
        guard case .memoryAdded(let type, let entryID) = bugResult else {
            XCTFail("Expected memoryAdded result for bug")
            return
        }
        XCTAssertEqual(type, .bugs)
        XCTAssertTrue(entryID.hasPrefix("BUG-"))

        let bugFile = projectURL.appendingPathComponent("BUGS.md", isDirectory: false)
        let bugContent = try String(contentsOf: bugFile, encoding: .utf8)
        XCTAssertTrue(bugContent.contains(entryID))
        XCTAssertTrue(bugContent.contains("Crash in proof parser"))

        let parkResult = await store.executePromptCommandIfPresent("UNGIT park: resume from restore preflight")
        guard case .memoryAdded(let parkType, let parkID) = parkResult else {
            XCTFail("Expected memoryAdded result for park")
            return
        }
        XCTAssertEqual(parkType, .park)
        XCTAssertTrue(parkID.hasPrefix("PARK-"))

        let parkFile = projectURL.appendingPathComponent("PARK.md", isDirectory: false)
        let parkContent = try String(contentsOf: parkFile, encoding: .utf8)
        XCTAssertTrue(parkContent.contains(parkID))
        XCTAssertTrue(parkContent.contains("resume from restore preflight"))
    }

    @MainActor
    func testProjectStoreForkPointCommandCreatesPreChangeSnapshot() async throws {
        let projectURL = try makeInitializedProject(named: "ForkPointSemantic")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let store = ProjectStore()
        await store.openProject(at: projectURL)

        let result = await store.executePromptCommandIfPresent("UNGIT fork point")
        guard case .quickSaved(let snapshotID, let title) = result else {
            XCTFail("Expected quickSaved from fork point")
            return
        }
        XCTAssertEqual(title, "Fork Point")

        let timeline = store.timeline
        guard let entry = timeline.first(where: { $0.id == snapshotID }) else {
            XCTFail("Fork point snapshot missing in timeline")
            return
        }
        XCTAssertEqual(entry.snapshotType, .preChange)
        XCTAssertEqual(entry.status, .working)
        XCTAssertEqual(store.project?.currentPathName, "main")
    }

    @MainActor
    func testProjectStorePruneSnapshotsKeepsHistoryAndMarksPrunedArchives() async throws {
        let projectURL = try makeInitializedProject(named: "PrunePolicy")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let store = ProjectStore()
        await store.openProject(at: projectURL)

        for idx in 1...12 {
            let result = await store.executePromptCommandIfPresent("UNGIT quick save: Incremental \(idx)")
            guard case .quickSaved = result else {
                XCTFail("Expected quickSaved for incremental \(idx)")
                return
            }
        }

        let milestone = await store.executePromptCommandIfPresent("UNGIT quick milestone: Anchor")
        guard case .quickSaved = milestone else {
            XCTFail("Expected milestone snapshot")
            return
        }

        let preview = await store.executePromptCommandIfPresent("UNGIT prune snapshots")
        guard case .prune(let previewReport) = preview else {
            XCTFail("Expected prune preview report")
            return
        }
        XCTAssertTrue(previewReport.contains("Prune Preview"))

        let apply = await store.executePromptCommandIfPresent("UNGIT prune snapshots: confirm")
        guard case .prune(let applyReport) = apply else {
            XCTFail("Expected prune apply report")
            return
        }
        XCTAssertTrue(applyReport.contains("Prune Complete"))

        let timeline = store.timeline
        XCTAssertEqual(timeline.count, 13)

        let pruned = timeline.filter { !$0.archiveAvailable }
        XCTAssertEqual(pruned.count, 2)
        XCTAssertTrue(pruned.allSatisfy { $0.snapshotType == .featureWorks })

        let milestoneEntry = timeline.first(where: { $0.snapshotType == .milestone })
        XCTAssertEqual(milestoneEntry?.archiveAvailable, true)
    }

    @MainActor
    func testProjectStorePruneSnapshotByIDPreviewAndApply() async throws {
        let projectURL = try makeInitializedProject(named: "PruneSingle")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let store = ProjectStore()
        await store.openProject(at: projectURL)

        let first = await store.executePromptCommandIfPresent("UNGIT quick save: One")
        guard case .quickSaved(let firstID, _) = first else {
            XCTFail("Expected first quick save")
            return
        }
        _ = await store.executePromptCommandIfPresent("UNGIT quick save: Two")

        let preview = await store.executePromptCommandIfPresent("UNGIT prune snapshot \(firstID)")
        guard case .prune(let previewReport) = preview else {
            XCTFail("Expected prune preview result")
            return
        }
        XCTAssertTrue(previewReport.contains("Prune Snapshot Preview"))

        let apply = await store.executePromptCommandIfPresent("UNGIT prune snapshot \(firstID): confirm")
        guard case .prune(let applyReport) = apply else {
            XCTFail("Expected prune apply result")
            return
        }
        XCTAssertTrue(applyReport.contains("Prune Snapshot Complete"))

        guard let entry = store.timeline.first(where: { $0.id == firstID }) else {
            XCTFail("Expected pruned entry in timeline")
            return
        }
        XCTAssertFalse(entry.archiveAvailable)
    }

    @MainActor
    func testReleaseArchiveIsProtectedFromPruneByPolicy() async throws {
        let projectURL = try makeInitializedProject(named: "ReleaseLock")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let store = ProjectStore()
        await store.openProject(at: projectURL)

        let save = await store.executePromptCommandIfPresent("UNGIT quick release")
        guard case .quickSaved(let snapshotID, _) = save else {
            XCTFail("Expected quickSaved release snapshot")
            return
        }

        guard store.timeline.contains(where: { $0.id == snapshotID }) else {
            XCTFail("Missing release snapshot entry")
            return
        }
        let manifestURL = projectURL
            .appendingPathComponent(".ungit", isDirectory: true)
            .appendingPathComponent("manifests", isDirectory: true)
            .appendingPathComponent("\(snapshotID).json", isDirectory: false)
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(SnapshotManifest.self, from: data)
        XCTAssertTrue(manifest.archiveLocked ?? false)

        let prune = await store.executePromptCommandIfPresent("UNGIT prune snapshot \(snapshotID): confirm")
        guard case .prune(let report) = prune else {
            XCTFail("Expected prune report for locked release")
            return
        }
        XCTAssertTrue(report.contains("protected and cannot be pruned"))
    }

    func testRestoreDrillMixedProjectShape() throws {
        let projectURL = try makeInitializedProject(named: "RestoreDrillMixed")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        // SwiftPM shape
        try write("import Foundation\n", to: projectURL.appendingPathComponent("Package.swift", isDirectory: false))
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("Sources/App", isDirectory: true), withIntermediateDirectories: true)
        try write("print(\"hello\")\n", to: projectURL.appendingPathComponent("Sources/App/main.swift", isDirectory: false))

        // Xcode workspace / project shape
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("UNGIT.xcworkspace", isDirectory: true), withIntermediateDirectories: true)
        try write("<Workspace version=\"1.0\"></Workspace>\n", to: projectURL.appendingPathComponent("UNGIT.xcworkspace/contents.xcworkspacedata", isDirectory: false))
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("UNGIT.xcodeproj", isDirectory: true), withIntermediateDirectories: true)
        try write("// !$*UTF8*$!\n", to: projectURL.appendingPathComponent("UNGIT.xcodeproj/project.pbxproj", isDirectory: false))

        // Mixed assets shape
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true), withIntermediateDirectories: true)
        try write("{\"images\":[],\"info\":{\"version\":1,\"author\":\"xcode\"}}", to: projectURL.appendingPathComponent("Assets.xcassets/AppIcon.appiconset/Contents.json", isDirectory: false))
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("Resources", isDirectory: true), withIntermediateDirectories: true)
        try write("data", to: projectURL.appendingPathComponent("Resources/sample.bin", isDirectory: false))

        let initializer = ProjectInitializer()
        let snapshotService = SnapshotService()
        let restoreService = RestoreSafetyService()
        let project = try initializer.loadProject(at: projectURL)
        let notes = SnapshotNotes(
            title: "Restore Drill Baseline",
            summary: "baseline",
            whatChanged: "",
            why: "",
            importantFilesTouched: [],
            gotchas: "",
            tags: ["drill"],
            status: .trusted,
            snapshotType: .milestone,
            pathName: "main",
            proofCommand: "",
            linkedMemoryIDs: []
        )
        let saved = try snapshotService.saveSnapshot(projectURL: projectURL, project: project, notes: notes)

        // Mutate project heavily to simulate drift/regression.
        try? FileManager.default.removeItem(at: projectURL.appendingPathComponent("Sources", isDirectory: true))
        try? FileManager.default.removeItem(at: projectURL.appendingPathComponent("UNGIT.xcworkspace", isDirectory: true))
        try? FileManager.default.removeItem(at: projectURL.appendingPathComponent("Assets.xcassets", isDirectory: true))
        try write("junk", to: projectURL.appendingPathComponent("junk.tmp", isDirectory: false))

        try restoreService.restoreSnapshot(
            projectURL: projectURL,
            entry: saved,
            project: project,
            snapshotService: snapshotService
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("Sources/App/main.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("UNGIT.xcworkspace/contents.xcworkspacedata").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("Assets.xcassets/AppIcon.appiconset/Contents.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("junk.tmp").path))

        let drillsURL = projectURL.appendingPathComponent("RESTORE_DRILLS.md", isDirectory: false)
        let drills = try String(contentsOf: drillsURL, encoding: .utf8)
        XCTAssertTrue(drills.contains("Snapshot ID: \(saved.id)"))
        XCTAssertTrue(drills.contains("Outcome: Success"))
    }

    func testPathServiceForkCloneIsDeprecated() throws {
        let projectURL = try makeInitializedProject(named: "PathDeprecated")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let initializer = ProjectInitializer()
        let snapshotService = SnapshotService()
        let project = try initializer.loadProject(at: projectURL)

        let notes = SnapshotNotes(
            title: "Baseline",
            summary: "",
            whatChanged: "",
            why: "",
            importantFilesTouched: [],
            gotchas: "",
            tags: [],
            status: .working,
            snapshotType: .featureWorks,
            pathName: "main",
            proofCommand: "",
            linkedMemoryIDs: []
        )
        let saved = try snapshotService.saveSnapshot(projectURL: projectURL, project: project, notes: notes)

        XCTAssertThrowsError(
            try PathService().createPathFromSnapshot(
                projectURL: projectURL,
                project: project,
                snapshotEntry: saved,
                pathName: "deprecated-fork",
                destinationFolderURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("deprecated"))
        }
    }

    func testManifestStoreSkipsCorruptManifestAndReportsIssue() throws {
        let projectURL = try makeInitializedProject(named: "ManifestCorruption")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let initializer = ProjectInitializer()
        let snapshotService = SnapshotService()
        let project = try initializer.loadProject(at: projectURL)

        let notes = SnapshotNotes(
            title: "Valid Snapshot",
            summary: "",
            whatChanged: "",
            why: "",
            importantFilesTouched: [],
            gotchas: "",
            tags: [],
            status: .working,
            snapshotType: .featureWorks,
            pathName: "main",
            proofCommand: "",
            linkedMemoryIDs: []
        )
        _ = try snapshotService.saveSnapshot(projectURL: projectURL, project: project, notes: notes)

        let layout = ProjectLayout(projectURL: projectURL)
        let corruptURL = layout.manifestsURL.appendingPathComponent("CORRUPT.json", isDirectory: false)
        try write("{ not-valid-json ", to: corruptURL)

        let loaded = try ManifestStore().loadAllManifestsWithIssues(at: layout)
        XCTAssertFalse(loaded.manifests.isEmpty)
        XCTAssertEqual(loaded.issues.count, 1)
        XCTAssertEqual(loaded.issues.first?.fileName, "CORRUPT.json")
    }

    func testRestorePreflightToolDetectsCorruptManifestAndStillEvaluatesArchive() throws {
        let projectURL = try makeInitializedProject(named: "PreflightHealth")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let initializer = ProjectInitializer()
        let snapshotService = SnapshotService()
        let project = try initializer.loadProject(at: projectURL)

        let notes = SnapshotNotes(
            title: "Trusted",
            summary: "",
            whatChanged: "",
            why: "",
            importantFilesTouched: [],
            gotchas: "",
            tags: [],
            status: .rollbackPoint,
            snapshotType: .trustedRollback,
            pathName: "main",
            proofCommand: "",
            linkedMemoryIDs: []
        )
        let saved = try snapshotService.saveSnapshot(projectURL: projectURL, project: project, notes: notes)

        let layout = ProjectLayout(projectURL: projectURL)
        try write("{bad", to: layout.manifestsURL.appendingPathComponent("BROKEN.json", isDirectory: false))

        let router = UngitToolRouter()
        let envelope = router.execute(tool: "ungit_restore_preflight", arguments: [
            "project_path": .string(projectURL.path),
            "snapshot_id": .string(saved.id)
        ])

        XCTAssertTrue(envelope.ok)
        let data = envelope.data?.objectValue
        XCTAssertEqual(data?["snapshot_id"]?.stringValue, saved.id)
        XCTAssertEqual(data?["archive_exists"]?.boolValue, true)
        XCTAssertEqual(data?["archive_valid"]?.boolValue, true)
        XCTAssertEqual(data?["can_proceed"]?.boolValue, true)
        XCTAssertEqual(data?["manifest_issue_count"]?.intValue, 1)
    }

    func testReviewTimelineToolReturnsContinuityMetadataAndRestoreDrills() throws {
        let projectURL = try makeInitializedProject(named: "ContinuityReview")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let initializer = ProjectInitializer()
        let snapshotService = SnapshotService()
        let project = try initializer.loadProject(at: projectURL)

        let olderNotes = SnapshotNotes(
            title: "Anchor",
            summary: "anchor summary",
            whatChanged: "",
            why: "",
            importantFilesTouched: [],
            gotchas: "",
            tags: ["anchor"],
            status: .trusted,
            snapshotType: .milestone,
            pathName: "main",
            proofCommand: "",
            linkedMemoryIDs: [],
            changeIntent: "Stabilize baseline",
            riskLevel: .low,
            outcome: .worked
        )
        let older = try snapshotService.saveSnapshot(projectURL: projectURL, project: project, notes: olderNotes)

        let newerNotes = SnapshotNotes(
            title: "Risky Refactor",
            summary: "refactor",
            whatChanged: "",
            why: "",
            importantFilesTouched: [],
            gotchas: "",
            tags: ["refactor"],
            status: .working,
            snapshotType: .preChange,
            pathName: "main",
            proofCommand: "",
            linkedMemoryIDs: [],
            changeIntent: "Reshape restore flow safely",
            riskLevel: .high,
            outcome: .partial
        )
        let newer = try snapshotService.saveSnapshot(projectURL: projectURL, project: project, notes: newerNotes)

        let drillsURL = projectURL.appendingPathComponent("RESTORE_DRILLS.md", isDirectory: false)
        let drillLog = """
        # RESTORE_DRILLS

        Restore drill history with outcomes, notes, and follow-up issues.

        ## Restore Drill 2026-04-03T12:00:00Z
        - Snapshot ID: \(newer.id)
        - Snapshot Title: \(newer.title)
        - Outcome: Success
        - Notes: Archive replay validated.
        """
        try write(drillLog, to: drillsURL)

        let router = UngitToolRouter()
        let envelope = router.execute(tool: "ungit_review_timeline", arguments: [
            "project_path": .string(projectURL.path),
            "from_snapshot_id": .string(older.id),
            "focus": .string("drift")
        ])

        XCTAssertTrue(envelope.ok)
        let data = envelope.data?.objectValue
        XCTAssertEqual(data?["focus"]?.stringValue, "drift")
        XCTAssertEqual(data?["snapshot_count"]?.intValue, 2)
        XCTAssertEqual(data?["from_snapshot_id"]?.stringValue, older.id)

        let snapshots = data?["snapshots"]?.arrayValue ?? []
        XCTAssertEqual(snapshots.count, 2)
        let newestRow = snapshots.first?.objectValue
        XCTAssertEqual(newestRow?["id"]?.stringValue, newer.id)
        XCTAssertEqual(newestRow?["change_intent"]?.stringValue, "Reshape restore flow safely")
        XCTAssertEqual(newestRow?["risk_level"]?.stringValue, "High")
        XCTAssertEqual(newestRow?["outcome"]?.stringValue, "Partial")

        let highRiskIDs = data?["high_risk_snapshot_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertEqual(highRiskIDs, [newer.id])

        let partialOrRevertedIDs = data?["partial_or_reverted_snapshot_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertEqual(partialOrRevertedIDs, [newer.id])

        let drills = data?["restore_drills"]?.arrayValue ?? []
        XCTAssertEqual(drills.count, 1)
        XCTAssertEqual(drills.first?.objectValue?["snapshot_id"]?.stringValue, newer.id)

        let highRiskWithoutDrill = data?["high_risk_without_restore_drill_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertTrue(highRiskWithoutDrill.isEmpty)
    }

    private func makeInitializedProject(named name: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ungit-e2e-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try ProjectInitializer().initializeProjectIfNeeded(at: root)
        try write("# \(name)\n", to: root.appendingPathComponent("README.md", isDirectory: false))
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
