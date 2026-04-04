import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static var builtInScreen: NSScreen? {
        if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) { return s }
        let names = ["built-in", "color lcd", "retina lcd", "liquid retina"]
        if let s = NSScreen.screens.first(where: { scr in
            let n = scr.localizedName.lowercased()
            return names.contains(where: { n.contains($0) })
        }) { return s }
        return NSScreen.screens.first
    }

    static var menuBarHeight: CGFloat {
        guard let screen = builtInScreen else { return 24 }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        self.contentView = contentView
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !isKeyWindow {
                makeKeyAndOrderFront(nil)
            }
        }
        super.sendEvent(event)
    }

    func positionAtNotch() {
        guard let screen = FloatingPanel.builtInScreen else { return }
        let panelWidth: CGFloat = 740
        let panelHeight: CGFloat = 520
        let x = screen.frame.midX - panelWidth / 2
        let overshoot: CGFloat = 4
        let y = screen.frame.maxY + overshoot

        setContentSize(NSSize(width: panelWidth, height: panelHeight))
        setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }
}

// MARK: - Passthrough hosting view
// Pass through clicks outside the pill. The pill is 340pt wide, centered
// in a 400pt panel. Everything outside the center band is transparent.

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }

        // Panel is 740pt wide. Content is centered.
        // Collapsed pill: 340pt → margin = (740-340)/2 = 200, minus ear ~5 → ~195
        // Expanded pill: 680pt → margin = (740-680)/2 = 30, minus ear ~5 → ~25
        // We use a generous margin that works for the expanded state.
        // The collapsed state has its own clipping via the pill frame.
        let margin: CGFloat = 25
        if point.x < margin || point.x > bounds.width - margin {
            return nil
        }

        return super.hitTest(point) ?? self
    }
}

// MARK: - WindowManager

final class WindowManager {
    static let shared = WindowManager()

    private(set) var panel: FloatingPanel?

    func createPanel<Content: View>(content: Content) {
        let hostingView = PassthroughHostingView(rootView: content)
        let p = FloatingPanel(contentView: hostingView)
        p.positionAtNotch()
        p.orderFrontRegardless()
        self.panel = p
    }

    func reposition() {
        guard FloatingPanel.builtInScreen != nil else {
            panel?.orderOut(nil); return
        }
        panel?.positionAtNotch()
        panel?.orderFrontRegardless()
    }
}
