import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("UNGIT Help")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Local-first project snapshots with clear restore safety. UNGIT stores manifests and archives in your project’s `.ungit` folder.")
                    .foregroundStyle(.secondary)

                section("Core Terms", [
                    "Project: your working folder.",
                    "Snapshot: one saved project state (manifest + zip archive).",
                    "Timeline: ordered history of snapshots.",
                    "Restore: replace live files from a selected snapshot.",
                    "Milestone / Release Candidate / Release: high-value landmarks."
                ])

                section("Recommended Workflow", [
                    "1. Open a project and capture Project Summary / Goals.",
                    "2. Use `UNGIT quick save` for normal checkpoints.",
                    "3. Use `UNGIT quick pre-change` before risky refactors.",
                    "4. Use milestones and release landmarks at major points.",
                    "5. Verify important snapshots before relying on them for rollback."
                ])

                section("Verification Commands", [
                    "`UNGIT verify snapshot <snapshot-id>`",
                    "`UNGIT verify snapshot <snapshot-id> archive`",
                    "`UNGIT verify latest milestone`",
                    "`UNGIT verify latest trusted rollback`"
                ])

                section("Restore Safety", [
                    "Restore requires explicit approval before live mutation.",
                    "UNGIT creates a safety snapshot before restore.",
                    "Archive Proof runs in isolated temp workspace.",
                    "If Xcode is open, UNGIT can prompt to quit it first."
                ])

                section("Where Data Lives", [
                    "`.ungit/manifests`: snapshot metadata JSON.",
                    "`.ungit/snapshots`: zip archives.",
                    "Pruning removes archives only; history entries remain."
                ])

                section("For New Users", [
                    "Use the `Project` menu to open/switch recent projects.",
                    "Use `Actions` for save/review/restore/export tools.",
                    "Use the right command reference pane for command syntax."
                ])
            }
            .padding(16)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.body)
            }
        }
    }
}
