import Foundation
import WebKit

@MainActor
final class FaviconService {
    static let shared = FaviconService()

    private let cache = NSCache<NSURL, NSData>()

    func placeholderSymbol(for url: URL?) -> String {
        guard let host = url?.host(percentEncoded: false)?.lowercased() else {
            return "globe"
        }

        if host.contains("github") { return "chevron.left.forwardslash.chevron.right" }
        if host.contains("google") { return "magnifyingglass" }
        if host.contains("apple") { return "apple.logo" }
        if host.contains("localhost") { return "server.rack" }
        return "globe"
    }

    func faviconData(for pageURL: URL?, candidateURL: URL?) async -> Data? {
        let candidates = faviconCandidates(pageURL: pageURL, candidateURL: candidateURL)

        for url in candidates {
            if let cachedData = cache.object(forKey: url as NSURL) {
                return cachedData as Data
            }

            guard let fetchedData = await fetchImageData(from: url) else { continue }
            cache.setObject(fetchedData as NSData, forKey: url as NSURL)
            return fetchedData
        }

        return nil
    }

    private func faviconCandidates(pageURL: URL?, candidateURL: URL?) -> [URL] {
        var urls: [URL] = []

        if let candidateURL {
            urls.append(candidateURL)
        }

        if let pageURL, let scheme = pageURL.scheme, let host = pageURL.host(percentEncoded: false) {
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.port = pageURL.port
            components.path = "/favicon.ico"

            if let faviconURL = components.url {
                urls.append(faviconURL)
            }
        }

        return Array(NSOrderedSet(array: urls)) as? [URL] ?? urls
    }

    private func fetchImageData(from url: URL) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode),
                data.count > 0
            else {
                return nil
            }

            return data
        } catch {
            return nil
        }
    }
}
