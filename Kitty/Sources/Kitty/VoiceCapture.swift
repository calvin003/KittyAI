import AVFoundation
import Speech

/// Push-to-talk voice capture with live transcription via
/// `SFSpeechRecognizer` (on-device when the locale supports it).
final class VoiceCapture {

    enum CaptureError: Error, LocalizedError {
        case recognizerUnavailable
        case notAuthorized
        case audioEngineFailed(Error)

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: return "Speech recognizer unavailable for this locale."
            case .notAuthorized:         return "Speech recognition not authorized in System Settings."
            case .audioEngineFailed(let e): return "Audio engine failed: \(e.localizedDescription)"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: .current)
                                                  ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var lastTranscript: String = ""

    /// Begin capturing. `onPartial` is called on a background queue with
    /// the running transcript every time the recognizer has more text.
    func start(onPartial: @escaping (String) -> Void) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw CaptureError.notAuthorized
        }
        guard let recognizer, recognizer.isAvailable else {
            throw CaptureError.recognizerUnavailable
        }

        // Clean up any previous run.
        cancelInternal()
        lastTranscript = ""

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            req.addsPunctuation = true
        }
        // Prefer on-device when available — privacy + offline.
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        self.request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cancelInternal()
            throw CaptureError.audioEngineFailed(error)
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                self?.lastTranscript = text
                onPartial(text)
                if result.isFinal {
                    // Nothing extra to do — `stop()` is what drives end-of-turn.
                }
            }
            if error != nil {
                // Surfacing recognizer errors here would be noisy; the final
                // `stop()` call still returns whatever we've got so far.
            }
        }
    }

    /// Stop capture and return the final (best-effort) transcript.
    @discardableResult
    func stop() -> String {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        // Give the recognizer a brief moment to flush; we don't await it
        // strictly because push-to-talk wants snappy turn-end.
        task?.finish()
        let text = lastTranscript
        request = nil
        task = nil
        return text
    }

    private func cancelInternal() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
