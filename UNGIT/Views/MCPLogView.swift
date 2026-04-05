import SwiftUI
import AppKit
import Combine

final class MCPLogViewModel: ObservableObject {
    @Published var content: String = ""
    @Published var lastUpdated: Date?
    @Published var logExists = false
    @Published var errorMessage: String?

    let logURL: URL

    init(logURL: URL = MCPLogViewModel.defaultLogURL) {
        self.logURL = logURL
    }

    func refresh() {
        let fm = FileManager.default
        logExists = fm.fileExists(atPath: logURL.path)
        guard logExists else {
            content = ""
            lastUpdated = Date()
            errorMessage = nil
            return
        }

        do {
            content = try String(contentsOf: logURL, encoding: .utf8)
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        do {
            try Data().write(to: logURL, options: .atomic)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logURL.path, forType: .string)
    }

    static var defaultLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/UNGIT", isDirectory: true)
            .appendingPathComponent("mcp-server.log", isDirectory: false)
    }
}

struct MCPLogView: View {
    @StateObject private var viewModel = MCPLogViewModel()
    @State private var autoRefresh = true
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Refresh") { viewModel.refresh() }
                Toggle("Auto-refresh", isOn: $autoRefresh)
                    .toggleStyle(.checkbox)
                Button("Clear Log") { viewModel.clear() }
                    .disabled(!viewModel.logExists)
                Spacer()
                Button("Copy Path") { viewModel.copyPath() }
                Button("Reveal in Finder") { viewModel.revealInFinder() }
            }

            Text("Log: \(viewModel.logURL.path)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let lastUpdated = viewModel.lastUpdated {
                Text("Last updated: \(DateFormatters.display.string(from: lastUpdated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                Text("Error: \(errorMessage)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Group {
                if !viewModel.logExists {
                    ContentUnavailableView(
                        "No MCP Log File Yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Start a Codex session that launches UNGIT MCP, then refresh.")
                    )
                } else if viewModel.content.isEmpty {
                    ContentUnavailableView(
                        "MCP Log Is Empty",
                        systemImage: "doc.plaintext",
                        description: Text("No server events recorded yet.")
                    )
                } else {
                    ScrollView {
                        Text(viewModel.content)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.06))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .onAppear { viewModel.refresh() }
        .onReceive(timer) { _ in
            guard autoRefresh else { return }
            viewModel.refresh()
        }
    }
}
