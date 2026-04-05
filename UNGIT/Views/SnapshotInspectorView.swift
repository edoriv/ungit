import Foundation
import SwiftUI

struct SnapshotInspectorView: View {
    let entry: TimelineEntry?
    let manifest: SnapshotManifest?

    var body: some View {
        ScrollView {
            if let entry {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Viewing Snapshot")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(entry.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(DateFormatters.display.string(from: entry.createdAt))
                        .foregroundStyle(.secondary)

                    if entry.snapshotType == .trustedRollback {
                        Label("Safe Restore Point", systemImage: "shield.fill")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    } else if entry.snapshotType == .releaseCandidate || entry.snapshotType == .release {
                        Label("Sacred Landmark", systemImage: "flag.checkered")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.indigo)
                    }

                    inspectorSection("Snapshot Info") {
                        keyValue("Type", entry.snapshotType.rawValue)
                        keyValue("Status", entry.status.rawValue)
                        keyValue("Proof State", entry.proofVerificationStatus.rawValue)
                        let proofMode = manifest?.proofVerificationMode?.rawValue ?? "Not Recorded"
                        keyValue("Proof Mode", proofMode)
                        if let manifest {
                            keyValue("Risk Level", manifest.notes.riskLevel.rawValue)
                            keyValue("Outcome", manifest.notes.outcome?.rawValue ?? "Not Set")
                        }
                        keyValue("Path", entry.pathName)
                        keyValue("Automatic Safety", entry.isAutomaticSafetySnapshot ? "Yes" : "No")
                        if entry.snapshotType == .trustedRollback && entry.proofVerificationStatus != .verified {
                            keyValue("Rollback Check", "Trusted Rollback should be Verified")
                        } else if entry.snapshotType == .trustedRollback && manifest?.proofVerificationMode != .archive {
                            keyValue("Rollback Check", "Trusted Rollback should use Archive Proof")
                        } else if (entry.snapshotType == .releaseCandidate || entry.snapshotType == .release) && entry.proofVerificationStatus != .verified {
                            keyValue("Release Check", "\(entry.snapshotType.rawValue) should be Verified")
                        } else if (entry.snapshotType == .releaseCandidate || entry.snapshotType == .release) && manifest?.proofVerificationMode != .archive {
                            keyValue("Release Check", "\(entry.snapshotType.rawValue) should use Archive Proof")
                        }
                    }

                    if !entry.summary.isEmpty {
                        inspectorSection("Summary") {
                            Text(entry.summary)
                        }
                    }

                    inspectorSection("Files / Archive") {
                        keyValue("Archive", entry.archiveAvailable ? entry.archiveRelativePath : "Archive removed (history preserved)")
                        if manifest?.archiveLocked == true {
                            keyValue("Archive Protection", "Protected by UNGIT policy")
                        }
                        if let reason = manifest?.archivePruneReason, !reason.isEmpty {
                            keyValue("Prune Reason", reason)
                        }
                    }

                    if let manifest {
                        let hasNotes = !manifest.notes.whatChanged.isEmpty ||
                            !manifest.notes.why.isEmpty ||
                            !manifest.notes.gotchas.isEmpty ||
                            !manifest.notes.importantFilesTouched.isEmpty ||
                            !manifest.notes.tags.isEmpty

                        if hasNotes {
                            inspectorSection("Notes") {
                                if !manifest.notes.whatChanged.isEmpty {
                                    noteBlock("What Changed", manifest.notes.whatChanged)
                                }
                                if !manifest.notes.why.isEmpty {
                                    noteBlock("Why", manifest.notes.why)
                                }
                                if !manifest.notes.changeIntent.isEmpty {
                                    noteBlock("Change Intent", manifest.notes.changeIntent)
                                }
                                if !manifest.notes.gotchas.isEmpty {
                                    noteBlock("Gotchas", manifest.notes.gotchas)
                                }
                                if !manifest.notes.importantFilesTouched.isEmpty {
                                    noteBlock("Important Files", manifest.notes.importantFilesTouched.joined(separator: ", "))
                                }
                                if !manifest.notes.proofCommand.isEmpty {
                                    noteBlock("Proof Command", manifest.notes.proofCommand)
                                }
                                if !manifest.notes.linkedMemoryIDs.isEmpty {
                                    noteBlock("Linked IDs", manifest.notes.linkedMemoryIDs.joined(separator: ", "))
                                }
                                if !manifest.notes.tags.isEmpty {
                                    noteBlock("Tags", manifest.notes.tags.joined(separator: ", "))
                                }
                                if let proofDetails = manifest.proofDetails, !proofDetails.isEmpty {
                                    noteBlock("Proof Output", proofDetails)
                                }
                            }
                        }

                        if let resource = manifest.resourceSnapshot {
                            inspectorSection("Resource Snapshot") {
                                keyValue("Captured At", resource.capturedAt)
                                if let cpu = resource.cpuPercentObserved {
                                    keyValue("CPU (observed)", String(format: "%.1f%%", cpu))
                                }
                                if let memory = resource.memoryMBObserved {
                                    keyValue("Memory (observed)", String(format: "%.1f MB", memory))
                                }
                                if let energy = resource.energyImpactObserved, !energy.isEmpty {
                                    keyValue("Energy Impact (observed)", energy)
                                }
                                if let disk = resource.diskKbpsObserved {
                                    keyValue("Disk KB/s (observed)", String(format: "%.1f", disk))
                                }
                                if let network = resource.networkKbpsObserved {
                                    keyValue("Network KB/s (observed)", String(format: "%.1f", network))
                                }
                                Text(resource.captureContext)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            } else {
                ContentUnavailableView("No Snapshot Selected", systemImage: "clock.badge.questionmark", description: Text("Choose a snapshot from the timeline."))
                    .padding(30)
            }
        }
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(key):")
                .fontWeight(.semibold)
            Text(value)
                .foregroundStyle(.secondary)
        }
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

    private func noteBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(value)
        }
    }
}
