import AppKit
@preconcurrency import AVFoundation
@preconcurrency import Speech
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
    @State private var aiSidebarUITestingState = ""
    @State private var aiSidebarResizeStartWidth: CGFloat?
    @State private var miniPlayerOrigin: CGPoint?
    @State private var miniPlayerExpandedSize = MiniPlayerLayout.defaultExpandedSize
    @SceneStorage("candoa.aiSidebarWidth") private var aiSidebarWidth = 480.0
    private let sidebarWidth = CandoaChromeStyle.sidebarWidth
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
        let currentAISidebarWidth = clampedAISidebarWidth(CGFloat(aiSidebarWidth))

        ZStack(alignment: .leading) {
            WebViewContainer(store: store)
                .ignoresSafeArea(.container, edges: .top)
                .padding(.leading, isSidebarVisible ? sidebarTotalWidth : 0)
                .padding(.trailing, isAISidebarVisible ? currentAISidebarWidth : 0)

            sidebarLayout
                .offset(x: isSidebarPresented ? 0 : -sidebarTotalWidth)
                .zIndex(2)

            if isAISidebarVisible {
                AISidebarView(store: store, uiTestingState: $aiSidebarUITestingState) {
                    toggleAISidebar()
                }
                .frame(width: currentAISidebarWidth)
                .overlay(alignment: .leading) {
                    AISidebarResizeHandle(isResizing: aiSidebarResizeStartWidth != nil)
                        .frame(width: AISidebarLayout.resizeHandleHitWidth)
                        .offset(x: -AISidebarLayout.resizeHandleHitWidth / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onChanged { value in
                                    let startWidth = aiSidebarResizeStartWidth ?? currentAISidebarWidth
                                    if aiSidebarResizeStartWidth == nil {
                                        aiSidebarResizeStartWidth = currentAISidebarWidth
                                    }
                                    aiSidebarWidth = Double(clampedAISidebarWidth(startWidth - value.translation.width))
                                }
                                .onEnded { _ in
                                    aiSidebarResizeStartWidth = nil
                                }
                        )
                }
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

                VStack(spacing: 0) {
                    Text(stateDescription)
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .accessibilityLabel(stateDescription)
                        .accessibilityIdentifier("ui-testing-state")

                    Text(aiSidebarUITestingState)
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .accessibilityLabel(aiSidebarUITestingState)
                        .accessibilityIdentifier("ask-ui-testing-state")
                }
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

    private func clampedAISidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, AISidebarLayout.minWidth), AISidebarLayout.maxWidth)
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

private enum AISidebarLayout {
    static let minWidth: CGFloat = 360
    static let maxWidth: CGFloat = 720
    static let resizeHandleHitWidth: CGFloat = 12
}

private struct AISidebarResizeHandle: View {
    let isResizing: Bool
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(CandoaChromeStyle.sidebarTextSecondary.opacity(isActive ? 0.64 : 0.28))
                .frame(width: isActive ? 3 : 1)
                .padding(.vertical, 10)
        }
        .contentShape(Rectangle())
        .candoaAISidebarCursor(AISidebarResizeCursor.horizontal)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Resize Ask Sidebar")
    }

    private var isActive: Bool {
        isHovering || isResizing
    }
}

private enum AISidebarResizeCursor {
    static var horizontal: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.columnResize(directions: .all)
        }
        return .resizeLeftRight
    }
}

private struct AISidebarCursorHoverModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content
            .background(AISidebarCursorRectView(cursor: cursor))
            .onContinuousHover { phase in
                if case .active = phase {
                    cursor.set()
                }
            }
            .onHover { isHovering in
                if isHovering {
                    cursor.set()
                }
            }
    }
}

