import Foundation

enum UngitQuickCommandKind {
    case save
    case preChange
    case featureWorks
    case trustedRollback
    case milestone
    case releaseCandidate
    case release

    var snapshotType: SnapshotType {
        switch self {
        case .save: return .featureWorks
        case .preChange: return .preChange
        case .featureWorks: return .featureWorks
        case .trustedRollback: return .trustedRollback
        case .milestone: return .milestone
        case .releaseCandidate: return .releaseCandidate
        case .release: return .release
        }
    }

    var status: SnapshotStatus {
        switch self {
        case .milestone, .releaseCandidate, .release:
            return .trusted
        case .trustedRollback:
            return .rollbackPoint
        default:
            return .working
        }
    }

    var defaultTag: String {
        switch self {
        case .save: return "quick-save"
        case .preChange: return "pre-change"
        case .featureWorks: return "feature-works"
        case .trustedRollback: return "rollback"
        case .milestone: return "milestone"
        case .releaseCandidate: return "release-candidate"
        case .release: return "release"
        }
    }

}

enum UngitCommand {
    case quick(kind: UngitQuickCommandKind, title: String?)
    case verifySnapshot(id: String, mode: ProofVerificationMode?)
    case verifyLatest(kind: UngitVerifyLatestKind, mode: ProofVerificationMode?)
    case showTimeline
    case showSnapshot(id: String)
    case handoff
    case review(title: String?)
    case reviewCriticalLesson
    case restoreLatestTrustedRollback
    case restoreSnapshot(id: String)
    case addMemory(type: MemoryFileType, title: String?)
    case parkUpdate(text: String?)
    case preflightRestore
    case forkPoint(title: String?)
    case pruneSnapshots(apply: Bool)
    case pruneSnapshot(id: String, apply: Bool)
}

enum UngitVerifyLatestKind: Equatable {
    case snapshot
    case milestone
    case trustedRollback
    case releaseCandidate
    case release
}

struct NotesDraftService {
    func parseCommand(from input: String) -> UngitCommand? {
        guard input.range(of: "(?i)^UNGIT\\s+", options: .regularExpression) != nil else {
            return nil
        }

        let body = input.replacingOccurrences(
            of: "(?i)^UNGIT\\s+",
            with: "",
            options: .regularExpression
        ).trimmed

        if let parsed = parseAddMemoryCommand(from: body) {
            return parsed
        }

        if let parsed = parseParkUpdateCommand(from: body) {
            return parsed
        }

        if let parsed = parseForkPointCommand(from: body) {
            return parsed
        }

        if let parsed = parsePruneSnapshotsCommand(from: body) {
            return parsed
        }

        if let parsed = parsePruneSnapshotCommand(from: body) {
            return parsed
        }

        if let parsed = parseRestoreCommand(from: body) {
            return parsed
        }

        if let parsed = parseVerifyCommand(from: body) {
            return parsed
        }

        if let parsed = parseShowCommand(from: body) {
            return parsed
        }

        let (headRaw, titleRaw) = splitHeadAndTitle(body)
        let head = normalizedCommandText(headRaw)
        let title = titleRaw.trimmed

        if head == "preflight restore" {
            return .preflightRestore
        }

        if head == "handoff" {
            return .handoff
        }

        if head == "review save" {
            if title.lowercased().contains("capture critical lesson") {
                return .reviewCriticalLesson
            }
            return .review(title: title.isEmpty ? nil : title)
        }

        if head == "save milestone" {
            return .quick(kind: .milestone, title: title.isEmpty ? nil : title)
        }

        guard head.hasPrefix("quick ") else { return nil }
        let suffix = String(head.dropFirst("quick ".count))

        let kind: UngitQuickCommandKind?
        switch suffix {
        case "save":
            kind = .save
        case "pre change", "prechange":
            kind = .preChange
        case "feature works", "featureworks":
            kind = .featureWorks
        case "trusted rollback", "trustedrollback":
            kind = .trustedRollback
        case "milestone":
            kind = .milestone
        case "release candidate", "releasecandidate", "rc":
            kind = .releaseCandidate
        case "release":
            kind = .release
        default:
            kind = nil
        }

        guard let kind else { return nil }
        return .quick(kind: kind, title: title.isEmpty ? nil : title)
    }

