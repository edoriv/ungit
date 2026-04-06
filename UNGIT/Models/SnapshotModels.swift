import Foundation

enum SnapshotType: String, Codable, CaseIterable, Identifiable {
    case preChange = "Pre-Change"
    case featureWorks = "Feature Works"
    case trustedRollback = "Trusted Rollback"
    case milestone = "Milestone"
    case remoteCorrectionReview = "Remote Correction Review"
    case releaseCandidate = "Release Candidate"
    case release = "Release"
    case experiment = "Experiment"
    case cleanup = "Cleanup"
    case fix = "Fix"

    var id: String { rawValue }

    var isSacredLandmark: Bool {
        switch self {
        case .trustedRollback, .milestone, .releaseCandidate, .release:
            return true
        default:
            return false
        }
    }

    var prefersArchiveProof: Bool {
        switch self {
        case .trustedRollback, .releaseCandidate, .release:
            return true
        default:
            return false
        }
    }
}

enum RemotePublishFailureReason: String, Codable {
    case remotePathDiverged = "Remote Path Diverged"
    case remoteAuthFailed = "Remote Auth Failed"
    case remoteMissing = "Remote Missing"
    case noGitRepository = "No Git Repo"
    case workspaceDriftDetected = "Workspace Drift Detected"
    case publishBlocked = "Publish Blocked"
    case unknown = "Unknown"
}

enum RemoteCorrectionRecommendationLevel: String, Codable {
    case safe = "Safe"
    case caution = "Caution"
    case risky = "Risky"
}

enum RemoteCorrectionSelectedAction: String, Codable {
    case inspectOnly = "Inspect Only"
    case publishToNewPath = "Publish to New Path"
    case manualAdoptLater = "Manual Adopt Later"
    case ignore = "Ignore"
}

enum RemoteCorrectionFileStatus: String, Codable {
    case added = "Added"
    case modified = "Modified"
    case deleted = "Deleted"
}

struct RemoteCorrectionChangedFile: Codable, Identifiable {
    var path: String
    var status: RemoteCorrectionFileStatus

    var id: String { "\(status.rawValue):\(path)" }
}

struct RemoteCorrectionReviewRecord: Codable {
    var linkedMilestoneSnapshotID: String
    var reasonForReview: RemotePublishFailureReason
    var remotePath: String
    var changedFiles: [RemoteCorrectionChangedFile]
    var summaryOfRemoteChanges: String
    var codexRecommendation: String?
    var recommendationLevel: RemoteCorrectionRecommendationLevel
    var humanSelectedNextAction: RemoteCorrectionSelectedAction
    var reviewedAt: Date
    var reviewedAtISO8601: String
}

enum SnapshotStatus: String, Codable, CaseIterable, Identifiable {
    case trusted = "Trusted"
    case working = "Working"
    case experimental = "Experimental"
    case broken = "Broken"
    case rollbackPoint = "Rollback Point"

    var id: String { rawValue }
}

enum SnapshotRiskLevel: String, Codable, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }
}

enum SnapshotOutcome: String, Codable, CaseIterable, Identifiable {
    case worked = "Worked"
    case partial = "Partial"
    case reverted = "Reverted"

    var id: String { rawValue }
}

enum ProofVerificationStatus: String, Codable {
    case verified = "Verified"
    case unverified = "Unverified"
    case broken = "Broken"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch raw.lowercased() {
        case "verified":
            self = .verified
        case "unverified":
            self = .unverified
        case "broken", "drift detected":
            self = .broken
        default:
            self = .unverified
        }
    }
}

enum ProofVerificationMode: String, Codable {
    case lightweight = "Lightweight Proof"
    case archive = "Archive Proof"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch raw.lowercased() {
        case "archive proof", "archive":
            self = .archive
        case "lightweight proof", "lightweight":
            self = .lightweight
        default:
            self = .lightweight
        }
    }
}

enum RemotePublishState: String, Codable {
    case notPublished = "Not Published"
    case publishing = "Publishing"
    case published = "Published"
    case publishFailed = "Publish Failed"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch raw.lowercased() {
        case "publishing":
            self = .publishing
        case "published":
            self = .published
        case "publish failed", "failed", "error":
            self = .publishFailed
        default:
            self = .notPublished
        }
    }
}

struct RemotePublishPreflight: Codable {
    var snapshotID: String
    var snapshotTitle: String
    var snapshotType: SnapshotType
    var isGitRepository: Bool
    var originRemoteURL: String?
    var currentBranch: String?
    var snapshotIsLatest: Bool
    var workingTreeDriftedSinceSnapshot: Bool
    var stagedChangesPresent: Bool
    var unstagedChangesPresent: Bool
    var untrackedFilesPresent: Bool
    var ignoredFilesPresent: Bool
    var publishAllowed: Bool
    var blockingReasons: [String]

