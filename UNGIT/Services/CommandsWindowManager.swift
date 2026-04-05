import Foundation
import SwiftUI
import AppKit

@MainActor
final class CommandsWindowManager {
    static let shared = CommandsWindowManager()

    private var panel: NSPanel?

    private init() {}

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let hosting = NSHostingController(rootView: CommandsReferenceView())
        let panel = NSPanel(
            contentRect: NSRect(x: 140, y: 140, width: 460, height: 420),
            styleMask: [.titled, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "UNGIT Commands"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = hosting

        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