private struct AISidebarCursorRectView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> AISidebarCursorRectNSView {
        let view = AISidebarCursorRectNSView(frame: .zero)
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: AISidebarCursorRectNSView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class AISidebarCursorRectNSView: NSView {
    var cursor: NSCursor = .arrow {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}

private extension View {
    func candoaAISidebarCursor(_ cursor: NSCursor) -> some View {
        modifier(AISidebarCursorHoverModifier(cursor: cursor))
    }
}

private struct AISidebarView: View {
    @ObservedObject var store: BrowserStore
    @Binding var uiTestingState: String
    let onClose: () -> Void

    @StateObject private var speechController = AISidebarSpeechController()
    @State private var prompt = ""
    @State private var messages: [AISidebarMessage] = []
    @State private var mentionedContext: [AISidebarContextMention] = []
    @State private var isMentionMenuPresented = false
    @State private var isFileImporterPresented = false
    @State private var selectedMentionIndex = 0
    @State private var streamTask: Task<Void, Never>?
    @State private var includesCurrentPageContext = true
    @State private var lastSubmittedPageContext: CandoaAIPageContext?
    @FocusState private var isPromptFocused: Bool

    private var activePageTitle: String {
        let title = store.activeTab?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Current Page" : title
    }

    private var activePageSubtitle: String {
        store.activeTab?.url?.host(percentEncoded: false) ?? ""
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
        let query = trimmedMentionQuery
        let tabs = store.visibleTabsForActiveSpace
        guard !query.isEmpty else { return tabs }
        return tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(query) ||
                (tab.url?.host(percentEncoded: false)?.localizedCaseInsensitiveContains(query) ?? false) ||
                (tab.url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var trimmedMentionQuery: String {
        mentionQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var tabMentionOptions: [AISidebarMentionOption] {
        let allOpenTabsOption: [AISidebarMentionOption]
        if trimmedMentionQuery.isEmpty, !mentionedContext.contains(.allOpenTabs) {
            allOpenTabsOption = [
                AISidebarMentionOption(
                    id: "all-open-tabs",
                    title: "All open tabs",
                    detail: "\(store.visibleTabsForActiveSpace.count)",
                    symbolName: "rectangle.stack",
                    faviconData: nil,
                    action: .mention(.allOpenTabs)
                )
            ]
        } else {
            allOpenTabsOption = []
        }

        let tabOptions = availableTabMentions.prefix(6).map { tab in
            AISidebarMentionOption(
                id: "tab-\(tab.id.uuidString)",
                title: tab.title,
                detail: tab.url?.host(percentEncoded: false),
                symbolName: tab.faviconSymbol,
                faviconData: tab.faviconData,
                action: .mention(.tab(tab.id))
            )
        }

        return allOpenTabsOption + tabOptions + historyMentionOptions
    }

    private var historyMentionOptions: [AISidebarMentionOption] {
        guard !trimmedMentionQuery.isEmpty else { return [] }

        let openTabURLKeys = Set(store.visibleTabsForActiveSpace.compactMap {
            $0.url.map { normalizedMentionURLKey($0) }
        })

        return store.recentHistory(matching: trimmedMentionQuery, limit: 6)
            .filter { !openTabURLKeys.contains(normalizedMentionURLKey($0.url)) }
            .map { visit in
                let title = visit.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let host = visit.url.host(percentEncoded: false) ?? visit.url.absoluteString
                return AISidebarMentionOption(
                    id: "history-\(visit.id.uuidString)",
                    title: title.isEmpty ? host : title,
                    detail: "\(host) - History",
                    symbolName: FaviconService.shared.placeholderSymbol(for: visit.url),
                    faviconData: nil,
                    action: .mention(
                        .history(
                            AISidebarHistoryContext(
                                id: visit.id,
                                title: title.isEmpty ? host : title,
                                url: visit.url
                            )
                        )
                    )
                )
            }
    }

    private var fileMentionOptions: [AISidebarMentionOption] {
        guard trimmedMentionQuery.isEmpty else { return [] }
        return [
            AISidebarMentionOption(
                id: "upload-file",
                title: "Upload file from computer",
                detail: "Text files",
                symbolName: "doc.badge.plus",
                faviconData: nil,
                action: .uploadFile
            )
        ]
    }

    private var mentionOptions: [AISidebarMentionOption] {
        tabMentionOptions + fileMentionOptions
    }

    private var contextChips: [AISidebarContextChip] {
        let currentChip = includesCurrentPageContext ? [
            AISidebarContextChip(
                id: "current",
                title: activePageTitle,
                subtitle: activePageSubtitle,
                symbolName: store.activeTab?.faviconSymbol ?? "safari",
                faviconData: store.activeTab?.faviconData,
                isRemovable: true
            )
        ] : []

        return currentChip + mentionedContext.map { chip(for: $0) }
    }

    private var modelUnavailableReason: String? {
        if BrowserStore.isUITesting {
            return "Ask is using deterministic UI test responses."
        }

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
            topBar

            if messages.isEmpty {
                Spacer(minLength: 60)
                emptyState
                Spacer(minLength: 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(messages) { message in
                                AISidebarMessageRow(
                                    message: message,
                                    themeColorHex: store.activeThemeColorHexes.first
                                )
                                    .id(message.id)
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
            }

            composer
        }
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(CandoaChromeStyle.sidebarBorder)
                .frame(width: 1)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            uiTestingState = uiTestingAskState
            DispatchQueue.main.async {
                isPromptFocused = true
            }
        }
        .onDisappear {
            uiTestingState = ""
            cancelStream()
            speechController.cancelListening()
        }
        .onChange(of: uiTestingAskState) { _, state in
            uiTestingState = state
        }
        .onChange(of: store.activeTabID) {
            includesCurrentPageContext = true
        }
        .onChange(of: store.activeTab?.url) {
            includesCurrentPageContext = true
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.text, .plainText, .json, .sourceCode, .image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .accessibilityIdentifier("ask-sidebar")
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            AISidebarTopBarIconButton(
                symbolName: "square.and.pencil",
                helpText: "New Ask"
            ) {
                prompt = ""
                mentionedContext = []
                messages = []
                includesCurrentPageContext = true
                lastSubmittedPageContext = nil
                cancelStream()
            }

            Spacer()

            AISidebarTopBarIconButton(
                symbolName: "xmark",
                helpText: "Close Ask Sidebar",
                iconSize: 18
            ) {
                onClose()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Try asking")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                .padding(.horizontal, 2)

            ForEach(starterHints) { hint in
                AISidebarStarterHintButton(
                    hint: hint,
                    accentColor: askAccentColor
                ) {
                    submitPrompt(hint.prompt)
                }
            }
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var starterHints: [AISidebarStarterHint] {
        [
            AISidebarStarterHint(
                title: "Summarize this page",
                prompt: "Summarize this page.",
                symbolName: "doc.text"
            ),
            AISidebarStarterHint(
                title: "What are the key details?",
                prompt: "What are the key details on this page?",
                symbolName: "list.bullet"
            ),
            AISidebarStarterHint(
                title: "What should I do next?",
                prompt: "Based on this page, what should I do next?",
                symbolName: "arrow.turn.down.right"
            )
        ]
    }

    private var askAccentColor: Color {
        guard let hex = store.activeThemeColorHexes.first else {
            return Color.accentColor
        }
        return Color(spaceHex: hex)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if isMentionMenuPresented {
                mentionMenu
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            inputSurface
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var inputSurface: some View {
        let hasContext = !contextChips.isEmpty

        return VStack(alignment: .leading, spacing: hasContext ? 12 : 0) {
            if hasContext {
                contextTagRow
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask a question about this page...", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(.system(size: 14))
                    .focused($isPromptFocused)
                    .accessibilityIdentifier("ask-input-field")
                    .onSubmit {
                        if !performSelectedMention() {
                            submitPrompt()
                        }
                    }
                    .onChange(of: prompt) { _, _ in
                        syncMentionMenu()
                    }
                    .onKeyPress(.return) {
                        if performSelectedMention() {
                            return .handled
                        }

                        submitPrompt()
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        guard isMentionMenuPresented else { return .ignored }
                        moveMentionSelection(by: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard isMentionMenuPresented else { return .ignored }
                        moveMentionSelection(by: -1)
                        return .handled
                    }

                AISidebarComposerIconButton(symbolName: "plus", helpText: "Add Context") {
                    showMentionMenuFromButton()
                }

                AISidebarComposerIconButton(
                    symbolName: "mic",
                    helpText: speechController.isListening ? "Stop Listening" : "Dictate"
                ) {
                    handleMicButton()
                }

                AISidebarComposerSendButton(
                    isEnabled: !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    submitPrompt()
                }
                .accessibilityIdentifier("ask-send-button")
            }

            if speechController.isListening || speechController.statusMessage != nil {
                speechStatusRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, hasContext ? 12 : 9)
        .padding(.bottom, hasContext ? 10 : 9)
        .background {
            RoundedRectangle(cornerRadius: hasContext ? 16 : 14, style: .continuous)
                .fill(CandoaChromeStyle.sidebarControlFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: hasContext ? 16 : 14, style: .continuous)
                .stroke(CandoaChromeStyle.sidebarControlStroke, lineWidth: 1)
        }
    }

    private var speechStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(speechController.displayText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                .lineLimit(1)
                .padding(.leading, 4)

            HStack(spacing: 9) {
                Button {
                    speechController.cancelListening()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CandoaChromeStyle.sidebarIcon)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(!speechController.isListening)
                .help("Cancel Dictation")

                AISidebarSpeechWaveformView()
                    .frame(height: 18)

                Text(speechController.elapsedText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CandoaChromeStyle.sidebarIcon)
                    .frame(width: 38, alignment: .trailing)

                Button {
                    commitSpeechTranscript()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(speechController.isListening ? CandoaChromeStyle.sidebarTextSecondary : CandoaChromeStyle.sidebarIcon)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(!speechController.isListening)
                .help("Stop Dictation")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private var contextTagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(contextChips) { chip in
                    AISidebarContextChipView(chip: chip) {
                        removeMention(chip.id)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
    }

    private var mentionMenu: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TABS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                .padding(.horizontal, 10)

            ForEach(Array(tabMentionOptions.enumerated()), id: \.element.id) { index, option in
                mentionButton(
                    option: option,
                    isSelected: index == selectedMentionIndex
                )
            }

            if !fileMentionOptions.isEmpty {
                Divider()

                Text("FILES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                    .padding(.horizontal, 10)

                ForEach(Array(fileMentionOptions.enumerated()), id: \.element.id) { index, option in
                    mentionButton(
                        option: option,
                        isSelected: tabMentionOptions.count + index == selectedMentionIndex
                    )
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CandoaChromeStyle.popoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CandoaChromeStyle.popoverBorder, lineWidth: 1)
        }
        .shadow(color: Color(nsColor: .shadowColor).opacity(0.18), radius: 16, y: 8)
    }

    private func mentionButton(
        option: AISidebarMentionOption,
        isSelected: Bool
    ) -> some View {
        AISidebarMentionButton(
            title: option.title,
            detail: option.detail,
            symbolName: option.symbolName,
            faviconData: option.faviconData,
            isSelected: isSelected,
            action: {
                runMentionOption(option)
            }
        )
    }

    private var uiTestingAskState: String {
        let composerChipText = contextChips
            .map { "\($0.title)|\($0.subtitle)" }
            .joined(separator: ",")
        let lastUserText = messages.last { $0.role == .user }?.text ?? ""
        let lastAssistantText = messages.last { $0.role == .assistant }?.text ?? ""
        let messageText = messages.enumerated()
            .map { index, message in
                let role = message.role == .user ? "user" : "assistant"
                let sentChipText = message.contextChips
                    .map { "\($0.title)|\($0.subtitle)" }
                    .joined(separator: ",")
                return "\(index):\(role):chips=[\(sentChipText)]:text=\(message.text)"
            }
            .joined(separator: "||")

        return "composerChips=[\(composerChipText)];lastUser=[\(lastUserText)];lastAssistant=[\(lastAssistantText)];messages=[\(messageText)]"
    }

    private func submitPrompt(_ promptOverride: String? = nil) {
        let submittedPrompt = (promptOverride ?? prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        guard CandoaAskPromptPolicy.canSubmit(submittedPrompt, hasConversation: !messages.isEmpty) else { return }

        prompt = ""
        cancelStream()

        let submittedContextChips = contextChips.map {
            AISidebarContextChip(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                symbolName: $0.symbolName,
                faviconData: $0.faviconData,
                isRemovable: false
            )
        }
        let contextMentions = mentionedContext
        let normalizedSubmittedPrompt = CandoaAskPromptPolicy.normalizedText(submittedPrompt)
        let existingRecentTurns = recentTurns()
        let shouldRefreshCurrentPageContext = CandoaAskDrafts.asksAboutVisibleControl(
            normalizedSubmittedPrompt,
            recentTurns: existingRecentTurns
        )
        let includesCurrentPage = includesCurrentPageContext || shouldRefreshCurrentPageContext
        let currentPageTabID = includesCurrentPage ? store.activeTabID : nil
        let inheritedPageContext = lastSubmittedPageContext
        let shouldUseCurrentContextOnly = !submittedContextChips.isEmpty
            && CandoaAskDrafts.referencesCurrentPage(normalizedSubmittedPrompt)
        let recentTurns = shouldUseCurrentContextOnly ? [] : existingRecentTurns

        messages.append(AISidebarMessage(
            role: .user,
            text: submittedPrompt,
            isStreaming: false,
            contextChips: submittedContextChips
        ))

        let responseID = UUID()
        messages.append(AISidebarMessage(id: responseID, role: .assistant, text: "", isStreaming: true))

        let unavailableReason = modelUnavailableReason
        mentionedContext = []
        includesCurrentPageContext = false
        isMentionMenuPresented = false

        streamTask = Task {
            let submittedPageContext = await combinedContext(
                for: contextMentions,
                currentPageTabID: currentPageTabID
            )
            let pageContext = submittedPageContext.hasAttachedContext
                ? submittedPageContext
                : inheritedPageContext ?? submittedPageContext

            if submittedPageContext.hasAttachedContext {
                await MainActor.run {
                    lastSubmittedPageContext = submittedPageContext
                }
            }

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
                            messages[index].text = CandoaAskDrafts.response(
                                for: submittedPrompt,
                                context: pageContext,
                                recentTurns: recentTurns
                            )
                        }
                        messages[index].isStreaming = false
                        streamTask = nil
                    }
                    return
                } catch {
                    await streamLocalResponse(
                        CandoaAskDrafts.response(
                            for: submittedPrompt,
                            context: pageContext,
                            recentTurns: recentTurns
                        ),
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
                    recentTurns: recentTurns,
                    modelUnavailableReason: unavailableReason
                ),
                into: responseID
            )
        }
    }

    private func combinedContext(
        for mentions: [AISidebarContextMention],
        currentPageTabID: UUID?
    ) async -> CandoaAIPageContext {
        let currentContext = currentPageTabID != nil
            ? await store.aiPageContext(for: currentPageTabID)
            : CandoaAIPageContext(title: nil, url: nil, text: nil)
        var sections: [String] = []

        if currentPageTabID != nil, !mentions.isEmpty {
            sections.append(contextSection(title: "Current page", context: currentContext))
        }

        for mention in mentions {
            switch mention {
            case .allOpenTabs:
                let tabLines = store.visibleTabsForActiveSpace.map { tab in
                    let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : tab.title
                    return "- \(title): \(tab.url?.absoluteString ?? "No URL")"
                }
                sections.append("All open tabs:\n\(tabLines.joined(separator: "\n"))")
            case .tab(let tabID):
                guard tabID != currentPageTabID else { continue }
                let tabContext = await store.aiPageContext(for: tabID)
                sections.append(contextSection(title: "Mentioned tab", context: tabContext))
            case .history(let historyContext):
                sections.append(
                    """
                    History page:
                    Title: \(historyContext.title)
                    URL: \(historyContext.url.absoluteString)
                    """
                )
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
        selectedMentionIndex = 0
    }

    private func showMentionMenuFromButton() {
        if mentionQuery == nil {
            prompt += prompt.hasSuffix(" ") || prompt.isEmpty ? "@" : " @"
        }
        isMentionMenuPresented = true
        selectedMentionIndex = 0
        isPromptFocused = true
    }

    private func moveMentionSelection(by delta: Int) {
        let count = mentionOptions.count
        guard count > 0 else { return }
        selectedMentionIndex = ((selectedMentionIndex + delta) % count + count) % count
    }

    private func performSelectedMention() -> Bool {
        guard isMentionMenuPresented, mentionOptions.indices.contains(selectedMentionIndex) else {
            return false
        }

        runMentionOption(mentionOptions[selectedMentionIndex])
        return true
    }

    private func runMentionOption(_ option: AISidebarMentionOption) {
        switch option.action {
        case .mention(let mention):
            addMention(mention)
        case .uploadFile:
            clearMentionToken()
            isMentionMenuPresented = false
            isFileImporterPresented = true
        }
    }

    private func handleMicButton() {
        if speechController.isListening {
            commitSpeechTranscript()
            return
        }

        Task {
            await speechController.startListening()
        }
    }

    private func commitSpeechTranscript() {
        let transcript = speechController.stopListening()
        guard !transcript.isEmpty else { return }

        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt = transcript
        } else {
            prompt += prompt.hasSuffix(" ") ? transcript : " \(transcript)"
        }
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
        if chipID == "current" {
            includesCurrentPageContext = false
            return
        }

        mentionedContext.removeAll { chip(for: $0).id == chipID }
    }

    private func chip(for mention: AISidebarContextMention) -> AISidebarContextChip {
        switch mention {
        case .allOpenTabs:
            return AISidebarContextChip(
                id: "all-open-tabs",
                title: "All open tabs",
                subtitle: "\(store.visibleTabsForActiveSpace.count) tabs",
                symbolName: "rectangle.stack",
                faviconData: nil,
                isRemovable: true
            )
        case .tab(let id):
            let tab = store.tabs.first { $0.id == id }
            let tabTitle = tab?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return AISidebarContextChip(
                id: "tab-\(id.uuidString)",
                title: tabTitle?.isEmpty == false ? tabTitle! : "Mentioned tab",
                subtitle: tab?.url?.host(percentEncoded: false) ?? "",
                symbolName: tab?.faviconSymbol ?? "macwindow",
                faviconData: tab?.faviconData,
                isRemovable: true
            )
        case .history(let historyContext):
            return AISidebarContextChip(
                id: "history-\(historyContext.id.uuidString)",
                title: historyContext.title,
                subtitle: historyContext.url.host(percentEncoded: false) ?? "History",
                symbolName: FaviconService.shared.placeholderSymbol(for: historyContext.url),
                faviconData: nil,
                isRemovable: true
            )
        case .file(let fileContext):
            return AISidebarContextChip(
                id: "file-\(fileContext.id.uuidString)",
                title: fileContext.name,
                subtitle: "Uploaded file",
                symbolName: "doc.text",
                faviconData: nil,
                isRemovable: true
            )
        }
    }

    private func normalizedMentionURLKey(_ url: URL) -> String {
        var key = url.absoluteString.lowercased()
        if key.hasSuffix("/") {
            key.removeLast()
        }
        return key
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

        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if contentType?.conforms(to: .image) == true {
            guard
                let image = NSImage(contentsOf: url),
                let recognizedText = CandoaImageTextRecognizer.recognizedText(in: image)
            else {
                return
            }

            addMention(
                .file(
                    AISidebarFileContext(
                        name: url.lastPathComponent,
                        text: "Uploaded image OCR text:\n\(recognizedText)"
                    )
                )
            )
            return
        }

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

private struct AISidebarStarterHint: Identifiable, Equatable {
    let title: String
    let prompt: String
    let symbolName: String

    var id: String { prompt }
}

private struct AISidebarStarterHintButton: View {
    let hint: AISidebarStarterHint
    let accentColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: hint.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accentColor)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(accentColor.opacity(isHovered ? 0.18 : 0.12))
                    }

                Text(hint.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CandoaChromeStyle.sidebarText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? CandoaChromeStyle.sidebarControlFillHover : CandoaChromeStyle.sidebarControlFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CandoaChromeStyle.sidebarControlStroke, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovered = hovering
            }
        }
    }
}

private struct AISidebarTopBarIconButton: View {
    let symbolName: String
    let helpText: String
    var iconSize: CGFloat = 15
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: iconSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CandoaChromeStyle.sidebarIcon.opacity(isHovered ? 0.92 : 0.72))
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? CandoaChromeStyle.sidebarControlFillHover : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovered = hovering
            }
        }
    }
}

private struct AISidebarMessageRow: View {
    let message: AISidebarMessage
    let themeColorHex: String?

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser {
                Spacer(minLength: 42)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 7) {
                if isUser, !message.contextChips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.contextChips.prefix(2)) { chip in
                            AISidebarSentContextChipView(chip: chip)
                        }

                        if message.contextChips.count > 2 {
                            Text("+\(message.contextChips.count - 2)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(CandoaChromeStyle.sidebarControlFill)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.system(size: 13.5))
                            .foregroundStyle(messageForeground)
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
                .background(messageBackground)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            if !isUser {
                Spacer(minLength: 42)
            }
        }
    }

    private var messageBackground: Color {
        guard isUser else { return CandoaChromeStyle.sidebarControlFill }
        guard let themeColorHex else { return CandoaChromeStyle.sidebarControlFillActive }
        return Color(spaceHex: themeColorHex).opacity(0.82)
    }

    private var messageForeground: Color {
        guard isUser else { return CandoaChromeStyle.sidebarText }
        guard let themeColorHex else { return CandoaChromeStyle.sidebarText }
        return CandoaChromeStyle.prefersDarkForeground(forSpaceHex: themeColorHex)
            ? Color.black.opacity(0.84)
            : Color.white.opacity(0.92)
    }
}

private struct AISidebarSentContextChipView: View {
    let chip: AISidebarContextChip

    var body: some View {
        HStack(spacing: 6) {
            AISidebarMentionIcon(symbolName: chip.symbolName, faviconData: chip.faviconData)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(chip.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CandoaChromeStyle.sidebarText)
                    .lineLimit(1)

                if !chip.subtitle.isEmpty {
                    Text(chip.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .frame(maxWidth: 150, alignment: .leading)
        .background(CandoaChromeStyle.sidebarControlFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

@MainActor
private final class AISidebarSpeechController: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var statusMessage: String?
    @Published private(set) var elapsedText = "00:00"

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var elapsedTask: Task<Void, Never>?
    private var startedAt: Date?

    var displayText: String {
        if !transcript.isEmpty {
            return transcript
        }
        return statusMessage ?? "Listening..."
    }

    func startListening() async {
        guard !isListening else { return }

        transcript = ""
        statusMessage = "Listening..."
        elapsedText = "00:00"

        guard await requestSpeechAuthorization() else {
            statusMessage = "Speech recognition is not allowed."
            return
        }

        guard await requestMicrophoneAuthorization() else {
            statusMessage = "Microphone access is not allowed."
            return
        }

        guard speechRecognizer?.isAvailable == true else {
            statusMessage = "Speech recognition is unavailable."
            return
        }

        do {
            try startAudioRecognition()
        } catch {
            stopAudioRecognition()
            statusMessage = "Could not start dictation."
        }
    }

    @discardableResult
    func stopListening() -> String {
        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopAudioRecognition()
        statusMessage = nil
        return finalTranscript
    }

    func cancelListening() {
        transcript = ""
        stopAudioRecognition()
        statusMessage = nil
    }

    private func startAudioRecognition() throws {
        stopAudioRecognition()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
        startedAt = Date()
        startElapsedClock()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stopAudioRecognition()
                }
            }
        }
    }

    private func stopAudioRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        elapsedTask?.cancel()
        elapsedTask = nil
        startedAt = nil
        isListening = false
    }

    private func startElapsedClock() {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.updateElapsedText()
                }
            }
        }
    }

    private func updateElapsedText() {
        guard let startedAt else {
            elapsedText = "00:00"
            return
        }

        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        elapsedText = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { isAllowed in
                    continuation.resume(returning: isAllowed)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

private struct AISidebarComposerIconButton: View {
    let symbolName: String
    let helpText: String
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foregroundStyle)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(backgroundFill)
                }
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(helpText)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovered = hovering
            }
        }
    }

    private var foregroundStyle: Color {
        guard isEnabled else { return CandoaChromeStyle.sidebarIcon.opacity(0.55) }
        return isHovered ? CandoaChromeStyle.sidebarTextSecondary : CandoaChromeStyle.sidebarIcon
    }

    private var backgroundFill: Color {
        guard isEnabled, isHovered else { return Color.clear }
        return CandoaChromeStyle.sidebarControlFillHover
    }
}

private struct AISidebarComposerSendButton: View {
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background {
                    Circle()
                        .fill(backgroundFill)
                }
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help("Ask")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovered = hovering
            }
        }
    }

    private var iconColor: Color {
        isEnabled ? Color.black.opacity(0.88) : CandoaChromeStyle.sidebarIcon.opacity(0.58)
    }

    private var backgroundFill: Color {
        guard isEnabled else { return CandoaChromeStyle.sidebarControlFillHover }
        return isHovered ? Color.white.opacity(0.82) : Color.white.opacity(0.96)
    }
}

private struct AISidebarSpeechWaveformView: View {
    private let levels: [CGFloat] = [
        0.12, 0.18, 0.10, 0.22, 0.34, 0.16, 0.42, 0.28, 0.58, 0.36,
        0.70, 0.30, 0.44, 0.24, 0.54, 0.20, 0.48, 0.34, 0.64, 0.26,
        0.40, 0.18, 0.32, 0.22, 0.52, 0.30, 0.46, 0.28, 0.68, 0.36,
        0.24, 0.20, 0.38, 0.18, 0.28, 0.14
    ]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(CandoaChromeStyle.sidebarTextSecondary.opacity(index % 5 == 0 ? 0.86 : 0.72))
                        .frame(width: 1.5, height: max(2, proxy.size.height * levels[index]))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct AISidebarMentionButton: View {
    let title: String
    let detail: String?
    let symbolName: String
    let faviconData: Data?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AISidebarMentionIcon(symbolName: symbolName, faviconData: faviconData, isSelected: isSelected)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : CandoaChromeStyle.sidebarText)
                        .lineLimit(1)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.72) : CandoaChromeStyle.sidebarTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovered = hovering
            }
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor
        }

        return isHovered ? CandoaChromeStyle.sidebarControlFillHover : Color.clear
    }
}