    func buildForkPointDraft(providedTitle: String?, pathName: String) -> SnapshotDraft {
        var draft = SnapshotDraft.empty(pathName: pathName)
        draft.snapshotType = .preChange
        draft.status = .working
        draft.riskLevel = .high

        let title = providedTitle?.trimmed.isEmpty == false
            ? (providedTitle?.trimmed ?? "")
            : "Fork Point"

        draft.title = title
        draft.summary = title
        draft.tagsText = "fork-point,pre-change"
        draft.whatChanged = "Intentional divergence point captured before changing direction."
        draft.why = "Preserve a stable rewind point to recover original intent."
        draft.gotchas = "Fork Point is a semantic marker snapshot; it does not create a cloned project folder."
        draft.changeIntent = "Create a safe branch point before changing direction."

        return draft
    }

    func buildQuickDraft(
        kind: UngitQuickCommandKind,
        providedTitle: String?,
        pathName: String
    ) -> SnapshotDraft {
        var draft = SnapshotDraft.empty(pathName: pathName)
        draft.snapshotType = kind.snapshotType
        draft.status = kind.status
        draft.riskLevel = suggestedRiskLevel(for: kind.snapshotType)

        let title = providedTitle?.trimmed.isEmpty == false
            ? (providedTitle?.trimmed ?? "")
            : generatedQuickTitle(kind: kind, pathName: pathName)

        draft.title = title
        draft.summary = title
        draft.tagsText = kind.defaultTag
        draft.whatChanged = "Checkpoint captured from current working project state."
        draft.why = "Preserve a clear restore point for safe progress and recovery."
        draft.gotchas = ""
        draft.changeIntent = "Continue progress safely with a traceable checkpoint."

        return draft
    }

    func buildDraft(from userInput: String, pathName: String) -> SnapshotDraft {
        let text = userInput.trimmed
        var draft = SnapshotDraft.empty(pathName: pathName)

        guard !text.isEmpty else { return draft }

        draft.title = text
        draft.summary = text
        draft.riskLevel = .medium

        let lower = text.lowercased()
        if lower.contains("capture critical lesson") || lower.contains("critical lesson") {
            draft.title = "Critical Lesson"
            draft.summary = "Critical lesson capture for regression-safe project memory."
            draft.snapshotType = .fix
            draft.status = .working
            draft.tagsText = "critical-lesson,regression-risk"
            draft.whatChanged = """
            Critical Lesson
            Problem: What was broken?
            Fix: What exact change fixed it?
            Why it works: Why this fix works.
            Do not change: What must not be changed later.
            Proof: One code or command example that actually worked.
            """
            draft.why = "Capture this learning so recovery, regression triage, and future changes stay aligned with working intent."
            draft.gotchas = "Mark known regression risks and boundaries that must remain stable."
            draft.proofCommand = ""
            draft.changeIntent = "Capture the exact lesson so future work avoids repeat regressions."
            draft.outcome = .worked
            return draft
        } else if lower.contains("milestone") {
            draft.snapshotType = .milestone
            draft.status = .trusted
            draft.tagsText = "milestone"
            draft.riskLevel = .low
        } else if lower.contains("release candidate") || lower == "rc" {
            draft.snapshotType = .releaseCandidate
            draft.status = .trusted
            draft.tagsText = "release-candidate"
            draft.riskLevel = .high
        } else if lower.contains("release") {
            draft.snapshotType = .release
            draft.status = .trusted
            draft.tagsText = "release"
            draft.riskLevel = .high
        } else if lower.contains("pre") || lower.contains("before") {
            draft.snapshotType = .preChange
            draft.status = .working
            draft.tagsText = "pre-change"
            draft.riskLevel = .high
        } else if lower.contains("rollback") || lower.contains("stable") {
            draft.snapshotType = .trustedRollback
            draft.status = .rollbackPoint
            draft.tagsText = "rollback,stable"
            draft.riskLevel = .low
        } else if lower.contains("fix") {
            draft.snapshotType = .fix
            draft.status = .working
            draft.tagsText = "fix"
            draft.riskLevel = .medium
        } else if lower.contains("cleanup") || lower.contains("polish") {
            draft.snapshotType = .cleanup
            draft.status = .working
            draft.tagsText = "cleanup"
            draft.riskLevel = .low
        } else if lower.contains("experiment") {
            draft.snapshotType = .experiment
            draft.status = .experimental
            draft.tagsText = "experiment"
            draft.riskLevel = .high
        }

        draft.whatChanged = "Describe the important changes made in this point."
        draft.why = "Explain why this work was done and what goal it supports."
        draft.gotchas = "Note tricky parts, caveats, or things to watch next time."
        if draft.changeIntent.isEmpty {
            draft.changeIntent = "Document the current intention so timeline continuity stays clear."
        }

        return draft
    }

