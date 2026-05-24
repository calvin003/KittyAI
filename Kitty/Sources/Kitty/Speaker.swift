import AVFoundation

/// Audio output for Kitty — pure sound effects, no TTS.
///
/// Each reply is bookended by a random meow .wav from `Resources/`.
/// `playMeow()` is async and resumes when playback finishes, so the
/// AppDelegate can `await` it in sequence.
final class Speaker: NSObject {

    private var player: AVAudioPlayer?
    private var meowContinuation: CheckedContinuation<Void, Never>?

    /// Play one random meow .wav from the bundle. Awaits playback completion.
    /// If no .wav files are bundled or playback fails, returns immediately.
    func playMeow() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            // If a previous meow was still pending, resolve it first.
            if let pending = meowContinuation {
                pending.resume()
                meowContinuation = nil
            }
            guard let url = pickRandomMeowURL() else {
                cont.resume()
                return
            }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.delegate = self
                p.volume = 0.95
                self.meowContinuation = cont
                self.player = p
                p.prepareToPlay()
                p.play()
            } catch {
                cont.resume()
            }
        }
    }

    /// Stop any in-flight meow and unblock pending awaits.
    func stop() {
        player?.stop()
        player = nil
        if let c = meowContinuation { c.resume(); meowContinuation = nil }
    }

    // MARK: - private

    private func pickRandomMeowURL() -> URL? {
        let urls = Bundle.main.urls(forResourcesWithExtension: "wav",
                                    subdirectory: nil) ?? []
        return urls.randomElement()
    }
}

extension Speaker: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        meowContinuation?.resume()
        meowContinuation = nil
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        meowContinuation?.resume()
        meowContinuation = nil
    }
}
