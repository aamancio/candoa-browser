import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var store: BrowserStore
    @State private var query = ""
    @State private var selectedSearchProvider: SearchProvider?
    @State private var fieldFocusRequestID = UUID()
    @FocusState private var isSearchFocused: Bool

    private var activeTint: Color {
        selectedSearchProvider?.paletteColor ?? Color(red: 0.26, green: 0.27, blue: 0.88)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.02)
                .ignoresSafeArea()
                .onTapGesture {
                    store.dismissCommandPalette()
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
                        SearchProviderChip(provider: selectedSearchProvider)
                    }

                    searchField
                        .layoutPriority(1)

                    if let headerSearchProvider {
                        Spacer(minLength: 12)

                        Text("Search \(headerSearchProvider.name)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.36))
                            .lineLimit(1)

                        Text("Tab")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.66))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(filteredCommands.prefix(6).enumerated()), id: \.element.id) { index, command in
                            Button {
                                run(command)
                            } label: {
                                PaletteCommandRow(
                                    command: command,
                                    isSelected: index == 0,
                                    selectedTint: activeTint
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                }
                .frame(maxHeight: 320)
            }
            .frame(width: 860)
            .background(PaletteBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.30), radius: 46, y: 24)
        }
        .background(
            CommandPaletteKeyMonitor(
                isProviderChipDeletable: selectedSearchProvider != nil && query.isEmpty,
                onDeleteProviderChip: deleteSelectedSearchProvider
            )
        )
        .onAppear {
            query = store.commandPaletteInitialText
            selectedSearchProvider = nil
            fieldFocusRequestID = UUID()
            focusSearchField()
        }
        .onExitCommand {
            store.dismissCommandPalette()
        }
        .onChange(of: fieldFocusRequestID) { _, _ in
            focusSearchField()
        }
    }

    private var searchField: some View {
        ZStack(alignment: .leading) {
            if let autocompleteSuggestion, !autocompleteSuggestion.suffix.isEmpty {
                HStack(spacing: 0) {
                    Text(query)
                        .foregroundStyle(.clear)
                    Text(autocompleteSuggestion.suffix)
                        .foregroundStyle(Color.white.opacity(0.30))
                }
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            TextField("", text: $query, prompt: Text(placeholderText).foregroundStyle(Color.white.opacity(0.52)))
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.86))
                .focused($isSearchFocused)
                .onSubmit(performFirstCommand)
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
        let trimmedQuery = commandQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let commands = commandCandidates(for: trimmedQuery, isResumingSearchURL: isResumingSearchURL)
        guard !trimmedQuery.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery) ||
            ($0.detail?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
            $0.searchText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var leadingSymbolName: String {
        isResumingSearchURL ? "globe" : "magnifyingglass"
    }

    private var headerSearchProvider: SearchProvider? {
        guard selectedSearchProvider == nil, !isResumingSearchURL else { return nil }
        return autocompleteSuggestion?.provider ?? store.navigationService.searchProvider(matching: query)
    }

    private var placeholderText: String {
        selectedSearchProvider == nil ? "Search or Enter URL..." : "Search..."
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
        autocompleteSuggestion(for: query, allowsProviderSuggestions: selectedSearchProvider == nil && !isResumingSearchURL)
    }

    private func commandCandidates(for trimmedQuery: String, isResumingSearchURL: Bool = false) -> [PaletteCommand] {
        let historyCommands = historyCommands(for: trimmedQuery)
        let commands = historyCommands + tabCommands + spaceCommands + baseCommands

        if let selectedSearchProvider {
            guard !trimmedQuery.isEmpty else { return commands }

            let providerSearchCommand = PaletteCommand(
                title: trimmedQuery,
                detail: nil,
                symbolName: "magnifyingglass",
                searchText: "\(selectedSearchProvider.name) \(trimmedQuery)",
                style: .providerSearch(selectedSearchProvider),
                action: .searchProvider(selectedSearchProvider, trimmedQuery)
            )

            return [providerSearchCommand] + commands
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

        if let provider = suggestedSearchProvider(for: trimmedQuery, allowsAutocomplete: !isResumingSearchURL) {
            let matchingProviders = searchProviderCommands.filter { $0.provider == provider }
            return matchingProviders + [navigateCommand] + commands
        }

        return [navigateCommand] + commands
    }

    private var defaultSuggestions: [PaletteCommand] {
        let recentHistory = store.recentHistory(limit: 4).map(historyCommand)
        let recentTabs = store.tabs
            .filter { $0.url != nil }
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
            .prefix(4)
            .map { tab in
                PaletteCommand(
                    title: tab.title,
                    detail: tab.url?.host(percentEncoded: false),
                    symbolName: tab.faviconSymbol,
                    searchText: "\(tab.title) \(tab.url?.absoluteString ?? "")",
                    style: .tab,
                    action: .switchTab(tab.id)
                )
            }

        return [defaultSearchCommand] + recentHistory + recentTabs + Array(searchProviderCommands.dropFirst().prefix(2))
    }

    private var defaultSearchCommand: PaletteCommand {
        PaletteCommand(
            title: "Google",
            detail: nil,
            symbolName: "google",
            searchText: "google search",
            style: .provider(NavigationService.searchProviders[0]),
            action: .navigate(NavigationService.searchProviders[0].homeURL.absoluteString)
        )
    }

    private var searchProviderCommands: [PaletteCommand] {
        NavigationService.searchProviders.map { provider in
            PaletteCommand(
                title: provider.name,
                detail: "Open Site",
                symbolName: provider.id == "google" ? "google" : provider.symbolName,
                searchText: ([provider.name] + provider.aliases).joined(separator: " "),
                style: .provider(provider),
                action: .navigate(provider.homeURL.absoluteString)
            )
        }
    }

    private var baseCommands: [PaletteCommand] {
        [
            PaletteCommand(title: BrowserCommandTitles.newTab, symbolName: "plus", action: .newTab),
            PaletteCommand(title: BrowserCommandTitles.closeCurrentTab, symbolName: "xmark", action: .closeCurrentTab),
            PaletteCommand(title: BrowserCommandTitles.duplicateTab, symbolName: "square.on.square", action: .duplicateCurrentTab),
            PaletteCommand(title: BrowserCommandTitles.reloadTab, symbolName: "arrow.clockwise", action: .reloadTab),
            PaletteCommand(title: BrowserCommandTitles.toggleSplitView, symbolName: "rectangle.split.1x2", action: .toggleSplitView),
            PaletteCommand(title: BrowserCommandTitles.createSpace, symbolName: "square.grid.2x2", action: .createSpace),
            PaletteCommand(title: BrowserCommandTitles.focusAddressBar, symbolName: "text.cursor", action: .focusAddressBar)
        ]
    }

    private func historyCommands(for query: String) -> [PaletteCommand] {
        guard !query.isEmpty else { return [] }
        return store.recentHistory(matching: query, limit: 8).map(historyCommand)
    }

    private func historyCommand(for visit: HistoryVisit) -> PaletteCommand {
        PaletteCommand(
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

    private func performFirstCommand() {
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

        guard let command = filteredCommands.first else { return }
        run(command)
    }

    private func activateSearchProviderFromQuery() {
        guard selectedSearchProvider == nil else {
            fieldFocusRequestID = UUID()
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

        guard let provider = store.navigationService.searchProvider(matching: commandQueryText) else {
            fieldFocusRequestID = UUID()
            return
        }

        selectedSearchProvider = provider
        query = ""
        fieldFocusRequestID = UUID()
    }

    private func deleteSelectedSearchProvider() {
        selectedSearchProvider = nil
        fieldFocusRequestID = UUID()
    }

    private func run(_ command: PaletteCommand) {
        let opensNewTab = store.consumeCommandPaletteNewTabIntent()
        store.dismissCommandPalette()

        switch command.action {
        case .newTab:
            store.newTab()
            store.focusAddressBar()
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

private struct PaletteBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.09)
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.68)
        }
    }
}

private struct CommandPaletteKeyMonitor: NSViewRepresentable {
    let isProviderChipDeletable: Bool
    let onDeleteProviderChip: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isProviderChipDeletable: isProviderChipDeletable,
            onDeleteProviderChip: onDeleteProviderChip
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitorIfNeeded()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isProviderChipDeletable = isProviderChipDeletable
        context.coordinator.onDeleteProviderChip = onDeleteProviderChip
        context.coordinator.installMonitorIfNeeded()
    }

    final class Coordinator {
        var isProviderChipDeletable: Bool
        var onDeleteProviderChip: () -> Void
        private var monitor: Any?

        init(isProviderChipDeletable: Bool, onDeleteProviderChip: @escaping () -> Void) {
            self.isProviderChipDeletable = isProviderChipDeletable
            self.onDeleteProviderChip = onDeleteProviderChip
        }

        func installMonitorIfNeeded() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard
                    let self,
                    isProviderChipDeletable,
                    Self.isPlainDelete(event)
                else {
                    return event
                }

                onDeleteProviderChip()
                return nil
            }
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

    private var backgroundColor: Color {
        if isSelected {
            return command.selectedColor ?? selectedTint
        }

        return Color.clear
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
                .foregroundStyle(isSelected ? .white : Color.white.opacity(0.82))
                .lineLimit(1)

            if let detail = command.detail, !detail.isEmpty {
                Text("— \(detail)")
                    .foregroundStyle(isSelected ? Color.white.opacity(0.60) : Color.white.opacity(0.32))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if command.showsSwitchToTab {
                Text("Switch to Tab")
                    .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.34))
                    .lineLimit(1)

                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.94) : Color.white.opacity(0.08))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? backgroundColor : Color.white.opacity(0.56))
                }
                .frame(width: 24, height: 24)
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
                    .foregroundStyle(isSelected ? Color.white.opacity(0.72) : Color.white.opacity(0.52))
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
                .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.white.opacity(0.56))
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

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

private struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    var detail: String?
    let symbolName: String
    var searchText = ""
    var style: PaletteCommandStyle = .generic
    let action: PaletteAction

    var provider: SearchProvider? {
        switch style {
        case .provider(let provider), .providerSearch(let provider):
            return provider
        case .generic, .tab, .history:
            return nil
        }
    }

    var selectedColor: Color? {
        switch style {
        case .provider(let provider), .providerSearch(let provider):
            return provider.paletteColor
        case .generic, .tab, .history:
            return nil
        }
    }

    var showsSwitchToTab: Bool {
        if case .tab = style {
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

private enum PaletteCommandStyle {
    case generic
    case tab
    case history
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
    case navigate(String)
    case searchProvider(SearchProvider, String)
    case switchTab(UUID)
    case switchSpace(UUID)
}

private struct SearchProviderChip: View {
    let provider: SearchProvider

    var body: some View {
        Text(provider.name)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(provider.paletteColor)
            .clipShape(Capsule())
            .shadow(color: provider.paletteColor.opacity(0.42), radius: 14, y: 2)
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
