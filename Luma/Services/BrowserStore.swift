import Combine
import Foundation

@MainActor
final class BrowserStore: ObservableObject {
    @Published private(set) var spaces: [BrowserSpace]
    @Published private(set) var tabs: [BrowserTab]
    @Published var activeSpaceID: UUID
    @Published var activeTabID: UUID?
    @Published var splitTabID: UUID?
    @Published var isSplitViewEnabled = false
    @Published var isCommandPalettePresented = false
    @Published var commandPaletteInitialText = ""
    @Published var commandPaletteResumeQuery = ""
    @Published var commandPaletteSessionID = UUID()
    @Published private(set) var commandPaletteOpensNewTab = false
    @Published var isCreateSpacePresented = false
    @Published var addressFocusRequestID = UUID()
    @Published private(set) var isTabSwitcherPresented = false
    @Published private(set) var tabSwitcherTabs: [BrowserTab] = []
    @Published private(set) var tabSwitcherSelectedTabID: UUID?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published var draggedTabID: UUID?

    let navigationService: NavigationService
    let webCoordinator: WebViewCoordinator

    private static let defaultHomeURL = URL(string: "https://www.google.com/?hl=en&gl=us")!
    private static let defaultHomeTitle = "Google"

    private let persistenceService: PersistenceService
    private let faviconService: FaviconService
    private var saveCancellable: AnyCancellable?
    private var tabSwitcherHideWorkItem: DispatchWorkItem?
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
        "#66BFA3",
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
        webCoordinator: WebViewCoordinator = WebViewCoordinator()
    ) {
        self.persistenceService = persistenceService
        self.navigationService = navigationService
        self.faviconService = faviconService
        self.webCoordinator = webCoordinator

        if let restoredState = persistenceService.loadState(), !restoredState.spaces.isEmpty {
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
            let defaultSpace = BrowserSpace(name: "Personal", symbolName: "circle.grid.2x2")
            let defaultTab = Self.homeTab(spaceID: defaultSpace.id)
            spaces = [defaultSpace]
            tabs = [defaultTab]
            activeSpaceID = defaultSpace.id
            activeTabID = defaultTab.id
            splitTabID = nil
            isSplitViewEnabled = false
        }

        self.webCoordinator.attach(store: self)
        repairSessionState()
        restoreVisibleWebViews()
        updateNavigationState()
        configureAutosave()
    }

    func focusAddressBar() {
        let activeURL = activeTab?.url
        commandPaletteInitialText = activeURL?.absoluteString ?? ""
        commandPaletteResumeQuery = activeURL.flatMap(navigationService.searchQuery(from:)) ?? ""
        commandPaletteSessionID = UUID()
        commandPaletteOpensNewTab = false
        isCommandPalettePresented = true
        addressFocusRequestID = UUID()
    }

    func openCommandPalette() {
        commandPaletteInitialText = ""
        commandPaletteResumeQuery = ""
        commandPaletteSessionID = UUID()
        commandPaletteOpensNewTab = false
        isCommandPalettePresented = true
    }

    func openNewTabCommandPalette() {
        commandPaletteInitialText = ""
        commandPaletteResumeQuery = ""
        commandPaletteSessionID = UUID()
        commandPaletteOpensNewTab = true
        isCommandPalettePresented = true
    }

    func dismissCommandPalette() {
        isCommandPalettePresented = false
        commandPaletteOpensNewTab = false
    }

    func consumeCommandPaletteNewTabIntent() -> Bool {
        let opensNewTab = commandPaletteOpensNewTab
        commandPaletteOpensNewTab = false
        return opensNewTab
    }

    func beginSpaceCreation() {
        isCommandPalettePresented = false
        commandPaletteOpensNewTab = false
        isCreateSpacePresented = true
    }

    @discardableResult
    func dataStoreID(for spaceID: UUID) -> UUID {
        spaces.first(where: { $0.id == spaceID })?.dataStoreID ?? spaceID
    }

    @discardableResult
    func createSpace(
        name: String? = nil,
        symbolName: String? = nil,
        themeColorHex: String? = nil,
        dataStoreID: UUID? = nil
    ) -> BrowserSpace {
        let spaceNumber = spaces.count + 1
        let paletteIndex = spaces.count % spaceSymbols.count
        let space = BrowserSpace(
            name: name ?? "Space \(spaceNumber)",
            symbolName: symbolName ?? spaceSymbols[paletteIndex],
            themeColorHex: themeColorHex ?? spaceThemeColors[paletteIndex],
            dataStoreID: dataStoreID ?? UUID()
        )
        spaces.append(space)
        switchSpace(to: space.id)
        _ = newTab()
        return space
    }

    func renameSpace(_ id: UUID, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = trimmedName
    }

    func updateSpaceTheme(_ id: UUID, colorHex: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].themeColorHex = colorHex
    }

    func cycleSpaceIcon(_ id: UUID) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let currentSymbolIndex = spaceSymbols.firstIndex(of: spaces[index].symbolName) ?? -1
        let nextSymbolIndex = (currentSymbolIndex + 1 + spaceSymbols.count) % spaceSymbols.count
        spaces[index].symbolName = spaceSymbols[nextSymbolIndex]
    }

    func deleteSpace(_ id: UUID) {
        guard spaces.count > 1, let deletedSpaceIndex = spaces.firstIndex(where: { $0.id == id }) else { return }

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

        tabs[tabIndex].spaceID = targetSpaceID
        tabs[tabIndex].sortOrder = nextSortOrder(spaceID: targetSpaceID, pinned: tabs[tabIndex].isPinned)

        if !tabs.contains(where: { $0.spaceID == sourceSpaceID }) {
            tabs.append(Self.homeTab(spaceID: sourceSpaceID, sortOrder: 0))
        }

        if activeTabID == tabID {
            switchTab(to: tabID)
        } else if splitTabID == tabID {
            splitTabID = nil
            isSplitViewEnabled = false
            updateNavigationState()
        }

        normalizeSortOrder()
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
        tabs.remove(at: index)
        webCoordinator.removeWebView(for: id)

        if splitTabID == id {
            splitTabID = replacementSplitTab(excluding: id)?.id
            isSplitViewEnabled = splitTabID != nil
        }

        if tabs.filter({ $0.spaceID == closingTab.spaceID }).isEmpty {
            _ = newInternalBlankTab(in: closingTab.spaceID)
            return
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

    func switchTab(to id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].lastAccessedAt = Date()
        activeSpaceID = tabs[index].spaceID
        activeTabID = id
        if splitTabID == id {
            splitTabID = replacementSplitTab(excluding: id)?.id
        }
        updateNavigationState()
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
        guard let tabID = activeTabID, let url = navigationService.destinationURL(for: rawInput) else { return }
        setURL(url, title: title(for: url), for: tabID)
        webCoordinator.load(url, in: tabID)
    }

    func navigateActiveTab(to url: URL) {
        guard let tabID = activeTabID else { return }
        setURL(url, title: title(for: url), for: tabID)
        webCoordinator.load(url, in: tabID)
    }

    func navigateNewTab(to rawInput: String) {
        guard let url = navigationService.destinationURL(for: rawInput) else { return }
        newTab(url: url)
    }

    func navigateNewTab(to url: URL) {
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

        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tabs[index].title = title
        } else if let url {
            tabs[index].title = self.title(for: url)
        }

        tabs[index].url = url
        tabs[index].faviconSymbol = faviconService.placeholderSymbol(for: url)
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
            let url
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
        persistenceService.recentHistory(matching: query, limit: limit)
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
        guard let url else { return "New Tab" }
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

    private func saveSnapshot() {
        persistenceService.saveState(
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
        )
    }

    private func switchTab(offset: Int) {
        let visibleTabs = visibleTabsForActiveSpace
        guard !visibleTabs.isEmpty else { return }
        let currentIndex = visibleTabs.firstIndex(where: { $0.id == activeTabID }) ?? 0
        let nextIndex = (currentIndex + offset + visibleTabs.count) % visibleTabs.count
        let selectedTabID = visibleTabs[nextIndex].id
        switchTab(to: selectedTabID)
        presentTabSwitcher(selectedTabID: selectedTabID)
    }

    private func switchTabInRecentOrder(offset: Int, keepsPreviewOpen: Bool) {
        let recentTabs = isTabSwitcherPresented && !tabSwitcherTabs.isEmpty
            ? tabSwitcherTabs
            : recentTabsForActiveSpace(limit: 10)
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
        let currentIndex = recentTabs.firstIndex(where: { $0.id == currentSelectionID }) ?? 0
        let nextIndex = (currentIndex + offset + recentTabs.count) % recentTabs.count
        let selectedTabID = recentTabs[nextIndex].id
        switchTab(to: selectedTabID)
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
        let previewTabs = Array((candidates ?? recentTabsForActiveSpace(limit: 10)).prefix(10))
        guard !previewTabs.isEmpty else {
            hideTabSwitcher()
            return
        }

        tabSwitcherHideWorkItem?.cancel()
        tabSwitcherTabs = previewTabs
        tabSwitcherSelectedTabID = selectedTabID ?? activeTabID ?? previewTabs.first?.id
        isTabSwitcherPresented = true

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
        isTabSwitcherPresented = false
    }

    private func recentTabsForActiveSpace(limit: Int) -> [BrowserTab] {
        tabs
            .filter { $0.spaceID == activeSpaceID }
            .sorted {
                if $0.lastAccessedAt == $1.lastAccessedAt {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.lastAccessedAt > $1.lastAccessedAt
            }
            .prefix(limit)
            .map { $0 }
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

    private static func homeTab(spaceID: UUID, sortOrder: Double = 0, pinned: Bool = false) -> BrowserTab {
        BrowserTab(
            title: defaultHomeTitle,
            url: defaultHomeURL,
            faviconSymbol: "magnifyingglass",
            isPinned: pinned,
            spaceID: spaceID,
            sortOrder: sortOrder
        )
    }

    private func repairSessionState() {
        if spaces.isEmpty {
            spaces = [BrowserSpace(name: "Personal", symbolName: "circle.grid.2x2")]
        }

        let spaceIDs = Set(spaces.map(\.id))
        tabs = tabs.filter { spaceIDs.contains($0.spaceID) }

        for index in tabs.indices where Self.isHomePlaceholderURL(tabs[index].url) {
            tabs[index].url = Self.defaultHomeURL
            tabs[index].title = Self.defaultHomeTitle
            tabs[index].faviconSymbol = faviconService.placeholderSymbol(for: Self.defaultHomeURL)
            tabs[index].faviconData = nil
        }

        for space in spaces where !tabs.contains(where: { $0.spaceID == space.id }) {
            tabs.append(Self.homeTab(spaceID: space.id, sortOrder: 0))
        }

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

    private static func isHomePlaceholderURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        return url.absoluteString == "about:blank"
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
