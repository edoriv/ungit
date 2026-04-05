// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UngitMCP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ungit-mcp", targets: ["ungit-mcp"])
    ],
    targets: [
        .target(
            name: "UngitMCPBridge",
            path: ".",
            sources: [
                "UNGIT/Models/AppError.swift",
                "UNGIT/Models/DateFormatters.swift",
                "UNGIT/Models/ProjectModels.swift",
                "UNGIT/Models/SnapshotModels.swift",
                "UNGIT/Models/StringExtensions.swift",
                "UNGIT/Services/ArchiveService.swift",
                "UNGIT/Services/CurrentStateService.swift",
                "UNGIT/Services/DirectoryChangeWatcher.swift",
                "UNGIT/Services/ExtractedProjectValidator.swift",
                "UNGIT/Services/FileSystemService.swift",
                "UNGIT/Services/JSONFileStore.swift",
                "UNGIT/Services/LogService.swift",
                "UNGIT/Services/ManifestStore.swift",
                "UNGIT/Services/NotesDraftService.swift",
                "UNGIT/Services/PathService.swift",
                "UNGIT/Services/ProcessRunner.swift",
                "UNGIT/Services/ProjectInitializer.swift",
                "UNGIT/Services/ProjectLayout.swift",
                "UNGIT/Services/ResourceSnapshotService.swift",
                "UNGIT/Services/RestoreSafetyService.swift",
                "UNGIT/Services/SnapshotService.swift",
                "UNGIT/Stores/ProjectStore.swift",
                "MCPBridge/Sources/UngitMCPBridge/JSONValue.swift",
                "MCPBridge/Sources/UngitMCPBridge/MCPServer.swift",
                "MCPBridge/Sources/UngitMCPBridge/UngitToolRouter.swift"
            ]
        ),
        .executableTarget(
            name: "ungit-mcp",
            dependencies: ["UngitMCPBridge"],
            path: "MCPBridge/Sources/ungit-mcp"
        ),
        .testTarget(
            name: "UngitMCPBridgeTests",
            dependencies: ["UngitMCPBridge"],
            path: "MCPBridge/Tests/UngitMCPBridgeTests"
        )
    ]
)
