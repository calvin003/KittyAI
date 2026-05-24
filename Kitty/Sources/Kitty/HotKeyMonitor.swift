import AppKit

/// Global push-to-talk on Ctrl+Option.
///
/// Works by monitoring `.flagsChanged` events system-wide and firing
/// `onPress` when *both* modifiers transition into being held, and
/// `onRelease` when either is dropped while the gesture is active.
///
/// Requires the Accessibility permission. Without it `addGlobalMonitorForEvents`
/// silently delivers nothing, which is the #1 source of "hotkey doesn't work".
final class HotKeyMonitor {

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// Set of modifiers that must all be held simultaneously.
    private let required: NSEvent.ModifierFlags = [.control, .option]

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isActive = false

    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged,
                                                          handler: handler)
        // Also intercept locally so it works when Kitty's own panel has focus.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor  { NSEvent.removeMonitor(l); localMonitor  = nil }
        isActive = false
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let allHeld = flags.isSuperset(of: required)

        if allHeld && !isActive {
            isActive = true
            onPress?()
        } else if !allHeld && isActive {
            isActive = false
            onRelease?()
        }
    }
}
