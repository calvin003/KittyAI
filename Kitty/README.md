# Kitty

A tiny cat AI buddy that lives on your Mac. A cat sprite trails behind your cursor wherever it goes. Hold **⌃⌥ (Ctrl+Option)** anywhere, talk, release — the cat changes mood, a small bubble appears above its head with the answer, and it speaks the reply out loud. The brain is a local Ollama model running on `localhost:11434`.

## The cat

The cat has three moods, each driven by a separate PNG you drop into `Sources/Kitty/Resources/`:

| File | When it's shown |
|---|---|
| `cat_idle.png`      | hanging out, nothing happening |
| `cat_listening.png` | mic is open, you're talking |
| `cat_busy.png`      | thinking and answering |

Square images, transparent background (~256×256 or larger) look best. If a file is missing the app falls back to a flat colored circle so it still runs.

## Stack

- **App:** native macOS, SwiftUI + AppKit, menu-bar agent (no Dock icon)
- **Voice in:** `AVAudioEngine` mic tap → `SFSpeechRecognizer` (on-device when available)
- **Voice out:** `AVSpeechSynthesizer`
- **Brain:** Ollama HTTP (`POST /api/chat`, streaming)
- **Hotkey:** global `NSEvent` flagsChanged monitor (push-to-talk on Ctrl+Option)

## Prerequisites

1. macOS 13+ (Ventura or later)
2. Xcode 15+
3. [Ollama](https://ollama.com) running locally, with at least one model pulled:
   ```bash
   brew install ollama
   ollama serve &
   ollama pull llama3.2
   ```
   The default model name is `llama3.2` — change it in `OllamaClient.swift` if you pulled something else.

## Build & run

### Option A — XcodeGen (one command)

```bash
brew install xcodegen
cd Kitty
xcodegen generate
open Kitty.xcodeproj
```

Then press **⌘R** in Xcode.

### Option B — by hand in Xcode

1. Xcode → File → New → Project → **macOS / App**, Interface: **SwiftUI**, Language: **Swift**. Name it `Kitty`.
2. Delete the generated `ContentView.swift` and the `@main` `App` struct.
3. Drag every file under `Sources/Kitty/` into the new target.
4. Open the target's **Info** tab, add the keys from `Sources/Kitty/Info.plist` (microphone usage, speech recognition usage, `LSUIElement = YES`).
5. **Signing & Capabilities** → ensure **App Sandbox** is *off* (the global hotkey + screen tools won't work in the sandbox), or — if you want sandboxing — add the *Audio Input* entitlement and accept the loss of system-wide hotkey.
6. Build & run.

## First-run permissions

On first launch you'll be prompted for three things — say yes to all:

1. **Microphone** — to hear you.
2. **Speech Recognition** — to transcribe what you said.
3. **Accessibility** — required to monitor the Ctrl+Option modifier globally. Open System Settings → Privacy & Security → Accessibility, add Kitty, toggle it on. (The app will pop the dialog automatically the first time it tries to register.)

If the hotkey does nothing, that third permission is the culprit 99% of the time.

## Using it

- The Kitty icon (•) appears in the menu bar.
- Press and **hold ⌃⌥** anywhere. The panel slides in next to the cursor: *“listening…”*
- Speak. Release the keys when you're done.
- It transcribes, sends to Ollama, streams the reply into the panel, and speaks it.

## Roadmap (things wired up to be easy to add)

- **Screen vision** — hook a `ScreenCaptureKit` snapshot into the prompt before sending to a vision-capable model (`llava`, `bakllava`).
- **"Kitty agent" mode** — second hotkey that opens a background task with tool-use (file edits, web fetch) instead of a quick chat.
- **Wake word** — replace the modifier monitor with Picovoice Porcupine.
- **Cursor-follow window** — current panel pins to the cursor at activation; switch to live-following by re-positioning on a CGEventTap mouse-move.

## File map

| File | What it does |
|---|---|
| `KittyApp.swift` | `@main` entry, hands off to `AppDelegate`. |
| `AppDelegate.swift` | Menu-bar item, permission prompts, wires hotkey → capture → Ollama → speaker. |
| `HotKeyMonitor.swift` | Global Ctrl+Option push-to-talk detector. |
| `VoiceCapture.swift` | `AVAudioEngine` + `SFSpeechRecognizer` live transcription. |
| `OllamaClient.swift` | Streaming `/api/chat` client. |
| `Speaker.swift` | `AVSpeechSynthesizer` wrapper. |
| `FloatingPanel.swift` | Borderless click-through `NSPanel` that lerps toward the cursor. |
| `CursorTracker.swift` | Global mouseMoved monitor → emits cursor positions. |
| `CatAssets.swift` | Loads the three cat PNGs and maps phase → mood. |
| `HUDView.swift` | Cat sprite + speech bubble above it. |
| `ConversationState.swift` | `@MainActor` `ObservableObject` shared by HUD + AppDelegate. |
| `Info.plist` | Usage strings + `LSUIElement`. |
