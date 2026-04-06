import SwiftUI

struct TimelineDaySummary: Identifiable {
    let id: String
    let dayLabel: String
    let entries: [TimelineEntry]

    init(dayLabel: String, entries: [TimelineEntry]) {
        self.id = "day-summary-\(dayLabel)"
        self.dayLabel = dayLabel
        self.entries = entries
    }
}

struct TimelineListView: View {
    let entries: [TimelineEntry]
    @Binding var selectedID: String?
    let onSelectDaySummary: (TimelineDaySummary) -> Void

    var body: some View {
        List(selection: $selectedID) {
            ForEach(rows) { row in
                switch row {
                case .dayHeader(_, let day, let burstCount, let dayEntries):
                    Button {
                        onSelectDaySummary(TimelineDaySummary(dayLabel: day, entries: dayEntries))
                    } label: {
                        HStack {
                            Text(day)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(burstCount) snapshot\(burstCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show day summary")
                    .listRowSeparator(.hidden)

                case .gap(_, let days):
                    Text("No snapshots for \(days) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)

                case .entry(let entry):
                    SnapshotRow(entry: entry)
                        .tag(entry.id)
                }
            }
        }
        .listStyle(.inset)
    }

    private var rows: [TimelineRow] {
        makeRows(for: entries)
    }

    private func makeRows(for pathEntries: [TimelineEntry]) -> [TimelineRow] {
        guard !pathEntries.isEmpty else { return [] }

        let sorted = pathEntries.sorted { $0.createdAtISO8601 > $1.createdAtISO8601 }
        var rows: [TimelineRow] = []
        var dayBuckets: [(date: Date, entries: [TimelineEntry])] = []
        let calendar = Calendar.current

        for entry in sorted {
            let day = calendar.startOfDay(for: entry.createdAt)
            if let last = dayBuckets.last, calendar.isDate(last.date, inSameDayAs: day) {
                var updated = last
                updated.entries.append(entry)
                dayBuckets[dayBuckets.count - 1] = updated
            } else {
                dayBuckets.append((date: day, entries: [entry]))
            }
        }

        for (index, bucket) in dayBuckets.enumerated() {
            rows.append(.dayHeader(
                id: "day-\(bucket.date.timeIntervalSince1970)",
                day: DateFormatters.dayHeader.string(from: bucket.date),
                burstCount: bucket.entries.count,
                entries: bucket.entries
            ))

            for entry in bucket.entries {
                rows.append(.entry(entry))
            }

            if index < dayBuckets.count - 1 {
                let nextDay = dayBuckets[index + 1].date
                let gap = max(0, calendar.dateComponents([.day], from: nextDay, to: bucket.date).day ?? 0) - 1
                if gap >= 2 {
                    rows.append(.gap(id: "gap-\(index)-\(gap)", days: gap))
                }
            }
        }

        return rows
    }
}

private struct SnapshotRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            marker
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(entry.title)
                        .font(titleFont)
                        .fontWeight(titleWeight)
                        .lineLimit(1)
                    Spacer()
                    Text(DateFormatters.display.string(from: entry.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    tag(text: entry.snapshotType.rawValue, color: typeColor)
                    tag(text: entry.status.rawValue, color: statusColor)
                    proofTag
                    if entry.remotePublishState == .published {
                        tag(text: "Published", color: .indigo)
                    } else if entry.remotePublishState == .publishing {
                        tag(text: "Publishing", color: .orange)
                    } else if entry.remotePublishState == .publishFailed {
                        tag(text: "Publish Failed", color: .red)
                    }
                    if !entry.archiveAvailable {
                        tag(text: "Pruned", color: .red)
                    }
                    Text(entry.pathName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if entry.snapshotType == .trustedRollback {
                    Text("Safe Restore Point")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                } else if entry.snapshotType == .remoteCorrectionReview {
                    Text("Remote Correction Review")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                } else if entry.snapshotType == .releaseCandidate || entry.snapshotType == .release {
                    Text("Sacred Landmark")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.indigo)
                }

                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .opacity(isMinor ? 0.82 : 1)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(backgroundTint)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(isMinor ? 0.9 : 1)
    }

    private var marker: some View {
        ZStack {
            Circle()
                .fill(typeColor.opacity(0.18))
                .frame(width: markerSize, height: markerSize)
            Circle()
                .stroke(typeColor, lineWidth: 1.4)
                .frame(width: markerSize, height: markerSize)
            if let symbol = markerSymbol {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .bold))
                    .foregroundStyle(typeColor)
            }
        }
    }

    private var markerSize: CGFloat {
        isMajor ? 18 : (isMinor ? 12 : 14)
    }

    private var symbolSize: CGFloat {
        isMajor ? 8 : 7
    }

    private var isMajor: Bool {
        entry.snapshotType.isSacredLandmark
    }

    private var isMinor: Bool {
        entry.snapshotType == .preChange || entry.snapshotType == .fix || entry.snapshotType == .cleanup
    }

    private var titleFont: Font {
        isMajor ? .subheadline : .body
    }

    private var titleWeight: Font.Weight {
        if entry.snapshotType == .milestone { return .semibold }
        if entry.snapshotType == .releaseCandidate { return .semibold }
        if entry.snapshotType == .release { return .semibold }
        if entry.snapshotType == .trustedRollback { return .medium }
        if entry.snapshotType == .remoteCorrectionReview { return .medium }
        return isMinor ? .regular : .medium
    }

    private var backgroundTint: Color {
        if entry.snapshotType == .milestone {
            return typeColor.opacity(0.08)
        }
        if entry.snapshotType == .releaseCandidate || entry.snapshotType == .release {
            return typeColor.opacity(0.08)
        }
        if entry.snapshotType == .trustedRollback {
            return .green.opacity(0.10)
        }
        if entry.snapshotType == .remoteCorrectionReview {
            return .orange.opacity(0.09)
        }
        return .clear
    }

    private var markerSymbol: String? {
        switch entry.snapshotType {
        case .milestone:
            return "star.fill"
        case .releaseCandidate:
            return "flag.checkered.2.crossed"
        case .release:
            return "flag.checkered"
        case .trustedRollback:
            return "shield.fill"
        case .remoteCorrectionReview:
            return "doc.text.magnifyingglass"
        case .preChange:
            return "pause.fill"
        case .featureWorks:
            return "checkmark"
        case .fix:
            return "wrench.fill"
        case .cleanup:
            return "sparkles"
        case .experiment:
            return "flask.fill"
        }
    }

    private var typeColor: Color {
        switch entry.snapshotType {
        case .milestone:
            return .indigo
        case .releaseCandidate:
            return .purple
        case .release:
            return .green
        case .trustedRollback:
            return .green
        case .remoteCorrectionReview:
            return .orange
        case .preChange:
            return .orange
        case .featureWorks:
            return .blue
        case .fix:
            return .teal
        case .cleanup:
            return .mint
        case .experiment:
            return .pink
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .trusted:
            return .green
        case .working:
            return .blue
        case .experimental:
            return .orange
        case .broken:
            return .red
        case .rollbackPoint:
            return .purple
        }
    }

    private var proofColor: Color {
        switch entry.proofVerificationStatus {
        case .verified:
            return .green
        case .unverified:
            return .orange
        case .broken:
            return .red
        }
    }

    @ViewBuilder
    private var proofTag: some View {
        if entry.proofVerificationStatus == .verified && entry.proofVerificationMode == .archive {
            tag(text: entry.proofVerificationStatus.rawValue, color: proofColor, systemImage: "star.fill")
        } else {
            tag(text: entry.proofVerificationStatus.rawValue, color: proofColor)
        }
    }

    private func tag(text: String, color: Color, systemImage: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.14))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private enum TimelineRow: Identifiable {
    case dayHeader(id: String, day: String, burstCount: Int, entries: [TimelineEntry])
    case gap(id: String, days: Int)
    case entry(TimelineEntry)

    var id: String {
        switch self {
        case .dayHeader(let id, _, _, _):
            return id
        case .gap(let id, _):
            return id
        case .entry(let entry):
            return entry.id
        }
    }
}
