import SwiftUI
import AppKit

struct CommandsReferenceView: View {
    @State private var copiedText: String?

    private let groups: [(title: String, commands: [(command: String, tooltip: String)])] = [
        ("Save", [
            ("UNGIT quick save", "Auto title from current context"),
            ("UNGIT quick pre-change", "Auto title from current context"),
            ("UNGIT quick feature works", "Auto title from current context"),
            ("UNGIT quick trusted rollback", "Auto title from current context"),
            ("UNGIT quick milestone", "Auto title from current context"),
            ("UNGIT quick release candidate", "Create sacred release-candidate landmark"),
            ("UNGIT quick release", "Create sacred release landmark"),
            ("UNGIT save milestone", "Create a milestone snapshot"),
            ("UNGIT fork point", "Save a semantic divergence marker snapshot")
        ]),
        ("Review", [
            ("UNGIT review save", "Show drafted notes before saving"),
            ("UNGIT review save: capture critical lesson", "Document exact fix and why it worked")
        ]),
        ("Utility", [
            ("UNGIT handoff", "Generate project handoff export and choose save location"),
            ("UNGIT show timeline", "Show latest timeline activity"),
            ("UNGIT show snapshot <snapshot-id>", "Show details for one snapshot"),
            ("UNGIT verify snapshot <snapshot-id>", "Run proof checks for one snapshot using default mode"),
            ("UNGIT verify snapshot <snapshot-id> archive", "Run isolated archive replay proof for one snapshot"),
            ("UNGIT verify latest milestone", "Verify the newest Milestone snapshot"),
            ("UNGIT preflight restore", "Run non-destructive restore readiness checks")
        ]),
        ("Prune / Restore", [
            ("UNGIT prune snapshots", "Preview safe archive pruning (history kept)"),
            ("UNGIT prune snapshots: confirm", "Apply archive pruning using default retention policy"),
            ("UNGIT prune snapshot <snapshot-id>", "Preview pruning one specific snapshot archive"),
            ("UNGIT prune snapshot <snapshot-id>: confirm", "Apply prune for one specific snapshot archive"),
            ("UNGIT restore latest trusted rollback", "Use when current state regressed"),
            ("UNGIT restore snapshot <snapshot-id>", "Restore one specific snapshot ID")
        ]),
        ("Notes", [
            ("UNGIT add bug: <title>", "Add a bug entry to BUGS.md"),
            ("UNGIT add idea: <title>", "Add an idea entry to IDEAS.md"),
            ("UNGIT add todo: <title>", "Add a TODO entry to TODO.md"),
            ("UNGIT park: <note>", "Add a PARK entry for handoff/context"),
            ("UNGIT update park: <note>", "Add a PARK entry for current handoff/update")
        ])
    ]

    private let recoveryPrompts: [String] = [
        "Review the UNGIT timeline from the last trusted rollback to now.",
        "Look at the milestone where trash first worked, then compare the later fixes and tell me where intent drift probably happened.",
        "We lost the plot. Read the recent UNGIT snapshots and summarize what we were trying to do."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UNGIT Commands")
                .font(.headline)
                .fontWeight(.semibold)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(groups, id: \.title) { group in
                        Text(group.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)

                        ForEach(group.commands, id: \.command) { item in
                            Button {
                                copy(item.command)
                                copiedText = item.command
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(item.command)
                                        .foregroundStyle(.primary)
                                        .font(.system(.callout, design: .monospaced))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.84)
                                        .multilineTextAlignment(.leading)

                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(.quaternary.opacity(0.45))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help(item.tooltip)
                        }
                    }

                    Divider()
                        .padding(.vertical, 6)

                    Text("Recovery Prompts")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(recoveryPrompts, id: \.self) { prompt in
                        Button {
                            copy(prompt)
                            copiedText = prompt
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(prompt)
                                    .foregroundStyle(.primary)
                                    .font(.body)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                }
            }

            if let copiedText {
                Text("Copied: \(copiedText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 360, minHeight: 360)
        .background(.regularMaterial)
    }

    private func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}