    var hasChangesToPublish: Bool {
        stagedChangesPresent || unstagedChangesPresent || untrackedFilesPresent
    }
}

struct MilestonePublicationWindow: Codable {
    var previousPublishedMilestoneID: String?
    var firstIncludedSnapshotID: String?
    var lastIncludedSnapshotID: String?
    var includedSnapshotIDs: [String]
    var compiledChangelog: String
}

struct SnapshotRemoteMetadata: Codable {
    var publishState: RemotePublishState
    var branchName: String?
    var commitSHA: String?
    var publishedAt: Date?
    var publishedAtISO8601: String?
    var lastPublishAttemptAt: Date?
    var lastPublishAttemptAtISO8601: String?
    var lastPublishError: String?
    var requestedBy: String?
    var approvedBy: String?
    var executedBy: String?
    var latestPreflight: RemotePublishPreflight?
    var publicationWindow: MilestonePublicationWindow?

    enum CodingKeys: String, CodingKey {
        case publishState
        case branchName
        case commitSHA
        case publishedAt
        case publishedAtISO8601
        case lastPublishAttemptAt
        case lastPublishAttemptAtISO8601
        case lastPublishError
        case requestedBy
        case approvedBy
        case executedBy
        case latestPreflight
        case publicationWindow
    }

    init(
        publishState: RemotePublishState = .notPublished,
        branchName: String? = nil,
        commitSHA: String? = nil,
        publishedAt: Date? = nil,
        publishedAtISO8601: String? = nil,
        lastPublishAttemptAt: Date? = nil,
        lastPublishAttemptAtISO8601: String? = nil,
        lastPublishError: String? = nil,
        requestedBy: String? = nil,
        approvedBy: String? = nil,
        executedBy: String? = nil,
        latestPreflight: RemotePublishPreflight? = nil,
        publicationWindow: MilestonePublicationWindow? = nil
    ) {
        self.publishState = publishState
        self.branchName = branchName
        self.commitSHA = commitSHA
        self.publishedAt = publishedAt
        self.publishedAtISO8601 = publishedAtISO8601
        self.lastPublishAttemptAt = lastPublishAttemptAt
        self.lastPublishAttemptAtISO8601 = lastPublishAttemptAtISO8601
        self.lastPublishError = lastPublishError
        self.requestedBy = requestedBy
        self.approvedBy = approvedBy
        self.executedBy = executedBy
        self.latestPreflight = latestPreflight
        self.publicationWindow = publicationWindow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        publishState = try c.decodeIfPresent(RemotePublishState.self, forKey: .publishState) ?? .notPublished
        branchName = try c.decodeIfPresent(String.self, forKey: .branchName)
        commitSHA = try c.decodeIfPresent(String.self, forKey: .commitSHA)
        publishedAt = try c.decodeIfPresent(Date.self, forKey: .publishedAt)
        publishedAtISO8601 = try c.decodeIfPresent(String.self, forKey: .publishedAtISO8601)
        lastPublishAttemptAt = try c.decodeIfPresent(Date.self, forKey: .lastPublishAttemptAt)
        lastPublishAttemptAtISO8601 = try c.decodeIfPresent(String.self, forKey: .lastPublishAttemptAtISO8601)
        lastPublishError = try c.decodeIfPresent(String.self, forKey: .lastPublishError)
        requestedBy = try c.decodeIfPresent(String.self, forKey: .requestedBy)
        approvedBy = try c.decodeIfPresent(String.self, forKey: .approvedBy)
        executedBy = try c.decodeIfPresent(String.self, forKey: .executedBy)
        latestPreflight = try c.decodeIfPresent(RemotePublishPreflight.self, forKey: .latestPreflight)
        publicationWindow = try c.decodeIfPresent(MilestonePublicationWindow.self, forKey: .publicationWindow)
    }
}

struct ProjectSizeMetrics: Codable {
    var fileCount: Int
    var codeSizeApproxLines: Int
}

struct ResourceSnapshot: Codable {
    var capturedAt: String
    var cpuPercentObserved: Double?
    var memoryMBObserved: Double?
    var energyImpactObserved: String?
    var diskKbpsObserved: Double?
    var networkKbpsObserved: Double?
    var captureContext: String

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case cpuPercentObserved = "cpu_percent_observed"
        case memoryMBObserved = "memory_mb_observed"
        case energyImpactObserved = "energy_impact_observed"
        case diskKbpsObserved = "disk_kbps_observed"
        case networkKbpsObserved = "network_kbps_observed"
        case captureContext = "capture_context"
    }
}

