import AppKit

/// Reports the current cursor position globally so the floating cat can
/// follow it. Uses both a global monitor (events from other apps) and a
/// local monitor (events while Kitty's own windows have focus).
///
/// Requires the Accessibility permission for the global monitor — same
/// permission the push-to-talk hotkey needs.
final class CursorTracker {

    var onMove: ((NSPoint) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?

    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.fire()
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
            handler: handler
        )
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { event in
            handler(event)
            return event
        }
        // Belt-and-suspenders: if for whatever reason the move events stop
        // arriving (some fullscreen apps swallow them), keep nudging the
        // window to wherever the cursor actually is.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.fire()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
        // Emit once immediately so the window has a real position before
        // the first mouse move.
        fire()
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor  { NSEvent.removeMonitor(l); localMonitor  = nil }
        pollTimer?.invalidate(); pollTimer = nil
    }

    private func fire() {
        onMove?(NSEvent.mouseLocation)
    }
}
