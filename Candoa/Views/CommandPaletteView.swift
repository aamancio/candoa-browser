import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var store: BrowserStore
    @State private var query = ""
    @State private var selectedSearchProvider: SearchProvider?
    @State private var isActionsMode = false
    @State private var isAskMode = false
    @State private var isAskSupported = false
    @State private var askMessages: [PaletteAskMessage] = []
    @State private var askStreamTask: Task<Void, Never>?
    @State private var selectedCommandIndex = 0
    @State private var fieldFocusRequestID = UUID()
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// Arc's command bar accent — the one selection color everywhere.
    static let paletteTint = Color(red: 0.26, green: 0.27, blue: 0.88)
    static let askTint = Color(red: 0.11, green: 0.52, blue: 0.62)
    private static let maxVisibleCommandCount = 6
    private static let commandRowHeight: CGFloat = 46
    private static let commandRowSpacing: CGFloat = 7
    private static let resultsVerticalPadding: CGFloat = 22
    private static let headerHeight: CGFloat = 70
    private static let dividerHeight: CGFloat = 1

    private var activeTint: Color {
        if isAskMode {
            return Self.askTint
        }

        return selectedSearchProvider?.paletteColor ?? Self.paletteTint
    }

    private static func resolveAskSupport() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = CandoaFoundationModelsService.availability {
                return true
            }
        }
        #endif

        return false
    }

    var body: some View {
        ZStack {
            Color(nsColor: .shadowColor)
                .opacity(colorScheme == .dark ? 0.12 : 0.06)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissPalette()
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    PaletteIconView(
                        symbolName: leadingSymbolName,
                        isSelected: false,
                        size: 24,
                        provider: headerSearchProvider
                    )

                    if let selectedSearchProvider {
                        PaletteChip(text: selectedSearchProvider.name, color: selectedSearchProvider.paletteColor)
                    } else if isAskMode {
                        PaletteChip(text: "Ask", color: Self.askTint)
                    }

                    searchField
                        .layoutPriority(1)

                    if let headerSearchProvider {
                        Spacer(minLength: 12)

                        HStack(spacing: 8) {
                            Text("Search \(headerSearchProvider.name)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text("Tab")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)

                Rectangle()
                    .fill(CandoaChromeStyle.popoverBorder)
                    .frame(height: 1)

                if isAskMode {
                    askConversationView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(Array(visibleCommands.enumerated()), id: \.element.id) { index, command in
                                Button {
                                    run(command)
                                } label: {
                                    PaletteCommandRow(
                                        command: command,
                                        isSelected: index == selectedCommandIndex,
                                        selectedTint: activeTint
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                    }
                    // ScrollView always claims its max height; with few rows
                    // that left a dead slab under the results. Size it to the
                    // rows instead (Arc's bar hugs its content).
                    .frame(height: resultsHeight)
                }
            }
            // Zen's floating urlbar width: min(window width / 1.5, 750)
            // (ZenUIManager.updateTabsToolbar's --zen-urlbar-width).
            .containerRelativeFrame(.horizontal) { length, _ in
                min(length / 1.5, 750)
            }
            .background(PaletteBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CandoaChromeStyle.popoverBorder, lineWidth: 1)
            }
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.24), radius: 46, y: 24)
            .frame(height: anchoredPaletteHeight, alignment: .top)
        }
        .background(
            CommandPaletteKeyMonitor(
                isProviderChipDeletable: (selectedSearchProvider != nil || isAskMode) && query.isEmpty,
                onDeleteProviderChip: deleteSelectedSearchProvider,
                onMoveSelection: moveSelection,
                onCancel: { dismissPalette() }
            )
        )
        .onAppear {
            isAskSupported = Self.resolveAskSupport()
            query = store.commandPaletteInitialText
            selectedSearchProvider = nil
            isActionsMode = false
            isAskMode = false
            askMessages = []
            cancelAskStream()
            selectedCommandIndex = 0
            fieldFocusRequestID = UUID()
            focusSearchField()
        }
        .onExitCommand {
            dismissPalette()
        }
        .onChange(of: fieldFocusRequestID) { _, _ in
            focusSearchField()
        }
        .onChange(of: query) { _, _ in
            selectedCommandIndex = 0
        }
        .onChange(of: selectedSearchProvider) { _, _ in
            selectedCommandIndex = 0
        }
        .onChange(of: isActionsMode) { _, _ in
            selectedCommandIndex = 0
        }
        .onChange(of: isAskMode) { _, _ in
            selectedCommandIndex = 0
        }
        .onDisappear {
            cancelAskStream()
        }
    }

    private var visibleCommands: [PaletteCommand] {
        Array(dedupedCommands(filteredCommands).prefix(Self.maxVisibleCommandCount))
    }

    /// Exact height of the visible rows (46pt rows, 7pt spacing, 11pt
    /// vertical padding), so the results area hugs its content.
    private var resultsHeight: CGFloat {
        resultsHeight(for: CGFloat(visibleCommands.count))
    }

    /// The palette itself shrinks with its result count, but it sits inside
    /// this fixed-height anchor so typing does not recenter the surface.
    private var anchoredPaletteHeight: CGFloat {
        return Self.headerHeight + Self.dividerHeight + resultsHeight(for: CGFloat(Self.maxVisibleCommandCount))
    }

    private func resultsHeight(for count: CGFloat) -> CGFloat {
        count * Self.commandRowHeight + max(0, count - 1) * Self.commandRowSpacing + Self.resultsVerticalPadding
    }

    /// The same page can surface as several history visits plus an open tab;
    /// Arc shows it once. Tab rows and navigations collapse on their target,
    /// keeping the first (highest-ranked) occurrence.
    private func dedupedCommands(_ commands: [PaletteCommand]) -> [PaletteCommand] {
        var seenKeys = Set<String>()
        return commands.filter { command in
            switch command.action {
            case .navigate(let input):
                // Two keys: revisits of one page can differ by tracking
                // params (same title+host, different URL), and the same URL
                // can carry different titles across visits. Either repeating
                // reads as a duplicate row.
                let urlInserted = seenKeys
                    .insert("navigate:\(normalizedURLKey(input))").inserted
                let labelInserted = seenKeys
                    .insert("navlabel:\(command.title.lowercased())|\(command.detail?.lowercased() ?? "")").inserted
                return urlInserted && labelInserted
            case .switchTab(let id):
                // Tab rows claim their page's label too, so a history visit
                // of the same page (under a cosmetically different URL)
                // can't trail it as a second row. The label must also be
                // unclaimed: two tabs on the same page read as one entry,
                // so only the first (highest-ranked) shows.
                let idInserted = seenKeys.insert("tab:\(id.uuidString)").inserted
                let labelInserted = seenKeys
                    .insert("navlabel:\(command.title.lowercased())|\(command.detail?.lowercased() ?? "")").inserted
                return idInserted && labelInserted
            default:
                return true
            }
        }
    }

    /// Pages get revisited with cosmetic URL differences (trailing slash,
    /// letter case); those must still count as the same target.
    private func normalizedURLKey(_ text: String) -> String {
        var key = text.lowercased()
        if key.hasSuffix("/") {
            key.removeLast()
        }
        return key
    }

    private func openTab(matching url: URL) -> BrowserTab? {
        let key = normalizedURLKey(url.absoluteString)
        return store.tabs.first {
            guard let tabURL = $0.url else { return false }
            return normalizedURLKey(tabURL.absoluteString) == key
        }
    }

    /// The open tab on a provider's site, if any — provider rows offer
    /// "Switch to Tab" instead of opening the site again in a fresh tab.
    /// The most recently used tab wins; the active tab is excluded so the
    /// row keeps its open-site action when the user is already there.
    private func openTab(onSiteOf provider: SearchProvider) -> BrowserTab? {
        guard let providerHost = normalizedHost(provider.homeURL) else { return nil }
        return store.tabs
            .filter { $0.id != store.activeTabID && normalizedHost($0.url) == providerHost }
            .max { $0.lastAccessedAt < $1.lastAccessedAt }
    }

    private func normalizedHost(_ url: URL?) -> String? {
        guard var host = url?.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }

    /// The open tab showing this visit's page, if any. Exact URL match
    /// first; SPA sites mutate the query string after the visit is
    /// recorded (YouTube adds playback params), so a same-host tab whose
    /// title still matches the visit counts as the same page.
    private func openTab(for visit: HistoryVisit) -> BrowserTab? {
        if let tab = openTab(matching: visit.url) {
            return tab
        }

        let title = visit.title.lowercased()
        guard !title.isEmpty, let host = visit.url.host(percentEncoded: false)?.lowercased() else {
            return nil
        }

        return store.tabs.first { tab in
            guard let tabURL = tab.url else { return false }
            return tab.title.lowercased() == title
                && tabURL.host(percentEncoded: false)?.lowercased() == host
        }
    }

    /// Arc/Zen-style result navigation: Up/Down arrows and Control-P/N move
    /// the highlight through the visible results, wrapping at the ends.
    private func moveSelection(by delta: Int) {
        let count = isAskMode && askMessages.isEmpty ? askSuggestions.count : visibleCommands.count
        guard count > 0 else { return }
        selectedCommandIndex = ((selectedCommandIndex + delta) % count + count) % count
    }

    private var askConversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if askMessages.isEmpty {
                        ForEach(Array(askSuggestions.enumerated()), id: \.element.title) { index, suggestion in
                            Button {
                                submitAskQuery(promptOverride: suggestion.prompt)
                            } label: {
                                PaletteAskSuggestionRow(
                                    suggestion: suggestion,
                                    isSelected: index == selectedCommandIndex
                                )
                            }
                            .buttonStyle(.plain)
                        }

                    } else {
                        ForEach(askMessages) { message in
                            PaletteAskMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .frame(height: askResultsHeight)
            .onChange(of: askMessages) { _, messages in
                guard let lastID = messages.last?.id else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private var askResultsHeight: CGFloat {
        resultsHeight(for: CGFloat(Self.maxVisibleCommandCount))
    }

    private var askSuggestions: [PaletteAskSuggestion] {
        [
            PaletteAskSuggestion(title: "Summarize this page", prompt: "Summarize this page"),
            PaletteAskSuggestion(title: "Compare the top options", prompt: "Compare the top options on this page"),
            PaletteAskSuggestion(title: "What should I know before buying?", prompt: "What should I know before buying from this page?"),
            PaletteAskSuggestion(title: "Explain this simply", prompt: "Explain this page simply")
        ]
    }

    private var searchField: some View {
        ZStack(alignment: .leading) {
            if let autocompleteSuggestion, !autocompleteSuggestion.suffix.isEmpty {
                HStack(spacing: 0) {
                    Text(query)
                        .foregroundStyle(.clear)
                    Text(autocompleteSuggestion.suffix)
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            TextField("", text: $query, prompt: Text(placeholderText).foregroundStyle(.secondary))
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .focused($isSearchFocused)
                .onSubmit(performSelectedCommand)
                .onKeyPress(.tab) {
                    activateSearchProviderFromQuery()
                    return .handled
                }
        }
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFocused = true

            guard shouldSelectCurrentURL else { return }

            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }

    private var filteredCommands: [PaletteCommand] {
        if isAskMode {
            return []
        }

        if isActionsMode {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else { return actionCommands }
            return actionCommands.filter {
                $0.title.localizedCaseInsensitiveContains(trimmedQuery)
            }
        }

        let trimmedQuery = commandQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let commands = commandCandidates(for: trimmedQuery, isResumingSearchURL: isResumingSearchURL)
        guard !trimmedQuery.isEmpty else { return commands }
        let isAskQuery = isAskSupported && askPrompt(from: trimmedQuery) != nil
        return commands.filter {
            (isAskQuery && $0.style == .ask) ||
            $0.title.localizedCaseInsensitiveContains(trimmedQuery) ||
            ($0.detail?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
            $0.searchText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    /// Arc's Tab-key Actions mode: commands that act on the current tab,
    /// with their shortcut badges, in Arc's order.
    private var actionCommands: [PaletteCommand] {
        [
            PaletteCommand(
                title: BrowserCommandTitles.copyURL,
                symbolName: "doc.on.doc",
                shortcutHint: "⇧⌘C",
                action: .copyURL
            ),
            PaletteCommand(
                title: BrowserCommandTitles.closeCurrentTab,
                symbolName: "xmark",
                shortcutHint: "⌘W",
                action: .closeCurrentTab
            ),
            PaletteCommand(
                title: BrowserCommandTitles.reloadTab,
                symbolName: "arrow.clockwise",
                shortcutHint: "⌘R",
                action: .reloadTab
            ),
            PaletteCommand(
                title: BrowserCommandTitles.copyURLAsMarkdown,
                symbolName: "doc.on.doc",
                shortcutHint: "⇧⌥⌘C",
                action: .copyURLAsMarkdown
            ),
            PaletteCommand(
                title: BrowserCommandTitles.pinOrUnpinTab,
                symbolName: "pin",
                shortcutHint: "⌘D",
                action: .togglePinTab
            ),
            PaletteCommand(
                title: BrowserCommandTitles.duplicateTab,
                symbolName: "square.on.square",
                action: .duplicateCurrentTab
            ),
            PaletteCommand(
                title: BrowserCommandTitles.toggleSplitView,
                symbolName: "rectangle.split.1x2",
                action: .toggleSplitView
            )
        ]
    }

    private var leadingSymbolName: String {
        if isAskMode {
            return "sparkles"
        }

        return isResumingSearchURL ? "globe" : "magnifyingglass"
    }

    /// The provider the Tab key would activate right now. Mirrors
    /// `activateSearchProviderFromQuery` exactly so the "Search X — Tab" hint
    /// never appears when pressing Tab wouldn't start a site search.
    private var headerSearchProvider: SearchProvider? {
        guard selectedSearchProvider == nil, !isActionsMode, !isAskMode, !isResumingSearchURL else { return nil }
        if let autocompleteSuggestion {
            return autocompleteSuggestion.provider
        }
        return store.navigationService.searchProvider(matching: commandQueryText)
    }

    private var placeholderText: String {
        if isAskMode {
            return "Ask anything..."
        }

        return selectedSearchProvider == nil && !isActionsMode ? "Search or Enter URL..." : "Search..."
    }

    private var isResumingSearchURL: Bool {
        !store.commandPaletteResumeQuery.isEmpty &&
            !store.commandPaletteInitialText.isEmpty &&
            query == store.commandPaletteInitialText
    }

    private var commandQueryText: String {
        isResumingSearchURL ? store.commandPaletteResumeQuery : query
    }

    private var shouldSelectCurrentURL: Bool {
        !store.commandPaletteInitialText.isEmpty && query == store.commandPaletteInitialText
    }

    private var autocompleteSuggestion: PaletteAutocompleteSuggestion? {
        autocompleteSuggestion(
            for: query,
            allowsProviderSuggestions: selectedSearchProvider == nil && !isActionsMode && !isAskMode && !isResumingSearchURL
        )
    }

    private func commandCandidates(for trimmedQuery: String, isResumingSearchURL: Bool = false) -> [PaletteCommand] {
        // Open tabs rank above history matches (Arc's ordering), which also
        // lets the dedupe keep the tab row when a page exists as both.
        let commands = tabCommands + historyCommands(for: trimmedQuery) + spaceCommands + baseCommands

        if let selectedSearchProvider {
            let suggestionCommands = providerSearchSuggestionCommands(
                for: selectedSearchProvider,
                matching: trimmedQuery
            )

            guard !trimmedQuery.isEmpty else { return suggestionCommands }

            let providerSearchCommand = PaletteCommand(
                title: trimmedQuery,
                detail: nil,
                symbolName: "magnifyingglass",
                searchText: "\(selectedSearchProvider.name) \(trimmedQuery)",
                style: .providerSearch(selectedSearchProvider),
                action: .searchProvider(selectedSearchProvider, trimmedQuery)
            )

            return [providerSearchCommand] + suggestionCommands.filter {
                $0.title.localizedCaseInsensitiveCompare(trimmedQuery) != .orderedSame
            } + commands
        }

        guard !trimmedQuery.isEmpty else { return defaultSuggestions }

        let navigateCommand: PaletteCommand
        if isResumingSearchURL {
            navigateCommand = PaletteCommand(
                title: trimmedQuery,
                detail: nil,
                symbolName: "globe",
                searchText: "\(trimmedQuery) \(query)",
                action: .navigate(trimmedQuery)
            )
        } else {
            navigateCommand = PaletteCommand(
                title: "Search or Go to \"\(trimmedQuery)\"",
                detail: store.commandPaletteOpensNewTab ? "Open in new tab" : "Open in current tab",
                symbolName: "globe",
                searchText: trimmedQuery,
                action: .navigate(trimmedQuery)
            )
        }

        if !store.commandPalettePrefersCurrentTabNavigation,
           let provider = suggestedSearchProvider(for: trimmedQuery, allowsAutocomplete: !isResumingSearchURL) {
            let matchingProviders = searchProviderCommands.filter { $0.provider == provider }
            return matchingProviders + [navigateCommand] + commands
        }

        if isAskSupported, askPrompt(from: trimmedQuery) != nil {
            return [askCommand] + [navigateCommand] + commands
        }

        return [navigateCommand] + commands
    }

    private var defaultSuggestions: [PaletteCommand] {
        // Resting state: the user's recent trail — open tabs and history
        // interleaved by recency. Rows backed by an open tab carry Switch to
        // Tab (historyCommand converts matches); the page the user is on
        // never suggests itself; providers pad the tail so the palette
        // always has substance.
        let activeTabURLKey = store.activeTab?.url.map { normalizedURLKey($0.absoluteString) }
        let historyEntries: [(visitedAt: Date, command: PaletteCommand)] = store.recentHistory(limit: 6)
            .filter {
                normalizedURLKey($0.url.absoluteString) != activeTabURLKey
                    && openTab(for: $0)?.id != store.activeTabID
            }
            .map { ($0.visitedAt, historyCommand(for: $0)) }
        let tabEntries: [(visitedAt: Date, command: PaletteCommand)] = store.tabs
            .filter { $0.spaceID == store.activeSpaceID && $0.url != nil && $0.id != store.activeTabID }
            .map { tab in
                (
                    tab.lastAccessedAt,
                    PaletteCommand(
                        title: tab.title,
                        detail: tab.url?.host(percentEncoded: false),
                        symbolName: tab.faviconSymbol,
                        searchText: "\(tab.title) \(tab.url?.absoluteString ?? "")",
                        style: .tab,
                        action: .switchTab(tab.id)
                    )
                )
            }

        let recentTrail = (historyEntries + tabEntries)
            .sorted { $0.visitedAt > $1.visitedAt }
            .map(\.command)

        let primaryCommands = isAskSupported ? [defaultSearchCommand, askCommand] : [defaultSearchCommand]
        return primaryCommands + recentTrail + Array(searchProviderCommands.dropFirst().prefix(2))
    }

    private var askCommand: PaletteCommand {
        PaletteCommand(
            title: "Ask",
            detail: "Candoa",
            symbolName: "sparkles",
            searchText: "ask ai candoa apple intelligence foundation models",
            style: .ask,
            action: .startAsk
        )
    }

    private var defaultSearchCommand: PaletteCommand {
        let provider = NavigationService.searchProviders[0]
        let openTab = openTab(onSiteOf: provider)
        return PaletteCommand(
            title: "Google",
            detail: nil,
            symbolName: "google",
            searchText: "google search",
            style: .provider(provider),
            action: openTab.map { .switchTab($0.id) } ?? .navigate(provider.homeURL.absoluteString)
        )
    }

    private var searchProviderCommands: [PaletteCommand] {
        NavigationService.searchProviders.map { provider in
            let openTab = openTab(onSiteOf: provider)
            return PaletteCommand(
                title: provider.name,
                detail: openTab == nil ? "Open Site" : nil,
                symbolName: provider.id == "google" ? "google" : provider.symbolName,
                searchText: ([provider.name] + provider.aliases).joined(separator: " "),
                style: .provider(provider),
                action: openTab.map { .switchTab($0.id) } ?? .navigate(provider.homeURL.absoluteString)
            )
        }
    }

    private func providerSearchSuggestionCommands(
        for provider: SearchProvider,
        matching rawQuery: String
    ) -> [PaletteCommand] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedQuery = query.lowercased()

        let tabSuggestions = store.tabs
            .filter { $0.spaceID == store.activeSpaceID }
            .compactMap { tab -> (Date, String)? in
                guard
                    let url = tab.url,
                    let suggestion = store.navigationService.searchQuery(from: url, provider: provider)
                else {
                    return nil
                }

                return (tab.lastAccessedAt, suggestion)
            }

        let historySuggestions = store.recentHistory(limit: 40)
            .compactMap { visit -> (Date, String)? in
                guard let suggestion = store.navigationService.searchQuery(from: visit.url, provider: provider) else {
                    return nil
                }

                return (visit.visitedAt, suggestion)
            }

        var seenSuggestions = Set<String>()
        return (tabSuggestions + historySuggestions)
            .sorted { $0.0 > $1.0 }
            .compactMap { _, suggestion -> PaletteCommand? in
                let normalizedSuggestion = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedSuggestion.isEmpty else { return nil }

                let suggestionKey = normalizedSuggestion.lowercased()
                guard seenSuggestions.insert(suggestionKey).inserted else { return nil }
                guard lowercasedQuery.isEmpty || suggestionKey.contains(lowercasedQuery) else { return nil }

                return PaletteCommand(
                    title: normalizedSuggestion,
                    detail: nil,
                    symbolName: "magnifyingglass",
                    searchText: "\(provider.name) \(normalizedSuggestion)",
                    style: .providerSearch(provider),
                    action: .searchProvider(provider, normalizedSuggestion)
                )
            }
    }

    private var baseCommands: [PaletteCommand] {
        let commands = [
            PaletteCommand(title: BrowserCommandTitles.newTab, symbolName: "plus", action: .newTab),
            PaletteCommand(title: BrowserCommandTitles.closeCurrentTab, symbolName: "xmark", action: .closeCurrentTab),
            PaletteCommand(title: BrowserCommandTitles.duplicateTab, symbolName: "square.on.square", action: .duplicateCurrentTab),
            PaletteCommand(title: BrowserCommandTitles.reloadTab, symbolName: "arrow.clockwise", action: .reloadTab),
            PaletteCommand(title: BrowserCommandTitles.toggleSplitView, symbolName: "rectangle.split.1x2", action: .toggleSplitView),
            PaletteCommand(title: BrowserCommandTitles.createSpace, symbolName: "square.grid.2x2", action: .createSpace),
            PaletteCommand(title: BrowserCommandTitles.focusAddressBar, symbolName: "text.cursor", action: .focusAddressBar)
        ]

        return isAskSupported ? [askCommand] + commands : commands
    }

    private func historyCommands(for query: String) -> [PaletteCommand] {
        guard !query.isEmpty else { return [] }
        return store.recentHistory(matching: query, limit: 8).map(historyCommand)
    }

    private func historyCommand(for visit: HistoryVisit) -> PaletteCommand {
        // A history entry that's already open belongs to its tab — Arc shows
        // "Switch to Tab" on those rows instead of opening a fresh visit.
        if let openTab = openTab(for: visit), openTab.id != store.activeTabID {
            return PaletteCommand(
                title: openTab.title.isEmpty ? visit.title : openTab.title,
                detail: hostDisplayText(for: visit.url),
                symbolName: openTab.faviconSymbol,
                searchText: "\(visit.title) \(visit.url.absoluteString)",
                style: .tab,
                action: .switchTab(openTab.id)
            )
        }

        return PaletteCommand(
            title: visit.title,
            detail: hostDisplayText(for: visit.url),
            symbolName: "clock.arrow.circlepath",
            searchText: "\(visit.title) \(visit.url.absoluteString)",
            style: .history,
            action: .navigate(visit.url.absoluteString)
        )
    }

    private var tabCommands: [PaletteCommand] {
        store.tabs
            .sorted {
                if $0.lastAccessedAt == $1.lastAccessedAt {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.lastAccessedAt > $1.lastAccessedAt
            }
            .map {
                let spaceName = spaceName(for: $0.spaceID)
                let urlText = $0.url?.absoluteString ?? ""
                return PaletteCommand(
                    title: $0.title,
                    detail: urlText.isEmpty ? spaceName : hostDisplayText(for: $0.url),
                    symbolName: $0.faviconSymbol,
                    searchText: "\($0.title) \(spaceName) \(urlText)",
                    style: .tab,
                    action: .switchTab($0.id)
                )
            }
    }

    private var spaceCommands: [PaletteCommand] {
        store.spaces.map {
            PaletteCommand(
                title: "Switch Space",
                detail: $0.name,
                symbolName: $0.symbolName,
                searchText: $0.name,
                action: .switchSpace($0.id)
            )
        }
    }

    private func performSelectedCommand() {
        if isAskMode {
            let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty, askMessages.isEmpty, askSuggestions.indices.contains(selectedCommandIndex) {
                submitAskQuery(promptOverride: askSuggestions[selectedCommandIndex].prompt)
            } else {
                submitAskQuery()
            }
            return
        }

        let commands = visibleCommands
        if selectedCommandIndex > 0, selectedCommandIndex < commands.count {
            run(commands[selectedCommandIndex])
            return
        }

        let trimmedQuery = commandQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selectedSearchProvider, !trimmedQuery.isEmpty {
            run(
                PaletteCommand(
                    title: "Search \(selectedSearchProvider.name)",
                    symbolName: selectedSearchProvider.symbolName,
                    action: .searchProvider(selectedSearchProvider, trimmedQuery)
                )
            )
            return
        }

        guard let command = commands.first else { return }
        run(command)
    }

    private func activateSearchProviderFromQuery() {
        guard selectedSearchProvider == nil, !isActionsMode, !isAskMode else {
            fieldFocusRequestID = UUID()
            return
        }

        if isAskSupported, let prompt = askPrompt(from: commandQueryText) {
            activateAskMode(prompt: prompt, submitsImmediately: false)
            return
        }

        if let autocompleteSuggestion {
            if let provider = autocompleteSuggestion.provider {
                selectedSearchProvider = provider
                query = ""
            } else {
                query = autocompleteSuggestion.text
            }
            fieldFocusRequestID = UUID()
            return
        }

        if let provider = store.navigationService.searchProvider(matching: commandQueryText) {
            selectedSearchProvider = provider
            query = ""
            fieldFocusRequestID = UUID()
            return
        }

        // Arc's rule: anything without a provider chip to enter gets the
        // Actions panel instead — Tab never lands on nothing.
        isActionsMode = true
        query = ""
        fieldFocusRequestID = UUID()
    }

    private func deleteSelectedSearchProvider() {
        selectedSearchProvider = nil
        isActionsMode = false
        isAskMode = false
        askMessages = []
        cancelAskStream()
        fieldFocusRequestID = UUID()
    }

    private func dismissPalette() {
        isSearchFocused = false
        cancelAskStream()
        store.dismissCommandPalette()
    }

    private func run(_ command: PaletteCommand) {
        if case .startAsk = command.action {
            guard isAskSupported else { return }
            activateAskMode(prompt: askPrompt(from: commandQueryText) ?? "", submitsImmediately: true)
            return
        }

        let opensNewTab = store.consumeCommandPaletteNewTabIntent()
        dismissPalette()

        // Deferred one tick: executing the command (tab creation, web view
        // swap) in the same transaction as the dismissal interrupts the
        // palette's removal transition, stranding an invisible palette over
        // the window that swallows every mouse click.
        DispatchQueue.main.async {
            perform(command, opensNewTab: opensNewTab)
        }
    }

    private func perform(_ command: PaletteCommand, opensNewTab: Bool) {
        switch command.action {
        case .newTab:
            store.openNewTabCommandPalette()
        case .closeCurrentTab:
            store.closeCurrentTab()
        case .duplicateCurrentTab:
            store.duplicateCurrentTab()
        case .reloadTab:
            store.reloadActiveTab()
        case .toggleSplitView:
            store.toggleSplitView()
        case .createSpace:
            store.beginSpaceCreation()
        case .focusAddressBar:
            store.focusAddressBar()
        case .copyURL:
            store.copyActiveTabURL()
        case .copyURLAsMarkdown:
            store.copyActiveTabURL(asMarkdown: true)
        case .togglePinTab:
            store.togglePinForActiveTab()
        case .startAsk:
            break
        case .navigate(let input):
            if opensNewTab {
                store.navigateNewTab(to: input)
            } else {
                store.navigateActiveTab(to: input)
            }
        case .searchProvider(let provider, let input):
            guard let url = store.navigationService.searchURL(provider: provider, query: input) else { return }
            if opensNewTab {
                store.navigateNewTab(to: url)
            } else {
                store.navigateActiveTab(to: url)
            }
        case .switchTab(let id):
            store.switchTab(to: id)
        case .switchSpace(let id):
            store.switchSpace(to: id)
        }
    }

    private func activateAskMode(prompt: String, submitsImmediately: Bool) {
        guard isAskSupported else { return }

        selectedSearchProvider = nil
        isActionsMode = false
        cancelAskStream()
        isAskMode = true
        askMessages = []
        query = prompt
        fieldFocusRequestID = UUID()

        if submitsImmediately, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submitAskQuery(promptOverride: prompt)
        }
    }

    private func askPrompt(from rawQuery: String) -> String? {
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedQuery = trimmedQuery.lowercased()

        for command in ["ask", "ai", "candoa"] {
            if lowercasedQuery == command {
                return ""
            }

            let prefix = "\(command) "
            if lowercasedQuery.hasPrefix(prefix) {
                let startIndex = trimmedQuery.index(trimmedQuery.startIndex, offsetBy: prefix.count)
                return String(trimmedQuery[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private func submitAskQuery(promptOverride: String? = nil) {
        guard isAskSupported else { return }

        let prompt = (promptOverride ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard PaletteAskPromptPolicy.canSubmit(prompt, hasConversation: !askMessages.isEmpty) else { return }
        let usesPageContext = PaletteAskPromptPolicy.usesPageContext(prompt)

        query = ""
        cancelAskStream()

        let recentTurns = recentAskTurns()
        askMessages.append(PaletteAskMessage(role: .user, text: prompt, isStreaming: false))

        let responseID = UUID()
        askMessages.append(PaletteAskMessage(id: responseID, role: .assistant, text: "", isStreaming: true))

        askStreamTask = Task {
            let pageContext = usesPageContext
                ? await store.activeAIPageContext()
                : CandoaAIPageContext(title: nil, url: nil, text: nil)

            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                switch CandoaFoundationModelsService.availability {
                case .available:
                    do {
                        var receivedText = false
                        for try await partialText in CandoaFoundationModelsService.streamResponse(
                            to: prompt,
                            context: pageContext,
                            recentTurns: recentTurns
                        ) {
                            if Task.isCancelled { return }

                            await MainActor.run {
                                guard let index = askMessages.firstIndex(where: { $0.id == responseID }) else { return }
                                askMessages[index].text = partialText
                                receivedText = receivedText || !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            }
                        }

                        await MainActor.run {
                            guard let index = askMessages.firstIndex(where: { $0.id == responseID }) else { return }
                            if !receivedText {
                                askMessages[index].text = draftAskResponse(for: prompt, context: pageContext)
                            }
                            askMessages[index].isStreaming = false
                            askStreamTask = nil
                        }
                        return
                    } catch {
                        await MainActor.run {
                            guard let index = askMessages.firstIndex(where: { $0.id == responseID }) else { return }
                            askMessages[index].text = draftAskResponse(for: prompt, context: pageContext)
                            askMessages[index].isStreaming = false
                            askStreamTask = nil
                        }
                        return
                    }
                case .unavailable(let reason):
                    await streamLocalAskResponse(
                        draftAskResponse(for: prompt, context: pageContext, modelUnavailableReason: reason),
                        into: responseID
                    )
                    return
                }
            }
            #endif

            await streamLocalAskResponse(draftAskResponse(for: prompt, context: pageContext), into: responseID)
        }
    }

    @MainActor
    private func streamLocalAskResponse(_ response: String, into responseID: UUID) async {
        guard let index = askMessages.firstIndex(where: { $0.id == responseID }) else { return }
        askMessages[index].text = ""
        askMessages[index].isStreaming = true

        for chunk in streamChunks(for: response) {
            if Task.isCancelled { return }

            do {
                try await Task.sleep(nanoseconds: 34_000_000)
            } catch {
                return
            }

            if Task.isCancelled { return }

            guard let index = askMessages.firstIndex(where: { $0.id == responseID }) else { return }
            askMessages[index].text += chunk
        }

        guard let index = askMessages.firstIndex(where: { $0.id == responseID }) else { return }
        askMessages[index].isStreaming = false
        askStreamTask = nil
    }

    private func recentAskTurns() -> [CandoaAIConversationTurn] {
        askMessages.compactMap { message in
            let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return nil }

            let role: CandoaAIConversationTurn.Role
            switch message.role {
            case .user:
                role = .user
            case .assistant:
                role = .assistant
            }

            return CandoaAIConversationTurn(role: role, text: trimmedText)
        }
    }

    private func cancelAskStream() {
        askStreamTask?.cancel()
        askStreamTask = nil

        for index in askMessages.indices where askMessages[index].isStreaming {
            askMessages[index].isStreaming = false
        }
    }

    private func draftAskResponse(
        for prompt: String,
        context: CandoaAIPageContext,
        modelUnavailableReason: String? = nil
    ) -> String {
        if let modelUnavailableReason,
           arithmeticAnswer(for: prompt) == nil,
           quickLocalAnswer(for: prompt) == nil {
            return modelUnavailableReason
        }

        if let arithmeticAnswer = arithmeticAnswer(for: prompt) {
            return arithmeticAnswer
        }

        if let quickAnswer = quickLocalAnswer(for: prompt) {
            return quickAnswer
        }

        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pageTitle = context.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageText = pageTitle?.isEmpty == false ? pageTitle! : "this page"

        if normalizedPrompt.contains("summarize") {
            return summaryDraft(from: context.text) ?? "I could not read enough page text to summarize \(pageText)."
        }

        if normalizedPrompt.contains("compare") {
            return "I can read the page now, but comparison still needs a product/option extractor. Try asking a specific question about one item on \(pageText)."
        }

        if normalizedPrompt.contains("buying") {
            return "For buying decisions, I would look for price, return policy, dimensions, reviews, warranty, and whether the listing clearly matches what you need."
        }

        if normalizedPrompt.contains("explain") {
            return summaryDraft(from: context.text) ?? "I could not read enough page text to explain \(pageText)."
        }

        return "I can't answer that yet."
    }

    private func summaryDraft(from pageText: String?) -> String? {
        guard let pageText else { return nil }
        let normalizedText = pageText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.count > 80 else { return nil }

        let sentences = normalizedText
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 30 }
            .prefix(3)

        let summary = sentences.map { "• \($0)" }.joined(separator: "\n")
        return summary.isEmpty ? String(normalizedText.prefix(420)) : summary
    }

    private func streamChunks(for response: String) -> [String] {
        response.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { index, word in
            index == 0 ? String(word) : " \(word)"
        }
    }

    private func quickLocalAnswer(for prompt: String) -> String? {
        let normalizedPrompt = normalizedQuestionText(prompt)

        if normalizedPrompt.contains("capital of united states") ||
            normalizedPrompt.contains("capital of the united states") ||
            normalizedPrompt.contains("capital of usa") ||
            normalizedPrompt.contains("capital of the usa") ||
            normalizedPrompt.contains("capital of america") {
            return "Washington, D.C."
        }

        if normalizedPrompt.contains("president of united states") ||
            normalizedPrompt.contains("president of the united states") ||
            normalizedPrompt.contains("president of usa") {
            return "I can't answer current political questions yet."
        }

        return nil
    }

    private func normalizedQuestionText(_ text: String) -> String {
        PaletteAskPromptPolicy.normalizedText(text)
    }

    private func arithmeticAnswer(for prompt: String) -> String? {
        let tokens = arithmeticTokens(for: prompt)
        guard tokens.count >= 3 else { return nil }

        for index in 0..<(tokens.count - 2) {
            guard
                case .number(let left) = tokens[index],
                case .operation(let operation) = tokens[index + 1],
                case .number(let right) = tokens[index + 2]
            else {
                continue
            }

            let result: Double
            switch operation {
            case .add:
                result = left + right
            case .subtract:
                result = left - right
            case .multiply:
                result = left * right
            case .divide:
                guard right != 0 else { return "I can't divide by zero." }
                result = left / right
            }

            return formatArithmeticResult(result)
        }

        return nil
    }

    private func arithmeticTokens(for prompt: String) -> [PaletteArithmeticToken] {
        let normalizedPrompt = prompt
            .lowercased()
            .replacingOccurrences(of: "+", with: " plus ")
            .replacingOccurrences(of: "-", with: " minus ")
            .replacingOccurrences(of: "*", with: " times ")
            .replacingOccurrences(of: "×", with: " times ")
            .replacingOccurrences(of: "/", with: " divided ")

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "."))
        let words = normalizedPrompt
            .components(separatedBy: allowedCharacters.inverted)
            .filter { !$0.isEmpty }

        var tokens: [PaletteArithmeticToken] = []
        for word in words {
            if let number = arithmeticNumber(for: word) {
                tokens.append(.number(number))
                continue
            }

            if let operation = arithmeticOperation(for: word) {
                tokens.append(.operation(operation))
            }
        }

        return tokens
    }

    private func arithmeticNumber(for word: String) -> Double? {
        if let number = Double(word) {
            return number
        }

        let numberWords: [String: Double] = [
            "zero": 0,
            "one": 1,
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5,
            "six": 6,
            "seven": 7,
            "eight": 8,
            "nine": 9,
            "ten": 10,
            "eleven": 11,
            "twelve": 12,
            "thirteen": 13,
            "fourteen": 14,
            "fifteen": 15,
            "sixteen": 16,
            "seventeen": 17,
            "eighteen": 18,
            "nineteen": 19,
            "twenty": 20
        ]

        return numberWords[word]
    }

    private func arithmeticOperation(for word: String) -> PaletteArithmeticOperation? {
        switch word {
        case "plus", "add", "added":
            return .add
        case "minus", "subtract", "subtracted", "less":
            return .subtract
        case "times", "multiply", "multiplied", "x":
            return .multiply
        case "divided", "divide", "over":
            return .divide
        default:
            return nil
        }
    }

    private func formatArithmeticResult(_ result: Double) -> String {
        if result.rounded(.towardZero) == result {
            return "\(Int(result))"
        }

        return String(format: "%.4g", result)
    }

    private func spaceName(for id: UUID) -> String {
        store.spaces.first { $0.id == id }?.name ?? "Unknown Space"
    }

    private func hostDisplayText(for url: URL?) -> String {
        url?.host(percentEncoded: false) ?? ""
    }

    private func suggestedSearchProvider(for rawQuery: String, allowsAutocomplete: Bool) -> SearchProvider? {
        if allowsAutocomplete,
           let provider = autocompleteSuggestion(
                for: rawQuery,
                allowsProviderSuggestions: selectedSearchProvider == nil
           )?.provider {
            return provider
        }

        return store.navigationService.searchProvider(matching: rawQuery)
    }

    private func autocompleteSuggestion(
        for rawQuery: String,
        allowsProviderSuggestions: Bool
    ) -> PaletteAutocompleteSuggestion? {
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            allowsProviderSuggestions,
            !trimmedQuery.isEmpty,
            trimmedQuery == rawQuery,
            !trimmedQuery.contains("\n")
        else {
            return nil
        }

        return providerAutocompleteSuggestion(for: trimmedQuery)
            ?? localAutocompleteSuggestion(for: trimmedQuery)
    }

    private func providerAutocompleteSuggestion(for rawQuery: String) -> PaletteAutocompleteSuggestion? {
        var bestCandidate: (suggestion: PaletteAutocompleteSuggestion, score: Int, providerIndex: Int, candidateIndex: Int)?

        for (providerIndex, provider) in NavigationService.searchProviders.enumerated() {
            for (candidateIndex, text) in autocompleteTexts(for: provider).enumerated() {
                guard let suggestion = makeAutocompleteSuggestion(text: text, query: rawQuery, provider: provider) else {
                    continue
                }

                let score = text.contains(".") ? 0 : 1
                if let bestCandidate {
                    guard score < bestCandidate.score ||
                        (score == bestCandidate.score && providerIndex < bestCandidate.providerIndex) ||
                        (score == bestCandidate.score && providerIndex == bestCandidate.providerIndex && candidateIndex < bestCandidate.candidateIndex)
                    else {
                        continue
                    }
                }

                bestCandidate = (suggestion, score, providerIndex, candidateIndex)
            }
        }

        return bestCandidate?.suggestion
    }

    private func localAutocompleteSuggestion(for rawQuery: String) -> PaletteAutocompleteSuggestion? {
        let historySuggestion = store.recentHistory(matching: rawQuery, limit: 8)
            .flatMap { autocompleteTexts(title: $0.title, url: $0.url) }
            .compactMap { makeAutocompleteSuggestion(text: $0, query: rawQuery) }
            .first

        if let historySuggestion {
            return historySuggestion
        }

        return store.tabs
            .filter { $0.spaceID == store.activeSpaceID }
            .sorted {
                if $0.lastAccessedAt == $1.lastAccessedAt {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.lastAccessedAt > $1.lastAccessedAt
            }
            .flatMap { autocompleteTexts(title: $0.title, url: $0.url) }
            .compactMap { makeAutocompleteSuggestion(text: $0, query: rawQuery) }
            .first
    }

    private func autocompleteTexts(for provider: SearchProvider) -> [String] {
        let hostText = normalizedHostDisplayText(for: provider.homeURL.host(percentEncoded: false))
        let domainAliases = provider.aliases
            .filter { $0.contains(".") }
            .compactMap { normalizedHostDisplayText(for: $0) }

        let aliasTexts = provider.aliases.filter { !$0.contains(".") && $0.count > 2 }
        return uniqueAutocompleteTexts(([hostText].compactMap { $0 } + domainAliases + [provider.name] + aliasTexts))
    }

    private func autocompleteTexts(title: String, url: URL?) -> [String] {
        let hostText = normalizedHostDisplayText(for: url?.host(percentEncoded: false))
        return uniqueAutocompleteTexts(([hostText, url?.absoluteString].compactMap { $0 } + [title]))
    }

    private func makeAutocompleteSuggestion(
        text: String,
        query: String,
        provider: SearchProvider? = nil
    ) -> PaletteAutocompleteSuggestion? {
        guard text.range(of: query, options: [.anchored, .caseInsensitive]) != nil else {
            return nil
        }

        guard text.count > query.count else {
            return nil
        }

        let suffixStart = text.index(text.startIndex, offsetBy: query.count)
        let resolvedProvider = provider ?? store.navigationService.searchProvider(matching: text)
        return PaletteAutocompleteSuggestion(
            text: text,
            suffix: String(text[suffixStart...]),
            provider: resolvedProvider
        )
    }

    private func normalizedHostDisplayText(for host: String?) -> String? {
        guard var host = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !host.isEmpty else {
            return nil
        }

        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }

        if host.hasPrefix("en.") {
            host.removeFirst(3)
        }

        return host
    }

    private func uniqueAutocompleteTexts(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueTexts: [String] = []

        for text in texts {
            let normalizedText = text.lowercased()
            guard !seen.contains(normalizedText) else { continue }
            seen.insert(normalizedText)
            uniqueTexts.append(text)
        }

        return uniqueTexts
    }
}

// Arc's command bar is a consistent, near-solid surface — it never picks up
// what's behind the window. The previous behind-window material sampled the
// desktop wallpaper through Candoa, washing the panel with whatever happened
// to be back there (and kept a live blur compositing while open).
private struct PaletteBackground: View {
    var body: some View {
        CandoaChromeStyle.popoverBackground
    }
}

private struct CommandPaletteKeyMonitor: NSViewRepresentable {
    let isProviderChipDeletable: Bool
    let onDeleteProviderChip: () -> Void
    let onMoveSelection: (Int) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isProviderChipDeletable: isProviderChipDeletable,
            onDeleteProviderChip: onDeleteProviderChip,
            onMoveSelection: onMoveSelection,
            onCancel: onCancel
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitorIfNeeded()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isProviderChipDeletable = isProviderChipDeletable
        context.coordinator.onDeleteProviderChip = onDeleteProviderChip
        context.coordinator.onMoveSelection = onMoveSelection
        context.coordinator.onCancel = onCancel
        context.coordinator.installMonitorIfNeeded()
    }

    final class Coordinator {
        var isProviderChipDeletable: Bool
        var onDeleteProviderChip: () -> Void
        var onMoveSelection: (Int) -> Void
        var onCancel: () -> Void
        private var monitor: Any?

        init(
            isProviderChipDeletable: Bool,
            onDeleteProviderChip: @escaping () -> Void,
            onMoveSelection: @escaping (Int) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.isProviderChipDeletable = isProviderChipDeletable
            self.onDeleteProviderChip = onDeleteProviderChip
            self.onMoveSelection = onMoveSelection
            self.onCancel = onCancel
        }

        func installMonitorIfNeeded() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self else { return event }

                if Self.isPlainEscape(event) {
                    onCancel()
                    return nil
                }

                if let delta = Self.selectionDelta(for: event) {
                    onMoveSelection(delta)
                    return nil
                }

                guard
                    isProviderChipDeletable,
                    Self.isPlainDelete(event)
                else {
                    return event
                }

                onDeleteProviderChip()
                return nil
            }
        }

        /// Up/Down arrows and the standard Control-P/Control-N field-editor
        /// bindings move the result selection, matching Arc and Zen.
        private static func selectionDelta(for event: NSEvent) -> Int? {
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .function, .numericPad])

            if modifiers.isEmpty {
                switch event.keyCode {
                case 125: return 1   // Down Arrow
                case 126: return -1  // Up Arrow
                default: return nil
                }
            }

            if modifiers == .control {
                switch event.keyCode {
                case 45: return 1    // Control-N
                case 35: return -1   // Control-P
                default: return nil
                }
            }

            return nil
        }

        private static func isPlainEscape(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .function, .numericPad])
            return modifiers.isEmpty && event.keyCode == 53
        }

        private static func isPlainDelete(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.subtracting(.capsLock).isEmpty else { return false }
            return event.keyCode == 51 || event.keyCode == 117
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

private struct PaletteCommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool
    let selectedTint: Color

    // Arc keeps the selection highlight one constant accent everywhere;
    // provider brand colors belong on the chip, never on the selected row.
    private var backgroundColor: Color {
        isSelected ? selectedTint : Color.clear
    }

    var body: some View {
        HStack(spacing: 12) {
            PaletteIconView(
                symbolName: command.symbolName,
                isSelected: isSelected,
                size: 24,
                provider: command.provider
            )

            Text(command.title)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)

            if let detail = command.detail, !detail.isEmpty {
                Text("— \(detail)")
                    .foregroundStyle(isSelected ? Color.white.opacity(0.68) : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if command.showsSwitchToTab {
                Text("Switch to Tab")
                    .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.secondary)
                    .lineLimit(1)
            } else if let shortcutHint = command.shortcutHint {
                Text(shortcutHint)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(isSelected ? backgroundColor : Color.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(isSelected ? Color.white.opacity(0.94) : Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .font(.system(size: 13.5, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(height: 46)
        .contentShape(Rectangle())
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct PaletteAskMessageRow: View {
    let message: PaletteAskMessage

    private var isUser: Bool {
        message.role == .user
    }

    private var bubbleColor: Color {
        isUser ? CommandPaletteView.askTint : Color.primary.opacity(0.08)
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser {
                Spacer(minLength: 52)
            }

            VStack(alignment: .leading, spacing: 6) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(isUser ? Color.white : Color.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else if message.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } else {
                    Text("No response.")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !isUser {
                Spacer(minLength: 52)
            }
        }
    }
}

private struct PaletteAskSuggestionRow: View {
    let suggestion: PaletteAskSuggestion
    let isSelected: Bool

    private var backgroundColor: Color {
        isSelected ? CommandPaletteView.askTint.opacity(0.36) : Color.clear
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.secondary)
                .frame(width: 24, height: 24)

            Text(suggestion.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .contentShape(Rectangle())
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct PaletteIconView: View {
    let symbolName: String
    let isSelected: Bool
    let size: CGFloat
    var provider: SearchProvider? = nil

    var body: some View {
        Group {
            if let provider {
                providerIcon(provider)
            } else if symbolName == "google" {
                googleIcon
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.68, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.72) : Color.secondary)
                    .frame(width: size, height: size)
            }
        }
    }

    private var googleIcon: some View {
        GoogleGMark()
            .frame(width: size * 0.72, height: size * 0.72)
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    @ViewBuilder
    private func providerIcon(_ provider: SearchProvider) -> some View {
        switch provider.id {
        case "google":
            googleIcon
        case "youtube":
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.0, blue: 0.0))
                    .frame(width: size * 0.95, height: size * 0.68)

                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.31, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 1)
            }
            .frame(width: size, height: size)
        case "amazon":
            AmazonBrandMark()
                .fill(Color(red: 1.0, green: 0.60, blue: 0.0))
                .frame(width: size, height: size)
            .frame(width: size, height: size)
        case "reddit":
            RedditBrandMark(isSelected: isSelected, size: size)
                .frame(width: size, height: size)
        default:
            Image(systemName: provider.symbolName)
                .font(.system(size: size * 0.68, weight: .medium))
                .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
                .frame(width: size, height: size)
        }
    }
}

private struct AmazonBrandMark: Shape {
    private static let pathData = "M.045 18.02c.072-.116.187-.124.348-.022 3.636 2.11 7.594 3.166 11.87 3.166 2.852 0 5.668-.533 8.447-1.595l.315-.14c.138-.06.234-.1.293-.13.226-.088.39-.046.525.13.12.174.09.336-.12.48-.256.19-.6.41-1.006.654-1.244.743-2.64 1.316-4.185 1.726a17.617 17.617 0 01-10.951-.577 17.88 17.88 0 01-5.43-3.35c-.1-.074-.151-.15-.151-.22 0-.047.021-.09.051-.13zm6.565-6.218c0-1.005.247-1.863.743-2.577.495-.71 1.17-1.25 2.04-1.615.796-.335 1.756-.575 2.912-.72.39-.046 1.033-.103 1.92-.174v-.37c0-.93-.105-1.558-.3-1.875-.302-.43-.78-.65-1.44-.65h-.182c-.48.046-.896.196-1.246.46-.35.27-.575.63-.675 1.096-.06.3-.206.465-.435.51l-2.52-.315c-.248-.06-.372-.18-.372-.39 0-.046.007-.09.022-.15.247-1.29.855-2.25 1.82-2.88.976-.616 2.1-.975 3.39-1.05h.54c1.65 0 2.957.434 3.888 1.29.135.15.27.3.405.48.12.165.224.314.283.45.075.134.15.33.195.57.06.254.105.42.135.51.03.104.062.3.076.615.01.313.02.493.02.553v5.28c0 .376.06.72.165 1.036.105.313.21.54.315.674l.51.674c.09.136.136.256.136.36 0 .12-.06.226-.18.314-1.2 1.05-1.86 1.62-1.963 1.71-.165.135-.375.15-.63.045a6.062 6.062 0 01-.526-.496l-.31-.347a9.391 9.391 0 01-.317-.42l-.3-.435c-.81.886-1.603 1.44-2.4 1.665-.494.15-1.093.227-1.83.227-1.11 0-2.04-.343-2.76-1.034-.72-.69-1.08-1.665-1.08-2.94l-.05-.076zm3.753-.438c0 .566.14 1.02.425 1.364.285.34.675.512 1.155.512.045 0 .106-.007.195-.02.09-.016.134-.023.166-.023.614-.16 1.08-.553 1.424-1.178.165-.28.285-.58.36-.91.09-.32.12-.59.135-.8.015-.195.015-.54.015-1.005v-.54c-.84 0-1.484.06-1.92.18-1.275.36-1.92 1.17-1.92 2.43l-.035-.02zm9.162 7.027c.03-.06.075-.11.132-.17.362-.243.714-.41 1.05-.5a8.094 8.094 0 011.612-.24c.14-.012.28 0 .41.03.65.06 1.05.168 1.172.33.063.09.099.228.099.39v.15c0 .51-.149 1.11-.424 1.8-.278.69-.664 1.248-1.156 1.68-.073.06-.14.09-.197.09-.03 0-.06 0-.09-.012-.09-.044-.107-.12-.064-.24.54-1.26.806-2.143.806-2.64 0-.15-.03-.27-.087-.344-.145-.166-.55-.257-1.224-.257-.243 0-.533.016-.87.046-.363.045-.7.09-1 .135-.09 0-.148-.014-.18-.044-.03-.03-.036-.047-.02-.077 0-.017.006-.03.02-.063v-.06z"

    func path(in rect: CGRect) -> Path {
        SVGPathData(pathData: Self.pathData).path(in: rect)
    }
}

private struct RedditBrandMark: View {
    let isSelected: Bool
    let size: CGFloat

    private var orange: Color {
        Color(red: 1.00, green: 0.27, blue: 0.05)
    }

    private var markColor: Color {
        isSelected ? .white : orange
    }

    var body: some View {
        ZStack {
            if !isSelected {
                Circle()
                    .fill(orange)
                    .frame(width: size * 0.92, height: size * 0.92)
            }

            ZStack {
                Circle()
                    .fill(isSelected ? .white : Color.white)
                    .frame(width: size * 0.54, height: size * 0.42)
                    .offset(y: size * 0.08)

                Circle()
                    .fill(markColor)
                    .frame(width: size * 0.08, height: size * 0.08)
                    .offset(x: -size * 0.14, y: size * 0.06)

                Circle()
                    .fill(markColor)
                    .frame(width: size * 0.08, height: size * 0.08)
                    .offset(x: size * 0.14, y: size * 0.06)

                Capsule()
                    .fill(markColor)
                    .frame(width: size * 0.18, height: size * 0.035)
                    .offset(y: size * 0.17)

                Capsule()
                    .fill(isSelected ? .white : Color.white)
                    .frame(width: size * 0.25, height: size * 0.07)
                    .rotationEffect(.degrees(-28))
                    .offset(x: size * 0.11, y: -size * 0.16)

                Circle()
                    .fill(isSelected ? .white : Color.white)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .offset(x: size * 0.24, y: -size * 0.27)

                Circle()
                    .fill(isSelected ? .white : Color.white)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .offset(x: -size * 0.32, y: size * 0.08)

                Circle()
                    .fill(isSelected ? .white : Color.white)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .offset(x: size * 0.32, y: size * 0.08)
            }
        }
    }
}

private struct GoogleGMark: View {
    var body: some View {
        ZStack {
            GoogleGPath(path: blueGooglePath)
                .fill(Color(red: 0.26, green: 0.52, blue: 0.96))
            GoogleGPath(path: greenGooglePath)
                .fill(Color(red: 0.20, green: 0.66, blue: 0.33))
            GoogleGPath(path: yellowGooglePath)
                .fill(Color(red: 0.98, green: 0.74, blue: 0.02))
            GoogleGPath(path: redGooglePath)
                .fill(Color(red: 0.92, green: 0.26, blue: 0.21))
        }
    }

    private var blueGooglePath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 22.56, y: 12.25))
        path.addCurve(to: CGPoint(x: 22.36, y: 10), control1: CGPoint(x: 22.56, y: 11.47), control2: CGPoint(x: 22.49, y: 10.72))
        path.addLine(to: CGPoint(x: 12, y: 10))
        path.addLine(to: CGPoint(x: 12, y: 14.26))
        path.addLine(to: CGPoint(x: 17.92, y: 14.26))
        path.addCurve(to: CGPoint(x: 15.71, y: 17.57), control1: CGPoint(x: 17.66, y: 15.63), control2: CGPoint(x: 16.88, y: 16.79))
        path.addLine(to: CGPoint(x: 15.71, y: 20.34))
        path.addLine(to: CGPoint(x: 19.28, y: 20.34))
        path.addCurve(to: CGPoint(x: 22.56, y: 12.25), control1: CGPoint(x: 21.36, y: 18.42), control2: CGPoint(x: 22.56, y: 15.6))
        path.closeSubpath()
        return path
    }

    private var greenGooglePath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 23))
        path.addCurve(to: CGPoint(x: 19.28, y: 20.34), control1: CGPoint(x: 14.97, y: 23), control2: CGPoint(x: 17.46, y: 22.02))
        path.addLine(to: CGPoint(x: 15.71, y: 17.57))
        path.addCurve(to: CGPoint(x: 12, y: 18.63), control1: CGPoint(x: 14.73, y: 18.23), control2: CGPoint(x: 13.48, y: 18.63))
        path.addCurve(to: CGPoint(x: 5.84, y: 14.1), control1: CGPoint(x: 9.14, y: 18.63), control2: CGPoint(x: 6.71, y: 16.7))
        path.addLine(to: CGPoint(x: 2.18, y: 14.1))
        path.addLine(to: CGPoint(x: 2.18, y: 16.94))
        path.addCurve(to: CGPoint(x: 12, y: 23), control1: CGPoint(x: 3.99, y: 20.53), control2: CGPoint(x: 7.7, y: 23))
        path.closeSubpath()
        return path
    }

    private var yellowGooglePath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 5.84, y: 14.09))
        path.addCurve(to: CGPoint(x: 5.49, y: 12), control1: CGPoint(x: 5.62, y: 13.43), control2: CGPoint(x: 5.49, y: 12.73))
        path.addCurve(to: CGPoint(x: 5.84, y: 9.91), control1: CGPoint(x: 5.49, y: 11.27), control2: CGPoint(x: 5.62, y: 10.57))
        path.addLine(to: CGPoint(x: 5.84, y: 7.07))
        path.addLine(to: CGPoint(x: 2.18, y: 7.07))
        path.addCurve(to: CGPoint(x: 1, y: 12), control1: CGPoint(x: 1.43, y: 8.55), control2: CGPoint(x: 1, y: 10.22))
        path.addCurve(to: CGPoint(x: 2.18, y: 16.93), control1: CGPoint(x: 1, y: 13.78), control2: CGPoint(x: 1.43, y: 15.45))
        path.addLine(to: CGPoint(x: 5.03, y: 14.71))
        path.addLine(to: CGPoint(x: 5.84, y: 14.09))
        path.closeSubpath()
        return path
    }

    private var redGooglePath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 5.38))
        path.addCurve(to: CGPoint(x: 16.21, y: 7.02), control1: CGPoint(x: 13.62, y: 5.38), control2: CGPoint(x: 15.06, y: 5.94))
        path.addLine(to: CGPoint(x: 19.36, y: 3.87))
        path.addCurve(to: CGPoint(x: 12, y: 1), control1: CGPoint(x: 17.45, y: 2.09), control2: CGPoint(x: 14.97, y: 1))
        path.addCurve(to: CGPoint(x: 2.18, y: 7.07), control1: CGPoint(x: 7.7, y: 1), control2: CGPoint(x: 3.99, y: 3.47))
        path.addLine(to: CGPoint(x: 5.84, y: 9.91))
        path.addCurve(to: CGPoint(x: 12, y: 5.38), control1: CGPoint(x: 6.71, y: 7.31), control2: CGPoint(x: 9.14, y: 5.38))
        path.closeSubpath()
        return path
    }
}

