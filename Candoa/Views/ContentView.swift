import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = BrowserStore()
    @StateObject private var updateService = AppUpdateService.shared
    @StateObject private var systemAppearance = SystemAppearanceObserver()
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("candoa.windowAutosaveID") private var windowAutosaveID = UUID().uuidString
    @State private var isSidebarVisible = true
    @State private var isSidebarHoverRevealed = false
    @State private var isSidebarRevealSuppressed = false
    @State private var isAISidebarVisible = false
    @State private var miniPlayerOrigin: CGPoint?
    @State private var miniPlayerExpandedSize = MiniPlayerLayout.defaultExpandedSize
    private let sidebarWidth = CandoaChromeStyle.sidebarWidth
    private let aiSidebarWidth: CGFloat = 360
    private let sidebarDividerWidth: CGFloat = 0

    private var activeThemeAppearance: SpaceThemeAppearance {
        store.spaceThemeAppearancePreview ?? store.activeSpace?.themeAppearance ?? .automatic
    }

    // SwiftUI latches the last explicit color scheme on its window; passing
    // nil ("no preference") never releases it. So "automatic" is resolved to
    // the live system appearance instead of nil — see SystemAppearanceObserver.
    private var resolvedColorScheme: ColorScheme {
        activeThemeAppearance.colorScheme ?? systemAppearance.colorScheme
    }

    private var activeThemeHexes: [String] {
        store.activeThemeColorHexes
    }

    private var activeThemeIntensityMultiplier: Double {
        store.activeThemeIntensityMultiplier
    }

    private var sidebarTotalWidth: CGFloat {
        sidebarWidth + sidebarDividerWidth
    }

    private var isSidebarPresented: Bool {
        isSidebarVisible || isSidebarHoverRevealed
    }

    private var isSidebarOverlaying: Bool {
        isSidebarHoverRevealed && !isSidebarVisible
    }

    var body: some View {
        ZStack(alignment: .leading) {
            WebViewContainer(store: store)
                .ignoresSafeArea(.container, edges: .top)
                .padding(.leading, isSidebarVisible ? sidebarTotalWidth : 0)
                .padding(.trailing, isAISidebarVisible ? aiSidebarWidth : 0)

            sidebarLayout
                .offset(x: isSidebarPresented ? 0 : -sidebarTotalWidth)
                .zIndex(2)

            if isAISidebarVisible {
                AISidebarView(store: store) {
                    toggleAISidebar()
                }
                .frame(width: aiSidebarWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(3)
            }

            if store.isCommandPalettePresented {
                CommandPaletteView(store: store)
                    .id(store.commandPaletteSessionID)
                    // Removal must be instant: an animated removal overlaps
                    // the committed command's web view swap, which interrupts
                    // the transition and strands an invisible palette that
                    // swallows every click in the window.
                    .transition(.identity)
                    .zIndex(10)
            }

            if store.isTabSwitcherPresented {
                TabSwitcherOverlay(store: store)
                    .zIndex(9)
            }

            if let mediaTab = store.floatingMiniPlayerTab,
               let mediaState = store.floatingMiniPlayerState {
                GeometryReader { proxy in
                    let leadingInset = isSidebarVisible ? sidebarTotalWidth : 0
                    let availableSize = CGSize(
                        width: max(0, proxy.size.width - leadingInset),
                        height: proxy.size.height
                    )

                    HStack(spacing: 0) {
                        if isSidebarVisible {
                            Color.clear
                                .frame(width: sidebarTotalWidth)
                                .allowsHitTesting(false)
                        }

                        FloatingMiniPlayerContainer(
                            store: store,
                            tab: mediaTab,
                            state: mediaState,
                            availableSize: availableSize,
                            summon: store.pendingMiniPlayerSummon,
                            origin: $miniPlayerOrigin,
                            expandedSize: $miniPlayerExpandedSize
                        )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
                .ignoresSafeArea(.container, edges: .top)
                .transition(.scale(scale: 0.98, anchor: .bottomLeading).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .overlay {
            // Zen anchors its toast container at the window's absolute
            // top-right (8px in from both edges), floating over the title
            // bar — so the pill must escape the top safe area.
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .allowsHitTesting(false)

                if let toast = store.copiedURLToast {
                    CopiedURLToastView(
                        toast: toast,
                        themeColorHex: store.activeThemeColorHexes.first,
                        onShareInteractionChanged: { store.setCopiedURLToastSharing($0) }
                    )
                    .onHover { store.setCopiedURLToastHovered($0) }
                    .padding(.top, CopiedURLToastView.windowEdgeSpacing)
                    .padding(.trailing, CopiedURLToastView.windowEdgeSpacing)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.01, anchor: .top),
                        removal: .scale(scale: 0.5, anchor: .top).combined(with: .opacity)
                    ))
                    .id(toast.id)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .bottomTrailing) {
            if BrowserStore.isUITesting {
                let stateDescription = store.uiTestingStateDescription(sidebarVisible: isSidebarVisible)

                Text(stateDescription)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityLabel(stateDescription)
                    .accessibilityIdentifier("ui-testing-state")
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: store.copiedURLToast)
        .background {
            CandoaWindowBackdrop(store: store)
                .ignoresSafeArea()
        }
        .preferredColorScheme(resolvedColorScheme)
        .background(
            WindowInteractionConfigurator(
                autosaveName: "\(AppConfiguration.windowAutosaveNamePrefix).\(windowAutosaveID)"
            )
        )
        .background(
            MouseMoveMonitor(
                isSidebarVisible: $isSidebarVisible,
                isSidebarHoverRevealed: $isSidebarHoverRevealed,
                isSidebarRevealSuppressed: $isSidebarRevealSuppressed
            )
        )
        .background(
            KeyboardShortcutMonitor {
                openNewTabFlow()
            } onCommandW: {
                closeTabOrWindow()
            } onFocusAddressBar: {
                store.focusAddressBar()
            } onCopyURL: {
                store.copyActiveTabURL()
            } onCopyURLAsMarkdown: {
                store.copyActiveTabURL(asMarkdown: true)
            } onCaptureFullPage: {
                store.captureActiveTabPage()
            } onPinOrUnpinTab: {
                store.togglePinForActiveTab()
            } onToggleSidebar: {
                toggleSidebar()
            } onToggleAISidebar: {
                toggleAISidebar()
            } onFindInPage: {
                store.showFindBar()
            } onReload: {
                store.reloadActiveTab()
            } onControlTab: {
                store.switchToNextRecentTab(keepsPreviewOpen: true)
            } onControlShiftTab: {
                store.switchToPreviousRecentTab(keepsPreviewOpen: true)
            } onControlReleased: {
                store.finishTabSwitcherInteraction()
            } onCommandDigit: { digit in
                store.switchToTab(at: digit)
            } onControlDigit: { digit in
                store.switchToSpace(at: digit)
            } onGoBack: {
                store.goBack()
            } onGoForward: {
                store.goForward()
            } onZoomIn: {
                store.zoomInActiveTab()
            } onZoomOut: {
                store.zoomOutActiveTab()
            } onAddSplit: {
                addSplitView()
            } onCloseSplit: {
                store.closeSplitView()
            }
        )
        // isCommandPalettePresented deliberately has no .animation(value:)
        // here — the palette animates in via withAnimation at the present
        // call sites only, so its dismissal is never an animated removal
        // (see BrowserStore.presentCommandPalette).
        .animation(.easeOut(duration: 0.14), value: store.isTabSwitcherPresented)
        .animation(.easeOut(duration: 0.16), value: store.mediaControllerTabID)
        .animation(.easeOut(duration: 0.18), value: isSidebarPresented)
        .animation(.easeOut(duration: 0.18), value: isSidebarVisible)
        .animation(.easeOut(duration: 0.18), value: isAISidebarVisible)
        .focusedSceneValue(\.browserCommandActions, browserCommandActions)
        .alert(
            "Relaunch Candoa",
            isPresented: Binding(
                get: { store.syncRestartMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        store.syncRestartMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                store.syncRestartMessage = nil
            }
        } message: {
            Text(store.syncRestartMessage ?? "")
        }
        .onAppear {
            updateService.startCheckingForUpdates()
        }
        .onDisappear {
            store.flushSession()
            updateService.stopCheckingForUpdates()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.flushSession()
            }
        }
    }

    private var browserCommandActions: BrowserCommandActions {
        BrowserCommandActions(
            newTab: openNewTabFlow,
            focusAddressBar: store.focusAddressBar,
            openCommandPalette: store.openCommandPalette,
            toggleSidebar: toggleSidebar,
            toggleAISidebar: toggleAISidebar,
            reloadTab: store.reloadActiveTab,
            goBack: store.goBack,
            goForward: store.goForward,
            closeCurrentTab: closeTabOrWindow,
            nextTab: store.switchToNextTab,
            previousTab: store.switchToPreviousTab,
            nextSpace: store.switchToNextSpace,
            previousSpace: store.switchToPreviousSpace,
            reopenClosedTab: store.reopenLastClosedTab,
            pinOrUnpinTab: store.togglePinForActiveTab,
            clearUnpinnedTabs: store.clearUnpinnedTabs,
            copyURL: { store.copyActiveTabURL() },
            copyURLAsMarkdown: { store.copyActiveTabURL(asMarkdown: true) },
            findInPage: store.showFindBar,
            findNext: store.findNext,
            findPrevious: store.findPrevious,
            zoomIn: store.zoomInActiveTab,
            zoomOut: store.zoomOutActiveTab,
            resetZoom: store.resetZoomForActiveTab,
            addSplitView: addSplitView,
            closeSplitView: store.closeSplitView,
            isWorkspaceICloudSyncEnabled: store.iCloudWorkspaceSyncEnabled,
            isHistoryICloudSyncEnabled: store.iCloudHistorySyncEnabled,
            setWorkspaceICloudSyncEnabled: store.setWorkspaceICloudSyncEnabled,
            setHistoryICloudSyncEnabled: store.setHistoryICloudSyncEnabled
        )
    }

    private var sidebarLayout: some View {
        HStack(spacing: 0) {
            SidebarView(
                store: store,
                availableUpdate: updateService.availableUpdate,
                showsWindowControls: isSidebarPresented,
                windowControlsHiddenOffset: -sidebarTotalWidth,
                onUpdateBannerTapped: {
                    updateService.openAvailableUpdate()
                },
                onToggleSidebar: toggleSidebar
            )
                .frame(width: sidebarWidth)
        }
        .frame(width: sidebarTotalWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background {
            // Opaque backing only when the sidebar floats over the web view
            // (hover reveal). When pinned, it stays transparent so the
            // window-wide backdrop reads as one continuous surface.
            if isSidebarOverlaying {
                CandoaWindowBackdrop(store: store)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .shadow(
            color: Color.black.opacity(isSidebarOverlaying ? 0.22 : 0),
            radius: 16,
            x: 3,
            y: 0
        )
    }

    private func toggleSidebar() {
        if isSidebarVisible {
            isSidebarVisible = false
            isSidebarHoverRevealed = false
            isSidebarRevealSuppressed = true
        } else {
            isSidebarVisible = true
            isSidebarHoverRevealed = false
            isSidebarRevealSuppressed = false
        }
    }

    private func toggleAISidebar() {
        isAISidebarVisible.toggle()
    }

    private func openNewTabFlow() {
        store.openNewTabCommandPalette()
    }

    private func addSplitView() {
        guard !store.isSplitViewEnabled else { return }
        store.toggleSplitView()
    }

    private func closeTabOrWindow() {
        if store.visibleTabsForActiveSpace.count > 1 {
            store.closeCurrentTab()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}

private struct AISidebarView: View {
    @ObservedObject var store: BrowserStore
    let onClose: () -> Void

    @State private var prompt = ""
    @State private var messages: [AISidebarMessage] = []
    @State private var mentionedContext: [AISidebarContextMention] = []
    @State private var isMentionMenuPresented = false
    @State private var isFileImporterPresented = false
    @State private var streamTask: Task<Void, Never>?
    @FocusState private var isPromptFocused: Bool

    private let suggestions = [
        AISidebarSuggestion(title: "Summarize this page", prompt: "Summarize this page", symbolName: "doc.text"),
        AISidebarSuggestion(title: "Find key details", prompt: "Find the key details on this page", symbolName: "list.bullet"),
        AISidebarSuggestion(title: "Explain this simply", prompt: "Explain this page simply", symbolName: "text.bubble"),
        AISidebarSuggestion(title: "Suggest useful questions", prompt: "Suggest useful questions I can ask about this page", symbolName: "questionmark.bubble")
    ]

    private var activePageTitle: String {
        let title = store.activeTab?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Current Page" : title
    }

    private var mentionQuery: String? {
        let text = prompt as NSString
        let selectedRange = NSApp.keyWindow?.firstResponder
            .flatMap { $0 as? NSTextView }?
            .selectedRange() ?? NSRange(location: text.length, length: 0)
        let cursorLocation = min(selectedRange.location, text.length)
        let prefix = text.substring(to: cursorLocation)
        guard let atRange = prefix.range(of: "@", options: .backwards) else { return nil }
        let token = String(prefix[atRange.upperBound...])
        guard token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return token
    }

    private var availableTabMentions: [BrowserTab] {
        let query = mentionQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tabs = store.visibleTabsForActiveSpace
        guard !query.isEmpty else { return tabs }
        return tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(query) ||
                (tab.url?.host(percentEncoded: false)?.localizedCaseInsensitiveContains(query) ?? false) ||
                (tab.url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var contextChips: [AISidebarContextChip] {
        [AISidebarContextChip(id: "current", title: activePageTitle, symbolName: "safari", isRemovable: false)] +
            mentionedContext.map { chip(for: $0) }
    }

    private var modelUnavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch CandoaFoundationModelsService.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                return reason
            }
        }
        #endif

        return "Ask needs Apple Intelligence before it can answer open-ended questions."
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            emptyState
                            suggestionList
                        } else {
                            ForEach(messages) { message in
                                AISidebarMessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(14)
                }
                .onChange(of: messages) { _, updatedMessages in
                    guard let lastID = updatedMessages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.14)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            contextStrip
            composer
        }
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(CandoaChromeStyle.sidebarBorder)
                .frame(width: 1)
        }
        .onAppear {
            DispatchQueue.main.async {
                isPromptFocused = true
            }
        }
        .onDisappear {
            cancelStream()
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.text, .plainText, .json, .sourceCode],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .accessibilityIdentifier("ask-sidebar")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CommandPaletteView.askTint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ask")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CandoaChromeStyle.sidebarText)

                Text(activePageTitle)
                    .font(.caption)
                    .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Close Ask Sidebar")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about this page")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CandoaChromeStyle.sidebarText)

            Text("Use the current tab as context when your question mentions this page.")
                .font(.system(size: 13))
                .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var contextStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(contextChips) { chip in
                    AISidebarContextChipView(chip: chip) {
                        removeMention(chip.id)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 8) {
            ForEach(suggestions) { suggestion in
                Button {
                    submitPrompt(suggestion.prompt)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CandoaChromeStyle.sidebarIcon)
                            .frame(width: 20)

                        Text(suggestion.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CandoaChromeStyle.sidebarText)
                            .lineLimit(1)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(CandoaChromeStyle.sidebarControlFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if isMentionMenuPresented {
                mentionMenu
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask a question about this page...", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(.system(size: 14))
                    .focused($isPromptFocused)
                    .onSubmit {
                        submitPrompt()
                    }
                    .onChange(of: prompt) { _, _ in
                        syncMentionMenu()
                    }

                Button {
                    showMentionMenuFromButton()
                } label: {
                    Image(systemName: "at")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Add Context")

                Button {
                    submitPrompt()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Ask")
            }
        }
        .padding(12)
        .background(CandoaChromeStyle.sidebarControlFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CandoaChromeStyle.sidebarControlStroke, lineWidth: 1)
        }
        .padding(12)
    }

    private var mentionMenu: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TABS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                .padding(.horizontal, 10)

            if !mentionedContext.contains(.allOpenTabs) {
                mentionButton(
                    title: "All open tabs",
                    detail: "\(store.visibleTabsForActiveSpace.count)",
                    symbolName: "rectangle.stack",
                    action: {
                        addMention(.allOpenTabs)
                    }
                )
            }

            ForEach(availableTabMentions.prefix(6)) { tab in
                mentionButton(
                    title: tab.title,
                    detail: tab.url?.host(percentEncoded: false),
                    symbolName: tab.faviconSymbol,
                    faviconData: tab.faviconData,
                    action: {
                        addMention(.tab(tab.id))
                    }
                )
            }

            Divider()

            Text("FILES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                .padding(.horizontal, 10)

            mentionButton(
                title: "Upload file from computer",
                detail: "Text files",
                symbolName: "doc.badge.plus",
                action: {
                    clearMentionToken()
                    isMentionMenuPresented = false
                    isFileImporterPresented = true
                }
            )
        }
        .padding(8)
        .background(CandoaChromeStyle.popoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CandoaChromeStyle.popoverBorder, lineWidth: 1)
        }
        .shadow(color: Color(nsColor: .shadowColor).opacity(0.18), radius: 16, y: 8)
    }

    private func mentionButton(
        title: String,
        detail: String?,
        symbolName: String,
        faviconData: Data? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AISidebarMentionIcon(symbolName: symbolName, faviconData: faviconData)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CandoaChromeStyle.sidebarText)
                        .lineLimit(1)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func submitPrompt(_ promptOverride: String? = nil) {
        let submittedPrompt = (promptOverride ?? prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        guard PaletteAskPromptPolicy.canSubmit(submittedPrompt, hasConversation: !messages.isEmpty) else { return }

        prompt = ""
        cancelStream()

        let recentTurns = recentTurns()
        messages.append(AISidebarMessage(role: .user, text: submittedPrompt, isStreaming: false))

        let responseID = UUID()
        messages.append(AISidebarMessage(id: responseID, role: .assistant, text: "", isStreaming: true))

        let contextMentions = mentionedContext
        let unavailableReason = modelUnavailableReason

        streamTask = Task {
            let pageContext = await combinedContext(for: contextMentions)

            #if canImport(FoundationModels)
            if #available(macOS 26.0, *), unavailableReason == nil {
                do {
                    var receivedText = false
                    for try await partialText in CandoaFoundationModelsService.streamResponse(
                        to: submittedPrompt,
                        context: pageContext,
                        recentTurns: recentTurns
                    ) {
                        if Task.isCancelled { return }

                        await MainActor.run {
                            guard let index = messages.firstIndex(where: { $0.id == responseID }) else { return }
                            messages[index].text = partialText
                            receivedText = receivedText || !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                    }

                    await MainActor.run {
                        guard let index = messages.firstIndex(where: { $0.id == responseID }) else { return }
                        if !receivedText {
                            messages[index].text = CandoaAskDrafts.response(for: submittedPrompt, context: pageContext)
                        }
                        messages[index].isStreaming = false
                        streamTask = nil
                    }
                    return
                } catch {
                    await streamLocalResponse(
                        CandoaAskDrafts.response(for: submittedPrompt, context: pageContext),
                        into: responseID
                    )
                    return
                }
            }
            #endif

            await streamLocalResponse(
                CandoaAskDrafts.response(
                    for: submittedPrompt,
                    context: pageContext,
                    modelUnavailableReason: unavailableReason
                ),
                into: responseID
            )
        }
    }

    private func combinedContext(for mentions: [AISidebarContextMention]) async -> CandoaAIPageContext {
        let currentContext = await store.activeAIPageContext()
        var sections: [String] = []

        sections.append(contextSection(title: "Current page", context: currentContext))

        for mention in mentions {
            switch mention {
            case .allOpenTabs:
                let tabLines = store.visibleTabsForActiveSpace.map { tab in
                    let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : tab.title
                    return "- \(title): \(tab.url?.absoluteString ?? "No URL")"
                }
                sections.append("All open tabs:\n\(tabLines.joined(separator: "\n"))")
            case .tab(let tabID):
                guard tabID != store.activeTabID else { continue }
                let tabContext = await store.aiPageContext(for: tabID)
                sections.append(contextSection(title: "Mentioned tab", context: tabContext))
            case .file(let fileContext):
                sections.append("Uploaded file: \(fileContext.name)\n\(fileContext.text)")
            }
        }

        let combinedText = sections
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        return CandoaAIPageContext(
            title: currentContext.title,
            url: currentContext.url,
            text: combinedText.isEmpty ? currentContext.text : combinedText
        )
    }

    private func contextSection(title: String, context: CandoaAIPageContext) -> String {
        var lines = ["\(title):"]
        if let pageTitle = context.title, !pageTitle.isEmpty {
            lines.append("Title: \(pageTitle)")
        }
        if let url = context.url, !url.isEmpty {
            lines.append("URL: \(url)")
        }
        if let text = context.text, !text.isEmpty {
            lines.append("Text excerpt:\n\(text)")
        }
        return lines.joined(separator: "\n")
    }

    private func syncMentionMenu() {
        isMentionMenuPresented = mentionQuery != nil
    }

    private func showMentionMenuFromButton() {
        if mentionQuery == nil {
            prompt += prompt.hasSuffix(" ") || prompt.isEmpty ? "@" : " @"
        }
        isMentionMenuPresented = true
        isPromptFocused = true
    }

    private func addMention(_ mention: AISidebarContextMention) {
        guard !mentionedContext.contains(mention) else {
            clearMentionToken()
            isMentionMenuPresented = false
            return
        }

        mentionedContext.append(mention)
        clearMentionToken()
        isMentionMenuPresented = false
        isPromptFocused = true
    }

    private func removeMention(_ chipID: String) {
        mentionedContext.removeAll { chip(for: $0).id == chipID }
    }

    private func chip(for mention: AISidebarContextMention) -> AISidebarContextChip {
        switch mention {
        case .allOpenTabs:
            return AISidebarContextChip(
                id: "all-open-tabs",
                title: "All open tabs",
                symbolName: "rectangle.stack",
                isRemovable: true
            )
        case .tab(let id):
            let tabTitle = store.tabs.first { $0.id == id }?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return AISidebarContextChip(
                id: "tab-\(id.uuidString)",
                title: tabTitle?.isEmpty == false ? tabTitle! : "Mentioned tab",
                symbolName: "macwindow",
                isRemovable: true
            )
        case .file(let fileContext):
            return AISidebarContextChip(
                id: "file-\(fileContext.id.uuidString)",
                title: fileContext.name,
                symbolName: "doc.text",
                isRemovable: true
            )
        }
    }

    private func clearMentionToken() {
        guard mentionQuery != nil else { return }
        let text = prompt as NSString
        let selectedRange = NSApp.keyWindow?.firstResponder
            .flatMap { $0 as? NSTextView }?
            .selectedRange() ?? NSRange(location: text.length, length: 0)
        let cursorLocation = min(selectedRange.location, text.length)
        let prefix = text.substring(to: cursorLocation)
        guard prefix.range(of: "@", options: .backwards) != nil else { return }

        let nsAtLocation = (prefix as NSString).range(of: "@", options: .backwards).location
        let replacementRange = NSRange(location: nsAtLocation, length: cursorLocation - nsAtLocation)
        prompt = text.replacingCharacters(in: replacementRange, with: "")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let trimmed = contents
            .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = String(trimmed.prefix(8000))
        guard !excerpt.isEmpty else { return }

        addMention(.file(AISidebarFileContext(name: url.lastPathComponent, text: excerpt)))
    }

    @MainActor
    private func streamLocalResponse(_ response: String, into responseID: UUID) async {
        guard let index = messages.firstIndex(where: { $0.id == responseID }) else { return }
        messages[index].text = ""
        messages[index].isStreaming = true

        for chunk in response.split(separator: " ", omittingEmptySubsequences: false).enumerated().map({ $0.offset == 0 ? String($0.element) : " \($0.element)" }) {
            if Task.isCancelled { return }

            do {
                try await Task.sleep(nanoseconds: 24_000_000)
            } catch {
                return
            }

            guard let index = messages.firstIndex(where: { $0.id == responseID }) else { return }
            messages[index].text += chunk
        }

        guard let index = messages.firstIndex(where: { $0.id == responseID }) else { return }
        messages[index].isStreaming = false
        streamTask = nil
    }

    private func recentTurns() -> [CandoaAIConversationTurn] {
        messages.compactMap { message in
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return CandoaAIConversationTurn(role: message.role.conversationRole, text: text)
        }
    }

    private func cancelStream() {
        streamTask?.cancel()
        streamTask = nil

        for index in messages.indices where messages[index].isStreaming {
            messages[index].isStreaming = false
        }
    }
}

private struct AISidebarMessageRow: View {
    let message: AISidebarMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser {
                Spacer(minLength: 42)
            }

            VStack(alignment: .leading, spacing: 6) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(isUser ? Color.white : CandoaChromeStyle.sidebarText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else if message.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("No response.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isUser ? CommandPaletteView.askTint : CandoaChromeStyle.sidebarControlFill)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            if !isUser {
                Spacer(minLength: 42)
            }
        }
    }
}

private struct AISidebarContextChipView: View {
    let chip: AISidebarContextChip
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: chip.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CandoaChromeStyle.sidebarIcon)

            Text(chip.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CandoaChromeStyle.sidebarText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160, alignment: .leading)

            if chip.isRemovable {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .help("Remove Context")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(CandoaChromeStyle.sidebarControlFill)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(CandoaChromeStyle.sidebarControlStroke, lineWidth: 1)
        }
    }
}

private struct AISidebarMentionIcon: View {
    let symbolName: String
    var faviconData: Data?

    var body: some View {
        Group {
            if let faviconData, let image = NSImage(data: faviconData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CandoaChromeStyle.sidebarIcon)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct AISidebarContextChip: Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let isRemovable: Bool
}

private enum AISidebarContextMention: Equatable {
    case allOpenTabs
    case tab(UUID)
    case file(AISidebarFileContext)
}

private struct AISidebarFileContext: Equatable {
    var id = UUID()
    let name: String
    let text: String
}

private struct AISidebarMessage: Identifiable, Equatable {
    var id = UUID()
    let role: AISidebarMessageRole
    var text: String
    var isStreaming: Bool
}

private enum AISidebarMessageRole: Equatable {
    case user
    case assistant

    var conversationRole: CandoaAIConversationTurn.Role {
        switch self {
        case .user:
            return .user
        case .assistant:
            return .assistant
        }
    }
}

private struct AISidebarSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let prompt: String
    let symbolName: String
}

private enum CandoaAskDrafts {
    static func response(
        for prompt: String,
        context: CandoaAIPageContext,
        modelUnavailableReason: String? = nil
    ) -> String {
        let normalizedPrompt = PaletteAskPromptPolicy.normalizedText(prompt)
        let pageTitle = context.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageText = pageTitle?.isEmpty == false ? pageTitle! : "this page"

        if normalizedPrompt.contains("what is this page about") || normalizedPrompt.contains("summarize") {
            return summaryDraft(from: context.text) ?? "I could not read enough page text to summarize \(pageText)."
        }

        if normalizedPrompt.contains("key details") || normalizedPrompt.contains("key facts") {
            return summaryDraft(from: context.text) ?? "I could not read enough page text to find key details on \(pageText)."
        }

        if normalizedPrompt.contains("compare") {
            return "I can read the page now, but comparison still needs a product or option extractor. Try asking a specific question about one item on \(pageText)."
        }

        if normalizedPrompt.contains("explain") {
            return summaryDraft(from: context.text) ?? "I could not read enough page text to explain \(pageText)."
        }

        if normalizedPrompt.contains("suggest useful questions") {
            return """
            You could ask:
            - What matters most on this page?
            - What should I do next?
            - What is missing or unclear?
            """
        }

        if let modelUnavailableReason {
            return modelUnavailableReason
        }

        return "I can't answer that yet."
    }

    private static func summaryDraft(from pageText: String?) -> String? {
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

        let summary = sentences.map { "- \($0)" }.joined(separator: "\n")
        return summary.isEmpty ? String(normalizedText.prefix(420)) : summary
    }
}
