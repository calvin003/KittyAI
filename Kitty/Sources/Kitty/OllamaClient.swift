import Foundation

/// Minimal streaming client for Ollama's `/api/chat`.
///
/// Ollama returns newline-delimited JSON objects of the form
/// `{"message":{"role":"assistant","content":"..."}, "done":false}`.
/// We yield each `content` fragment as it arrives.
final class OllamaClient {

    var host: URL = URL(string: "http://127.0.0.1:11434")!
    var model: String = "llama3.2"
    var system: String = """
        You are Kitty, a tiny cat AI buddy that lives on the user's Mac. \
        You are literally a cat — playful, curious, affectionate, a bit silly. \
        Be concise: one or two short sentences unless they ask for more. \
        Write in lowercase, like a kitten texting back. \
        Sprinkle in cat sounds naturally — meow, mrrp, purr, mew, prrr — about \
        once every 1–3 replies, never forced, sometimes at the start, sometimes \
        the end, sometimes mid-sentence. Don't say "meow" in every reply; you're \
        a cat, not a parrot.
        """

    private var history: [Message] = []

    struct Message: Codable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: [String: Double]?
    }

    private struct ChatChunk: Decodable {
        let message: Message?
        let done: Bool
    }

    enum ClientError: Error, LocalizedError {
        case badStatus(Int, String)
        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body):
                return "Ollama responded \(code): \(body.prefix(200))"
            }
        }
    }

    /// Stream the assistant's reply for a single user prompt, threaded onto
    /// the conversation history so follow-ups work.
    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let userMsg = Message(role: "user", content: prompt)
                    var messages: [Message] = [Message(role: "system", content: system)]
                    messages.append(contentsOf: history)
                    messages.append(userMsg)

                    let body = ChatRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        options: ["temperature": 0.6]
                    )

                    var request = URLRequest(url: host.appendingPathComponent("api/chat"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        // Drain a little body for the error message.
                        var preview = ""
                        for try await line in bytes.lines {
                            preview += line + "\n"
                            if preview.count > 300 { break }
                        }
                        throw ClientError.badStatus(http.statusCode, preview)
                    }

                    var assembled = ""
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
                        let chunk: ChatChunk
                        do {
                            chunk = try decoder.decode(ChatChunk.self, from: data)
                        } catch {
                            // Ignore malformed lines rather than aborting the whole turn.
                            continue
                        }
                        if let piece = chunk.message?.content, !piece.isEmpty {
                            assembled += piece
                            continuation.yield(piece)
                        }
                        if chunk.done { break }
                    }

                    // Persist this turn into history for follow-ups.
                    history.append(userMsg)
                    history.append(Message(role: "assistant", content: assembled))
                    if history.count > 20 { history.removeFirst(history.count - 20) }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func clearHistory() {
        history.removeAll()
    }
}
