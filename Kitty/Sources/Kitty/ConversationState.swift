import SwiftUI

/// Shared, observable state for the HUD. Driven by AppDelegate as the
/// push-to-talk → transcribe → think → speak pipeline runs.
@MainActor
final class ConversationState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case thinking
        case answering
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var transcript: String = ""
    @Published var reply: String = ""

    func reset() {
        phase = .idle
        transcript = ""
        reply = ""
    }
}
