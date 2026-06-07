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
    @Published var addressFocusRequestID = UUID()
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published var draggedTabID: UUID?

    let navigationService: NavigationService
    let webCoordinator: WebViewCoordinator

    private let persistenceService: PersistenceService
    private let faviconService: FaviconService
    private var saveCancellable: AnyCancellable?

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
            let defaultTab = BrowserTab(spaceID: defaultSpace.id)
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
        commandPaletteInitialText = activeTab?.url?.absoluteString ?? ""
        isCommandPalettePresented = true
        addressFocusRequestID = UUID()
    }

    func openCommandPalette() {
        commandPaletteInitialText = ""
        isCommandPalettePresented = true
    }

    @discardableResult
    func createSpace(name: String? = nil) -> BrowserSpace {
        let spaceNumber = spaces.count + 1
        let space = BrowserSpace(name: name ?? "Space \(spaceNumber)", symbolName: "square.grid.2x2")
        spaces.append(space)
        switchSpace(to: space.id)
        _ = newTab()
        return space
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
            _ = newTab(in: closingTab.spaceID)
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
            let tab = newTab(in: activeSpaceID)
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
        switchTab(to: visibleTabs[nextIndex].id)
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

    private func repairSessionState() {
        if spaces.isEmpty {
            spaces = [BrowserSpace(name: "Personal", symbolName: "circle.grid.2x2")]
        }

        let spaceIDs = Set(spaces.map(\.id))
        tabs = tabs.filter { spaceIDs.contains($0.spaceID) }

        for space in spaces where !tabs.contains(where: { $0.spaceID == space.id }) {
            tabs.append(BrowserTab(spaceID: space.id, sortOrder: 0))
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
