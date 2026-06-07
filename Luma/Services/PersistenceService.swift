import Foundation

struct PersistenceService {
    static let shared = PersistenceService()

    private var stateURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("Luma Browser", isDirectory: true)
            .appendingPathComponent("session.json")
    }

    func loadState() -> BrowserWindowState? {
        do {
            let data = try Data(contentsOf: stateURL)
            return try JSONDecoder.luma.decode(BrowserWindowState.self, from: data)
        } catch {
            return nil
        }
    }

    func saveState(_ state: BrowserWindowState) {
        do {
            let folderURL = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let data = try JSONEncoder.luma.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            NSLog("Luma Browser failed to save session: \(error.localizedDescription)")
        }
    }
}

private extension JSONEncoder {
    static var luma: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var luma: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