private struct AISidebarContextChipView: View {
    let chip: AISidebarContextChip
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var isRemoveHovered = false

    var body: some View {
        HStack(spacing: 10) {
            AISidebarMentionIcon(symbolName: chip.symbolName, faviconData: chip.faviconData)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(chip.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CandoaChromeStyle.sidebarText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !chip.subtitle.isEmpty {
                    Text(chip.subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: 130, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 46)
        .background(Color.primary.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CandoaChromeStyle.sidebarControlStroke, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if chip.isRemovable && isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isRemoveHovered ? Color.black.opacity(0.86) : Color.white.opacity(0.9))
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(isRemoveHovered ? Color.white.opacity(0.96) : Color.white.opacity(0.22))
                        )
                }
                .buttonStyle(.borderless)
                .offset(x: 8, y: -8)
                .help("Remove Context")
                .transition(.opacity)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.10)) {
                        isRemoveHovered = hovering
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
                if !hovering {
                    isRemoveHovered = false
                }
            }
        }
    }
}

private struct AISidebarMentionIcon: View {
    let symbolName: String
    var faviconData: Data?
    var isSelected = false

    var body: some View {
        Group {
            if let faviconData, let image = NSImage(data: faviconData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.86) : CandoaChromeStyle.sidebarIcon)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct AISidebarMentionOption: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let symbolName: String
    let faviconData: Data?
    let action: AISidebarMentionAction
}

private enum AISidebarMentionAction {
    case mention(AISidebarContextMention)
    case uploadFile
}

private struct AISidebarContextChip: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let faviconData: Data?
    let isRemovable: Bool
}

