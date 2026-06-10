import CoreGraphics
import Foundation

enum AppConfiguration {
    static let minimumWindowWidth: CGFloat = 980
    static let minimumWindowHeight: CGFloat = 640
    static let windowAutosaveNamePrefix = "Luma.BrowserWindow"
}

enum BrowserCommandTitles {
    static let newTab = "New Tab"
    static let focusAddressBar = "Focus Address Bar"
    static let commandBar = "Command Bar"
    static let toggleSidebar = "Toggle Sidebar"
    static let reloadTab = "Reload Tab"
    static let back = "Back"
    static let forward = "Forward"
    static let closeCurrentTab = "Close Current Tab"
    static let nextTab = "Next Tab"
    static let previousTab = "Previous Tab"
    static let nextSpace = "Next Space"
    static let previousSpace = "Previous Space"
    static let duplicateTab = "Duplicate Tab"
    static let toggleSplitView = "Toggle Split View"
    static let createSpace = "Create Space"
    static let reopenClosedTab = "Reopen Closed Tab"
    static let pinOrUnpinTab = "Pin or Unpin Tab"
    static let clearUnpinnedTabs = "Clear Unpinned Tabs"
    static let copyURL = "Copy URL"
    static let copyURLAsMarkdown = "Copy URL as Markdown"
    static let findInPage = "Find in Page…"
    static let findNext = "Find Next"
    static let findPrevious = "Find Previous"
    static let zoomIn = "Zoom In"
    static let zoomOut = "Zoom Out"
    static let resetZoom = "Reset Zoom"
    static let addSplitView = "Add Split View"
    static let closeSplitView = "Close Split View"
}

enum BrowserDefaults {
    static let newTabTitle = BrowserCommandTitles.newTab
    static let addressPlaceholder = "Search or enter URL"
    static let defaultHomeTitle = "Google"
    static let defaultHomeURL = URL(string: "https://www.google.com/?hl=en&gl=us")!
    static let googleSearchURL = URL(string: "https://www.google.com/search?hl=en&gl=us")!
}

enum SidebarRevealConfiguration {
    static let revealDistanceFromLeftEdge: CGFloat = 64
    static let suppressionResetDistance: CGFloat = 96
    static let hideDistanceFromLeftEdge: CGFloat = 250
    static let pollingInterval: TimeInterval = 0.12
}

enum TabSwitcherConfiguration {
    static let previewLimit = 5
}
