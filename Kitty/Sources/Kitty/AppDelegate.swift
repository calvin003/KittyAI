import AppKit
import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let state = ConversationState()

    private let hotkey  = HotKeyMonitor()
    private let cursor  = CursorTracker()
    private let voice   = VoiceCapture()
    private let speaker = Speaker()
    private let ollama  = OllamaClient()
    private let textWindow = TextInputWindow()

    private var currentTask: Task<Void, Never>?
    private var typeHotkeyMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        buildPanel()
        requestPermissions()
        wireCursorTracking()
        wireHotkey()
        wireTextInput()
        panel.show()                    // cat appears immediately at launch
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.stop()
        cursor.stop()
        if let m = typeHotkeyMonitor { NSEvent.removeMonitor(m); typeHotkeyMonitor = nil }
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            button.image = NSImage(systemSymbolName: "pawprint.fill",
                                   accessibilityDescription: "Kitty")?
                .withSymbolConfiguration(config)
            button.toolTip = "Hold ⌃⌥ to talk to Kitty"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Kitty — hold ⌃⌥ to talk",
                                action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let typeItem = NSMenuItem(title: "Type to Kitty…",
                                  action: #selector(showTextInput),
                                  keyEquivalent: "t")
        typeItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(typeItem)
        menu.addItem(NSMenuItem(title: "Hide cat",
                                action: #selector(toggleCat),
                                keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Open Accessibility Settings…",
                                action: #selector(openAccessibility),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit Kitty",
                                action: #selector(NSApp.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private var catHidden = false
    @objc private func toggleCat(_ sender: NSMenuItem) {
        catHidden.toggle()
        if catHidden {
            panel.hide()
            sender.title = "Show cat"
        } else {
            panel.show()
            sender.title = "Hide cat"
        }
    }

    // MARK: - Panel

    private func buildPanel() {
        panel = FloatingPanel(rootView: HUDView().environmentObject(state))
    }

    // MARK: - Permissions

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        SFSpeechRecognizer.requestAuthorization { _ in }
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Cursor tracking

    private func wireCursorTracking() {
        cursor.onMove = { [weak self] point in
            Task { @MainActor in
                self?.panel.updateCursor(point)
            }
        }
        cursor.start()
    }

    // MARK: - Hotkey wiring

    private func wireHotkey() {
        hotkey.onPress = { [weak self] in
            Task { @MainActor in self?.beginTurn() }
        }
        hotkey.onRelease = { [weak self] in
            Task { @MainActor in self?.endTurn() }
        }
        hotkey.start()
    }

    // MARK: - Text input

    private func wireTextInput() {
        textWindow.onSubmit = { [weak self] text in
            Task { @MainActor in self?.submitText(text) }
        }
        // ⌘⌥T = open the text input bar globally. keyCode 17 = "T".
        typeHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let wanted: NSEvent.ModifierFlags = [.command, .option]
            if mods == wanted && event.keyCode == 17 {
                Task { @MainActor in self?.showTextInput() }
            }
        }
    }

    @objc private func showTextInput() {
        textWindow.showNearTop()
    }

    @MainActor
    private func submitText(_ text: String) {
        currentTask?.cancel()
        speaker.stop()
        // Don't reset transcript — show what they typed in the bubble too.
        state.transcript = ""
        state.reply = ""
        if catHidden { panel.show(); catHidden = false }
        processPrompt(text)
    }

    // MARK: - Conversation pipeline

    @MainActor
    private func beginTurn() {
        currentTask?.cancel()
        speaker.stop()
        state.reset()
        state.phase = .listening
        if catHidden { panel.show(); catHidden = false }

        do {
            try voice.start { [weak self] partial in
                Task { @MainActor in
                    self?.state.transcript = partial
                }
            }
        } catch {
            state.phase = .error("mic: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func endTurn() {
        guard state.phase == .listening else { return }
        let final = voice.stop()
        processPrompt(final)
    }

    /// Shared pipeline: takes a text prompt (from voice or keyboard), streams
    /// the reply from Ollama into the HUD, and plays one random meow when the
    /// reply starts arriving.
    @MainActor
    private func processPrompt(_ raw: String) {
        let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            state.phase = .idle
            return
        }

        state.transcript = prompt
        state.phase = .thinking
        state.reply = ""

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Opening meow — announces Kitty's about to reply.
                await self.speaker.playMeow()
                try Task.checkCancellation()

                // Stream the model's reply into the bubble.
                for try await chunk in ollama.stream(prompt: prompt) {
                    try Task.checkCancellation()
                    if self.state.phase == .thinking {
                        self.state.phase = .answering
                    }
                    self.state.reply.append(chunk)
                }

                // Closing meow.
                try Task.checkCancellation()
                await self.speaker.playMeow()

                self.state.phase = .idle
                // Clear the bubble after a beat so the cat goes back to
                // its idle, no-bubble look.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if case .idle = self.state.phase {
                        self.state.transcript = ""
                        self.state.reply = ""
                    }
                }
            } catch is CancellationError {
                // user pressed again mid-answer; quietly drop
            } catch {
                self.state.phase = .error(error.localizedDescription)
            }
        }
    }
}
