import AppKit
import Combine
import Foundation
import SwiftUI

struct TabMediaState: Equatable {
    var hasMedia = false
    var isPlaying = false
    var isMuted = false
    var isMiniPlayerEligible = false
    var currentTime: Double = 0
    var duration: Double = 0
}

@MainActor
final class BrowserStore: ObservableObject {
    private struct ClosedTabSnapshot {
        let url: URL
        let isPinned: Bool
        let spaceID: UUID
    }

    static let spaceNameCharacterLimit = 24

    @Published private(set) var spaces: [BrowserSpace]
    @Published private(set) var tabs: [BrowserTab]
    @Published var activeSpaceID: UUID
    @Published var activeTabID: UUID? {
        didSet {
            guard oldValue != activeTabID else { return }
            handleActiveTabChange(from: oldValue)
        }
    }
    @Published var splitTabID: UUID?
    @Published var isSplitViewEnabled = false
    @Published var isCommandPalettePresented = false
    @Published var commandPaletteInitialText = ""
    @Published var commandPaletteResumeQuery = ""
    @Published var commandPaletteSessionID = UUID()
    @Published private(set) var commandPaletteOpensNewTab = false
    @Published var isCreateSpacePresented = false
    @Published var editingSpaceID: UUID?
    @Published private(set) var isInitialSpaceSetupPresented = false
    @Published private(set) var spaceThemeAppearancePreview: SpaceThemeAppearance?
    @Published private(set) var isSpaceThemeColorPreviewActive = false
    @Published private(set) var spaceThemeColorHexPreview: String?
    @Published private(set) var spaceThemeAuxiliaryHexPreviews: [String] = []
    @Published private(set) var spaceThemeOpacityPreview: Double?
    @Published private(set) var spaceThemeTexturePreview: Double?
    @Published var addressFocusRequestID = UUID()
    @Published private(set) var isTabSwitcherPresented = false
    @Published private(set) var tabSwitcherTabs: [BrowserTab] = []
    @Published private(set) var tabSwitcherSelectedTabID: UUID?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published var draggedTabID: UUID?
    @Published var isFindBarPresented = false
    @Published var findQuery = ""
    @Published private(set) var mediaStates: [UUID: TabMediaState] = [:]
    @Published private(set) var mediaControllerTabID: UUID?
    @Published var isMiniPlayerMinimized = false
    @Published private(set) var dismissedMiniPlayerTabID: UUID?
    @Published private(set) var retainedPausedMiniPlayerTabID: UUID?
    @Published private(set) var iCloudWorkspaceSyncEnabled =
        LumaCloudKitEntitlements.hasConfiguredContainer && LumaSyncPreferences.syncsWorkspaceWithICloud
    @Published private(set) var iCloudHistorySyncEnabled =
        LumaCloudKitEntitlements.hasConfiguredContainer && LumaSyncPreferences.syncsHistoryWithICloud
    @Published var syncRestartMessage: String?
    @Published private(set) var copiedURLToast: CopiedURLToast?

    private var recentlyClosedTabs: [ClosedTabSnapshot] = []
    private static let recentlyClosedTabLimit = 50

    let navigationService: NavigationService
    let webCoordinator: WebViewCoordinator

    private let persistenceService: PersistenceService
    private let faviconService: FaviconService
    private var saveCancellable: AnyCancellable?
    private var remoteChangeCancellable: AnyCancellable?
    private var tabSwitcherHideWorkItem: DispatchWorkItem?
    private var tabSwitcherShowWorkItem: DispatchWorkItem?
    private var copiedURLToastHideWorkItem: DispatchWorkItem?
    private var isCopiedURLToastSharing = false
    private var tabSwitcherCandidates: [BrowserTab] = []
    private var isApplyingRemoteState = false
    private let spaceSymbols = [
        "circle.grid.2x2",
        "sparkle",
        "briefcase",
        "house",
        "paintpalette",
        "graduationcap",
        "bolt",
        "leaf"
    ]
    private let spaceThemeColors = [
        "#6E8BFF",
        "#74E0AA",
        "#E0A84F",
        "#DA6A72",
        "#9B7BE5",
        "#5CA8D8",
        "#D17FB3",
        "#8E9A5B"
    ]

    var activeSpace: BrowserSpace? {
        spaces.first { $0.id == activeSpaceID }
    }

    var activeThemeColorHexes: [String] {
        if isSpaceThemeColorPreviewActive {
            guard let spaceThemeColorHexPreview else { return [] }
            return [spaceThemeColorHexPreview] + spaceThemeAuxiliaryHexPreviews
        }

        guard !isSpaceSetupPresented else { return [] }
        return activeSpace?.themeColorHex.map { [$0] } ?? []
    }

    var activeThemeOpacity: Double {
        if let spaceThemeOpacityPreview {
            return spaceThemeOpacityPreview
        }

        guard !isSpaceSetupPresented else { return 0.5 }
        return activeSpace?.themeOpacity ?? 0.5
    }

    var activeThemeTexture: Double {
        if let spaceThemeTexturePreview {
            return spaceThemeTexturePreview
        }

        guard !isSpaceSetupPresented else { return 0 }
        return activeSpace?.themeTexture ?? 0
    }

    var activeThemeIntensityMultiplier: Double {
        let normalizedOpacity = (activeThemeOpacity - 0.3) / 0.6
        return min(1.45, max(0.25, 0.25 + normalizedOpacity * 1.2))
    }

    var isSpaceSetupPresented: Bool {
        isCreateSpacePresented || isInitialSpaceSetupPresented || editingSpaceID != nil
    }

    var editingSpace: BrowserSpace? {
        guard let editingSpaceID else { return nil }
        return spaces.first { $0.id == editingSpaceID }
    }

    var activeTab: BrowserTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    var activeSplitTab: BrowserTab? {
        guard isSplitViewEnabled, let splitTabID else { return nil }
        return tabs.first { $0.id == splitTabID && $0.spaceID == activeSpaceID }
    }

    var visibleTabsForActiveSpace: [BrowserTab] {
        pinnedTabsForActiveSpace + regularTabsForActiveSpace
    }

