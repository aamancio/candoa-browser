import Foundation

struct BrowserSpace: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var symbolName: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "sparkle",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.createdAt = createdAt
    }
}