private enum AISidebarContextMention: Equatable {
    case allOpenTabs
    case tab(UUID)
    case history(AISidebarHistoryContext)
    case file(AISidebarFileContext)
}

private struct AISidebarHistoryContext: Equatable {
    let id: UUID
    let title: String
    let url: URL
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
    var contextChips: [AISidebarContextChip] = []
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

private enum CandoaAskDrafts {
    static func response(
        for prompt: String,
        context: CandoaAIPageContext,
        recentTurns: [CandoaAIConversationTurn] = [],
        modelUnavailableReason: String? = nil
    ) -> String {
        let normalizedPrompt = CandoaAskPromptPolicy.normalizedText(prompt)
        let visibleControlPrompt = visibleControlPrompt(
            normalizedPrompt,
            recentTurns: recentTurns
        )
        let pageTitle = context.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageText = pageTitle?.isEmpty == false ? pageTitle! : "this page"

        if !context.hasAttachedContext, referencesCurrentPage(normalizedPrompt) {
            return noContextDraft
        }

        if let controlAnswer = visibleControlAnswer(for: visibleControlPrompt, contextText: context.text) {
            return controlAnswer
        }

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

        if referencesCurrentPage(normalizedPrompt) {
            return summaryDraft(from: context.text) ?? "I could not read enough page text to summarize \(pageText)."
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

    private static var noContextDraft: String {
        """
        I can't see what you're currently looking at because no page context is attached to this message.

        Attach the current page, mention a tab with @, or share the URL and I can summarize it.
        """
    }

    static func referencesCurrentPage(_ normalizedPrompt: String) -> Bool {
        normalizedPrompt.contains("this page")
            || normalizedPrompt.contains("this website")
            || normalizedPrompt.contains("this site")
            || normalizedPrompt.contains("what about this")
            || normalizedPrompt.contains("what about that")
            || normalizedPrompt.contains("that page")
            || normalizedPrompt.contains("that website")
            || normalizedPrompt.contains("page about")
            || normalizedPrompt.contains("website about")
            || normalizedPrompt.contains("summarize")
            || normalizedPrompt.contains("key details")
            || normalizedPrompt.contains("key facts")
            || normalizedPrompt.contains("what should i do next")
    }

    private static func visibleControlAnswer(for normalizedPrompt: String, contextText: String?) -> String? {
        guard asksAboutVisibleControl(normalizedPrompt) else { return nil }

        let controlLines = visibleControlLines(from: contextText)
        guard !controlLines.isEmpty else {
            return "I do not have a visible controls scan for this page, so I cannot reliably say where that button is."
        }

        let matchingLines = controlLines.filter { line in
            let normalizedLine = CandoaAskPromptPolicy.normalizedText(line)
            if asksAboutSignIn(normalizedPrompt) {
                return normalizedLine.contains("sign in")
                    || normalizedLine.contains("signin")
                    || normalizedLine.contains("log in")
                    || normalizedLine.contains("login")
                    || normalizedLine.contains("account")
            }

            let promptWords = Set(normalizedPrompt
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
            )
            return promptWords.contains(where: { normalizedLine.contains($0) })
        }

        if matchingLines.isEmpty, asksAboutSignIn(normalizedPrompt) {
            return "I do not see a visible Sign in or login control in the scanned page controls. It may be hidden behind an account menu, offscreen, or loaded after another interaction."
        }

        guard let firstMatch = matchingLines.first else {
            return "I do not see that control in the scanned visible page controls."
        }

        return "I found this visible control: \(firstMatch.replacingOccurrences(of: "- ", with: "", options: .anchored))"
    }

    static func asksAboutVisibleControl(
        _ normalizedPrompt: String,
        recentTurns: [CandoaAIConversationTurn] = []
    ) -> Bool {
        asksAboutSignIn(normalizedPrompt)
            || normalizedPrompt.contains("button")
            || normalizedPrompt.contains("click")
            || normalizedPrompt.contains("where is")
            || normalizedPrompt.contains("where can")
            || (
                isRetryPrompt(normalizedPrompt)
                    && recentTurns.reversed().contains { turn in
                        guard case .user = turn.role else { return false }
                        return asksAboutVisibleControl(CandoaAskPromptPolicy.normalizedText(turn.text))
                    }
            )
    }

    private static func asksAboutSignIn(_ normalizedPrompt: String) -> Bool {
        normalizedPrompt.contains("sign in")
            || normalizedPrompt.contains("signin")
            || normalizedPrompt.contains("log in")
            || normalizedPrompt.contains("login")
            || normalizedPrompt.contains("sign button")
    }

    private static func visibleControlPrompt(
        _ normalizedPrompt: String,
        recentTurns: [CandoaAIConversationTurn]
    ) -> String {
        guard isRetryPrompt(normalizedPrompt) else { return normalizedPrompt }

        return recentTurns.reversed().compactMap { turn -> String? in
            guard case .user = turn.role else { return nil }
            let candidate = CandoaAskPromptPolicy.normalizedText(turn.text)
            return asksAboutVisibleControl(candidate) ? candidate : nil
        }.first ?? normalizedPrompt
    }

    private static func isRetryPrompt(_ normalizedPrompt: String) -> Bool {
        normalizedPrompt == "check again"
            || normalizedPrompt == "try again"
            || normalizedPrompt == "scan again"
            || normalizedPrompt == "look again"
            || normalizedPrompt == "look one more time"
            || normalizedPrompt == "can you check again"
            || normalizedPrompt == "please check again"
    }

    private static func visibleControlLines(from contextText: String?) -> [String] {
        guard let contextText else { return [] }
        guard let controlsRange = contextText.range(of: "Visible page controls and links:") else { return [] }

        return contextText[controlsRange.upperBound...]
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("- ") }
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
