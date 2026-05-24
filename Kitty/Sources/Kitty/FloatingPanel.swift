import AppKit
import SwiftUI

/// Always-on-top, click-through panel that hosts the cat HUD and tracks
/// the cursor live. The panel never steals focus and never blocks clicks.
final class FloatingPanel: NSPanel {

    /// Cat-to-cursor offset in screen points. The cat sits to the lower-right
    /// of the cursor (negative y because the cat is drawn below the hotspot).
    var cursorOffset: NSPoint = NSPoint(x: 24, y: -36)

    /// Smoothing factor for cursor following. 1.0 = snap instantly, 0.18
    /// gives a nice springy lag like a Tamagotchi trailing behind.
    var followLerp: CGFloat = 0.22

    private var targetPosition: NSPoint?
    private var followTimer: Timer?

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .statusBar
        self.isMovableByWindowBackground = false
        self.hasShadow = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // The whole cat is purely cosmetic — never intercept clicks.
        self.ignoresMouseEvents = true

        let host = NSHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        self.contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Make the cat visible and start the smoothing timer.
    @MainActor
    func show() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().alphaValue = 1
        }
        startFollowingLoop()
    }

    @MainActor
    func hide() {
        followTimer?.invalidate()
        followTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    /// New cursor sample. The follow loop interpolates towards it.
    @MainActor
    func updateCursor(_ point: NSPoint) {
        targetPosition = desiredOrigin(forCursor: point)
        if !isVisible { return }
    }

    // MARK: - private

    private func startFollowingLoop() {
        followTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.stepFollow()
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func stepFollow() {
        guard let target = targetPosition else { return }
        let current = frame.origin
        let next = NSPoint(
            x: current.x + (target.x - current.x) * followLerp,
            y: current.y + (target.y - current.y) * followLerp
        )
        // Snap if we're within a hair, so the timer can idle.
        if abs(next.x - target.x) < 0.5 && abs(next.y - target.y) < 0.5 {
            setFrameOrigin(target)
        } else {
            setFrameOrigin(next)
        }
    }

    private func desiredOrigin(forCursor cursor: NSPoint) -> NSPoint {
        let size = frame.size
        var origin = NSPoint(
            x: cursor.x + cursorOffset.x,
            y: cursor.y + cursorOffset.y - size.height
        )
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
        if let bounds = screen?.visibleFrame {
            origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
            origin.y = min(max(origin.y, bounds.minY + 4), bounds.maxY - size.height - 4)
        }
        return origin
    }
}
