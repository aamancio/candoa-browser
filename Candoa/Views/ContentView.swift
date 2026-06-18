import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = BrowserStore()
    @StateObject private var updateService = AppUpdateService.shared
    @StateObject private var systemAppearance = SystemAppearanceObserver()
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("candoa.windowAutosaveID") private var windowAutosaveID = UUID().uuidString
    @State private var isSidebarVisible = true
    @State private var isSidebarHoverRevealed = false
    @State private var isSidebarRevealSuppressed = false
    @State private var miniPlayerOrigin: CGPoint?
    @State private var miniPlayerExpandedSize = MiniPlayerLayout.defaultExpandedSize
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
        ZStack(alignment: .leading) {
            WebViewContainer(store: store)
                .ignoresSafeArea(.container, edges: .top)
                .padding(.leading, isSidebarVisible ? sidebarTotalWidth : 0)

            sidebarLayout
                .offset(x: isSidebarPresented ? 0 : -sidebarTotalWidth)
                .zIndex(2)

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
        .sheet(
            isPresented: Binding(
                get: { store.isOnboardingPresented },
                set: { isPresented in
                    if !isPresented, store.isOnboardingPresented {
                        store.skipOnboarding()
                    }
                }
            )
        ) {
            OnboardingSetupView(store: store)
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

private struct OnboardingSetupView: View {
    @ObservedObject var store: BrowserStore

    @State private var step = 0
    @State private var spaceName: String
    @State private var symbolName: String
    @State private var themeAppearance: SpaceThemeAppearance
    @FocusState private var isSpaceNameFocused: Bool

    private let steps = 3
    private let symbolOptions: [(title: String, symbolName: String)] = [
        ("Personal", "circle.grid.2x2"),
        ("Work", "briefcase"),
        ("Study", "graduationcap"),
        ("Creative", "paintpalette"),
        ("Fast", "bolt")
    ]

    private var trimmedSpaceName: String {
        spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        step != 1 || !trimmedSpaceName.isEmpty
    }

    init(store: BrowserStore) {
        self.store = store
        _spaceName = State(initialValue: store.activeSpace?.name ?? "Personal")
        _symbolName = State(initialValue: store.activeSpace?.symbolName ?? "circle.grid.2x2")
        _themeAppearance = State(initialValue: store.activeSpace?.themeAppearance ?? BrowserSpace.defaultThemeAppearance)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0:
                    welcomeStep
                case 1:
                    spaceStep
                default:
                    tourStep
                }
            }
            .animation(.easeOut(duration: 0.18), value: step)

            Divider()

            footer
        }
        .frame(width: 520, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if step == 1 {
                isSpaceNameFocused = true
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                Text("Welcome to Candoa")
                    .font(.system(size: 28, weight: .semibold))

                Text("A sidebar-first browser built around Spaces, pinned tabs, and fast keyboard navigation.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 390)
            }

            VStack(alignment: .leading, spacing: 10) {
                onboardingPoint("square.grid.2x2", "Spaces keep browsing contexts separate.")
                onboardingPoint("pin", "Pinned tabs stay close without filling the active tab list.")
                onboardingPoint("command", "Command-T opens the command and new-tab flow.")
            }
            .padding(.top, 8)
        }
        .padding(36)
    }

    private var spaceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up your first Space")
                    .font(.system(size: 24, weight: .semibold))

                Text("Candoa creates a usable Space automatically. You can rename it now or change it later.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                TextField("Space name", text: $spaceName)
                    .focused($isSpaceNameFocused)
                    .onChange(of: spaceName) { _, newValue in
                        let limitedName = BrowserStore.limitedSpaceNameInput(newValue)
                        if limitedName != newValue {
                            spaceName = limitedName
                        }
                    }

                Picker("Icon", selection: $symbolName) {
                    ForEach(symbolOptions, id: \.symbolName) { option in
                        Label(option.title, systemImage: option.symbolName)
                            .tag(option.symbolName)
                    }
                }

                Picker("Appearance", selection: $themeAppearance) {
                    ForEach(SpaceThemeAppearance.allCases) { appearance in
                        Label(appearance.title, systemImage: appearance.symbolName)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Spacer(minLength: 0)
        }
        .padding(32)
    }

    private var tourStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "location.viewfinder")
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("A short tour will point at the real controls")
                    .font(.system(size: 24, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)

                Text("It uses native popovers anchored to the sidebar, command flow, and Space switcher. You can skip it at any time.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 390)
            }

            VStack(alignment: .leading, spacing: 10) {
                onboardingPoint("1.circle", "See where tabs and pinned tabs live.")
                onboardingPoint("2.circle", "Open the command and new-tab flow.")
                onboardingPoint("3.circle", "Switch and manage Spaces from the bottom of the sidebar.")
            }
            .padding(.top, 8)
        }
        .padding(36)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Skip Setup") {
                store.skipOnboarding()
            }

            Spacer()

            if step > 0 {
                Button("Back") {
                    step -= 1
                }
            }

            if step < steps - 1 {
                Button("Continue") {
                    step += 1
                    if step == 1 {
                        isSpaceNameFocused = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            } else {
                Button("Skip Tour") {
                    complete(startsTour: false)
                }

                Button("Start Browsing") {
                    complete(startsTour: true)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func onboardingPoint(_ symbolName: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }

    private func complete(startsTour: Bool) {
        store.completeOnboarding(
            spaceName: trimmedSpaceName,
            symbolName: symbolName,
            themeAppearance: themeAppearance,
            startsTour: startsTour
        )
    }
}
