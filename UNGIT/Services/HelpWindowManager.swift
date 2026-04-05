import Foundation
import SwiftUI
import AppKit

@MainActor
final class HelpWindowManager {
    static let shared = HelpWindowManager()

    private var panel: NSPanel?

    private init() {}

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let hosting = NSHostingController(rootView: HelpView())
        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 140, width: 860, height: 620),
            styleMask: [.titled, .utilityWindow, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        panel.title = "UNGIT Help"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting

        self.panel = panel
        panel.orderFrontRegardless()
    }
}
