import Foundation

struct BrowserFolder: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var spaceID: UUID
    var sortOrder: Double
    var isExpanded: Bool

    init(
        id: UUID = UUID(),
        name: String = "New Folder",
        spaceID: UUID,
        sortOrder: Double = 0,
        isExpanded: Bool = true
    ) {
        self.id = id
        self.name = name
        self.spaceID = spaceID
        self.sortOrder = sortOrder
        self.isExpanded = isExpanded
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case spaceID
        case sortOrder
        case isExpanded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Folder"
        spaceID = try container.decode(UUID.self, forKey: .spaceID)
        sortOrder = try container.decodeIfPresent(Double.self, forKey: .sortOrder) ?? 0
        isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
    }
}

struct BrowserWindowState: Codable, Equatable {
    var spaces: [BrowserSpace]
    var folders: [BrowserFolder]
    var tabs: [BrowserTab]
    var activeSpaceID: UUID
    var activeTabID: UUID?
    var splitTabID: UUID?
    var isSplitViewEnabled: Bool

    init(
        spaces: [BrowserSpace],
        folders: [BrowserFolder] = [],
        tabs: [BrowserTab],
        activeSpaceID: UUID,
        activeTabID: UUID?,
        splitTabID: UUID? = nil,
        isSplitViewEnabled: Bool = false
    ) {
        self.spaces = spaces
        self.folders = folders
        self.tabs = tabs
        self.activeSpaceID = activeSpaceID
        self.activeTabID = activeTabID
        self.splitTabID = splitTabID
        self.isSplitViewEnabled = isSplitViewEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case spaces
        case folders
        case tabs
        case activeSpaceID
        case activeTabID
        case splitTabID
        case isSplitViewEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spaces = try container.decodeIfPresent([BrowserSpace].self, forKey: .spaces) ?? []
        folders = try container.decodeIfPresent([BrowserFolder].self, forKey: .folders) ?? []
        tabs = try container.decodeIfPresent([BrowserTab].self, forKey: .tabs) ?? []
        activeSpaceID = try container.decodeIfPresent(UUID.self, forKey: .activeSpaceID) ?? spaces.first?.id ?? UUID()
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        splitTabID = try container.decodeIfPresent(UUID.self, forKey: .splitTabID)
        isSplitViewEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSplitViewEnabled) ?? false
    }
}