private struct GoogleGPath: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let xOffset = rect.midX - 12 * scale
        let yOffset = rect.midY - 12 * scale
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: xOffset, ty: yOffset))
    }
}

private struct SVGPathData {
    let pathData: String

    func path(in rect: CGRect) -> Path {
        var parser = Parser(pathData)
        let basePath = parser.parse()
        let scale = min(rect.width, rect.height) / 24
        let xOffset = rect.midX - 12 * scale
        let yOffset = rect.midY - 12 * scale
        return basePath.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: xOffset, ty: yOffset))
    }

    private struct Parser {
        let data: String
        var index: String.Index

        init(_ data: String) {
            self.data = data
            self.index = data.startIndex
        }

        mutating func parse() -> Path {
            var path = Path()
            var command: Character?
            var currentPoint = CGPoint.zero
            var subpathStart = CGPoint.zero

            while !isAtEnd {
                skipSeparators()
                guard !isAtEnd else { break }
                let commandStartIndex = index

                if let next = peek, next.isSVGPathCommand {
                    command = readCharacter()
                }

                guard let command else { break }

                switch command {
                case "M", "m":
                    var isFirstPoint = true
                    while let point = readPoint(relativeTo: command == "m" ? currentPoint : nil) {
                        if isFirstPoint {
                            path.move(to: point)
                            subpathStart = point
                            isFirstPoint = false
                        } else {
                            path.addLine(to: point)
                        }
                        currentPoint = point
                        if nextTokenIsCommand { break }
                    }
                case "L", "l":
                    while let point = readPoint(relativeTo: command == "l" ? currentPoint : nil) {
                        path.addLine(to: point)
                        currentPoint = point
                        if nextTokenIsCommand { break }
                    }
                case "H", "h":
                    while let x = readNumber() {
                        let point = CGPoint(x: command == "h" ? currentPoint.x + x : x, y: currentPoint.y)
                        path.addLine(to: point)
                        currentPoint = point
                        if nextTokenIsCommand { break }
                    }
                case "V", "v":
                    while let y = readNumber() {
                        let point = CGPoint(x: currentPoint.x, y: command == "v" ? currentPoint.y + y : y)
                        path.addLine(to: point)
                        currentPoint = point
                        if nextTokenIsCommand { break }
                    }
                case "C", "c":
                    while let control1 = readPoint(relativeTo: command == "c" ? currentPoint : nil),
                          let control2 = readPoint(relativeTo: command == "c" ? currentPoint : nil),
                          let point = readPoint(relativeTo: command == "c" ? currentPoint : nil) {
                        path.addCurve(to: point, control1: control1, control2: control2)
                        currentPoint = point
                        if nextTokenIsCommand { break }
                    }
                case "A", "a":
                    while let point = readArcEndpoint(relativeTo: command == "a" ? currentPoint : nil) {
                        path.addLine(to: point)
                        currentPoint = point
                        if nextTokenIsCommand { break }
                    }
                case "Z", "z":
                    path.closeSubpath()
                    currentPoint = subpathStart
                default:
                    return path
                }

                if index == commandStartIndex {
                    return path
                }
            }

            return path
        }

        private var isAtEnd: Bool {
            index >= data.endIndex
        }

        private var peek: Character? {
            isAtEnd ? nil : data[index]
        }

        private var nextTokenIsCommand: Bool {
            var copy = self
            copy.skipSeparators()
            return copy.peek?.isSVGPathCommand == true
        }

        private mutating func readCharacter() -> Character {
            let character = data[index]
            index = data.index(after: index)
            return character
        }

        private mutating func readPoint(relativeTo origin: CGPoint?) -> CGPoint? {
            guard let x = readNumber(), let y = readNumber() else { return nil }
            if let origin {
                return CGPoint(x: origin.x + x, y: origin.y + y)
            }
            return CGPoint(x: x, y: y)
        }

        private mutating func readArcEndpoint(relativeTo origin: CGPoint?) -> CGPoint? {
            let start = index
            guard
                readNumber() != nil,
                readNumber() != nil,
                readNumber() != nil,
                readArcFlag() != nil,
                readArcFlag() != nil,
                let x = readNumber(),
                let y = readNumber()
            else {
                index = start
                return nil
            }

            if let origin {
                return CGPoint(x: origin.x + x, y: origin.y + y)
            }
            return CGPoint(x: x, y: y)
        }

        private mutating func readArcFlag() -> Int? {
            skipSeparators()
            guard let flag = peek, flag == "0" || flag == "1" else { return nil }
            _ = readCharacter()
            return flag == "1" ? 1 : 0
        }

        private mutating func readNumber() -> CGFloat? {
            skipSeparators()
            let start = index

            if peek == "-" || peek == "+" {
                _ = readCharacter()
            }

            var hasDigit = false
            while let character = peek, character.isNumber {
                hasDigit = true
                _ = readCharacter()
            }

            if peek == "." {
                _ = readCharacter()
                while let character = peek, character.isNumber {
                    hasDigit = true
                    _ = readCharacter()
                }
            }

            if peek == "e" || peek == "E" {
                let exponentStart = index
                _ = readCharacter()

                if peek == "-" || peek == "+" {
                    _ = readCharacter()
                }

                var hasExponentDigit = false
                while let character = peek, character.isNumber {
                    hasExponentDigit = true
                    _ = readCharacter()
                }

                if !hasExponentDigit {
                    index = exponentStart
                }
            }

            guard hasDigit else {
                index = start
                return nil
            }

            guard let value = Double(String(data[start..<index])) else { return nil }
            return CGFloat(value)
        }

        private mutating func skipSeparators() {
            while let character = peek, character == "," || character.isWhitespace {
                _ = readCharacter()
            }
        }
    }
}

