import Foundation

struct SearchProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let aliases: [String]
    let symbolName: String
    let baseURL: URL
    let queryItemName: String

    func searchURL(for rawQuery: String) -> URL? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: queryItemName, value: query))
        components?.queryItems = queryItems
        return components?.url
    }

    func matches(_ rawInput: String) -> Bool {
        let input = Self.normalized(rawInput)
        guard !input.isEmpty else { return false }
        return searchTokens.contains { $0 == input || $0.hasPrefix(input) }
    }

    func exactlyMatches(_ rawInput: String) -> Bool {
        let input = Self.normalized(rawInput)
        guard !input.isEmpty else { return false }
        return searchTokens.contains(input)
    }

    private var searchTokens: [String] {
        ([name] + aliases).map(Self.normalized)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}

struct NavigationService {
    static let shared = NavigationService()

    static let searchProviders: [SearchProvider] = [
        SearchProvider(
            id: "google",
            name: "Google",
            aliases: ["g", "search", "google.com", "www.google.com"],
            symbolName: "magnifyingglass",
            baseURL: URL(string: "https://www.google.com/search")!,
            queryItemName: "q"
        ),
        SearchProvider(
            id: "youtube",
            name: "YouTube",
            aliases: ["yt", "video", "videos", "youtube.com", "www.youtube.com"],
            symbolName: "play.rectangle.fill",
            baseURL: URL(string: "https://www.youtube.com/results")!,
            queryItemName: "search_query"
        ),
        SearchProvider(
            id: "amazon",
            name: "Amazon",
            aliases: ["amz", "shop", "shopping", "amazon.com", "www.amazon.com"],
            symbolName: "shippingbox.fill",
            baseURL: URL(string: "https://www.amazon.com/s")!,
            queryItemName: "k"
        ),
        SearchProvider(
            id: "duckduckgo",
            name: "DuckDuckGo",
            aliases: ["duck", "ddg"],
            symbolName: "scope",
            baseURL: URL(string: "https://duckduckgo.com/")!,
            queryItemName: "q"
        ),
        SearchProvider(
            id: "bing",
            name: "Bing",
            aliases: ["b", "ben"],
            symbolName: "b.circle.fill",
            baseURL: URL(string: "https://www.bing.com/search")!,
            queryItemName: "q"
        ),
        SearchProvider(
            id: "github",
            name: "GitHub",
            aliases: ["gh", "code"],
            symbolName: "chevron.left.forwardslash.chevron.right",
            baseURL: URL(string: "https://github.com/search")!,
            queryItemName: "q"
        ),
        SearchProvider(
            id: "wikipedia",
            name: "Wikipedia",
            aliases: ["wiki", "w"],
            symbolName: "book.closed.fill",
            baseURL: URL(string: "https://en.wikipedia.org/w/index.php")!,
            queryItemName: "search"
        )
    ]

    private let searchBaseURL = URL(string: "https://www.google.com/search")!

    func destinationURL(for rawInput: String) -> URL? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if let directURL = directURL(from: input) {
            return directURL
        }

        if looksLikeHost(input), let url = URL(string: "https://\(input)") {
            return url
        }

        var components = URLComponents(url: searchBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: input)]
        return components?.url
    }

    func searchProvider(matching rawInput: String) -> SearchProvider? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        return Self.searchProviders.first { $0.exactlyMatches(input) }
            ?? Self.searchProviders.first { $0.matches(input) }
    }

    func searchURL(provider: SearchProvider, query: String) -> URL? {
        provider.searchURL(for: query)
    }

    func searchQuery(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              let queryItems = components.queryItems else {
            return nil
        }

        for provider in Self.searchProviders {
            guard let providerComponents = URLComponents(url: provider.baseURL, resolvingAgainstBaseURL: false),
                  let providerHost = providerComponents.host?.lowercased(),
                  host == providerHost || host.hasSuffix(".\(providerHost)"),
                  components.path == providerComponents.path else {
                continue
            }

            let query = queryItems
                .first { $0.name == provider.queryItemName }?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let query, !query.isEmpty {
                return query
            }
        }

        return nil
    }

    private func directURL(from input: String) -> URL? {
        guard let url = URL(string: input), let scheme = url.scheme?.lowercased() else {
            return nil
        }

        if ["http", "https"].contains(scheme), url.host != nil {
            return url
        }

        if scheme == "about" {
            return url
        }

        return nil
    }

    private func looksLikeHost(_ input: String) -> Bool {
        if input.contains(" ") || input.contains("\n") {
            return false
        }

        if input == "localhost" || input.hasPrefix("localhost:") {
            return true
        }

        if input.range(of: #"^(\d{1,3}\.){3}\d{1,3}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil {
            return true
        }

        return input.contains(".")
    }
}