    var pinnedTabsForActiveSpace: [BrowserTab] {
        tabs
            .filter { $0.spaceID == activeSpaceID && $0.isPinned }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var regularTabsForActiveSpace: [BrowserTab] {
        tabs
            .filter { $0.spaceID == activeSpaceID && !$0.isPinned }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    init(
        persistenceService: PersistenceService = .shared,
        navigationService: NavigationService = .shared,
        faviconService: FaviconService = .shared,
        webCoordinator: WebViewCoordinator = WebViewCoordinator(),
        restoresWebViews: Bool = true
    ) {
        self.persistenceService = persistenceService
        self.navigationService = navigationService
        self.faviconService = faviconService
        self.webCoordinator = webCoordinator

        let restoredState = persistenceService.loadState()
        var shouldPresentInitialSpaceSetup = false

        if let restoredState, !restoredState.spaces.isEmpty {
            spaces = restoredState.spaces
            tabs = restoredState.tabs
            activeSpaceID = restoredState.spaces.contains(where: { $0.id == restoredState.activeSpaceID })
                ? restoredState.activeSpaceID
                : restoredState.spaces[0].id
            activeTabID = restoredState.tabs.contains(where: { $0.id == restoredState.activeTabID })
                ? restoredState.activeTabID
                : restoredState.tabs.first(where: { $0.spaceID == activeSpaceID })?.id
            splitTabID = restoredState.tabs.contains(where: { $0.id == restoredState.splitTabID })
                ? restoredState.splitTabID
                : nil
            isSplitViewEnabled = restoredState.isSplitViewEnabled && splitTabID != nil && splitTabID != activeTabID
        } else {
            let defaultSpace = BrowserSpace(name: "", symbolName: "circle.grid.2x2")
            spaces = [defaultSpace]
            tabs = []
            activeSpaceID = defaultSpace.id
            activeTabID = nil
            splitTabID = nil
            isSplitViewEnabled = false
            shouldPresentInitialSpaceSetup = restoredState?.spaces.isEmpty ?? true
        }

        self.webCoordinator.attach(store: self)
        clearLegacyDefaultSpaceName()
        repairSessionState()
        shouldPresentInitialSpaceSetup = shouldPresentInitialSpaceSetup || needsInitialSpaceSetup()
        isInitialSpaceSetupPresented = shouldPresentInitialSpaceSetup
        if restoresWebViews {
            restoreVisibleWebViews()
        }
        updateNavigationState()
        configureAutosave()
        configureRemoteSyncObservation()
    }

    func focusAddressBar() {
        guard !isInitialSpaceSetupPresented else { return }

        let activeURL = activeTab?.url
        commandPaletteInitialText = activeURL?.absoluteString ?? ""
        commandPaletteResumeQuery = activeURL.flatMap(navigationService.searchQuery(from:)) ?? ""
        commandPaletteSessionID = UUID()
        commandPaletteOpensNewTab = false
        presentCommandPalette()
        addressFocusRequestID = UUID()
    }

    func openCommandPalette() {
        guard !isInitialSpaceSetupPresented else { return }

        commandPaletteInitialText = ""
        commandPaletteResumeQuery = ""
        commandPaletteSessionID = UUID()
        commandPaletteOpensNewTab = false
        presentCommandPalette()
    }

    func openNewTabCommandPalette() {
        guard !isInitialSpaceSetupPresented else { return }

        commandPaletteInitialText = ""
        commandPaletteResumeQuery = ""
        commandPaletteSessionID = UUID()
        commandPaletteOpensNewTab = true
        presentCommandPalette()
    }

    /// Presentation animates; dismissal deliberately does not. An animated
    /// removal keeps the palette in the hierarchy for the transition's
    /// duration, and a committed command's web view swap landing in that
    /// window interrupts the transition — stranding an invisible palette
    /// that swallows every mouse click until ⌘T is pressed again.
    private func presentCommandPalette() {
        withAnimation(.easeOut(duration: 0.14)) {
            isCommandPalettePresented = true
        }
    }

    func dismissCommandPalette() {
        isCommandPalettePresented = false
        commandPaletteOpensNewTab = false

        // The palette's TextField unmounts while the window's field editor is
        // still bound to it. Without an explicit hand-back the orphaned field
        // editor stays first responder and the window drops mouse events.
        if let window = NSApp.keyWindow {
            window.endEditing(for: nil)
            window.makeFirstResponder(nil)
        }
    }

    /// Arc-style ⌘T: no tab exists yet — the sidebar's New Tab button takes
    /// the selection highlight while the palette is open, and the real tab is
    /// only created when a result is picked.
    var isNewTabPaletteActive: Bool {
        isCommandPalettePresented && commandPaletteOpensNewTab
    }

    func consumeCommandPaletteNewTabIntent() -> Bool {
        let opensNewTab = commandPaletteOpensNewTab
        commandPaletteOpensNewTab = false
        return opensNewTab
    }

    func beginSpaceCreation() {
        guard !isInitialSpaceSetupPresented else { return }
        dismissCommandPalette()
        editingSpaceID = nil
        isCreateSpacePresented = true
    }

    func beginSpaceEditing(_ id: UUID) {
        guard !isInitialSpaceSetupPresented, spaces.contains(where: { $0.id == id }) else { return }
        dismissCommandPalette()
        isCreateSpacePresented = false
        switchSpace(to: id)
        editingSpaceID = id
    }

    @discardableResult
    func dataStoreID(for spaceID: UUID) -> UUID {
        spaces.first(where: { $0.id == spaceID })?.dataStoreID ?? spaceID
    }

    static func limitedSpaceNameInput(_ name: String) -> String {
        String(name.prefix(spaceNameCharacterLimit))
    }

    static func normalizedSpaceName(_ name: String) -> String {
        limitedSpaceNameInput(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @discardableResult
    func createSpace(
        name: String? = nil,
        symbolName: String? = nil,
        themeColorHex: String? = nil,
        themeAppearance: SpaceThemeAppearance = .automatic,
        themeOpacity: Double = 0.5,
        themeTexture: Double = 0,
        dataStoreID: UUID? = nil
    ) -> BrowserSpace {
        let spaceNumber = spaces.count + 1
        let paletteIndex = spaces.count % spaceSymbols.count
        let resolvedName = name
            .map(Self.normalizedSpaceName)
            .flatMap { $0.isEmpty ? nil : $0 }

        let space = BrowserSpace(
            name: resolvedName ?? "Space \(spaceNumber)",
            symbolName: symbolName ?? spaceSymbols[paletteIndex],
            themeColorHex: themeColorHex,
            themeAppearance: themeAppearance,
            themeOpacity: themeOpacity,
            themeTexture: themeTexture,
            dataStoreID: dataStoreID ?? UUID()
        )
        spaces.append(space)
        switchSpace(to: space.id)
        flushSession()
        return space
    }

    func completeInitialSpaceSetup(
        name: String,
        symbolName: String,
        themeColorHex: String?,
        themeAppearance: SpaceThemeAppearance = .automatic,
        themeOpacity: Double = 0.5,
        themeTexture: Double = 0,
        dataStoreID: UUID? = nil
    ) {
        let normalizedName = Self.normalizedSpaceName(name)
        guard !normalizedName.isEmpty else { return }

        if spaces.isEmpty {
            let defaultSpace = BrowserSpace(
                name: normalizedName,
                symbolName: symbolName,
                themeColorHex: themeColorHex,
                themeAppearance: themeAppearance,
                themeOpacity: themeOpacity,
                themeTexture: themeTexture,
                dataStoreID: dataStoreID
            )
            spaces = [defaultSpace]
            activeSpaceID = defaultSpace.id
        }

        let targetSpaceID = spaces.contains(where: { $0.id == activeSpaceID })
            ? activeSpaceID
            : spaces[0].id

        guard let index = spaces.firstIndex(where: { $0.id == targetSpaceID }) else { return }
        let previousDataStoreID = spaces[index].dataStoreID

        spaces[index].name = normalizedName
        spaces[index].symbolName = symbolName
        spaces[index].themeColorHex = themeColorHex
        spaces[index].themeAppearance = themeAppearance
        spaces[index].themeOpacity = min(0.9, max(0.3, themeOpacity))
        spaces[index].themeTexture = min(1, max(0, themeTexture))
        if let dataStoreID {
            spaces[index].dataStoreID = dataStoreID
        }

        activeSpaceID = spaces[index].id
        isInitialSpaceSetupPresented = false
        isCreateSpacePresented = false
        recreateWebViewsIfNeeded(
            in: spaces[index].id,
            previousDataStoreID: previousDataStoreID,
            nextDataStoreID: spaces[index].dataStoreID
        )
        repairSessionState()
        updateNavigationState()
        flushSession()
    }

    func renameSpace(_ id: UUID, to name: String) {
        let normalizedName = Self.normalizedSpaceName(name)
        guard !normalizedName.isEmpty, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = normalizedName
        flushSession()
    }

    func updateSpace(
        _ id: UUID,
        name: String,
        symbolName: String,
        themeColorHex: String?,
        themeAppearance: SpaceThemeAppearance,
        themeOpacity: Double,
        themeTexture: Double
    ) {
        let normalizedName = Self.normalizedSpaceName(name)
        guard !normalizedName.isEmpty, let index = spaces.firstIndex(where: { $0.id == id }) else { return }

        spaces[index].name = normalizedName
        spaces[index].symbolName = symbolName
        spaces[index].themeColorHex = themeColorHex
        spaces[index].themeAppearance = themeAppearance
        spaces[index].themeOpacity = min(0.9, max(0.3, themeOpacity))
        spaces[index].themeTexture = min(1, max(0, themeTexture))

        editingSpaceID = nil
        updateNavigationState()
        flushSession()
    }

    func updateSpaceTheme(_ id: UUID, colorHex: String?) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].themeColorHex = colorHex
        flushSession()
    }

    func updateSpaceThemeControls(_ id: UUID, opacity: Double, texture: Double) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].themeOpacity = min(0.9, max(0.3, opacity))
        spaces[index].themeTexture = min(1, max(0, texture))
        flushSession()
    }

