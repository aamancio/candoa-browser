import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct CandoaAIConversationTurn: Sendable {
    enum Role: Sendable {
        case user
        case assistant
    }

    let role: Role
    let text: String
}

struct CandoaAIPageContext: Sendable {
    let title: String?
    let url: String?
    let text: String?
}

enum CandoaAIAvailability: Sendable, Equatable {
    case available
    case unavailable(String)
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
enum CandoaFoundationModelsService {
    static var availability: CandoaAIAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("Apple Intelligence is not available on this Mac.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings to use Ask.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence is still preparing its model. Try again when it finishes.")
        @unknown default:
            return .unavailable("Apple Intelligence is not available right now.")
        }
    }

    static func streamResponse(
        to prompt: String,
        context: CandoaAIPageContext,
        recentTurns: [CandoaAIConversationTurn]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard case .available = availability else {
                        continuation.finish()
                        return
                    }

                    let session = LanguageModelSession(
                        instructions: """
                        You are Ask, Candoa's browser assistant.
                        Answer concisely and directly.
                        Use the current page context only when it is relevant.
                        If you cannot know something from the prompt or context, say so briefly.
                        Do not mention implementation details, model adapters, or Foundation Models.
                        """
                    )

                    let stream = session.streamResponse(
                        to: modelPrompt(
                            userPrompt: prompt,
                            context: context,
                            recentTurns: recentTurns
                        ),
                        options: GenerationOptions(maximumResponseTokens: 300)
                    )

                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func modelPrompt(
        userPrompt: String,
        context: CandoaAIPageContext,
        recentTurns: [CandoaAIConversationTurn]
    ) -> String {
        var parts: [String] = []

        if let title = context.title, !title.isEmpty {
            parts.append("Current page title: \(title)")
        }

        if let url = context.url, !url.isEmpty {
            parts.append("Current page URL: \(url)")
        }

        if let text = context.text, !text.isEmpty {
            parts.append("Current page text excerpt:\n\(text)")
        }

        let transcript = recentTurns
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(6)
            .map { turn in
                switch turn.role {
                case .user:
                    return "User: \(turn.text)"
                case .assistant:
                    return "Ask: \(turn.text)"
                }
            }
            .joined(separator: "\n")

        if !transcript.isEmpty {
            parts.append("Recent conversation:\n\(transcript)")
        }

        parts.append("User: \(userPrompt)")
        parts.append("Ask:")

        return parts.joined(separator: "\n\n")
    }
}
#endif