private extension Character {
    var isSVGPathCommand: Bool {
        switch self {
        case "M", "m", "L", "l", "H", "h", "V", "v", "C", "c", "A", "a", "Z", "z":
            true
        default:
            false
        }
    }
}

private struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    var detail: String?
    let symbolName: String
    var searchText = ""
    var style: PaletteCommandStyle = .generic
    var shortcutHint: String?
    let action: PaletteAction

    var provider: SearchProvider? {
        switch style {
        case .provider(let provider), .providerSearch(let provider):
            return provider
        case .generic, .tab, .history, .ask:
            return nil
        }
    }

    var showsSwitchToTab: Bool {
        if case .switchTab = action {
            return true
        }

        return false
    }
}

private struct PaletteAutocompleteSuggestion {
    let text: String
    let suffix: String
    let provider: SearchProvider?
}

private struct PaletteAskMessage: Identifiable, Equatable {
    var id = UUID()
    let role: PaletteAskRole
    var text: String
    var isStreaming: Bool
}

private struct PaletteAskSuggestion {
    let title: String
    let prompt: String
}

private enum PaletteArithmeticToken {
    case number(Double)
    case operation(PaletteArithmeticOperation)
}

private enum PaletteArithmeticOperation {
    case add
    case subtract
    case multiply
    case divide
}

