import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var store: BrowserStore
    @State private var query = ""
    @State private var selectedSearchProvider: SearchProvider?
    @State private var fieldFocusRequestID = UUID()

    var body: some View {
        ZStack {
            Color.black.opacity(0.02)
                .ignoresSafeArea()
                .onTapGesture {
                    store.isCommandPalettePresented = false
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    PaletteIconView(
                        symbolName: leadingSymbolName,
                        isSelected: false,
                        size: 24
                    )

                    if let selectedSearchProvider {
                        SearchProviderChip(provider: selectedSearchProvider)
                    }

                    PaletteSearchField(
                        text: $query,
                        placeholder: placeholderText,
                        focusRequestID: fieldFocusRequestID,
                        onSubmit: performFirstCommand,
                        onTab: activateSearchProviderFromQuery,
                        onCancel: { store.isCommandPalettePresented = false }
                    )
                    .frame(height: 30)
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
                                PaletteCommandRow(command: command, isSelected: index == 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                }
                .frame(maxHeight: 320)
            }
            .frame(width: 760)
            .background(PaletteBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.30), radius: 46, y: 24)
        }
        .onAppear {
            query = store.commandPaletteInitialText
            selectedSearchProvider = nil
            fieldFocusRequestID = UUID()
        }
        .onExitCommand {
            store.isCommandPalettePresented = false
        }
    }

    private var filteredCommands: [PaletteCommand] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let commands = commandCandidates(for: trimmedQuery)
        guard !trimmedQuery.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery) ||
            ($0.detail?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
            $0.searchText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var leadingSymbolName: String {
        if selectedSearchProvider != nil {
            return "magnifyingglass"
        }

        return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "globe"
            : "google"
    }

    private var placeholderText: String {
        selectedSearchProvider == nil ? "Search or Enter URL..." : "Search..."
    }

    private func commandCandidates(for trimmedQuery: String) -> [PaletteCommand] {
        let commands = tabCommands + spaceCommands + baseCommands

        if let selectedSearchProvider {
            guard !trimmedQuery.isEmpty else { return commands }

            let providerSearchCommand = PaletteCommand(
                title: "Search \(selectedSearchProvider.name) for \"\(trimmedQuery)\"",
                detail: "Open in current tab",
                symbolName: selectedSearchProvider.symbolName,
                searchText: "\(selectedSearchProvider.name) \(trimmedQuery)",
                action: .searchProvider(selectedSearchProvider, trimmedQuery)
            )

            return [providerSearchCommand] + commands
        }

        guard !trimmedQuery.isEmpty else { return defaultSuggestions }

        let navigateCommand = PaletteCommand(
            title: "Search or Go to \"\(trimmedQuery)\"",
            detail: "Open in current tab",
            symbolName: "globe",
            searchText: trimmedQuery,
            action: .navigate(trimmedQuery)
        )

        return [navigateCommand] + searchProviderCommands + commands
    }

    private var defaultSuggestions: [PaletteCommand] {
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
                    action: .switchTab(tab.id)
                )
            }

        return [defaultSearchCommand] + recentTabs + Array(searchProviderCommands.dropFirst().prefix(2))
    }

    private var defaultSearchCommand: PaletteCommand {
        PaletteCommand(
            title: "Google",
            detail: nil,
            symbolName: "google",
            searchText: "google search",
            action: .activateSearchProvider(NavigationService.searchProviders[0])
        )
    }

    private var searchProviderCommands: [PaletteCommand] {
        NavigationService.searchProviders.map { provider in
            PaletteCommand(
                title: provider.name,
                detail: "Press Tab",
                symbolName: provider.id == "google" ? "google" : provider.symbolName,
                searchText: ([provider.name] + provider.aliases).joined(separator: " "),
                action: .activateSearchProvider(provider)
            )
        }
    }

    private var baseCommands: [PaletteCommand] {
        [
            PaletteCommand(title: "New Tab", symbolName: "plus", action: .newTab),
            PaletteCommand(title: "Close Current Tab", symbolName: "xmark", action: .closeCurrentTab),
            PaletteCommand(title: "Duplicate Tab", symbolName: "square.on.square", action: .duplicateCurrentTab),
            PaletteCommand(title: "Reload Tab", symbolName: "arrow.clockwise", action: .reloadTab),
            PaletteCommand(title: "Toggle Split View", symbolName: "rectangle.split.1x2", action: .toggleSplitView),
            PaletteCommand(title: "Create Space", symbolName: "square.grid.2x2", action: .createSpace),
            PaletteCommand(title: "Focus Address Bar", symbolName: "text.cursor", action: .focusAddressBar)
        ]
    }

    private var tabCommands: [PaletteCommand] {
        store.tabs
            .sorted {
                if $0.spaceID == $1.spaceID {
                    return $0.sortOrder < $1.sortOrder
                }
                return spaceName(for: $0.spaceID) < spaceName(for: $1.spaceID)
            }
            .map {
                let spaceName = spaceName(for: $0.spaceID)
                let urlText = $0.url?.absoluteString ?? ""
                return PaletteCommand(
                    title: $0.title,
                    detail: urlText.isEmpty ? spaceName : hostDisplayText(for: $0.url),
                    symbolName: $0.faviconSymbol,
                    searchText: "\($0.title) \(spaceName) \(urlText)",
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
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
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

        guard let provider = store.navigationService.searchProvider(matching: query) else {
            fieldFocusRequestID = UUID()
            return
        }

        selectedSearchProvider = provider
        query = ""
        fieldFocusRequestID = UUID()
    }

    private func run(_ command: PaletteCommand) {
        if case .activateSearchProvider(let provider) = command.action {
            selectedSearchProvider = provider
            query = ""
            fieldFocusRequestID = UUID()
            return
        }

        store.isCommandPalettePresented = false

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
            store.createSpace()
            store.focusAddressBar()
        case .focusAddressBar:
            store.focusAddressBar()
        case .navigate(let input):
            store.navigateActiveTab(to: input)
        case .searchProvider(let provider, let input):
            guard let url = store.navigationService.searchURL(provider: provider, query: input) else { return }
            store.navigateActiveTab(to: url)
        case .activateSearchProvider:
            break
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

private struct PaletteCommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            PaletteIconView(symbolName: command.symbolName, isSelected: isSelected, size: 24)

            Text(command.title)
                .foregroundStyle(isSelected ? .white : Color.white.opacity(0.82))
                .lineLimit(1)

            if let detail = command.detail, !detail.isEmpty {
                Text("— \(detail)")
                    .foregroundStyle(isSelected ? Color.white.opacity(0.60) : Color.white.opacity(0.32))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)
        }
        .font(.system(size: 13.5, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(height: 46)
        .contentShape(Rectangle())
        .background(isSelected ? Color(red: 0.26, green: 0.27, blue: 0.88) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct PaletteIconView: View {
    let symbolName: String
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        Group {
            if symbolName == "google" {
                googleIcon
            } else if symbolName == "play.rectangle.fill" {
                youtubeIcon
            } else if symbolName == "shippingbox.fill" {
                amazonIcon
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.68, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.72) : Color.white.opacity(0.52))
                    .frame(width: size, height: size)
            }
        }
    }

    private var googleIcon: some View {
        Text("G")
            .font(.system(size: size * 0.58, weight: .bold))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.26, green: 0.52, blue: 0.96),
                        Color(red: 0.93, green: 0.20, blue: 0.16),
                        Color(red: 0.98, green: 0.74, blue: 0.18),
                        Color(red: 0.20, green: 0.66, blue: 0.33)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var youtubeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.76) : Color.white.opacity(0.50))
                .frame(width: size * 0.92, height: size * 0.68)

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.30, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.56))
                .offset(x: 1)
        }
        .frame(width: size, height: size)
    }

    private var amazonIcon: some View {
        Image(systemName: "cube.box.fill")
            .font(.system(size: size * 0.70, weight: .medium))
            .foregroundStyle(isSelected ? Color.white.opacity(0.76) : Color.white.opacity(0.50))
            .frame(width: size, height: size)
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
    let action: PaletteAction
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
    case activateSearchProvider(SearchProvider)
    case searchProvider(SearchProvider, String)
    case switchTab(UUID)
    case switchSpace(UUID)
}

