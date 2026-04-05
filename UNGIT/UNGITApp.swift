import SwiftUI

@main
struct UNGITApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Timeline") {
                    NotificationCenter.default.post(
                        name: .ungitSelectWorkspacePanel,
                        object: WorkspacePanel.timeline.rawValue
                    )
                }
                Button("Summary") {
                    NotificationCenter.default.post(
                        name: .ungitSelectWorkspacePanel,
                        object: WorkspacePanel.summary.rawValue
                    )
                }
                Button("Bugs") {
                    NotificationCenter.default.post(
                        name: .ungitSelectWorkspacePanel,
                        object: WorkspacePanel.bugs.rawValue
                    )
                }
                Button("Ideas") {
                    NotificationCenter.default.post(
                        name: .ungitSelectWorkspacePanel,
                        object: WorkspacePanel.ideas.rawValue
                    )
                }
                Button("TODO") {
                    NotificationCenter.default.post(
                        name: .ungitSelectWorkspacePanel,
                        object: WorkspacePanel.todo.rawValue
                    )
                }
                Button("Park") {
                    NotificationCenter.default.post(
                        name: .ungitSelectWorkspacePanel,
                        object: WorkspacePanel.park.rawValue
                    )
                }
            }
            CommandGroup(after: .windowArrangement) {
                Button("UNGIT MCP Log") {
                    MCPLogWindowManager.shared.show()
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("UNGIT Help") {
                    HelpWindowManager.shared.show()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
    }
}