private enum PaletteAskRole: Equatable {
    case user
    case assistant
}

enum PaletteAskPromptPolicy {
    private static let singleWordPageCommands: Set<String> = [
        "summarize",
        "summary",
        "explain",
        "compare"
    ]

    private static let pageContextPhrases = [
        "before buying",
        "compare the top options",
        "compare these options",
        "explain this",
        "explain this page",
        "from this page",
        "on this page",
        "summarize this",
        "summarize this page",
        "summary of this",
        "this article",
        "this listing",
        "this page",
        "this product",
        "this site",
        "top options"
    ]

    static func canSubmit(_ prompt: String, hasConversation: Bool = false) -> Bool {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return false }

        if containsArithmeticExpression(trimmedPrompt) {
            return true
        }

        let words = normalizedText(trimmedPrompt)
            .split(separator: " ")
            .map(String.init)

        guard let firstWord = words.first else { return false }

        if hasConversation, firstWord.count >= 3 {
            return true
        }

        if words.count == 1 {
            return firstWord.count >= 3 || singleWordPageCommands.contains(firstWord)
        }

        if words.count == 2 {
            return trimmedPrompt.contains("?") || words.joined().count >= 6
        }

        return true
    }

    static func usesPageContext(_ prompt: String) -> Bool {
        let normalizedPrompt = normalizedText(prompt)
        let words = normalizedPrompt
            .split(separator: " ")
            .map(String.init)

        if words.count == 1, let firstWord = words.first {
            return singleWordPageCommands.contains(firstWord)
        }

        return pageContextPhrases.contains { normalizedPrompt.contains($0) }
    }

    static func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "teh", with: "the")
            .replacingOccurrences(of: "whats", with: "what is")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func containsArithmeticExpression(_ prompt: String) -> Bool {
        let normalizedPrompt = prompt
            .lowercased()
            .replacingOccurrences(of: "+", with: " plus ")
            .replacingOccurrences(of: "-", with: " minus ")
            .replacingOccurrences(of: "*", with: " times ")
            .replacingOccurrences(of: "×", with: " times ")
            .replacingOccurrences(of: "/", with: " divided ")

        let words = normalizedPrompt
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        var hasNumber = false
        var hasOperation = false
        for word in words {
            if Double(word) != nil || numberWords.contains(word) {
                hasNumber = true
            }

            if operationWords.contains(word) {
                hasOperation = true
            }
        }

        return hasNumber && hasOperation
    }

    private static let numberWords: Set<String> = [
        "zero",
        "one",
        "two",
        "three",
        "four",
        "five",
        "six",
        "seven",
        "eight",
        "nine",
        "ten",
        "eleven",
        "twelve",
        "thirteen",
        "fourteen",
        "fifteen",
        "sixteen",
        "seventeen",
        "eighteen",
        "nineteen",
        "twenty"
    ]

    private static let operationWords: Set<String> = [
        "plus",
        "add",
        "added",
        "minus",
        "subtract",
        "subtracted",
        "less",
        "times",
        "multiply",
        "multiplied",
        "x",
        "divided",
        "divide",
        "over"
    ]
}

