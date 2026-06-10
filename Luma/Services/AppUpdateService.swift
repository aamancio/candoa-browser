import AppKit
import Combine
import Foundation

struct AppUpdate: Equatable {
    let version: String
    let downloadURL: URL?
    let releaseNotesURL: URL?
}

@MainActor
final class AppUpdateService: ObservableObject {
    @Published private(set) var availableUpdate: AppUpdate?

    private let manifestURL: URL?
    private let currentVersion: String
    private let session: URLSession
    private var checkTask: Task<Void, Never>?

    init(
        manifestURL: URL? = AppUpdateService.defaultManifestURL,
        currentVersion: String = AppUpdateService.bundleVersion,
        session: URLSession = .shared
    ) {
        self.manifestURL = manifestURL
        self.currentVersion = currentVersion
        self.session = session
    }

    func startCheckingForUpdates() {
        guard checkTask == nil, manifestURL != nil else { return }

        checkTask = Task { [weak self] in
            await self?.checkForUpdates()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: AppUpdateConfiguration.checkIntervalNanoseconds)
                } catch {
                    break
                }

                await self?.checkForUpdates()
            }
        }
    }

    func stopCheckingForUpdates() {
        checkTask?.cancel()
        checkTask = nil
    }

    func openAvailableUpdate() {
        guard let url = availableUpdate?.downloadURL ?? availableUpdate?.releaseNotesURL else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func checkForUpdates() async {
        guard let manifestURL else { return }

        do {
            let request = URLRequest(
                url: manifestURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: AppUpdateConfiguration.requestTimeout
            )
            let (data, response) = try await session.data(for: request)

            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                return
            }

            let manifest = try JSONDecoder().decode(AppUpdateManifest.self, from: data)
            let latestVersion = manifest.version.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !latestVersion.isEmpty, isVersion(latestVersion, newerThan: currentVersion) else {
                availableUpdate = nil
                return
            }

            availableUpdate = AppUpdate(
                version: latestVersion,
                downloadURL: manifest.downloadURL,
                releaseNotesURL: manifest.releaseNotesURL
            )
        } catch {
            // Keep the existing banner state on transient network or manifest errors.
        }
    }

    private func isVersion(_ version: String, newerThan currentVersion: String) -> Bool {
        version.compare(currentVersion, options: [.numeric, .caseInsensitive]) == .orderedDescending
    }

    private static var defaultManifestURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: AppUpdateConfiguration.manifestInfoKey) as? String else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, let url = URL(string: trimmedValue), url.scheme != nil else {
            return nil
        }

        return url
    }

    private static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

private struct AppUpdateManifest: Decodable {
    let version: String
    let downloadURL: URL?
    let releaseNotesURL: URL?

    enum CodingKeys: String, CodingKey {
        case version
        case latestVersion
        case downloadURL
        case url
        case releaseNotesURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decodeIfPresent(String.self, forKey: .version)
            ?? container.decodeIfPresent(String.self, forKey: .latestVersion)
            ?? ""
        downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
            ?? container.decodeIfPresent(URL.self, forKey: .url)
        releaseNotesURL = try container.decodeIfPresent(URL.self, forKey: .releaseNotesURL)
    }
}

private enum AppUpdateConfiguration {
    static let manifestInfoKey = "LumaUpdateManifestURL"
    static let checkIntervalNanoseconds: UInt64 = 6 * 60 * 60 * 1_000_000_000
    static let requestTimeout: TimeInterval = 10
}
