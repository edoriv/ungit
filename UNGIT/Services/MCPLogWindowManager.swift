import Foundation
import SwiftUI
import AppKit

@MainActor
final class MCPLogWindowManager {
    static let shared = MCPLogWindowManager()

    private var panel: NSPanel?

    private init() {}

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let hosting = NSHostingController(rootView: MCPLogView())
        let panel = NSPanel(
            contentRect: NSRect(x: 140, y: 120, width: 1020, height: 700),
            styleMask: [.titled, .utilityWindow, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        panel.title = "UNGIT MCP Log"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 860, height: 560)
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: 1020, height: 700))
        panel.center()

        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
