import SwiftUI
import AppKit

struct ProjectSummaryHeaderView: View {
    @State private var showMCPSetup = false
    @State private var copiedValue: String?

    let project: ProjectMetadata
    let entries: [TimelineEntry]
    let snapshotsStorageBytes: Int64
    let currentStateText: String
    let currentStateColor: Color
    private let statColumns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryLine("Project", project.name, emphasize: true)
            HStack(spacing: 8) {
                Circle()
                    .fill(currentStateColor)
                    .frame(width: 8, height: 8)
                Text(currentStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            summaryLine("Age", ageText)

            LazyVGrid(columns: statColumns, spacing: 12) {
                statPill("Snapshots", "\(entries.count) • \(formatBytes(snapshotsStorageBytes))")
                statPill("Landmarks", "\(landmarkCount)")
                statPill("Rollbacks", "\(trustedRollbackCount)")
            }
            .frame(maxWidth: .infinity)

            summaryLine("Last Activity", latestSnapshotText)

            if let sizeText = latestSizeText {
                Text(sizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            DisclosureGroup("MCP Setup", isExpanded: $showMCPSetup) {
                VStack(alignment: .leading, spacing: 8) {
                    setupCopyRow(label: "Command", value: mcpLaunchPath)
                    setupCopyRow(label: "Working Dir", value: "/")
                    setupCopyRow(label: "Working Dir (alt)", value: "~/")

                    if let copiedValue {
                        Text("Copied: \(copiedValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 10)
    }

    private var mcpLaunchPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/ungit-mcp", isDirectory: false)
            .path
    }

    private var landmarkCount: Int {
        entries.filter { $0.snapshotType.isSacredLandmark }.count
    }

    private var trustedRollbackCount: Int {
        entries.filter { $0.snapshotType == .trustedRollback }.count
    }

    private var latestSnapshotText: String {
        guard let latest = entries.first else { return "None" }
        return DateFormatters.display.string(from: latest.createdAt)
    }

    private var ageText: String {
        let days = max(0, Calendar.current.dateComponents([.day], from: project.createdAt, to: Date()).day ?? 0)
        if days == 0 { return "Today" }
        if days == 1 { return "1 day" }
        return "\(days) days"
    }

    private var latestSizeText: String? {
        guard let latest = entries.first else { return nil }
        guard let fileCount = latest.projectFileCount else { return nil }

        if let codeLines = latest.codeSizeApproxLines {
            return "Project Size: \(fileCount) files • Code Size (approx): \(formattedNumber(codeLines)) lines"
        }
        return "Project Size: \(fileCount) files"
    }

    private func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func summaryLine(_ label: String, _ value: String, emphasize: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(emphasize ? .headline : .subheadline)
                .fontWeight(emphasize ? .semibold : .medium)
        }
    }

    private func statPill(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    @ViewBuilder
    private func setupCopyRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text("\(label):")
                .foregroundStyle(.secondary)
            Spacer()
            Button(value) {
                let board = NSPasteboard.general
                board.clearContents()
                board.setString(value, forType: .string)
                copiedValue = value
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .lineLimit(1)
        }
    }
}