    func updateSpaceThemeAppearance(_ id: UUID, appearance: SpaceThemeAppearance) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].themeAppearance = appearance
        flushSession()
    }

    func previewSpaceThemeAppearance(_ appearance: SpaceThemeAppearance) {
        guard spaceThemeAppearancePreview != appearance else { return }
        spaceThemeAppearancePreview = appearance
    }

    func previewSpaceThemeColors(primaryHex: String?, auxiliaryHexes: [String] = []) {
        let normalizedAuxiliaryHexes = primaryHex == nil ? [] : auxiliaryHexes
        guard
            !isSpaceThemeColorPreviewActive ||
            spaceThemeColorHexPreview != primaryHex ||
            spaceThemeAuxiliaryHexPreviews != normalizedAuxiliaryHexes
        else { return }

        if !isSpaceThemeColorPreviewActive {
            isSpaceThemeColorPreviewActive = true
        }
        if spaceThemeColorHexPreview != primaryHex {
            spaceThemeColorHexPreview = primaryHex
        }
        if spaceThemeAuxiliaryHexPreviews != normalizedAuxiliaryHexes {
            spaceThemeAuxiliaryHexPreviews = normalizedAuxiliaryHexes
        }
    }

    func previewSpaceThemeControls(opacity: Double, texture: Double) {
        let clampedOpacity = min(0.9, max(0.3, opacity))
        let clampedTexture = min(1, max(0, texture))
        if spaceThemeOpacityPreview != clampedOpacity {
            spaceThemeOpacityPreview = clampedOpacity
        }
        if spaceThemeTexturePreview != clampedTexture {
            spaceThemeTexturePreview = clampedTexture
        }
    }

    func clearSpaceThemePreview() {
        spaceThemeAppearancePreview = nil
        isSpaceThemeColorPreviewActive = false
        spaceThemeColorHexPreview = nil
        spaceThemeAuxiliaryHexPreviews = []
        spaceThemeOpacityPreview = nil
        spaceThemeTexturePreview = nil
    }

    func clearSpaceThemeAppearancePreview() {
        clearSpaceThemePreview()
    }

    func cycleSpaceIcon(_ id: UUID) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let currentSymbolIndex = spaceSymbols.firstIndex(of: spaces[index].symbolName) ?? -1
        let nextSymbolIndex = (currentSymbolIndex + 1 + spaceSymbols.count) % spaceSymbols.count
        spaces[index].symbolName = spaceSymbols[nextSymbolIndex]
        flushSession()
    }

    func deleteSpace(_ id: UUID) {
        guard spaces.count > 1, let deletedSpaceIndex = spaces.firstIndex(where: { $0.id == id }) else { return }

        if editingSpaceID == id {
            editingSpaceID = nil
        }

        let removedTabIDs = tabs.filter { $0.spaceID == id }.map(\.id)
        tabs.removeAll { $0.spaceID == id }
        removedTabIDs.forEach { webCoordinator.removeWebView(for: $0) }

        spaces.remove(at: deletedSpaceIndex)

        if activeSpaceID == id {
            let replacementIndex = min(deletedSpaceIndex, spaces.count - 1)
            activeSpaceID = spaces[replacementIndex].id
            activeTabID = visibleTabsForActiveSpace.first?.id
        } else if removedTabIDs.contains(where: { $0 == activeTabID }) {
            activeTabID = visibleTabsForActiveSpace.first?.id
        }

        if let splitTabID, removedTabIDs.contains(splitTabID) {
            self.splitTabID = nil
            isSplitViewEnabled = false
        }

        repairSessionState()
        updateNavigationState()
        flushSession()
    }

    func moveSpace(_ id: UUID, by offset: Int) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + offset
        guard spaces.indices.contains(targetIndex) else { return }
        spaces.swapAt(index, targetIndex)
        flushSession()
    }

    func unloadSpace(_ id: UUID) {
        webCoordinator.unloadTabs(inSpaces: [id])
    }

    func unloadAllOtherSpaces(except id: UUID) {
        webCoordinator.unloadTabs(inSpaces: Set(spaces.map(\.id)).subtracting([id]))
    }

    func moveTab(_ tabID: UUID, toSpace targetSpaceID: UUID) {
        guard
            spaces.contains(where: { $0.id == targetSpaceID }),
            let tabIndex = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return
        }

        let sourceSpaceID = tabs[tabIndex].spaceID
        guard sourceSpaceID != targetSpaceID else { return }

        let sourceDataStoreID = dataStoreID(for: sourceSpaceID)
        let targetDataStoreID = dataStoreID(for: targetSpaceID)
        tabs[tabIndex].spaceID = targetSpaceID
        tabs[tabIndex].sortOrder = nextSortOrder(spaceID: targetSpaceID, pinned: tabs[tabIndex].isPinned)

        if sourceDataStoreID != targetDataStoreID {
            webCoordinator.removeWebView(for: tabID)
        }

        if activeTabID == tabID {
            switchTab(to: tabID)
            if let movedTab = tabs.first(where: { $0.id == tabID }) {
                webCoordinator.ensureLoaded(movedTab)
            }
        } else if splitTabID == tabID {
            splitTabID = nil
            isSplitViewEnabled = false
            updateNavigationState()
        }

        normalizeSortOrder()
        flushSession()
    }

    @discardableResult
    func newTab(url: URL? = nil, pinned: Bool = false, in spaceID: UUID? = nil) -> BrowserTab {
        let targetSpaceID = spaceID ?? activeSpaceID
        let tab = BrowserTab(
            title: title(for: url),
            url: url,
            faviconSymbol: faviconService.placeholderSymbol(for: url),
            isPinned: pinned,
            spaceID: targetSpaceID,
            sortOrder: nextSortOrder(spaceID: targetSpaceID, pinned: pinned)
        )

        tabs.insert(tab, at: 0)
        switchTab(to: tab.id)

        if let url {
            webCoordinator.load(url, in: tab.id)
        }

        return tab
    }

    func closeCurrentTab() {
        guard let activeTabID else { return }
        closeTab(activeTabID)
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closingTab = tabs[index]
        rememberClosedTab(closingTab)
        tabs.remove(at: index)
        webCoordinator.removeWebView(for: id)
        mediaStates[id] = nil
        if mediaControllerTabID == id {
            mediaControllerTabID = nil
        }

        if splitTabID == id {
            splitTabID = replacementSplitTab(excluding: id)?.id
            isSplitViewEnabled = splitTabID != nil
        }

        if activeTabID == id {
            let nextTab = tabs
                .filter { $0.spaceID == activeSpaceID }
                .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
                .first
            activeTabID = nextTab?.id
            updateNavigationState()
        }
    }

    func duplicateCurrentTab() {
        guard let tab = activeTab else { return }
        _ = newTab(url: tab.url, pinned: tab.isPinned, in: tab.spaceID)
    }

    func duplicateTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        _ = newTab(url: tab.url, pinned: tab.isPinned, in: tab.spaceID)
    }

    @discardableResult
    func createPopupTab(url: URL?, in spaceID: UUID) -> BrowserTab {
        let tab = BrowserTab(
            title: title(for: url),
            url: url,
            faviconSymbol: faviconService.placeholderSymbol(for: url),
            spaceID: spaceID,
            sortOrder: nextSortOrder(spaceID: spaceID, pinned: false)
        )

        tabs.insert(tab, at: 0)
        switchTab(to: tab.id)
        return tab
    }

    func reopenLastClosedTab() {
        guard let snapshot = recentlyClosedTabs.popLast() else { return }
        let targetSpaceID = spaces.contains(where: { $0.id == snapshot.spaceID })
            ? snapshot.spaceID
            : activeSpaceID
        _ = newTab(url: snapshot.url, pinned: snapshot.isPinned, in: targetSpaceID)
    }

    func clearUnpinnedTabs() {
        regularTabsForActiveSpace.map(\.id).forEach(closeTab)
    }

    func togglePinForActiveTab() {
        guard let activeTabID else { return }
        togglePin(activeTabID)
    }

    func togglePin(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let pinned = !tabs[index].isPinned
        tabs[index].isPinned = pinned
        tabs[index].sortOrder = nextSortOrder(spaceID: tabs[index].spaceID, pinned: pinned)
        normalizeSortOrder()
    }

    func switchToTab(at position: Int) {
        let visibleTabs = visibleTabsForActiveSpace
        guard position >= 1, position <= visibleTabs.count else { return }
        switchTab(to: visibleTabs[position - 1].id)
    }

    func switchToSpace(at position: Int) {
        guard position >= 1, position <= spaces.count else { return }
        switchSpace(to: spaces[position - 1].id)
    }

    func copyActiveTabURL(asMarkdown: Bool = false) {
        guard let tab = activeTab, let url = tab.url else { return }
        let value = asMarkdown ? "[\(tab.title)](\(url.absoluteString))" : url.absoluteString
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        presentCopiedURLToast(
            title: asMarkdown ? "Copied URL as Markdown" : "Copied current URL",
            url: url
        )
    }

    private func presentCopiedURLToast(title: String, url: URL) {
        isCopiedURLToastSharing = false
        copiedURLToast = CopiedURLToast(id: UUID(), title: title, url: url)
        scheduleCopiedURLToastDismissal()
    }

    /// Zen keeps the toast alive while hovered and restarts the dismissal
    /// timer on mouse-out.
    func setCopiedURLToastHovered(_ hovered: Bool) {
        guard copiedURLToast != nil, !isCopiedURLToastSharing else { return }
        if hovered {
            copiedURLToastHideWorkItem?.cancel()
            copiedURLToastHideWorkItem = nil
        } else {
            scheduleCopiedURLToastDismissal()
        }
    }

    /// While the share picker spawned from the toast is open, the toast must
    /// not auto-dismiss (tearing down its anchor would close the picker).
    func setCopiedURLToastSharing(_ sharing: Bool) {
        guard copiedURLToast != nil else {
            isCopiedURLToastSharing = false
            return
        }
        isCopiedURLToastSharing = sharing
        if sharing {
            copiedURLToastHideWorkItem?.cancel()
            copiedURLToastHideWorkItem = nil
        } else {
            scheduleCopiedURLToastDismissal()
        }
    }

    private func scheduleCopiedURLToastDismissal() {
        copiedURLToastHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.copiedURLToast = nil
                self.copiedURLToastHideWorkItem = nil
            }
        }
        copiedURLToastHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    func showFindBar() {
        guard activeTab != nil else { return }
        isFindBarPresented = true
    }

    func dismissFindBar() {
        guard isFindBarPresented else { return }
        isFindBarPresented = false
        if let activeTabID {
            webCoordinator.clearFindSelection(in: activeTabID)
        }
    }

    func findNext() {
        performFind(forward: true)
    }

    func findPrevious() {
        performFind(forward: false)
    }

    func zoomInActiveTab() {
        guard let activeTabID else { return }
        webCoordinator.zoomIn(tabID: activeTabID)
    }

    func zoomOutActiveTab() {
        guard let activeTabID else { return }
        webCoordinator.zoomOut(tabID: activeTabID)
    }

    func resetZoomForActiveTab() {
        guard let activeTabID else { return }
        webCoordinator.resetZoom(tabID: activeTabID)
    }

    private func performFind(forward: Bool) {
        guard let activeTabID, !findQuery.isEmpty else { return }
        webCoordinator.find(findQuery, forward: forward, in: activeTabID)
    }

    private func rememberClosedTab(_ tab: BrowserTab) {
        guard let url = tab.url else { return }
        recentlyClosedTabs.append(ClosedTabSnapshot(url: url, isPinned: tab.isPinned, spaceID: tab.spaceID))
        if recentlyClosedTabs.count > Self.recentlyClosedTabLimit {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - Self.recentlyClosedTabLimit)
        }
    }

    func switchTab(to id: UUID) {
        switchTab(to: id, updatesAccessTime: true)
    }

    private func switchTab(to id: UUID, updatesAccessTime: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if updatesAccessTime {
            tabs[index].lastAccessedAt = Date()
        }
        activeSpaceID = tabs[index].spaceID
        activeTabID = id
        if splitTabID == id {
            splitTabID = replacementSplitTab(excluding: id)?.id
        }
        updateNavigationState()
    }

    // MARK: - Media Controller

    var mediaControllerTab: BrowserTab? {
        guard let mediaControllerTabID else { return nil }
        return tabs.first { $0.id == mediaControllerTabID }
    }

    var mediaControllerState: TabMediaState? {
        guard let mediaControllerTabID else { return nil }
        return mediaStates[mediaControllerTabID]
    }

    var backgroundMediaControllerTab: BrowserTab? {
        guard let tab = mediaControllerTab, tab.id != activeTabID else { return nil }
        if isSplitViewEnabled, tab.id == splitTabID { return nil }
        return tab
    }

    var backgroundMediaControllerState: TabMediaState? {
        guard let tabID = backgroundMediaControllerTab?.id else { return nil }
        return mediaStates[tabID]
    }

    var floatingMiniPlayerTab: BrowserTab? {
        guard let tab = backgroundMediaControllerTab, tab.id != dismissedMiniPlayerTabID else { return nil }
        guard
            mediaStates[tab.id]?.isMiniPlayerEligible == true,
            mediaStates[tab.id]?.isPlaying == true || retainedPausedMiniPlayerTabID == tab.id
        else {
            return nil
        }
        return tab
    }

    var floatingMiniPlayerState: TabMediaState? {
        guard let tabID = floatingMiniPlayerTab?.id else { return nil }
        return mediaStates[tabID]
    }

    func updateMediaState(tabID: UUID, state: TabMediaState) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        mediaStates[tabID] = state.hasMedia ? state : nil

        if state.isPlaying, state.isMiniPlayerEligible {
            // The most recently playing tab owns the floating mini player; it
            // keeps it while paused so playback can be resumed from the card.
            if mediaControllerTabID != tabID {
                dismissedMiniPlayerTabID = nil
                isMiniPlayerMinimized = false
            }
            retainedPausedMiniPlayerTabID = nil
            mediaControllerTabID = tabID
        } else if mediaControllerTabID == tabID {
            if state.hasMedia, state.isMiniPlayerEligible, retainedPausedMiniPlayerTabID == tabID {
                return
            }

            mediaControllerTabID = nil
            dismissedMiniPlayerTabID = nil
            isMiniPlayerMinimized = false
            retainedPausedMiniPlayerTabID = nil
            webCoordinator.detachMiniPlayerWebView(for: tabID)
        }
    }

    func toggleMediaPlayback() {
        guard let mediaControllerTabID else { return }
        webCoordinator.toggleMediaPlayback(tabID: mediaControllerTabID)
    }

    func toggleMiniPlayerPlayback() {
        guard let mediaControllerTabID else { return }
        if mediaStates[mediaControllerTabID]?.isPlaying == true {
            retainedPausedMiniPlayerTabID = mediaControllerTabID
        } else {
            retainedPausedMiniPlayerTabID = nil
        }
        webCoordinator.toggleMediaPlayback(tabID: mediaControllerTabID)
    }

    func toggleMediaMute() {
        guard let mediaControllerTabID else { return }
        webCoordinator.toggleMediaMute(tabID: mediaControllerTabID)
    }

    func skipMediaTrack(forward: Bool) {
        guard let mediaControllerTabID else { return }
        webCoordinator.skipMediaTrack(tabID: mediaControllerTabID, forward: forward)
    }

    func seekMedia(by seconds: Double) {
        guard let mediaControllerTabID else { return }
        webCoordinator.seekMedia(tabID: mediaControllerTabID, by: seconds)
    }

    func seekMedia(to time: Double) {
        guard let mediaControllerTabID, time.isFinite else { return }
        webCoordinator.seekMedia(tabID: mediaControllerTabID, to: max(0, time))
    }

    func focusMediaTab() {
        guard let mediaControllerTabID else { return }
        dismissedMiniPlayerTabID = nil
        isMiniPlayerMinimized = false
        retainedPausedMiniPlayerTabID = nil
        switchTab(to: mediaControllerTabID)
    }

    func minimizeMiniPlayer() {
        hideMiniPlayer(pausesPlayback: false)
    }

    func expandMiniPlayer() {
        isMiniPlayerMinimized = false
    }

    func dismissMiniPlayer() {
        hideMiniPlayer(pausesPlayback: true)
    }

    private func hideMiniPlayer(pausesPlayback: Bool) {
        guard let mediaControllerTabID else { return }
        if pausesPlayback {
            webCoordinator.pauseMediaPlayback(tabID: mediaControllerTabID)
        }

        dismissedMiniPlayerTabID = mediaControllerTabID
        isMiniPlayerMinimized = false
        retainedPausedMiniPlayerTabID = nil
        webCoordinator.detachMiniPlayerWebView(for: mediaControllerTabID)
    }

    /// Leaving a media tab refreshes playback state so the in-app mini player
    /// can attach to the background web view immediately.
    private func handleActiveTabChange(from previousID: UUID?) {
        // Returning to a dismissed media tab re-arms the mini player so the
        // next switch away can summon it again.
        if activeTabID == dismissedMiniPlayerTabID {
            dismissedMiniPlayerTabID = nil
        }

        if
            let previousID,
            previousID != splitTabID,
            tabs.contains(where: { $0.id == previousID })
        {
            webCoordinator.refreshMediaState(tabID: previousID)
        }

        if let activeTabID {
            webCoordinator.refreshMediaState(tabID: activeTabID)
        }
    }

    func switchSpace(to id: UUID) {
        guard spaces.contains(where: { $0.id == id }) else { return }
        activeSpaceID = id

        if let existingTab = tabs
            .filter({ $0.spaceID == id })
            .sorted(by: { $0.lastAccessedAt > $1.lastAccessedAt })
            .first {
            activeTabID = existingTab.id
        } else {
            activeTabID = nil
        }

        if let splitTabID, tabs.first(where: { $0.id == splitTabID })?.spaceID != id {
            self.splitTabID = nil
            isSplitViewEnabled = false
        }

        updateNavigationState()
    }

    func switchToNextTab() {
        switchTab(offset: 1)
    }

    func switchToPreviousTab() {
        switchTab(offset: -1)
    }

    func switchToNextRecentTab(keepsPreviewOpen: Bool = false) {
        switchTabInRecentOrder(offset: 1, keepsPreviewOpen: keepsPreviewOpen)
    }

    func switchToPreviousRecentTab(keepsPreviewOpen: Bool = false) {
        switchTabInRecentOrder(offset: -1, keepsPreviewOpen: keepsPreviewOpen)
    }

    func finishTabSwitcherInteraction() {
        // Quick tap: Control was released before the preview appeared, so the
        // switch stays silent — just commit the interaction.
        if tabSwitcherShowWorkItem != nil {
            hideTabSwitcher()
            return
        }

        guard isTabSwitcherPresented else { return }

        tabSwitcherHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.hideTabSwitcher()
            }
        }
        tabSwitcherHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    func switchToNextSpace() {
        switchSpace(offset: 1)
    }

    func switchToPreviousSpace() {
        switchSpace(offset: -1)
    }

    func toggleSplitView() {
        if isSplitViewEnabled {
            isSplitViewEnabled = false
            splitTabID = nil
            return
        }

        openSplitView(with: replacementSplitTab(excluding: activeTabID)?.id)
    }

    func openSplitView(with tabID: UUID?) {
        guard let activeTabID else { return }
        let candidateID = tabID == activeTabID ? replacementSplitTab(excluding: activeTabID)?.id : tabID

        if let candidateID, tabs.contains(where: { $0.id == candidateID && $0.spaceID == activeSpaceID }) {
            splitTabID = candidateID
        } else {
            let tab = newInternalBlankTab(in: activeSpaceID)
            self.activeTabID = activeTabID
            splitTabID = tab.id
        }

        isSplitViewEnabled = splitTabID != nil && splitTabID != activeTabID
        updateNavigationState()
    }

    func closeSplitView() {
        isSplitViewEnabled = false
        splitTabID = nil
    }

    func reorderTabs(_ orderedIDs: [UUID], pinned: Bool) {
        for (offset, id) in orderedIDs.enumerated() {
            guard let index = tabs.firstIndex(where: { $0.id == id }) else { continue }
            tabs[index].isPinned = pinned
            tabs[index].sortOrder = Double(offset)
        }
    }

    func navigateActiveTab(to rawInput: String) {
        guard let url = navigationService.destinationURL(for: rawInput) else { return }
        navigateActiveTab(to: url)
    }

    func navigateActiveTab(to url: URL) {
        // Empty spaces have no active tab; navigating from the address
        // dialog should open one rather than dropping the input.
        guard let tabID = activeTabID else {
            _ = newTab(url: url)
            return
        }
        setURL(url, title: title(for: url), for: tabID)
        webCoordinator.load(url, in: tabID)
    }

    func navigateNewTab(to rawInput: String) {
        guard let url = navigationService.destinationURL(for: rawInput) else { return }
        navigateNewTab(to: url)
    }

    func navigateNewTab(to url: URL) {
        // Already sitting on an empty tab: fill it instead of stacking
        // another "New Tab" in the sidebar.
        if let activeTab, activeTab.url == nil {
            navigateActiveTab(to: url)
            return
        }

        newTab(url: url)
    }

    func goBack() {
        guard let activeTabID else { return }
        webCoordinator.goBack(tabID: activeTabID)
    }

    func goForward() {
        guard let activeTabID else { return }
        webCoordinator.goForward(tabID: activeTabID)
    }

    func reloadActiveTab() {
        guard let activeTabID else { return }
        webCoordinator.reload(tabID: activeTabID)
    }

    func stopLoadingActiveTab() {
        guard let activeTabID else { return }
        webCoordinator.stopLoading(tabID: activeTabID)
        setLoading(false, for: activeTabID)
    }

    func updateTabFromWebView(
        tabID: UUID,
        title: String?,
        url: URL?,
        isLoading: Bool,
        loadingProgress: Double,
        canGoBack: Bool,
        canGoForward: Bool
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        // The internal home page is loaded via loadHTMLString and WebKit
        // reports it as about:blank; keep the tab URL-less instead of
        // surfacing the placeholder in the tab row and address bar.
        let isInternalHomePage = Self.isLegacyBlankPlaceholderURL(url)
        let reportedURL = isInternalHomePage ? nil : url

        if isInternalHomePage {
            tabs[index].title = BrowserDefaults.newTabTitle
        } else if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tabs[index].title = title
        } else if let reportedURL {
            tabs[index].title = self.title(for: reportedURL)
        }

        tabs[index].url = reportedURL
        tabs[index].faviconSymbol = faviconService.placeholderSymbol(for: reportedURL)
        tabs[index].isLoading = isLoading
        tabs[index].loadingProgress = loadingProgress

        if activeTabID == tabID {
            self.canGoBack = canGoBack
            self.canGoForward = canGoForward
        }
    }

    func updateFavicon(tabID: UUID, data: Data?) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }), let data else { return }
        tabs[index].faviconData = data
    }

    func recordHistoryVisit(tabID: UUID, title: String?, url: URL?) {
        guard
            let index = tabs.firstIndex(where: { $0.id == tabID }),
            let url,
            !Self.isLegacyBlankPlaceholderURL(url)
        else {
            return
        }

        tabs[index].lastAccessedAt = Date()
        let tab = tabs[index]

        let resolvedTitle: String
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedTitle = title
        } else {
            resolvedTitle = self.title(for: url)
        }

        persistenceService.recordVisit(
            title: resolvedTitle,
            url: url,
            tabID: tabID,
            spaceID: tab.spaceID
        )
    }

    func recentHistory(matching query: String = "", limit: Int = 8) -> [HistoryVisit] {
        persistenceService.recentHistory(matching: query, in: activeSpaceID, limit: limit)
    }

    func flushSession() {
        saveSnapshot()
    }

    func setWorkspaceICloudSyncEnabled(_ enabled: Bool) {
        guard iCloudWorkspaceSyncEnabled != enabled else { return }

        if enabled, !LumaCloudKitEntitlements.hasConfiguredContainer {
            syncRestartMessage = """
            This build is not signed with the CloudKit entitlement yet. Enable the iCloud capability for iCloud.org.lumabrowser.LumaBrowser in Xcode, then build with your Apple Developer team.
            """
            return
        }

        iCloudWorkspaceSyncEnabled = enabled
        LumaSyncPreferences.syncsWorkspaceWithICloud = enabled

        if !enabled {
            iCloudHistorySyncEnabled = false
        }

        syncRestartMessage = enabled
            ? "Luma will start syncing Spaces and tabs through your private iCloud database after you relaunch the app."
            : "Luma will return to local-only Spaces and tabs after you relaunch the app."
    }

    func setHistoryICloudSyncEnabled(_ enabled: Bool) {
        guard iCloudHistorySyncEnabled != enabled else { return }

        if enabled, !LumaCloudKitEntitlements.hasConfiguredContainer {
            syncRestartMessage = """
            This build is not signed with the CloudKit entitlement yet. Enable the iCloud capability for iCloud.org.lumabrowser.LumaBrowser in Xcode before syncing history.
            """
            return
        }

        if enabled, !iCloudWorkspaceSyncEnabled {
            setWorkspaceICloudSyncEnabled(true)
        }

        iCloudHistorySyncEnabled = enabled
        LumaSyncPreferences.syncsHistoryWithICloud = enabled
        syncRestartMessage = enabled
            ? "Luma will sync browsing history through your private iCloud database after you relaunch the app."
            : "Luma will keep browsing history local-only after you relaunch the app."
    }

    func setLoading(_ isLoading: Bool, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].isLoading = isLoading
        updateNavigationState()
    }

    private func setURL(_ url: URL, title: String, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].url = url
        tabs[index].title = title
        tabs[index].faviconSymbol = faviconService.placeholderSymbol(for: url)
        tabs[index].faviconData = nil
        tabs[index].isLoading = true
        tabs[index].loadingProgress = 0.05
        tabs[index].lastAccessedAt = Date()
    }

    private func title(for url: URL?) -> String {
        guard let url else { return BrowserDefaults.newTabTitle }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    private func updateNavigationState() {
        guard let activeTabID else {
            canGoBack = false
            canGoForward = false
            return
        }

        let state = webCoordinator.navigationState(for: activeTabID)
        canGoBack = state.canGoBack
        canGoForward = state.canGoForward
    }

    private func configureAutosave() {
        let changes = Publishers.MergeMany(
            $spaces.map { _ in () }.eraseToAnyPublisher(),
            $tabs.map { _ in () }.eraseToAnyPublisher(),
            $activeSpaceID.map { _ in () }.eraseToAnyPublisher(),
            $activeTabID.map { _ in () }.eraseToAnyPublisher(),
            $splitTabID.map { _ in () }.eraseToAnyPublisher(),
            $isSplitViewEnabled.map { _ in () }.eraseToAnyPublisher()
        )

        saveCancellable = changes
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveSnapshot()
            }
    }

    private func configureRemoteSyncObservation() {
        guard persistenceService.syncsWorkspaceWithICloud else { return }

        remoteChangeCancellable = NotificationCenter.default
            .publisher(for: PersistenceService.remoteStoreDidChange)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyRemoteStateIfNeeded()
                }
            }
    }

    private func saveSnapshot() {
        guard !isInitialSpaceSetupPresented, !isApplyingRemoteState else { return }

        persistenceService.saveState(currentSnapshot())
    }

    private func currentSnapshot() -> BrowserWindowState {
        BrowserWindowState(
            spaces: spaces,
            tabs: tabs.map { tab in
                var persistedTab = tab
                persistedTab.isLoading = false
                persistedTab.loadingProgress = 0
                return persistedTab
            },
            activeSpaceID: activeSpaceID,
            activeTabID: activeTabID,
            splitTabID: splitTabID,
            isSplitViewEnabled: isSplitViewEnabled
        )
    }

    private func applyRemoteStateIfNeeded() {
        guard
            let remoteState = persistenceService.loadState(),
            !remoteState.spaces.isEmpty,
            remoteState != currentSnapshot()
        else {
            return
        }

        let previousTabs = tabs
        let previousSpaceDataStores = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0.dataStoreID) })
        isApplyingRemoteState = true
        defer { isApplyingRemoteState = false }

        spaces = remoteState.spaces
        tabs = remoteState.tabs
        activeSpaceID = remoteState.activeSpaceID
        activeTabID = remoteState.activeTabID
        splitTabID = remoteState.splitTabID
        isSplitViewEnabled = remoteState.isSplitViewEnabled
        clearLegacyDefaultSpaceName()
        repairSessionState()
        isInitialSpaceSetupPresented = needsInitialSpaceSetup()
        if !isInitialSpaceSetupPresented {
            isCreateSpacePresented = false
        }
        if let editingSpaceID, !spaces.contains(where: { $0.id == editingSpaceID }) {
            self.editingSpaceID = nil
        }

        let tabIDs = Set(tabs.map(\.id))
        for previousTab in previousTabs where !tabIDs.contains(previousTab.id) {
            webCoordinator.removeWebView(for: previousTab.id)
        }

        for tab in tabs {
            guard let previousTab = previousTabs.first(where: { $0.id == tab.id }) else { continue }
            let previousDataStoreID = previousSpaceDataStores[previousTab.spaceID] ?? previousTab.spaceID
            if previousTab.spaceID != tab.spaceID || previousDataStoreID != dataStoreID(for: tab.spaceID) {
                webCoordinator.removeWebView(for: tab.id)
            }
        }

        restoreVisibleWebViews()
        updateNavigationState()
    }

    private func switchTab(offset: Int) {
        let visibleTabs = visibleTabsForActiveSpace
        guard !visibleTabs.isEmpty else { return }
        let currentIndex = visibleTabs.firstIndex(where: { $0.id == activeTabID }) ?? 0
        let nextIndex = (currentIndex + offset + visibleTabs.count) % visibleTabs.count
        switchTab(to: visibleTabs[nextIndex].id)
    }

    private func switchTabInRecentOrder(offset: Int, keepsPreviewOpen: Bool) {
        // Control-Tab starts from most-recent order, so a quick press toggles
        // between the current tab and the previous tab. The list is frozen for
        // the whole interaction so hold-to-cycle doesn't shift underneath the
        // selection. (Candidates are cleared when the interaction ends,
        // including before the preview ever appears.)
        if tabSwitcherCandidates.isEmpty {
            tabSwitcherCandidates = recentTabsForActiveSpace()
        }

        let recentTabs = tabSwitcherCandidates
        guard !recentTabs.isEmpty else { return }
        guard recentTabs.count > 1 else {
            presentTabSwitcher(
                candidates: recentTabs,
                selectedTabID: activeTabID,
                autoHide: !keepsPreviewOpen
            )
            return
        }

        let currentSelectionID = tabSwitcherSelectedTabID ?? activeTabID
        let nextIndex: Int
        if let currentIndex = recentTabs.firstIndex(where: { $0.id == currentSelectionID }) {
            nextIndex = (currentIndex + offset + recentTabs.count) % recentTabs.count
        } else {
            // Active tab sits outside the top tabs: enter the list at the
            // nearest end instead of skipping past it.
            nextIndex = offset > 0 ? 0 : recentTabs.count - 1
        }
        let selectedTabID = recentTabs[nextIndex].id
        switchTab(to: selectedTabID, updatesAccessTime: false)
        presentTabSwitcher(
            candidates: recentTabs,
            selectedTabID: selectedTabID,
            autoHide: !keepsPreviewOpen
        )
    }

    private func presentTabSwitcher(
        candidates: [BrowserTab]? = nil,
        selectedTabID: UUID? = nil,
        autoHide: Bool = true
    ) {
        let selectedTabID = selectedTabID ?? activeTabID
        let previewTabs = tabSwitcherPreviewTabs(
            from: candidates ?? recentTabsForActiveSpace(),
            selectedTabID: selectedTabID
        )
        guard !previewTabs.isEmpty else {
            hideTabSwitcher()
            return
        }

        tabSwitcherHideWorkItem?.cancel()
        tabSwitcherTabs = previewTabs
        tabSwitcherSelectedTabID = selectedTabID ?? previewTabs.first?.id

        if isTabSwitcherPresented || autoHide {
            tabSwitcherShowWorkItem?.cancel()
            tabSwitcherShowWorkItem = nil
            isTabSwitcherPresented = true
        } else if tabSwitcherShowWorkItem == nil {
            // Hold-to-reveal: defer the overlay so a quick Control-Tab stays a
            // silent switch. Repeated presses keep the original deadline.
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.tabSwitcherShowWorkItem = nil
                    self.isTabSwitcherPresented = true
                }
            }
            tabSwitcherShowWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + TabSwitcherConfiguration.holdRevealDelay,
                execute: workItem
            )
        }

        guard autoHide else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.hideTabSwitcher()
            }
        }
        tabSwitcherHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: workItem)
    }

    private func hideTabSwitcher() {
        tabSwitcherHideWorkItem?.cancel()
        tabSwitcherHideWorkItem = nil
        tabSwitcherShowWorkItem?.cancel()
        tabSwitcherShowWorkItem = nil
        isTabSwitcherPresented = false
        tabSwitcherCandidates = []
        tabSwitcherSelectedTabID = nil

        // Commit the access time the cycling deferred, so the landed-on tab
        // becomes most recent for the next interaction.
        if let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[index].lastAccessedAt = Date()
        }
    }

    private func recentTabsForActiveSpace() -> [BrowserTab] {
        tabs
            .filter { $0.spaceID == activeSpaceID }
            .sorted {
                if $0.lastAccessedAt == $1.lastAccessedAt {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.lastAccessedAt > $1.lastAccessedAt
            }
    }

    private func tabSwitcherPreviewTabs(from candidates: [BrowserTab], selectedTabID: UUID?) -> [BrowserTab] {
        var previewTabs = Array(candidates.prefix(TabSwitcherConfiguration.previewLimit))
        guard
            let selectedTabID,
            !previewTabs.contains(where: { $0.id == selectedTabID }),
            let selectedTab = candidates.first(where: { $0.id == selectedTabID })
        else {
            return previewTabs
        }

        if previewTabs.count == TabSwitcherConfiguration.previewLimit {
            previewTabs[previewTabs.count - 1] = selectedTab
        } else {
            previewTabs.append(selectedTab)
        }

        return previewTabs
    }

    private func switchSpace(offset: Int) {
        guard !spaces.isEmpty, let currentIndex = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let nextIndex = (currentIndex + offset + spaces.count) % spaces.count
        switchSpace(to: spaces[nextIndex].id)
    }

    private func nextSortOrder(spaceID: UUID, pinned: Bool) -> Double {
        let orders = tabs
            .filter { $0.spaceID == spaceID && $0.isPinned == pinned }
            .map(\.sortOrder)
        return (orders.min() ?? 0) - 1
    }

    private func replacementSplitTab(excluding excludedID: UUID?) -> BrowserTab? {
        visibleTabsForActiveSpace.first { $0.id != excludedID }
    }

    private func newInternalBlankTab(in spaceID: UUID) -> BrowserTab {
        let tab = BrowserTab(
            spaceID: spaceID,
            sortOrder: nextSortOrder(spaceID: spaceID, pinned: false)
        )

        tabs.insert(tab, at: 0)
        switchTab(to: tab.id)
        return tab
    }

    private func recreateWebViewsIfNeeded(
        in spaceID: UUID,
        previousDataStoreID: UUID,
        nextDataStoreID: UUID
    ) {
        guard previousDataStoreID != nextDataStoreID else { return }

        let affectedTabIDs = tabs
            .filter { $0.spaceID == spaceID }
            .map(\.id)
        affectedTabIDs.forEach { webCoordinator.removeWebView(for: $0) }

        guard activeSpaceID == spaceID else { return }

        if let activeTab {
            webCoordinator.ensureLoaded(activeTab)
        }

        if let activeSplitTab {
            webCoordinator.ensureLoaded(activeSplitTab)
        }
    }

    private func repairSessionState() {
        if spaces.isEmpty {
            spaces = [BrowserSpace(name: "", symbolName: "circle.grid.2x2")]
        }

        for index in spaces.indices where !spaces[index].name.isEmpty {
            spaces[index].name = Self.normalizedSpaceName(spaces[index].name)
        }

        let spaceIDs = Set(spaces.map(\.id))
        tabs = tabs.filter { spaceIDs.contains($0.spaceID) }

        // Placeholder home tabs (about:blank / legacy Google home) are
        // transient; spaces restore empty rather than with a stale blank tab.
        tabs.removeAll(where: Self.isLegacyHomePlaceholder)

        if !spaceIDs.contains(activeSpaceID) {
            activeSpaceID = spaces[0].id
        }

        normalizeSortOrder()

        if activeTabID == nil || !tabs.contains(where: { $0.id == activeTabID && $0.spaceID == activeSpaceID }) {
            activeTabID = visibleTabsForActiveSpace.first?.id
        }

        if splitTabID == activeTabID || !tabs.contains(where: { $0.id == splitTabID && $0.spaceID == activeSpaceID }) {
            splitTabID = nil
            isSplitViewEnabled = false
        }
    }

    private func clearLegacyDefaultSpaceName() {
        // Only the untouched legacy default ("Personal" + original symbol,
        // no theme) goes back through onboarding. A user-created space that
        // happens to be named "Personal" must keep its name.
        guard spaces.count == 1,
              spaces[0].name == "Personal",
              spaces[0].symbolName == "circle.grid.2x2",
              spaces[0].themeColorHex == nil
        else { return }
        spaces[0].name = ""
    }

    private func needsInitialSpaceSetup() -> Bool {
        spaces.count == 1 && spaces[0].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isLegacyBlankPlaceholderURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.absoluteString == "about:blank"
    }

    private static func isLegacyHomePlaceholder(_ tab: BrowserTab) -> Bool {
        if isLegacyBlankPlaceholderURL(tab.url) {
            return true
        }

        return tab.url?.absoluteString == BrowserDefaults.googleHomeURL.absoluteString
            && tab.title == "Google"
            && tab.faviconSymbol == "magnifyingglass"
            && tab.faviconData == nil
    }

    private func normalizeSortOrder() {
        for spaceID in spaces.map(\.id) {
            normalizeSortOrder(spaceID: spaceID, pinned: true)
            normalizeSortOrder(spaceID: spaceID, pinned: false)
        }
    }

    private func normalizeSortOrder(spaceID: UUID, pinned: Bool) {
        let orderedIDs = tabs
            .filter { $0.spaceID == spaceID && $0.isPinned == pinned }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.lastAccessedAt > $1.lastAccessedAt
                }
                return $0.sortOrder < $1.sortOrder
            }
            .map(\.id)

        for (offset, id) in orderedIDs.enumerated() {
            guard let index = tabs.firstIndex(where: { $0.id == id }) else { continue }
            tabs[index].sortOrder = Double(offset)
        }
    }

    private func restoreVisibleWebViews() {
        if let activeTab {
            webCoordinator.ensureLoaded(activeTab)
        }

        if let activeSplitTab {
            webCoordinator.ensureLoaded(activeSplitTab)
        }
    }
}