private struct SearchProviderChip: View {
    let provider: SearchProvider

    var body: some View {
        Text(provider.name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(provider.paletteColor)
            .clipShape(Capsule())
    }
}

private struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequestID: UUID
    let onSubmit: () -> Void
    let onTab: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.font = NSFont.systemFont(ofSize: 17, weight: .medium)
        textField.textColor = NSColor.white.withAlphaComponent(0.86)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onTab = onTab
        context.coordinator.onCancel = onCancel

        if textField.stringValue != text {
            textField.stringValue = text
        }

        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.52),
                .font: NSFont.systemFont(ofSize: 17, weight: .medium)
            ]
        )

        guard context.coordinator.lastFocusRequestID != focusRequestID else { return }
        context.coordinator.lastFocusRequestID = focusRequestID

        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void = {}
        var onTab: () -> Void = {}
        var onCancel: () -> Void = {}
        var lastFocusRequestID: UUID?

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                onSubmit()
                return true
            case #selector(NSResponder.insertTab(_:)):
                onTab()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            default:
                return false
            }
        }
    }
}

private extension SearchProvider {
    var paletteColor: Color {
        switch id {
        case "youtube":
            return Color(red: 0.94, green: 0.05, blue: 0.05)
        case "amazon":
            return Color(red: 0.92, green: 0.52, blue: 0.06)
        case "duckduckgo":
            return Color(red: 0.32, green: 0.28, blue: 0.86)
        case "bing":
            return Color(red: 0.07, green: 0.48, blue: 0.60)
        case "github":
            return Color(red: 0.36, green: 0.36, blue: 0.40)
        case "wikipedia":
            return Color(red: 0.25, green: 0.25, blue: 0.27)
        default:
            return Color(red: 0.46, green: 0.30, blue: 0.18)
        }
    }
}
