import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let isPrivate: Bool
    @StateObject private var store: BrowserStore
    @StateObject private var updateService = AppUpdateService.shared
    @StateObject private var whatsNewService = WhatsNewService.shared

    init(isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        _store = StateObject(wrappedValue: BrowserStore(isPrivate: isPrivate))
    }
    @StateObject private var systemAppearance = SystemAppearanceObserver()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsOption.websiteAppearance) private var websiteAppearanceValue =
        WebsiteAppearance.automatic.rawValue
    @SceneStorage("talos.windowAutosaveID") private var windowAutosaveID = UUID().uuidString
    @State private var isSidebarVisible = true
    @State private var isSidebarHoverRevealed = false
    /// A closing sidebar keeps covering its lane until the page has laid out
    /// against it. WebKit reflows in another process, so the lane would
    /// otherwise stand empty beside a page still drawn at its old width.
    @State private var coversClosingSidebarLane = false
    @State private var closingSidebarLaneToken: UUID?
    /// The gap the page card leaves between itself and the sidebar
    /// (`WebViewContainer.surfacePadding`).
    private static let pageCardGutter: CGFloat = 8
    /// How long a closing sidebar will wait for the page before going anyway.
    /// Ordinary pages report in ~100ms and never reach this.
    private static let closingSidebarLaneCap = 150
    @State private var isSidebarRevealSuppressed = false
    @State private var isHistoryPresented = false
    @State private var miniPlayerOrigin: CGPoint? = MiniPlayerPersistence.loadOrigin()
    @State private var miniPlayerExpandedLongEdge = MiniPlayerPersistence.loadLongEdge()
    private let sidebarWidth = InterfaceStyle.sidebarWidth
    private let sidebarDividerWidth: CGFloat = 0

    private var activeThemeAppearance: SpaceThemeAppearance {
        store.spaceThemeAppearancePreview ?? store.activeSpace?.themeAppearance ?? .automatic
    }

    // SwiftUI latches the last explicit color scheme on its window; passing
    // nil ("no preference") never releases it. So "automatic" is resolved to
    // the live system appearance instead of nil — see SystemAppearanceObserver.
    // Private windows are always dark — the native macOS private-browsing
    // identity, matching Safari — regardless of system or Space appearance.
    private var resolvedColorScheme: ColorScheme {
        if isPrivate { return .dark }
        return activeThemeAppearance.colorScheme ?? systemAppearance.colorScheme
    }

    private var websiteAppearance: WebsiteAppearance {
        WebsiteAppearance(storedValue: websiteAppearanceValue)
    }

    /// True while a text field holds the keyboard — the address bar, a tab
    /// rename. AppKit hands those the field editor, so the
    /// responder is an NSTextView rather than the control itself.
    private var isEditingTextField: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
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
        isSidebarVisible || isSidebarHoverRevealed || coversClosingSidebarLane
    }

    private var webVisibleInterfaceInsets: BrowserInterfaceInsets {
        BrowserInterfaceInsets(leading: isSidebarVisible ? sidebarTotalWidth : 0)
    }

    /// The native bars hold a closing sidebar's lane until the cover lifts:
    /// they re-lay out in a single frame, so tracking the live insets slid
    /// their URL text under the still-covering sidebar, its tail peeking
    /// past the sidebar's edge for the length of the cover.
    private var barInterfaceInsets: BrowserInterfaceInsets {
        BrowserInterfaceInsets(
            leading: isSidebarVisible || coversClosingSidebarLane ? sidebarTotalWidth : 0
        )
    }

    private var isSidebarOverlaying: Bool {
        isSidebarHoverRevealed && !isSidebarVisible
    }

    /// Docked, the lane is transparent and the shared window backdrop shows
    /// through it. While the sidebar covers a lane it has already given up,
    /// the page beneath has widened into it, so the sidebar needs its own
    /// copy of that backdrop — the same one the hover overlay uses.
    private var paintsOwnSidebarBackdrop: Bool {
        isSidebarOverlaying || coversClosingSidebarLane
    }

    private var isFullWindowOnboardingPresented: Bool {
        store.isInitialOnboardingBlockingBrowsing
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if isFullWindowOnboardingPresented {
                InitialOnboardingCanvas(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                ZStack(alignment: .topTrailing) {
                    if isHistoryPresented {
                        HistoryView(
                            repository: store.historyRepository,
                            spaceID: store.activeSpaceID,
                            clearScope: store.isPrivate ? nil : ClearBrowsingDataPrompt.CurrentSpace(
                                id: store.activeSpaceID,
                                dataStoreID: store.dataStoreID(for: store.activeSpaceID)
                            ),
                            onOpen: { visit in
                                isHistoryPresented = false
                                store.navigateActiveTab(to: visit.url)
                            },
                            onOpenInNewTab: { visit in
                                isHistoryPresented = false
                                store.navigateNewTab(to: visit.url)
                            },
                            onCopyAddress: { visit in
                                store.copyURL(visit.url)
                            },
                            onDismiss: {
                                isHistoryPresented = false
                            }
                        )
                        .id(store.activeSpaceID)
                        .padding(.leading, isSidebarVisible ? sidebarTotalWidth : 0)
                        .tint(AppColor.accent)
                        .onChange(of: store.historyDismissRequestID) { _, _ in
                            isHistoryPresented = false
                        }
                    } else {
                        // Keep the WebKit host at one stable width when the
                        // sidebar toggles. WebKit paints through a remote
                        // layer; resizing that host exposes or stretches the
                        // previous frame before the WebContent process catches up
                        // and makes pages flash their scrollbars. The sidebar
                        // lane is reserved inside WebViewContainer instead.
                        WebViewContainer(
                            store: store,
                            visibleInterfaceInsets: webVisibleInterfaceInsets,
                            barInterfaceInsets: barInterfaceInsets,
                            onToggleSidebar: toggleSidebar
                        )
                    }
                }
                .ignoresSafeArea(
                    .container,
                    edges: isHistoryPresented ? [] : .top
                )

                sidebarLayout
                    // This subtree also coordinates AppKit's native window controls.
                    // One animatable progress value drives both the compositor
                    // translation and the embedded native traffic-light container.
                    // Separate SwiftUI/AppKit animations visibly drift apart.
                    .modifier(SidebarRevealEffect(
                        progress: isSidebarPresented ? 1 : 0,
                        hiddenOffset: -sidebarTotalWidth
                    ))
                    // A pinned show/hide must snap with the one-time WKWebView
                    // frame update above. Only the overlay hover reveal may slide;
                    // otherwise the sidebar temporarily separates from content.
                    .animation(.easeOut(duration: 0.18), value: isSidebarHoverRevealed)
                    .zIndex(2)
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
                // Centered on the page, not the window: the sidebar lane is
                // inset and the title-bar safe area is ignored, matching
                // where the web view actually is.
                TabSwitcherOverlay(store: store)
                    .padding(.leading, isSidebarVisible ? sidebarTotalWidth : 0)
                    .ignoresSafeArea(.container, edges: .top)
                    .zIndex(9)
            }

            if let hoveredLinkHref = store.hoveredLinkHref,
               !isFullWindowOnboardingPresented,
               !isHistoryPresented {
                LinkHoverPreviewPill(urlString: hoveredLinkHref)
                    .padding(.leading, (isSidebarVisible ? sidebarTotalWidth : 0) + 10)
                    .padding(.trailing, 10)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(8)
            }

            if let mediaTab = store.floatingMiniPlayerTab,
               let mediaState = store.floatingMiniPlayerState {
                // The player floats over the whole window — sidebar included,
                // like a PiP window over the browser — so it roams the full
                // content size; only the summon glide still needs to know
                // where the page lane is, since its start rect is
                // page-relative.
                GeometryReader { proxy in
                    let leadingInset = isSidebarVisible ? sidebarTotalWidth : 0
                    let pageLaneFrame = CGRect(
                        x: leadingInset,
                        y: 0,
                        width: max(1, proxy.size.width - leadingInset),
                        height: proxy.size.height
                    )

                    FloatingMiniPlayerContainer(
                        store: store,
                        tab: mediaTab,
                        state: mediaState,
                        availableSize: proxy.size,
                        pageLaneFrame: pageLaneFrame,
                        summon: store.pendingMiniPlayerSummon,
                        origin: $miniPlayerOrigin,
                        expandedLongEdge: $miniPlayerExpandedLongEdge
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
                .ignoresSafeArea(.container, edges: .top)
                // Leaving (back to its tab, or the media ending) is a plain
                // fade over the page — the page itself is already in place.
                .transition(.opacity)
                // Above the sidebar (2); only the modal overlays — link
                // pill, tab switcher, command palette — still cover it.
                .zIndex(7)
            }
        }
        .overlay {
            // Zen anchors its toast container at the window's absolute
            // top-right (8px in from both edges), floating over the title
            // bar — so the pill must escape the top safe area.
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .allowsHitTesting(false)

                VStack(alignment: .trailing, spacing: 8) {
                    if let toast = store.copiedURLToast {
                        CopiedURLToastView(
                            toast: toast,
                            onShareInteractionChanged: { store.setCopiedURLToastSharing($0) }
                        )
                        .onHover { store.setCopiedURLToastHovered($0) }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.01, anchor: .top),
                            removal: .scale(scale: 0.5, anchor: .top).combined(with: .opacity)
                        ))
                        .id(toast.id)
                    }
                }
                .padding(.top, CopiedURLToastView.windowEdgeSpacing)
                .padding(.trailing, CopiedURLToastView.windowEdgeSpacing)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .bottomTrailing) {
            if BrowserStore.isUITesting {
                let stateDescription = store.uiTestingStateDescription(sidebarVisible: isSidebarVisible)
                    + ";websiteAppearance=\(websiteAppearance.rawValue)"

                Text(stateDescription)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityLabel(stateDescription)
                    .accessibilityIdentifier("ui-testing-state")
            }
        }
        .sheet(isPresented: $store.isPrivacyReportPresented) {
            PrivacyReportView(onDismiss: { store.isPrivacyReportPresented = false })
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: store.copiedURLToast)
        .background {
            WindowBackdrop(store: store)
                .ignoresSafeArea()
        }
        .preferredColorScheme(resolvedColorScheme)
        .background(
            WindowInteractionConfigurator(
                autosaveName: "\(AppConfiguration.windowAutosaveNamePrefix).\(windowAutosaveID)",
                isPrivate: isPrivate,
                store: store
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
            } onReopenClosedTab: {
                store.reopenLastClosedTab()
            } onFocusAddressBar: {
                store.focusAddressBar()
            } onOpenCommandBar: {
                store.openCommandPalette()
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
            } onFindInPage: {
                showFind()
            } onFindNext: {
                store.findNext()
            } onFindPrevious: {
                store.findPrevious()
            } onEscape: {
                if store.isFindBarPresented {
                    store.dismissFindBar()
                    return true
                }
                // Reader is the next escape hatch down, but only when nothing
                // nearer owns the press: the palette and any field being
                // edited cancel themselves first. Otherwise Escape falls
                // through to the page, which needs it for its own dialogs and
                // for leaving HTML full screen.
                if store.isReaderActiveForActiveTab,
                   !store.isCommandPalettePresented,
                   !isEditingTextField {
                    store.hideReaderForActiveTab()
                    return true
                }
                return false
            } onReload: {
                store.reloadActiveTab()
            } onReloadFromOrigin: {
                store.reloadActiveTabFromOrigin()
            } onStopLoading: {
                store.stopLoadingActiveTabIfLoading()
            } onClearUnpinnedTabs: {
                store.clearUnpinnedTabs()
            } onControlTab: {
                store.switchToNextRecentTab(keepsPreviewOpen: true)
            } onControlShiftTab: {
                store.switchToPreviousRecentTab(keepsPreviewOpen: true)
            } onControlReleased: {
                store.finishTabSwitcherInteraction()
            } onTabSwitcherDelete: {
                store.closeHighlightedTabInTabSwitcher()
            } onTabSwitcherEscape: {
                store.cancelTabSwitcherInteraction()
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
            } onResetZoom: {
                store.resetZoomForActiveTab()
            } onNextTab: {
                store.switchToNextTab()
            } onPreviousTab: {
                store.switchToPreviousTab()
            } onNextSpace: {
                store.switchToNextSpace()
            } onPreviousSpace: {
                store.switchToPreviousSpace()
            } onToggleSplit: {
                toggleSplitView()
            } onSplitLayout: { layout in
                store.setSplitLayout(layout)
            } onZoomSplitPane: {
                store.toggleSplitPaneZoom()
            } onFocusSplitPane: { offset in
                store.focusAdjacentSplitPane(offset: offset)
            } onUnsplitPane: {
                store.unsplitFocusedPane()
            } onSplitWithTab: {
                store.openSplitWithCommandPalette()
            }
        )
        // isCommandPalettePresented deliberately has no .animation(value:)
        // here — the palette animates in via withAnimation at the present
        // call sites only, so its dismissal is never an animated removal
        // (see BrowserStore.presentCommandPalette).
        // Near-instant fade: the page underneath already switched on the
        // press, so any visible settle here would read as switching lag.
        .animation(.easeOut(duration: 0.08), value: store.isTabSwitcherPresented)
        // Keyed on presence, not value: moving between links swaps the text
        // instantly and only appear/disappear get the brief fade.
        .animation(.easeOut(duration: 0.1), value: store.hoveredLinkHref != nil)
        .animation(.easeOut(duration: 0.16), value: store.mediaControllerTabID)
        .focusedSceneValue(\.browserCommandActions, browserCommandActions)
        .onAppear {
            applyWebsiteAppearance()
            updateService.startCheckingForUpdates()
            store.applySplitPreviewFixtureIfNeeded()
            store.applySplitFixtureIfNeeded()
        }
        // Deferred off the appearance pass on purpose: presenting the palette
        // animates a published change, and making that change inside the
        // scene's first update loses the window SwiftUI is still building —
        // New Private Window opened nothing at all.
        .task {
            store.openPrivateWindowCommandBarIfNeeded()
        }
        .onOpenURL { url in
            store.openExternalURL(url)
        }
        .onDisappear {
            store.flushSession()
            updateService.stopCheckingForUpdates()
            if isPrivate {
                // The window is gone: tear down every web view and all
                // in-memory page residue now rather than waiting for the
                // store to deallocate.
                store.webCoordinator.purgeAllWebContent()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.flushSession()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSMenu.didBeginTrackingNotification
            )
        ) { notification in
            // The root menu posts once per menu-bar open: titles that mirror
            // inspector state (Show/Close Web Inspector, Start/Stop
            // recordings) catch up with changes made in the inspector's own
            // UI. The store only nudges observers when that state actually
            // drifted — an unconditional rebuild would strand "Reload Page
            // From Origin" as a drawn row of its own (#282).
            guard (notification.object as? NSMenu) === NSApp.mainMenu else { return }
            store.refreshDevelopMenuIfInspectorStateDrifted()
        }
        .onChange(of: store.pageLaneSettledTick) { _, _ in
            uncoverClosingSidebarLane()
        }
        .onChange(of: store.activeSpaceID) { _, _ in
            // A Space is its tabs, and they live in the sidebar. Switching
            // from the menu or the keyboard with the sidebar hidden would
            // otherwise change everything off-screen, so the switch brings
            // the sidebar back with it.
            revealSidebar()
        }
        .onChange(of: store.downloadsStore.items.first?.id) { _, newestItemID in
            // A new download (or a PDF-HUD save) with no visible response
            // reads as a dead button — the Dock already bounces the
            // Downloads stack (the modern system cue); the key window adds
            // the popover so the row is immediately visible. Phase/progress
            // updates keep the same newest id, so this fires once per
            // download.
            guard newestItemID != nil, controlActiveState == .key,
                  !store.isDownloadsPopoverPresented else { return }
            showDownloads()
        }
        .onChange(of: websiteAppearanceValue) { _, _ in
            applyWebsiteAppearance()
        }
        .onChange(of: systemAppearance.colorScheme) { _, _ in
            guard websiteAppearance == .automatic else { return }
            applyWebsiteAppearance()
        }
        .quickNoteActivity(for: store)
        // The dragged row's ghost, in the window's own top-left space —
        // which is what the drag source publishes — so the grab point stays
        // under the pointer exactly as it was when the row was picked up.
        .overlay(alignment: .topLeading) {
            if let ghost = store.tabDragGhost,
               let tab = store.tabs.first(where: { $0.id == ghost.tabID }) {
                TabDragGhostView(tab: tab, size: ghost.size)
                    // Hanging off the pointer, not centred on it: centred, the
                    // pill sat exactly on the drop line, and a line showing
                    // through a translucent pill is broken by the label —
                    // which reads as two drop marks instead of one.
                    .offset(
                        x: ghost.windowPoint.x + SidebarTabDragGhost.pointerOffset.width,
                        y: ghost.windowPoint.y + SidebarTabDragGhost.pointerOffset.height
                    )
                    .ignoresSafeArea()
            }
        }
    }

    private func applyWebsiteAppearance() {
        store.webCoordinator.updateWebsiteAppearance(
            websiteAppearance,
            systemUsesDarkAppearance: systemAppearance.colorScheme == .dark
        )
    }

    private func presentClearBrowsingData() {
        guard !store.isPrivate else { return }
        ClearBrowsingDataPrompt.present(
            currentSpace: ClearBrowsingDataPrompt.CurrentSpace(
                id: store.activeSpaceID,
                dataStoreID: store.dataStoreID(for: store.activeSpaceID)
            )
        )
    }

    private var browserCommandActions: BrowserCommandActions {
        BrowserCommandActions(
            newTab: openNewTabFlow,
            focusAddressBar: store.focusAddressBar,
            openCommandPalette: store.openCommandPalette,
            toggleSidebar: toggleSidebar,
            isSidebarVisible: isSidebarVisible,
            showHistory: showHistory,
            isHistoryVisible: isHistoryPresented,
            clearBrowsingData: presentClearBrowsingData,
            canClearBrowsingData: !store.isPrivate,
            showDownloads: showDownloads,
            isDownloadsVisible: store.isDownloadsPopoverPresented,
            showSiteInfo: showSiteInfo,
            canShowSiteInfo: store.activeTab?.url != nil,
            showPrivacyReport: { store.isPrivacyReportPresented.toggle() },
            toggleReader: store.toggleReaderForActiveTab,
            canToggleReader: store.canToggleReaderForActiveTab,
            isReaderActive: store.isReaderActiveForActiveTab,
            showQuickTour: showQuickTour,
            openExtensionGallery: { store.navigateNewTab(to: ChromeWebStore.galleryURL) },
            reloadTab: store.reloadActiveTab,
            reloadTabFromOrigin: store.reloadActiveTabFromOrigin,
            printPage: store.printActiveTab,
            canPrintActiveTab: store.canPrintActiveTab,
            openLocalFile: store.openLocalFileViaPanel,
            saveActiveTabAs: store.saveActiveTabAsWebArchive,
            exportActiveTabAsPDF: store.exportActiveTabAsPDF,
            canSaveActiveTab: store.canPrintActiveTab,
            stopLoading: store.stopLoadingActiveTab,
            isActiveTabLoading: store.activeTab?.isLoading == true,
            canReloadActiveTab: store.activeTab?.url != nil,
            goBack: store.goBack,
            goForward: store.goForward,
            goHome: store.goHome,
            returnToSearchResults: store.returnToSearchResults,
            canReturnToSearchResults: store.canReturnToSearchResults,
            closeCurrentTab: closeTabOrWindow,
            nextTab: store.switchToNextTab,
            previousTab: store.switchToPreviousTab,
            nextSpace: store.switchToNextSpace,
            previousSpace: store.switchToPreviousSpace,
            reopenClosedTab: store.reopenLastClosedTab,
            pinOrUnpinTab: store.togglePinForActiveTab,
            isActiveTabPinned: store.activeTab?.isPinned == true,
            isActiveTabFavorite: store.activeTab?.isFavorite == true,
            createSpace: store.beginSpaceCreation,
            editActiveSpace: { store.beginSpaceEditing(store.activeSpaceID) },
            spaces: store.spaces,
            activeSpaceID: store.activeSpaceID,
            selectSpace: store.requestSpaceSelection,
            canToggleFavorite: store.activeTab?.url != nil,
            toggleFavoriteForActiveTab: store.toggleFavoriteForActiveTab,
            duplicateTab: store.duplicateCurrentTab,
            clearUnpinnedTabs: store.clearUnpinnedTabs,
            copyURL: { store.copyActiveTabURL() },
            copyURLAsMarkdown: { store.copyActiveTabURL(asMarkdown: true) },
            findInPage: showFind,
            findNext: store.findNext,
            findPrevious: store.findPrevious,
            zoomIn: store.zoomInActiveTab,
            zoomOut: store.zoomOutActiveTab,
            resetZoom: store.resetZoomForActiveTab,
            toggleSplitView: toggleSplitView,
            setSplitLayout: store.setSplitLayout,
            isSplitDisplayed: store.isSplitViewDisplayed,
            toggleSplitPaneZoom: store.toggleSplitPaneZoom,
            isSplitPaneZoomed: store.isSplitPaneZoomed,
            focusSplitPane: store.focusAdjacentSplitPane,
            unsplitPane: store.unsplitFocusedPane,
            splitWithTab: store.openSplitWithCommandPalette,
            installedBrowsers: ExternalBrowserService.installedBrowsers(),
            openPageWith: { store.openActivePage(with: $0) },
            canUseDevelopTools: store.canUseDevelopTools,
            activeUserAgentPreset: store.activeUserAgentPreset,
            setUserAgentPreset: { store.setUserAgentPreset($0) },
            isCustomUserAgentActive: store.isCustomUserAgentActive,
            promptForCustomUserAgent: { store.promptForCustomUserAgent() },
            inspectablePages: store.inspectablePages,
            inspectPage: { store.inspectPage($0) },
            isWebInspectorVisible: store.isWebInspectorVisible,
            toggleWebInspector: { store.toggleWebInspector() },
            connectWebInspector: { store.connectWebInspector() },
            showJavaScriptConsole: { store.showJavaScriptConsole() },
            showPageSource: { store.showPageSource() },
            showPageResources: { store.showPageResources() },
            isRecordingTimeline: store.isRecordingTimeline,
            toggleTimelineRecording: { store.toggleTimelineRecording() },
            isSelectingElement: store.isSelectingElement,
            toggleElementSelection: { store.toggleElementSelection() },
            emptyCaches: { store.emptyCaches() },
            arrangeTabsByTitle: { store.arrangeTabs(by: .title) },
            arrangeTabsByWebsite: { store.arrangeTabs(by: .website) },
            canArrangeTabs: store.canArrangeTabs,
            canMuteActiveTab: store.canMuteActiveTab,
            isActiveTabMuted: store.isActiveTabMuted,
            toggleActiveTabMute: { store.toggleActiveTabMute() },
            canMuteOtherTabs: store.canMuteOtherTabs,
            muteOtherTabs: { store.muteOtherTabs() }
        )
    }

    private var sidebarLayout: some View {
        HStack(spacing: 0) {
            SidebarView(
                store: store,
                availableUpdate: updateService.availableUpdate,
                isInstallingUpdate: updateService.isInstallingUpdate,
                automaticUpdatesEnabled: Binding(
                    get: { updateService.automaticUpdatesEnabled },
                    set: { isEnabled in
                        updateService.setAutomaticUpdatesEnabled(isEnabled)
                    }
                ),
                onUpdateBannerTapped: {
                    updateService.openAvailableUpdate()
                },
                isWhatsNewVisible: whatsNewService.isPromptVisible,
                onWhatsNewTapped: {
                    whatsNewService.acknowledge()
                    _ = store.newTab(url: WhatsNewService.pageURL)
                },
                onWhatsNewDismissed: {
                    whatsNewService.acknowledge()
                },
                onToggleSidebar: toggleSidebar,
                isSidebarPinned: isSidebarVisible,
                onRevealSidebar: revealSidebar
            )
                .frame(width: sidebarWidth)
        }
        .frame(width: sidebarTotalWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(alignment: .leading) {
            // Docked, the lane stays transparent so the shared window backdrop
            // shows through and the sidebar matches the center exactly. Only
            // the hover overlay needs its own opaque copy over the page.
            if paintsOwnSidebarBackdrop {
                SidebarBackdrop(store: store)
                    // Covering a lane it has given up means covering the
                    // gutter beside it too: the page card has already widened
                    // across both, and WebKit has not painted either yet.
                    .frame(
                        width: sidebarTotalWidth
                            + (coversClosingSidebarLane ? Self.pageCardGutter : 0)
                    )
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .shadow(
            color: Color.black.opacity(isSidebarOverlaying ? 0.22 : 0),
            radius: 16,
            x: 3,
            y: 0
        )
        // Hangs here, not on the body's root chain, which is already at the
        // type-checker's expression budget.
        .onChange(of: store.sidebarToggleRequestID) { _, _ in
            toggleSidebar()
        }
    }

    // The pinned toggle deliberately snaps in a single frame: sidebar
    // translation, mask lane, and WebKit obscured insets all switch in one
    // commit, so the sidebar can never separate from the content beside it.
    // Only the pointer-driven hover reveal slides, as a floating overlay.
    private func toggleSidebar() {
        if isSidebarVisible {
            // The page widens first, under a sidebar that keeps covering the
            // lane, and the sidebar leaves once the page has laid out there.
            isSidebarVisible = false
            isSidebarHoverRevealed = false
            isSidebarRevealSuppressed = true
            coverClosingSidebarLane()
        } else {
            isSidebarVisible = true
            isSidebarHoverRevealed = false
            isSidebarRevealSuppressed = false
        }
    }

    /// Holds the lane until the page reports it laid out at the new width —
    /// but never longer than `closingSidebarLaneCap`. A heavy page can take
    /// ~200ms to reflow, and waiting that long for it makes the toggle feel
    /// slow; past the cap the sidebar goes and the page catches up on its
    /// own, the way it did before the cover.
    private func coverClosingSidebarLane() {
        guard store.activeTab != nil else {
            coversClosingSidebarLane = false
            return
        }
        let token = UUID()
        closingSidebarLaneToken = token
        coversClosingSidebarLane = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.closingSidebarLaneCap))
            guard closingSidebarLaneToken == token else { return }
            coversClosingSidebarLane = false
        }
    }

    /// The page has laid out against the new lane; the sidebar can go.
    private func uncoverClosingSidebarLane() {
        guard coversClosingSidebarLane else { return }
        closingSidebarLaneToken = nil
        coversClosingSidebarLane = false
    }

    /// Pins the sidebar open for something that needs it visible, leaving it
    /// alone when it already is.
    private func revealSidebar() {
        guard !isSidebarVisible else { return }
        isSidebarVisible = true
        isSidebarHoverRevealed = false
        isSidebarRevealSuppressed = false
    }

    private func showQuickTour() {
        revealSidebar()
        store.showQuickTour()
    }

    private func showHistory() {
        if isHistoryPresented {
            isHistoryPresented = false
            return
        }
        isHistoryPresented = true
    }

    private func showDownloads() {
        if store.isDownloadsPopoverPresented {
            store.isDownloadsPopoverPresented = false
            return
        }
        guard isSidebarVisible else {
            // The popover anchors to the sidebar's Downloads button, so a
            // hidden sidebar must be revealed first. Presenting in the same
            // transaction races the reveal commit and anchors nowhere
            // (see the two-beat handoff pattern) — defer to its completion.
            toggleSidebar()
            CATransaction.setCompletionBlock { [weak store] in
                store?.isDownloadsPopoverPresented = true
            }
            return
        }
        store.isDownloadsPopoverPresented = true
    }

    private func showSiteInfo() {
        if store.isSiteInfoPopoverPresented {
            store.isSiteInfoPopoverPresented = false
            return
        }
        guard isSidebarVisible else {
            // Anchored to the sidebar address pill, so a hidden sidebar must
            // be revealed first — same two-beat handoff as showDownloads.
            toggleSidebar()
            CATransaction.setCompletionBlock { [weak store] in
                store?.isSiteInfoPopoverPresented = true
            }
            return
        }
        store.isSiteInfoPopoverPresented = true
    }

    private func showFind() {
        if isHistoryPresented {
            NotificationCenter.default.post(name: .focusHistorySearch, object: nil)
        } else {
            store.showFindBar()
        }
    }

    private func openNewTabFlow() {
        isHistoryPresented = false
        store.openNewTab()
    }

    private func toggleSplitView() {
        store.toggleSplitView()
    }

    private func closeTabOrWindow() {
        if isHistoryPresented {
            isHistoryPresented = false
            return
        }

        store.closeCurrentTabOrWindow()
    }
}
