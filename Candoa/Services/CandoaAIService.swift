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

    var hasAttachedContext: Bool {
        [title, url, text].contains { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }
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
                        Treat the attached page context as the source for the current user message.
                        The attached page context may include a "Visible page controls and links" section from the currently visible viewport.
                        For questions about buttons, links, inputs, signing in, logging in, navigation, or where to click, answer only from the visible controls and links section.
                        If the requested control is not listed there, say that you do not see it in the visible scanned page context. Do not guess a location.
                        Words like "this", "that", "page", "site", and "website" in the current message refer to the attached page context when it exists.
                        If recent conversation conflicts with attached page context, the attached page context wins.
                        If no page context is attached and the user asks about this page or website, say that you cannot see what they are looking at and ask them to attach page context or share the URL.
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

        if !context.hasAttachedContext {
            parts.append("Current message context: no page context is attached.")
        }

        if let title = context.title, !title.isEmpty {
            parts.append("Current message attached page title: \(title)")
        }

        if let url = context.url, !url.isEmpty {
            parts.append("Current message attached page URL: \(url)")
        }

        if let text = context.text, !text.isEmpty {
            parts.append("Current message attached page text excerpt:\n\(text)")
        }

        parts.append("User: \(userPrompt)")
        parts.append("Ask:")

        return parts.joined(separator: "\n\n")
    }
}
#endif