    private func splitHeadAndTitle(_ body: String) -> (head: String, title: String) {
        guard let colon = body.firstIndex(of: ":") else {
            return (body, "")
        }

        let head = String(body[..<colon])
        let title = String(body[body.index(after: colon)...])
        return (head, title)
    }

    private func normalizedCommandText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }
            .joined(separator: " ")
    }

    private func parseAddMemoryCommand(from body: String) -> UngitCommand? {
        let pattern = #"(?i)^add\s+(bug|idea|todo)\s*(?::\s*(.*)|\s+(.*))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }

        let typeRaw = capture(match: match, in: body, index: 1).lowercased()
        let titleFromColon = capture(match: match, in: body, index: 2)
        let titleFromSpace = capture(match: match, in: body, index: 3)
        let title = [titleFromColon, titleFromSpace]
            .map { $0.trimmed }
            .first(where: { !$0.isEmpty })

        let type: MemoryFileType?
        switch typeRaw {
        case "bug": type = .bugs
        case "idea": type = .ideas
        case "todo": type = .todo
        default: type = nil
        }

        guard let type else { return nil }
        return .addMemory(type: type, title: title)
    }

    private func parseParkUpdateCommand(from body: String) -> UngitCommand? {
        let pattern = #"(?i)^(?:update\s+park|park)\s*(?::\s*(.*)|\s+(.*))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }

        let textFromColon = capture(match: match, in: body, index: 1)
        let textFromSpace = capture(match: match, in: body, index: 2)
        let text = [textFromColon, textFromSpace]
            .map { $0.trimmed }
            .first(where: { !$0.isEmpty })

        return .parkUpdate(text: text)
    }

    private func parseForkPointCommand(from body: String) -> UngitCommand? {
        let pattern = #"(?i)^fork\s+(?:point|path)\s*(?::\s*(.*)|\s+(.*))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }

        let titleFromColon = capture(match: match, in: body, index: 1)
        let titleFromSpace = capture(match: match, in: body, index: 2)
        let title = [titleFromColon, titleFromSpace]
            .map { $0.trimmed }
            .first(where: { !$0.isEmpty })

        return .forkPoint(title: title)
    }

    private func parsePruneSnapshotsCommand(from body: String) -> UngitCommand? {
        let pattern = #"(?i)^prune\s+snapshots(?:\s*:\s*(confirm|apply)|\s+(confirm|apply))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }

        let modeColon = capture(match: match, in: body, index: 1).lowercased()
        let modeSpace = capture(match: match, in: body, index: 2).lowercased()
        let mode = [modeColon, modeSpace].first { !$0.isEmpty } ?? ""
        let apply = mode == "confirm" || mode == "apply"
        return .pruneSnapshots(apply: apply)
    }

    private func parsePruneSnapshotCommand(from body: String) -> UngitCommand? {
        let pattern = #"(?i)^prune\s+snapshot\s+([A-F0-9-]+)\s*(?::\s*(confirm|apply)|\s+(confirm|apply))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }

        let rawID = capture(match: match, in: body, index: 1).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawID.isEmpty else { return nil }
        let modeColon = capture(match: match, in: body, index: 2).lowercased()
        let modeSpace = capture(match: match, in: body, index: 3).lowercased()
        let mode = [modeColon, modeSpace].first { !$0.isEmpty } ?? ""
        let apply = mode == "confirm" || mode == "apply"
        return .pruneSnapshot(id: rawID.uppercased(), apply: apply)
    }

    private func parseRestoreCommand(from body: String) -> UngitCommand? {
        let normalized = normalizedCommandText(body)
        if normalized == "restore latest trusted rollback" {
            return .restoreLatestTrustedRollback
        }

        let pattern = #"(?i)^restore\s+snapshot\s+([A-F0-9-]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }
        let rawID = capture(match: match, in: body, index: 1).trimmed.uppercased()
        guard !rawID.isEmpty else { return nil }
        return .restoreSnapshot(id: rawID)
    }

    private func parseVerifyCommand(from body: String) -> UngitCommand? {
        let verifySnapshotPattern = #"(?i)^verify\s+snapshot\s+([A-F0-9-]+)(?:\s+(archive|lightweight))?$"#
        if let regex = try? NSRegularExpression(pattern: verifySnapshotPattern) {
            let range = NSRange(body.startIndex..<body.endIndex, in: body)
            if let match = regex.firstMatch(in: body, options: [], range: range) {
                let rawID = capture(match: match, in: body, index: 1).trimmed.uppercased()
                guard !rawID.isEmpty else { return nil }
                let modeRaw = capture(match: match, in: body, index: 2).trimmed.lowercased()
                return .verifySnapshot(id: rawID, mode: parseProofMode(modeRaw))
            }
        }

        let verifyLatestPattern = #"(?i)^verify\s+(?:latest|most\s+recent)\s+(snapshot|milestone|trusted\s+rollback|release\s+candidate|release)(?:\s+(archive|lightweight))?$"#
        if let regex = try? NSRegularExpression(pattern: verifyLatestPattern) {
            let range = NSRange(body.startIndex..<body.endIndex, in: body)
            if let match = regex.firstMatch(in: body, options: [], range: range) {
                let kindRaw = capture(match: match, in: body, index: 1).trimmed.lowercased()
                let modeRaw = capture(match: match, in: body, index: 2).trimmed.lowercased()
                guard let kind = parseVerifyLatestKind(kindRaw) else { return nil }
                return .verifyLatest(kind: kind, mode: parseProofMode(modeRaw))
            }
        }

        return nil
    }

    private func parseShowCommand(from body: String) -> UngitCommand? {
        let normalized = normalizedCommandText(body)
        if normalized == "show timeline" {
            return .showTimeline
        }

        let pattern = #"(?i)^show\s+snapshot\s+([A-F0-9-]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }
        let rawID = capture(match: match, in: body, index: 1).trimmed.uppercased()
        guard !rawID.isEmpty else { return nil }
        return .showSnapshot(id: rawID)
    }

    private func parseVerifyLatestKind(_ raw: String) -> UngitVerifyLatestKind? {
        switch normalizedCommandText(raw) {
        case "snapshot":
            return .snapshot
        case "milestone":
            return .milestone
        case "trusted rollback":
            return .trustedRollback
        case "release candidate":
            return .releaseCandidate
        case "release":
            return .release
        default:
            return nil
        }
    }

    private func parseProofMode(_ raw: String) -> ProofVerificationMode? {
        switch raw {
        case "archive":
            return .archive
        case "lightweight":
            return .lightweight
        default:
            return nil
        }
    }

    private func capture(match: NSTextCheckingResult, in source: String, index: Int) -> String {
        guard index < match.numberOfRanges else { return "" }
        let nsRange = match.range(at: index)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: source) else { return "" }
        return String(source[range])
    }

    private func generatedQuickTitle(kind: UngitQuickCommandKind, pathName: String) -> String {
        let normalizedPath = pathName.trimmed
        let hasPathContext = !normalizedPath.isEmpty && normalizedPath.lowercased() != "main"

        let base: String
        switch kind {
        case .save:
            base = "Quick Save"
        case .preChange:
            base = "Pre-Change"
        case .featureWorks:
            base = "Feature Works"
        case .trustedRollback:
            base = "Trusted Rollback"
        case .milestone:
            base = "Milestone"
        case .releaseCandidate:
            base = "Release Candidate"
        case .release:
            base = "Release"
        }

        if hasPathContext {
            return "\(base) (\(normalizedPath))"
        }
        return base
    }

    private func suggestedRiskLevel(for type: SnapshotType) -> SnapshotRiskLevel {
        switch type {
        case .preChange, .experiment:
            return .high
        case .milestone, .trustedRollback, .releaseCandidate, .release, .cleanup:
            return .low
        case .featureWorks, .fix:
            return .medium
        }
    }
}