struct SnapshotNotes: Codable {
    var title: String
    var summary: String
    var whatChanged: String
    var why: String
    var importantFilesTouched: [String]
    var gotchas: String
    var tags: [String]
    var status: SnapshotStatus
    var snapshotType: SnapshotType
    var pathName: String
    var proofCommand: String
    var linkedMemoryIDs: [String]
    var changeIntent: String
    var riskLevel: SnapshotRiskLevel
    var outcome: SnapshotOutcome?

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case whatChanged
        case why
        case importantFilesTouched
        case gotchas
        case tags
        case status
        case snapshotType
        case pathName
        case proofCommand
        case linkedMemoryIDs
        case changeIntent
        case riskLevel
        case outcome
    }

    init(
        title: String,
        summary: String,
        whatChanged: String,
        why: String,
        importantFilesTouched: [String],
        gotchas: String,
        tags: [String],
        status: SnapshotStatus,
        snapshotType: SnapshotType,
        pathName: String,
        proofCommand: String,
        linkedMemoryIDs: [String],
        changeIntent: String = "",
        riskLevel: SnapshotRiskLevel = .medium,
        outcome: SnapshotOutcome? = nil
    ) {
        self.title = title
        self.summary = summary
        self.whatChanged = whatChanged
        self.why = why
        self.importantFilesTouched = importantFilesTouched
        self.gotchas = gotchas
        self.tags = tags
        self.status = status
        self.snapshotType = snapshotType
        self.pathName = pathName
        self.proofCommand = proofCommand
        self.linkedMemoryIDs = linkedMemoryIDs
        self.changeIntent = changeIntent
        self.riskLevel = riskLevel
        self.outcome = outcome
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        whatChanged = try c.decode(String.self, forKey: .whatChanged)
        why = try c.decode(String.self, forKey: .why)
        importantFilesTouched = try c.decode([String].self, forKey: .importantFilesTouched)
        gotchas = try c.decode(String.self, forKey: .gotchas)
        tags = try c.decode([String].self, forKey: .tags)
        status = try c.decode(SnapshotStatus.self, forKey: .status)
        snapshotType = try c.decode(SnapshotType.self, forKey: .snapshotType)
        pathName = try c.decode(String.self, forKey: .pathName)
        proofCommand = try c.decodeIfPresent(String.self, forKey: .proofCommand) ?? ""
        linkedMemoryIDs = try c.decodeIfPresent([String].self, forKey: .linkedMemoryIDs) ?? []
        changeIntent = try c.decodeIfPresent(String.self, forKey: .changeIntent) ?? ""
        riskLevel = try c.decodeIfPresent(SnapshotRiskLevel.self, forKey: .riskLevel) ?? .medium
        outcome = try c.decodeIfPresent(SnapshotOutcome.self, forKey: .outcome)
    }
}

