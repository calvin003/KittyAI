import AppKit
import SwiftUI

/// A small floating text-input bar — the typed-prompt counterpart to the
/// push-to-talk voice flow. Invoked by the ⌘⌥T hotkey or the menu item
/// "Type to Kitty…". On submit it calls `onSubmit` and dismisses itself.
final class TextInputWindow: NSWindow {

    var onSubmit: ((String) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 64),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = TextInputView(
            onSubmit: { [weak self] text in
                self?.onSubmit?(text)
                self?.dismiss()
            },
            onCancel: { [weak self] in self?.dismiss() }
        )
        self.contentView = NSHostingView(rootView: view)
    }

    // Borderless windows aren't key by default; we need to opt in so the
    // TextField can receive keystrokes.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func showNearTop() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let size = self.frame.size
            // Spotlight-style: centered horizontally, ~25% from top.
            let origin = NSPoint(
                x: f.midX - size.width / 2,
                y: f.maxY - size.height - f.height * 0.25
            )
            setFrameOrigin(origin)
        }
        // LSUIElement apps need a momentary activation to claim key focus.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
        // Return to accessory so the dock icon doesn't linger.
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct TextInputView: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)

            TextField("type to kitty…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focused)
                .onSubmit {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onSubmit(trimmed) }
                }
                .onExitCommand { onCancel() }

            if !text.isEmpty {
                Button(action: {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onSubmit(trimmed) }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .padding(8) // outer shadow gap
        .onAppear { focused = true }
    }
}
