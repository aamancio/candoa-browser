import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = BrowserStore()
    @StateObject private var updateService = AppUpdateService()
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("luma.windowAutosaveID") private var windowAutosaveID = UUID().uuidString
    @State private var isSidebarVisible = true
    @State private var isSidebarHoverRevealed = false
    @State private var isSidebarRevealSuppressed = false
    @State private var miniPlayerOrigin: CGPoint?
    @State private var miniPlayerExpandedSize = MiniPlayerLayout.defaultExpandedSize
    private let sidebarWidth = LumaChromeStyle.sidebarWidth
    private let sidebarDividerWidth: CGFloat = 0

    private var activeThemeAppearance: SpaceThemeAppearance {
        store.spaceThemeAppearancePreview ?? store.activeSpace?.themeAppearance ?? .automatic
    }

    private var preferredColorScheme: ColorScheme? {
        activeThemeAppearance.colorScheme
    }

    private var preferredNSAppearanceName: NSAppearance.Name? {
        activeThemeAppearance.nsAppearanceName
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

    var body: some View {
        ZStack(alignment: .leading) {
            SpaceThemeBackdrop(
                hexes: activeThemeHexes,
                intensity: (store.isSpaceSetupPresented ? 0.16 : 0.20) * activeThemeIntensityMultiplier,
                texture: store.activeThemeTexture
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            WebViewContainer(store: store)
                .ignoresSafeArea(.container, edges: .top)
                .padding(.leading, isSidebarVisible ? sidebarTotalWidth : 0)

            sidebarLayout
                .offset(x: isSidebarPresented ? 0 : -sidebarTotalWidth)
                .zIndex(2)

            if store.isCommandPalettePresented {
                CommandPaletteView(store: store)
                    .id(store.commandPaletteSessionID)
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
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
        .background {
            ZStack {
                LumaChromeStyle.windowBackground
                SpaceThemeBackdrop(
                    hexes: activeThemeHexes,
                    intensity: (store.isSpaceSetupPresented ? 0.10 : 0.16) * activeThemeIntensityMultiplier,
                    texture: store.activeThemeTexture
                )
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(preferredColorScheme)
        .background(
            WindowInteractionConfigurator(
                autosaveName: "\(AppConfiguration.windowAutosaveNamePrefix).\(windowAutosaveID)",
                appearanceName: preferredNSAppearanceName
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
        .animation(.easeOut(duration: 0.14), value: store.isCommandPalettePresented)
        .animation(.easeOut(duration: 0.14), value: store.isTabSwitcherPresented)
        .animation(.easeOut(duration: 0.16), value: store.mediaControllerTabID)
        .animation(.easeOut(duration: 0.16), value: store.isMiniPlayerMinimized)
        .animation(.easeOut(duration: 0.18), value: isSidebarPresented)
        .animation(.easeOut(duration: 0.18), value: isSidebarVisible)
        .focusedSceneValue(\.browserCommandActions, browserCommandActions)
        .alert(
            "Relaunch Luma",
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
            ZStack {
                LumaChromeStyle.sidebarBackground
                SpaceThemeBackdrop(
                    hexes: activeThemeHexes,
                    intensity: (store.isSpaceSetupPresented ? 0.10 : 0.18) * activeThemeIntensityMultiplier,
                    texture: store.activeThemeTexture
                )
            }
        }
        .shadow(
            color: Color.black.opacity(isSidebarVisible ? 0.16 : 0),
            radius: store.isSpaceSetupPresented && !activeThemeHexes.isEmpty ? 16 : 10,
            x: store.isSpaceSetupPresented && !activeThemeHexes.isEmpty ? 3 : 3,
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
