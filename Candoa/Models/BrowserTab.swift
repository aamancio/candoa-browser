import Foundation

struct BrowserTab: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var url: URL?
    var faviconSymbol: String
    var faviconData: Data?
    var isLoading: Bool
    var loadingProgress: Double
    var isFavorite: Bool
    var isPinned: Bool
    var folderID: UUID?
    var spaceID: UUID
    var sortOrder: Double
    var lastAccessedAt: Date

    init(
        id: UUID = UUID(),
        title: String = BrowserDefaults.newTabTitle,
        url: URL? = nil,
        faviconSymbol: String = "globe",
        faviconData: Data? = nil,
        isLoading: Bool = false,
        loadingProgress: Double = 0,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        folderID: UUID? = nil,
        spaceID: UUID,
        sortOrder: Double = 0,
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.faviconSymbol = faviconSymbol
        self.faviconData = faviconData
        self.isLoading = isLoading
        self.loadingProgress = loadingProgress
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.folderID = folderID
        self.spaceID = spaceID
        self.sortOrder = sortOrder
        self.lastAccessedAt = lastAccessedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case faviconSymbol
        case faviconData
        case isLoading
        case loadingProgress
        case isFavorite
        case isPinned
        case folderID
        case spaceID
        case sortOrder
        case lastAccessedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? BrowserDefaults.newTabTitle
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        faviconSymbol = try container.decodeIfPresent(String.self, forKey: .faviconSymbol) ?? "globe"
        faviconData = try container.decodeIfPresent(Data.self, forKey: .faviconData)
        isLoading = false
        loadingProgress = try container.decodeIfPresent(Double.self, forKey: .loadingProgress) ?? 0
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        spaceID = try container.decode(UUID.self, forKey: .spaceID)
        sortOrder = try container.decodeIfPresent(Double.self, forKey: .sortOrder) ?? 0
        lastAccessedAt = try container.decodeIfPresent(Date.self, forKey: .lastAccessedAt) ?? Date()
    }
}
