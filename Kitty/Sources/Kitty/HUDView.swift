import SwiftUI

struct HUDView: View {
    @EnvironmentObject var state: ConversationState

    private let catSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            // Speech bubble appears above the cat when there's something to say.
            if bubbleText != nil || hasError {
                bubble
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            cat
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 170, alignment: .center)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: state.phase)
        .animation(.easeOut(duration: 0.15), value: state.transcript)
        .animation(.easeOut(duration: 0.15), value: state.reply)
    }

    // MARK: - parts

    private var cat: some View {
        CatAssets.view(for: state.phase.mood, size: catSize)
            .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 6)
            .scaleEffect(catScale)
            .animation(
                state.phase == .listening
                    ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                    : .easeOut(duration: 0.2),
                value: state.phase
            )
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasError, case .error(let msg) = state.phase {
                Text(msg)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red)
            } else if let text = bubbleText {
                Text(text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        )
        .frame(maxWidth: 160, alignment: .leading)
    }

    // MARK: - derived

    private var catScale: CGFloat {
        switch state.phase {
        case .listening: return 1.05
        case .thinking:  return 0.98
        case .answering: return 1.0
        default:         return 1.0
        }
    }

    private var hasError: Bool {
        if case .error = state.phase { return true }
        return false
    }

    /// What to show in the bubble — prefer the streamed reply once it starts,
    /// otherwise show the live transcript so the user sees they're heard.
    private var bubbleText: String? {
        if !state.reply.isEmpty { return state.reply }
        if !state.transcript.isEmpty { return state.transcript }
        return nil
    }
}
