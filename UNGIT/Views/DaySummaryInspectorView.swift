import SwiftUI

struct DaySummaryInspectorView: View {
    let summary: TimelineDaySummary

    private var total: Int { summary.entries.count }
    private var verified: Int { summary.entries.filter { $0.proofVerificationStatus == .verified }.count }
    private var unverified: Int { summary.entries.filter { $0.proofVerificationStatus == .unverified }.count }
    private var broken: Int { summary.entries.filter { $0.proofVerificationStatus == .broken }.count }

    private var typeCounts: [(SnapshotType, Int)] {
        SnapshotType.allCases.compactMap { type in
            let count = summary.entries.filter { $0.snapshotType == type }.count
            return count > 0 ? (type, count) : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Viewing Day Summary")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(summary.dayLabel)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(total) snapshot\(total == 1 ? "" : "s") on this day")
                    .foregroundStyle(.secondary)

                inspectorSection("Proof Posture") {
                    HStack(spacing: 8) {
                        badge("Verified \(verified)", color: .green)
                        badge("Unverified \(unverified)", color: .orange)
                        if broken > 0 {
                            badge("Broken \(broken)", color: .red)
                        }
                    }
                }

                inspectorSection("Type Breakdown") {
                    ForEach(typeCounts, id: \.0.id) { item in
                        HStack {
                            Text(item.0.rawValue)
                            Spacer()
                            Text("\(item.1)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                inspectorSection("Entries") {
                    ForEach(summary.entries) { entry in
                        Text("• \(entry.title)")
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