struct SnapshotManifest: Codable, Identifiable {
    var id: String
    var projectID: String
    var createdAt: Date
    var createdAtISO8601: String
    var projectPath: String
    var archiveRelativePath: String
    var notes: SnapshotNotes
    var isAutomaticSafetySnapshot: Bool
    var projectSizeMetrics: ProjectSizeMetrics?
    var resourceSnapshot: ResourceSnapshot?
    var proofVerificationStatus: ProofVerificationStatus
    var proofVerificationMode: ProofVerificationMode?
    var proofCheckedAt: Date?
    var proofCheckedAtISO8601: String?
    var proofDetails: String?
    var archivePrunedAt: Date?
    var archivePrunedAtISO8601: String?
    var archivePruneReason: String?
    var archiveLocked: Bool?
    var remoteMetadata: SnapshotRemoteMetadata
    var remoteCorrectionReview: RemoteCorrectionReviewRecord?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case createdAt
        case createdAtISO8601
        case projectPath
        case archiveRelativePath
        case notes
        case isAutomaticSafetySnapshot
        case projectSizeMetrics
        case resourceSnapshot
        case proofVerificationStatus
        case proofVerificationMode
        case proofCheckedAt
        case proofCheckedAtISO8601
        case proofDetails
        case archivePrunedAt
        case archivePrunedAtISO8601
        case archivePruneReason
        case archiveLocked
        case remoteMetadata
        case remoteCorrectionReview
    }

    init(
        id: String,
        projectID: String,
        createdAt: Date,
        createdAtISO8601: String,
        projectPath: String,
        archiveRelativePath: String,
        notes: SnapshotNotes,
        isAutomaticSafetySnapshot: Bool,
        projectSizeMetrics: ProjectSizeMetrics?,
        resourceSnapshot: ResourceSnapshot?,
        proofVerificationStatus: ProofVerificationStatus,
        proofVerificationMode: ProofVerificationMode?,
        proofCheckedAt: Date?,
        proofCheckedAtISO8601: String?,
        proofDetails: String?,
        archivePrunedAt: Date?,
        archivePrunedAtISO8601: String?,
        archivePruneReason: String?,
        archiveLocked: Bool?,
        remoteMetadata: SnapshotRemoteMetadata = SnapshotRemoteMetadata(),
        remoteCorrectionReview: RemoteCorrectionReviewRecord? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.createdAt = createdAt
        self.createdAtISO8601 = createdAtISO8601
        self.projectPath = projectPath
        self.archiveRelativePath = archiveRelativePath
        self.notes = notes
        self.isAutomaticSafetySnapshot = isAutomaticSafetySnapshot
        self.projectSizeMetrics = projectSizeMetrics
        self.resourceSnapshot = resourceSnapshot
        self.proofVerificationStatus = proofVerificationStatus
        self.proofVerificationMode = proofVerificationMode
        self.proofCheckedAt = proofCheckedAt
        self.proofCheckedAtISO8601 = proofCheckedAtISO8601
        self.proofDetails = proofDetails
        self.archivePrunedAt = archivePrunedAt
        self.archivePrunedAtISO8601 = archivePrunedAtISO8601
        self.archivePruneReason = archivePruneReason
        self.archiveLocked = archiveLocked
        self.remoteMetadata = remoteMetadata
        self.remoteCorrectionReview = remoteCorrectionReview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectID = try c.decode(String.self, forKey: .projectID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        createdAtISO8601 = try c.decode(String.self, forKey: .createdAtISO8601)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        archiveRelativePath = try c.decode(String.self, forKey: .archiveRelativePath)
        notes = try c.decode(SnapshotNotes.self, forKey: .notes)
        isAutomaticSafetySnapshot = try c.decode(Bool.self, forKey: .isAutomaticSafetySnapshot)
        projectSizeMetrics = try c.decodeIfPresent(ProjectSizeMetrics.self, forKey: .projectSizeMetrics)
        resourceSnapshot = try c.decodeIfPresent(ResourceSnapshot.self, forKey: .resourceSnapshot)
        proofVerificationStatus = try c.decodeIfPresent(ProofVerificationStatus.self, forKey: .proofVerificationStatus) ?? .unverified
        proofVerificationMode = try c.decodeIfPresent(ProofVerificationMode.self, forKey: .proofVerificationMode)
        proofCheckedAt = try c.decodeIfPresent(Date.self, forKey: .proofCheckedAt)
        proofCheckedAtISO8601 = try c.decodeIfPresent(String.self, forKey: .proofCheckedAtISO8601)
        proofDetails = try c.decodeIfPresent(String.self, forKey: .proofDetails)
        archivePrunedAt = try c.decodeIfPresent(Date.self, forKey: .archivePrunedAt)
        archivePrunedAtISO8601 = try c.decodeIfPresent(String.self, forKey: .archivePrunedAtISO8601)
        archivePruneReason = try c.decodeIfPresent(String.self, forKey: .archivePruneReason)
        archiveLocked = try c.decodeIfPresent(Bool.self, forKey: .archiveLocked) ?? false
        remoteMetadata = try c.decodeIfPresent(SnapshotRemoteMetadata.self, forKey: .remoteMetadata) ?? SnapshotRemoteMetadata()
        remoteCorrectionReview = try c.decodeIfPresent(RemoteCorrectionReviewRecord.self, forKey: .remoteCorrectionReview)
    }
}

