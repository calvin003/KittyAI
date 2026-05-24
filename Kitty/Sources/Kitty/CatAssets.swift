import AppKit
import SwiftUI

/// Looks up the right cat sprite for the current conversation phase.
///
/// Required PNGs in `Sources/Kitty/Resources/`:
///   • `cat_idle.png`              — shown when nothing is happening
///   • `thinking&listeining.png`   — shown while mic is open OR while waiting on the model
///   • `reply.png`                 — shown while the model is streaming its answer
///
/// If a file is missing the app falls back to a colored disc so nothing
/// crashes — but you'll see a flat circle instead of a cat.
enum CatAssets {

    enum Mood {
        case idle, listenThink, answering
    }

    /// Returns the in-bundle image for the given mood, or nil if missing.
    static func image(for mood: Mood) -> NSImage? {
        NSImage(named: name(for: mood))
    }

    /// Convenience for SwiftUI: image or a colored fallback circle.
    @ViewBuilder
    static func view(for mood: Mood, size: CGFloat = 96) -> some View {
        if let nsImage = image(for: mood) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(fallbackColor(for: mood))
                .frame(width: size * 0.7, height: size * 0.7)
                .overlay(
                    Text(fallbackEmoji(for: mood))
                        .font(.system(size: size * 0.4))
                )
        }
    }

    // MARK: - private

    private static func name(for mood: Mood) -> String {
        switch mood {
        case .idle:        return "cat_idle"
        case .listenThink: return "thinking&listeining"
        case .answering:   return "reply"
        }
    }

    private static func fallbackColor(for mood: Mood) -> Color {
        switch mood {
        case .idle:        return .gray
        case .listenThink: return .pink
        case .answering:   return .yellow
        }
    }

    private static func fallbackEmoji(for mood: Mood) -> String {
        switch mood {
        case .idle:        return "🐱"
        case .listenThink: return "👂"
        case .answering:   return "💬"
        }
    }
}

extension ConversationState.Phase {
    var mood: CatAssets.Mood {
        switch self {
        case .idle, .error:         return .idle
        case .listening, .thinking: return .listenThink
        case .answering:            return .answering
        }
    }
}