private enum PaletteCommandStyle: Equatable {
    case generic
    case tab
    case history
    case ask
    case provider(SearchProvider)
    case providerSearch(SearchProvider)
}

private enum PaletteAction {
    case newTab
    case closeCurrentTab
    case duplicateCurrentTab
    case reloadTab
    case toggleSplitView
    case createSpace
    case focusAddressBar
    case copyURL
    case copyURLAsMarkdown
    case togglePinTab
    case startAsk
    case navigate(String)
    case searchProvider(SearchProvider, String)
    case switchTab(UUID)
    case switchSpace(UUID)
}

private struct PaletteChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(color)
            .clipShape(Capsule())
            .shadow(color: color.opacity(0.42), radius: 14, y: 2)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private extension SearchProvider {
    var paletteColor: Color {
        switch id {
        case "google":
            return Color(red: 0.26, green: 0.52, blue: 0.96)
        case "youtube":
            return Color(red: 0.94, green: 0.05, blue: 0.05)
        case "amazon":
            return Color(red: 0.92, green: 0.52, blue: 0.06)
        case "duckduckgo":
            return Color(red: 0.32, green: 0.28, blue: 0.86)
        case "bing":
            return Color(red: 0.07, green: 0.48, blue: 0.60)
        case "brave":
            return Color(red: 0.90, green: 0.26, blue: 0.08)
        case "startpage":
            return Color(red: 0.10, green: 0.36, blue: 0.92)
        case "qwant":
            return Color(red: 0.28, green: 0.42, blue: 0.94)
        case "mojeek":
            return Color(red: 0.08, green: 0.58, blue: 0.30)
        case "swisscows":
            return Color(red: 0.76, green: 0.18, blue: 0.38)
        case "ecosia":
            return Color(red: 0.10, green: 0.55, blue: 0.30)
        case "perplexity":
            return Color(red: 0.12, green: 0.62, blue: 0.65)
        case "kagi":
            return Color(red: 0.95, green: 0.45, blue: 0.22)
        case "yahoo":
            return Color(red: 0.38, green: 0.18, blue: 0.86)
        case "yandex":
            return Color(red: 0.92, green: 0.14, blue: 0.12)
        case "github":
            return Color(red: 0.36, green: 0.36, blue: 0.40)
        case "reddit":
            return Color(red: 1.00, green: 0.33, blue: 0.13)
        case "x":
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        case "spotify":
            return Color(red: 0.12, green: 0.72, blue: 0.32)
        case "chatgpt":
            return Color(red: 0.08, green: 0.58, blue: 0.45)
        case "claude":
            return Color(red: 0.72, green: 0.36, blue: 0.20)
        case "gemini":
            return Color(red: 0.34, green: 0.43, blue: 0.93)
        case "wikipedia":
            return Color(red: 0.25, green: 0.25, blue: 0.27)
        default:
            return Color(red: 0.46, green: 0.30, blue: 0.18)
        }
    }
}