struct TimelineEntry: Codable, Identifiable {
    var id: String
    var createdAt: Date
    var createdAtISO8601: String
    var manifestRelativePath: String
    var archiveRelativePath: String
    var title: String
    var summary: String
    var snapshotType: SnapshotType
    var status: SnapshotStatus
    var pathName: String
    var tags: [String]
    var isAutomaticSafetySnapshot: Bool
    var projectFileCount: Int?
    var codeSizeApproxLines: Int?
    var proofVerificationStatus: ProofVerificationStatus
    var proofVerificationMode: ProofVerificationMode?
    var remotePublishState: RemotePublishState
    var archiveAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case createdAtISO8601
        case manifestRelativePath
        case archiveRelativePath
        case title
        case summary
        case snapshotType
        case status
        case pathName
        case tags
        case isAutomaticSafetySnapshot
        case projectFileCount
        case codeSizeApproxLines
        case proofVerificationStatus
        case proofVerificationMode
        case remotePublishState
        case archiveAvailable
    }

    init(
        id: String,
        createdAt: Date,
        createdAtISO8601: String,
        manifestRelativePath: String,
        archiveRelativePath: String,
        title: String,
        summary: String,
        snapshotType: SnapshotType,
        status: SnapshotStatus,
        pathName: String,
        tags: [String],
        isAutomaticSafetySnapshot: Bool,
        projectFileCount: Int?,
        codeSizeApproxLines: Int?,
        proofVerificationStatus: ProofVerificationStatus,
        proofVerificationMode: ProofVerificationMode?,
        remotePublishState: RemotePublishState,
        archiveAvailable: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.createdAtISO8601 = createdAtISO8601
        self.manifestRelativePath = manifestRelativePath
        self.archiveRelativePath = archiveRelativePath
        self.title = title
        self.summary = summary
        self.snapshotType = snapshotType
        self.status = status
        self.pathName = pathName
        self.tags = tags
        self.isAutomaticSafetySnapshot = isAutomaticSafetySnapshot
        self.projectFileCount = projectFileCount
        self.codeSizeApproxLines = codeSizeApproxLines
        self.proofVerificationStatus = proofVerificationStatus
        self.proofVerificationMode = proofVerificationMode
        self.remotePublishState = remotePublishState
        self.archiveAvailable = archiveAvailable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        createdAtISO8601 = try c.decode(String.self, forKey: .createdAtISO8601)
        manifestRelativePath = try c.decode(String.self, forKey: .manifestRelativePath)
        archiveRelativePath = try c.decode(String.self, forKey: .archiveRelativePath)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        snapshotType = try c.decode(SnapshotType.self, forKey: .snapshotType)
        status = try c.decode(SnapshotStatus.self, forKey: .status)
        pathName = try c.decode(String.self, forKey: .pathName)
        tags = try c.decode([String].self, forKey: .tags)
        isAutomaticSafetySnapshot = try c.decode(Bool.self, forKey: .isAutomaticSafetySnapshot)
        projectFileCount = try c.decodeIfPresent(Int.self, forKey: .projectFileCount)
        codeSizeApproxLines = try c.decodeIfPresent(Int.self, forKey: .codeSizeApproxLines)
        proofVerificationStatus = try c.decodeIfPresent(ProofVerificationStatus.self, forKey: .proofVerificationStatus) ?? .unverified
        proofVerificationMode = try c.decodeIfPresent(ProofVerificationMode.self, forKey: .proofVerificationMode)
        remotePublishState = try c.decodeIfPresent(RemotePublishState.self, forKey: .remotePublishState) ?? .notPublished
        archiveAvailable = try c.decodeIfPresent(Bool.self, forKey: .archiveAvailable) ?? true
    }
}

struct SnapshotDraft {
    var title: String
    var summary: String
    var whatChanged: String
    var why: String
    var importantFilesTouchedText: String
    var gotchas: String
    var tagsText: String
    var proofCommand: String
    var linkedMemoryIDsText: String
    var status: SnapshotStatus
    var snapshotType: SnapshotType
    var pathName: String
    var changeIntent: String
    var riskLevel: SnapshotRiskLevel
    var outcome: SnapshotOutcome?

    static func empty(pathName: String) -> SnapshotDraft {
        SnapshotDraft(
            title: "",
            summary: "",
            whatChanged: "",
            why: "",
            importantFilesTouchedText: "",
            gotchas: "",
            tagsText: "",
            proofCommand: "",
            linkedMemoryIDsText: "",
            status: .working,
            snapshotType: .featureWorks,
            pathName: pathName,
            changeIntent: "",
            riskLevel: .medium,
            outcome: nil
        )
    }

    func toNotes(defaultTitle: String) -> SnapshotNotes {
        SnapshotNotes(
            title: title.isBlank ? defaultTitle : title.trimmed,
            summary: summary.trimmed,
            whatChanged: whatChanged.trimmed,
            why: why.trimmed,
            importantFilesTouched: importantFilesTouchedText
                .split(separator: ",")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty },
            gotchas: gotchas.trimmed,
            tags: tagsText
                .split(separator: ",")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty },
            status: status,
            snapshotType: snapshotType,
            pathName: pathName.trimmedOr("main"),
            proofCommand: proofCommand.trimmed,
            linkedMemoryIDs: linkedMemoryIDsText
                .split(separator: ",")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty },
            changeIntent: changeIntent.trimmed,
            riskLevel: riskLevel,
            outcome: outcome
        )
    }
}
