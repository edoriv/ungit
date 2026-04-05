import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let ungitSelectWorkspacePanel = Notification.Name("ungit.selectWorkspacePanel")
}

enum WorkspacePanel: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case summary = "Summary"
    case bugs = "Bugs"
    case ideas = "Ideas"
    case todo = "TODO"
    case park = "Park"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .timeline: return "clock.arrow.circlepath"
        case .summary: return "text.book.closed"
        case .bugs: return "ladybug"
        case .ideas: return "lightbulb"
        case .todo: return "checklist"
        case .park: return "parkingsign"
        }
    }

    var memoryType: MemoryFileType? {
        switch self {
        case .timeline: return nil
        case .summary: return .summary
        case .bugs: return .bugs
        case .ideas: return .ideas
        case .todo: return .todo
        case .park: return .park
        }
    }
}

struct ContentView: View {
    @StateObject private var store = ProjectStore()

    @State private var showSnapshotSheet = false
    @State private var restoreConfirmationVisible = false
    @State private var snapshotDraft = SnapshotDraft.empty(pathName: "main")
    @State private var selectedDaySummary: TimelineDaySummary?
    @State private var showRightSidebar = true
    @State private var selectedPanel: WorkspacePanel = .timeline
    @State private var memoryContent = ""
    @State private var showProjectSummaryPrompt = false
    @State private var projectSummaryPromptText = ""
    @State private var checkpointReminderVisible = false
    @State private var checkpointReminderText = ""
    private let xcodeBundleID = "com.apple.dt.Xcode"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                NavigationSplitView {
                    VStack(spacing: 10) {
                        if let project = store.project {
                            ProjectSummaryHeaderView(
                                project: project,
                                entries: store.timeline,
                                snapshotsStorageBytes: store.snapshotsStorageBytes,
                                currentStateText: currentStateText,
                                currentStateColor: currentStateColor
                            )
                        }

                        if store.project == nil {
                            ContentUnavailableView(
                                "No Project Loaded",
                                systemImage: "folder.badge.questionmark",
                                description: Text("Choose a folder and UNGIT will initialize local snapshot storage in .ungit.")
                            )
                            .padding(.top, 40)
                        }

                        panelPicker

                        TimelineListView(
                            entries: store.timeline,
                            selectedID: selectedIDBinding,
                            onSelectDaySummary: { summary in
                                selectedDaySummary = summary
                            }
                        )
                    }
                    .navigationTitle("Timeline")
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            HStack(spacing: 8) {
                                projectMenu
                                actionsMenu
                            }
                        }
                    }
                } detail: {
                    Group {
                        if selectedPanel == .timeline {
                            VStack(spacing: 0) {
                                if let selectedDaySummary {
                                    DaySummaryInspectorView(summary: selectedDaySummary)
                                } else {
                                    SnapshotInspectorView(entry: store.selectedEntry, manifest: store.selectedManifest)
                                }

                                Divider()

                                HStack(spacing: 10) {
                                    Text(store.statusMessage)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    if store.isBusy {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                .padding(10)
                            }
                            .navigationTitle(store.project?.name ?? "UNGIT")
                        } else {
                            memoryPanelView
                        }
                    }
                }
                .frame(minWidth: 760)

                if showRightSidebar {
                    Divider()
                    CommandsReferenceView()
                        .frame(width: 390)
                }
            }
            Button {
                showRightSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(showRightSidebar ? "Hide right sidebar" : "Show right sidebar")
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .sheet(isPresented: $showSnapshotSheet) {
            SnapshotEditorSheet(draft: snapshotDraft, title: "Save Snapshot") { draft in
                Task { await store.saveSnapshot(draft: draft) }
            }
        }
        .sheet(isPresented: $showProjectSummaryPrompt) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Project Summary / Goals")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Set a clear home base for this project so timeline decisions stay aligned.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $projectSummaryPromptText)
                    .font(.body.monospaced())
                    .frame(minHeight: 260)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )

                HStack {
                    Button("Not Now") {
                        store.deferProjectSummaryPrompt()
                        showProjectSummaryPrompt = false
                    }
                    Spacer()
                    Button("Save Summary") {
                        Task { await store.saveProjectSummary(content: projectSummaryPromptText) }
                        selectedPanel = .summary
                        showProjectSummaryPrompt = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(minWidth: 680, minHeight: 430)
        }
        .alert("Restore Snapshot?", isPresented: $restoreConfirmationVisible) {
            Button("Cancel", role: .cancel) {
                store.cancelPendingRestoreApproval()
            }
            Button("Restore", role: .destructive) {
                Task { await runProtectedRestoreFlow() }
            }
        } message: {
            Text("UNGIT will first create a safety snapshot of your current project, then replace the live project files with the selected snapshot.")
        }
        .alert("Error", isPresented: Binding(get: {
            store.errorMessage != nil
        }, set: { newValue in
            if !newValue {
                DispatchQueue.main.async {
                    store.errorMessage = nil
                }
            }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert("Snapshot Reminder", isPresented: $checkpointReminderVisible) {
            Button("Later", role: .cancel) {
                store.consumeCheckpointReminder()
            }
            Button("Quick Save") {
                Task { await store.saveQuickSnapshot(type: .featureWorks, title: "Quick Save") }
                store.consumeCheckpointReminder()
            }
            Button("Pre-Change") {
                Task { await store.saveQuickSnapshot(type: .preChange, title: "Pre-Change") }
                store.consumeCheckpointReminder()
            }
        } message: {
            Text(checkpointReminderText)
        }
        .task {
            await store.openMostRecentProjectIfAvailable()
            await loadSelectedMemoryIfNeeded()
        }
        .onChange(of: selectedPanel) { _, _ in
            Task { await loadSelectedMemoryIfNeeded() }
        }
        .onChange(of: store.shouldPromptForProjectSummary) { _, shouldPrompt in
            if shouldPrompt {
                projectSummaryPromptText = store.projectSummaryDraft
                showProjectSummaryPrompt = true
            }
        }
        .onChange(of: store.checkpointReminderMessage) { _, message in
            guard let message, !message.isEmpty else { return }
            checkpointReminderText = message
            checkpointReminderVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .ungitSelectWorkspacePanel)) { notification in
            guard let raw = notification.object as? String,
                  let panel = WorkspacePanel(rawValue: raw) else { return }
            selectedPanel = panel
        }
    }

    private var selectedIDBinding: Binding<String?> {
        Binding(
            get: { store.selectedEntry?.id },
            set: { newID in
                DispatchQueue.main.async {
                    selectedPanel = .timeline
                    selectedDaySummary = nil
                    store.selectedEntry = store.timeline.first(where: { $0.id == newID })
                }
            }
        )
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder"

        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.openProject(at: url) }
        }
    }

    private var currentStateText: String {
        switch store.currentStateStatus {
        case .matchesLatestSnapshot:
            return "Current State: Matches latest snapshot"
        case .notSavedSinceLastSnapshot:
            return "Current State: Not saved since last snapshot"
        case .noSnapshotsYet:
            return "Current State: No snapshots yet"
        case .unknown:
            return "Current State: Unknown"
        }
    }

    private var currentStateColor: Color {
        switch store.currentStateStatus {
        case .matchesLatestSnapshot:
            return .green
        case .notSavedSinceLastSnapshot:
            return .orange
        case .noSnapshotsYet, .unknown:
            return .gray
        }
    }

    private var panelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkspacePanel.allCases) { panel in
                    Button {
                        selectedPanel = panel
                    } label: {
                        Image(systemName: panel.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedPanel == panel ? .accentColor : .gray)
                    .help(panel.rawValue)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var projectMenu: some View {
        Menu("Project") {
            Button("Open Project…") {
                openProject()
            }

            Menu("Recent Projects") {
                if store.recentProjects.isEmpty {
                    Text("No recent projects")
                } else {
                    ForEach(store.recentProjects) { recent in
                        Button(recent.name) {
                            Task { await store.openRecentProject(path: recent.path) }
                        }
                        .help(recent.path)
                    }
                }
            }
        }
    }

    private var actionsMenu: some View {
        Menu("Actions") {
            Section("Save") {
                Button("Quick Save") {
                    Task { await store.saveQuickSnapshot(type: .featureWorks, title: "Quick Save") }
                }
                Button("Quick Pre-Change") {
                    Task { await store.saveQuickSnapshot(type: .preChange, title: "Pre-Change") }
                }
                Button("Quick Feature Works") {
                    Task { await store.saveQuickSnapshot(type: .featureWorks, title: "Feature Works") }
                }
                Button("Quick Trusted Rollback") {
                    Task { await store.saveQuickSnapshot(type: .trustedRollback, title: "Trusted Rollback") }
                }
                Button("Quick Milestone") {
                    Task { await store.saveQuickSnapshot(type: .milestone, title: "Milestone") }
                }
                Button("Quick Release Candidate") {
                    Task { await store.saveQuickSnapshot(type: .releaseCandidate, title: "Release Candidate") }
                }
                Button("Quick Release") {
                    Task { await store.saveQuickSnapshot(type: .release, title: "Release") }
                }
                Button("Fork Point") {
                    Task { _ = await store.executePromptCommandIfPresent("UNGIT fork point") }
                }
            }

            Section("Review") {
                Button("Review Save") {
                    snapshotDraft = store.draftFromShortInput("Review Save")
                    showSnapshotSheet = true
                }
                Button("Review Save: Capture Critical Lesson") {
                    snapshotDraft = store.draftCriticalLesson()
                    showSnapshotSheet = true
                }
            }

            Section("Restore / Verify") {
                Button("Restore Selected Snapshot…") {
                    guard store.selectedEntry != nil else { return }
                    restoreConfirmationVisible = true
                }
                .disabled(store.selectedEntry == nil)

                Button("Verify Selected Snapshot") {
                    guard let selected = store.selectedEntry else { return }
                    Task { _ = await store.executePromptCommandIfPresent("UNGIT verify snapshot \(selected.id)") }
                }
                .disabled(store.selectedEntry == nil)

                Button("Verify Selected Snapshot (Archive)") {
                    guard let selected = store.selectedEntry else { return }
                    Task { _ = await store.executePromptCommandIfPresent("UNGIT verify snapshot \(selected.id) archive") }
                }
                .disabled(store.selectedEntry == nil)
            }

            Section("Utility") {
                Button("UNGIT handoff…") {
                    exportTimelineWithSavePanel(mode: .projectHandoff)
                }

                Menu("Export Timeline") {
                    ForEach(TimelineExportMode.allCases) { mode in
                        Button(mode.rawValue) {
                            exportTimelineWithSavePanel(mode: mode)
                        }
                    }
                }

            }
        }
    }

    private func exportTimelineWithSavePanel(mode: TimelineExportMode) {
        guard store.projectURL != nil else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = store.defaultExportFileName(for: mode)
        panel.title = "Export \(mode.rawValue)"
        panel.message = "Choose where to save the timeline export."

        if panel.runModal() == .OK, let destination = panel.url {
            Task { await store.exportTimeline(mode: mode, destinationURL: destination) }
        }
    }

    private var memoryPanelView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedPanel.rawValue)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            TextEditor(text: $memoryContent)
                .font(.body.monospaced())
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .navigationTitle(store.project?.name ?? "UNGIT")
    }

    private func loadSelectedMemoryIfNeeded() async {
        guard let type = selectedPanel.memoryType else { return }
        memoryContent = await store.loadMemoryContent(type: type)
    }

    private enum XcodeRestoreChoice {
        case quitAndRestore
        case restoreAnyway
        case cancel
    }

    private enum XcodeQuitTimeoutChoice {
        case keepWaiting
        case cancelRestore
        case forceQuitAndRestore
    }

    @MainActor
    private func runProtectedRestoreFlow() async {
        var closedXcodeForRestore = false
        let approvalToken: String

        do {
            approvalToken = try store.issueRestoreApprovalTokenForSelectedSnapshot()
        } catch {
            store.errorMessage = error.localizedDescription
            return
        }

        if isXcodeRunning {
            let choice = promptXcodeRestoreChoice()
            switch choice {
            case .cancel:
                store.cancelPendingRestoreApproval()
                return
            case .restoreAnyway:
                break
            case .quitAndRestore:
                let didClose = await closeXcodeBeforeRestore()
                guard didClose else {
                    store.cancelPendingRestoreApproval()
                    return
                }
                closedXcodeForRestore = true
            }
        }

        await store.restoreSelectedSnapshot(approvalToken: approvalToken)
        guard store.errorMessage == nil else { return }

        if closedXcodeForRestore {
            promptToReopenRestoredProject()
        }
    }

    private var isXcodeRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: xcodeBundleID).isEmpty
    }

    @MainActor
    private func promptXcodeRestoreChoice() -> XcodeRestoreChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Xcode Is Open"
        alert.informativeText = "Restoring while Xcode is open can cause indexing and file watcher issues. It is safer to quit Xcode before Restore."
        alert.addButton(withTitle: "Quit Xcode and Restore")
        alert.addButton(withTitle: "Restore Anyway")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .quitAndRestore
        case .alertSecondButtonReturn:
            return .restoreAnyway
        default:
            return .cancel
        }
    }

    @MainActor
    private func closeXcodeBeforeRestore() async -> Bool {
        while isXcodeRunning {
            requestGracefulXcodeTermination()

            if await waitForXcodeToExit(timeoutSeconds: 10) {
                return true
            }

            let timeoutChoice = promptXcodeQuitTimeoutChoice()
            switch timeoutChoice {
            case .keepWaiting:
                continue
            case .cancelRestore:
                return false
            case .forceQuitAndRestore:
                forceTerminateXcode()
                if await waitForXcodeToExit(timeoutSeconds: 6) {
                    return true
                }
                showSimpleWarning(
                    title: "Xcode Still Running",
                    message: "UNGIT could not close Xcode. Restore was canceled to protect your project."
                )
                return false
            }
        }

        return true
    }

    private func requestGracefulXcodeTermination() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: xcodeBundleID)
        for app in apps {
            _ = app.terminate()
        }
    }

    private func forceTerminateXcode() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: xcodeBundleID)
        for app in apps {
            _ = app.forceTerminate()
        }
    }

    @MainActor
    private func promptXcodeQuitTimeoutChoice() -> XcodeQuitTimeoutChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Waiting For Xcode To Quit"
        alert.informativeText = "Xcode has not finished closing yet. Restore cannot begin until Xcode is fully closed."
        alert.addButton(withTitle: "Keep Waiting")
        alert.addButton(withTitle: "Cancel Restore")
        alert.addButton(withTitle: "Force Quit and Restore")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .keepWaiting
        case .alertSecondButtonReturn:
            return .cancelRestore
        default:
            return .forceQuitAndRestore
        }
    }

    private func waitForXcodeToExit(timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !isXcodeRunning {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return !isXcodeRunning
    }

    @MainActor
    private func promptToReopenRestoredProject() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Restore Complete"
        alert.informativeText = "UNGIT closed Xcode before Restore. Reopen the restored project now?"
        alert.addButton(withTitle: "Reopen Project")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            reopenRestoredProjectInXcode()
        }
    }

    private func reopenRestoredProjectInXcode() {
        guard let rootURL = store.projectURL else { return }
        let fm = FileManager.default
        let rootItems = (try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []

        if let workspace = rootItems.first(where: { $0.pathExtension == "xcworkspace" }) {
            NSWorkspace.shared.open(workspace)
            return
        }

        if let xcodeproj = rootItems.first(where: { $0.pathExtension == "xcodeproj" }) {
            NSWorkspace.shared.open(xcodeproj)
            return
        }

        showSimpleWarning(
            title: "No Xcode Project Found",
            message: "UNGIT could not find a .xcworkspace or .xcodeproj to reopen."
        )
    }

    @MainActor
    private func showSimpleWarning(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }

}

#Preview {
    ContentView()
}
