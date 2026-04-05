import SwiftUI

struct SnapshotEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var draft: SnapshotDraft
    let title: String
    let onSave: (SnapshotDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Form {
                TextField("Title", text: $draft.title)
                TextField("Summary", text: $draft.summary)
                Picker("Snapshot Type", selection: $draft.snapshotType) {
                    ForEach(SnapshotType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                Picker("Status", selection: $draft.status) {
                    ForEach(SnapshotStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                Picker("Risk Level", selection: $draft.riskLevel) {
                    ForEach(SnapshotRiskLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                Picker("Outcome", selection: outcomeBinding) {
                    Text("Not Set").tag(Optional<SnapshotOutcome>.none)
                    ForEach(SnapshotOutcome.allCases) { outcome in
                        Text(outcome.rawValue).tag(Optional(outcome))
                    }
                }
                TextField("Change Intent", text: $draft.changeIntent)
                TextField("Path", text: $draft.pathName)
                TextField("Tags (comma-separated)", text: $draft.tagsText)
                TextField("Linked bug/idea/todo IDs (comma-separated)", text: $draft.linkedMemoryIDsText)
                TextField("Proof command (optional)", text: $draft.proofCommand)
                TextField("Important files touched (comma-separated)", text: $draft.importantFilesTouchedText)
                TextField("What changed", text: $draft.whatChanged, axis: .vertical)
                TextField("Why", text: $draft.why, axis: .vertical)
                TextField("Gotchas", text: $draft.gotchas, axis: .vertical)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Snapshot") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 560)
    }

    private var outcomeBinding: Binding<SnapshotOutcome?> {
        Binding(
            get: { draft.outcome },
            set: { draft.outcome = $0 }
        )
    }
}
