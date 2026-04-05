import Foundation

struct ProjectLayout {
    let projectURL: URL

    var ungitURL: URL { projectURL.appendingPathComponent(".ungit", isDirectory: true) }
    var snapshotsURL: URL { ungitURL.appendingPathComponent("snapshots", isDirectory: true) }
    var manifestsURL: URL { ungitURL.appendingPathComponent("manifests", isDirectory: true) }
    var exportsURL: URL { ungitURL.appendingPathComponent("exports", isDirectory: true) }
    var restoresURL: URL { ungitURL.appendingPathComponent("restores", isDirectory: true) }
    var tempURL: URL { ungitURL.appendingPathComponent("temp", isDirectory: true) }
    var projectMetadataURL: URL { ungitURL.appendingPathComponent("project.json", isDirectory: false) }
    var projectLogJSONURL: URL { ungitURL.appendingPathComponent("project-log.json", isDirectory: false) }
    var projectLogMarkdownURL: URL { ungitURL.appendingPathComponent("project-log.md", isDirectory: false) }
    var restoreApprovalURL: URL { ungitURL.appendingPathComponent("restore-approval.json", isDirectory: false) }
    var restoreApprovalLogURL: URL { ungitURL.appendingPathComponent("restore-approval.log", isDirectory: false) }
    var projectSummaryURL: URL { projectURL.appendingPathComponent("PROJECT_SUMMARY.md", isDirectory: false) }
    var bugsURL: URL { projectURL.appendingPathComponent("BUGS.md", isDirectory: false) }
    var ideasURL: URL { projectURL.appendingPathComponent("IDEAS.md", isDirectory: false) }
    var todoURL: URL { projectURL.appendingPathComponent("TODO.md", isDirectory: false) }
    var parkURL: URL { projectURL.appendingPathComponent("PARK.md", isDirectory: false) }
    var restoreDrillsURL: URL { projectURL.appendingPathComponent("RESTORE_DRILLS.md", isDirectory: false) }
}
