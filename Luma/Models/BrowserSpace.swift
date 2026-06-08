import Foundation

struct BrowserSpace: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var symbolName: String
    var themeColorHex: String
    var dataStoreID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "sparkle",
        themeColorHex: String = "#6E8BFF",
        dataStoreID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.themeColorHex = themeColorHex
        self.dataStoreID = dataStoreID ?? id
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case symbolName
        case themeColorHex
        case dataStoreID
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Space"
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "sparkle"
        themeColorHex = try container.decodeIfPresent(String.self, forKey: .themeColorHex) ?? "#6E8BFF"
        dataStoreID = try container.decodeIfPresent(UUID.self, forKey: .dataStoreID) ?? id
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}
