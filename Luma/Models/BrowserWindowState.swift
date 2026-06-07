import Foundation

struct BrowserWindowState: Codable {
    var spaces: [BrowserSpace]
    var tabs: [BrowserTab]
    var activeSpaceID: UUID
    var activeTabID: UUID?
    var splitTabID: UUID?
    var isSplitViewEnabled: Bool

    init(
        spaces: [BrowserSpace],
        tabs: [BrowserTab],
        activeSpaceID: UUID,
        activeTabID: UUID?,
        splitTabID: UUID? = nil,
        isSplitViewEnabled: Bool = false
    ) {
        self.spaces = spaces
        self.tabs = tabs
        self.activeSpaceID = activeSpaceID
        self.activeTabID = activeTabID
        self.splitTabID = splitTabID
        self.isSplitViewEnabled = isSplitViewEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case spaces
        case tabs
        case activeSpaceID
        case activeTabID
        case splitTabID
        case isSplitViewEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spaces = try container.decodeIfPresent([BrowserSpace].self, forKey: .spaces) ?? []
        tabs = try container.decodeIfPresent([BrowserTab].self, forKey: .tabs) ?? []
        activeSpaceID = try container.decodeIfPresent(UUID.self, forKey: .activeSpaceID) ?? spaces.first?.id ?? UUID()
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        splitTabID = try container.decodeIfPresent(UUID.self, forKey: .splitTabID)
        isSplitViewEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSplitViewEnabled) ?? false
    }
}
