import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = BrowserStore()
    @SceneStorage("luma.windowAutosaveID") private var windowAutosaveID = UUID().uuidString
    @State private var isSidebarVisible = true
    @State private var isSidebarHoverRevealed = false
    @State private var isSidebarRevealSuppressed = false
    @State private var miniPlayerOrigin: CGPoint?
    @State private var miniPlayerExpandedSize = MiniPlayerLayout.defaultExpandedSize
    private let sidebarWidth: CGFloat = 232
    private let sidebarDividerWidth: CGFloat = 1

    private var sidebarTotalWidth: CGFloat {
        sidebarWidth + sidebarDividerWidth
    }

    private var isSidebarPresented: Bool {
        isSidebarVisible || isSidebarHoverRevealed
    }

    var body: some View {
        ZStack(alignment: .leading) {
            WebViewContainer(store: store)
                .ignoresSafeArea(.container, edges: .top)
                .padding(.leading, isSidebarVisible ? sidebarTotalWidth : 0)
                .blur(radius: store.isCreateSpacePresented ? 7 : 0)
                .animation(.easeOut(duration: 0.16), value: store.isCreateSpacePresented)

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
        .background(WindowInteractionConfigurator(autosaveName: "\(AppConfiguration.windowAutosaveNamePrefix).\(windowAutosaveID)"))
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
            closeSplitView: store.closeSplitView
        )
    }

    private var sidebarLayout: some View {
        HStack(spacing: 0) {
            SidebarView(store: store, onToggleSidebar: toggleSidebar)
                .frame(width: sidebarWidth)

            Divider()
        }
        .frame(width: sidebarTotalWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
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

private struct KeyboardShortcutMonitor: NSViewRepresentable {
    let onCommandT: () -> Void
    let onCommandW: () -> Void
    let onControlTab: () -> Void
    let onControlShiftTab: () -> Void
    let onControlReleased: () -> Void
    let onCommandDigit: (Int) -> Void
    let onControlDigit: (Int) -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onAddSplit: () -> Void
    let onCloseSplit: () -> Void

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        apply(to: coordinator)
        return coordinator
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitorIfNeeded()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: context.coordinator)
        context.coordinator.installMonitorIfNeeded()
    }

    private func apply(to coordinator: Coordinator) {
        coordinator.onCommandT = onCommandT
        coordinator.onCommandW = onCommandW
        coordinator.onControlTab = onControlTab
        coordinator.onControlShiftTab = onControlShiftTab
        coordinator.onControlReleased = onControlReleased
        coordinator.onCommandDigit = onCommandDigit
        coordinator.onControlDigit = onControlDigit
        coordinator.onZoomIn = onZoomIn
        coordinator.onZoomOut = onZoomOut
        coordinator.onAddSplit = onAddSplit
        coordinator.onCloseSplit = onCloseSplit
    }

    final class Coordinator: NSObject {
        var onCommandT: () -> Void = {}
        var onCommandW: () -> Void = {}
        var onControlTab: () -> Void = {}
        var onControlShiftTab: () -> Void = {}
        var onControlReleased: () -> Void = {}
        var onCommandDigit: (Int) -> Void = { _ in }
        var onControlDigit: (Int) -> Void = { _ in }
        var onZoomIn: () -> Void = {}
        var onZoomOut: () -> Void = {}
        var onAddSplit: () -> Void = {}
        var onCloseSplit: () -> Void = {}
        private var monitor: Any?

        private static let equalsKeyCode: UInt16 = 24
        private static let minusKeyCode: UInt16 = 27

        func installMonitorIfNeeded() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self else {
                    return event
                }

                if event.type == .flagsChanged {
                    if !Self.isControlPressed(event) {
                        onControlReleased()
                    }
                    return event
                }

                if Self.isCommandT(event) {
                    onCommandT()
                    return nil
                }

                if Self.isCommandW(event) {
                    onCommandW()
                    return nil
                }

                if Self.isControlShiftTab(event) {
                    onControlShiftTab()
                    return nil
                }

                if Self.isControlTab(event) {
                    onControlTab()
                    return nil
                }

                if let digit = Self.digit(for: event, requiring: .command) {
                    onCommandDigit(digit)
                    return nil
                }

                if let digit = Self.digit(for: event, requiring: .control) {
                    onControlDigit(digit)
                    return nil
                }

                if Self.matchesKey(event, keyCode: Self.equalsKeyCode, modifiers: [.control, .shift]) {
                    onAddSplit()
                    return nil
                }

                if Self.matchesKey(event, keyCode: Self.minusKeyCode, modifiers: [.control, .shift]) {
                    onCloseSplit()
                    return nil
                }

                // Catches both Command-= and Command-Shift-= (the literal Command-Plus).
                if Self.matchesZoomKey(event, keyCode: Self.equalsKeyCode) {
                    onZoomIn()
                    return nil
                }

                if Self.matchesZoomKey(event, keyCode: Self.minusKeyCode) {
                    onZoomOut()
                    return nil
                }

                return event
            }
        }

        private static func isCommandT(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return modifiers == .command &&
                event.charactersIgnoringModifiers?.lowercased() == "t"
        }

        private static func isCommandW(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return modifiers == .command &&
                event.charactersIgnoringModifiers?.lowercased() == "w"
        }

        private static func isControlTab(_ event: NSEvent) -> Bool {
            let modifiers = normalizedModifiers(for: event)
            return modifiers == .control && event.keyCode == 48
        }

        private static func isControlShiftTab(_ event: NSEvent) -> Bool {
            let modifiers = normalizedModifiers(for: event)
            return modifiers == [.control, .shift] && event.keyCode == 48
        }

        private static func isControlPressed(_ event: NSEvent) -> Bool {
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
        }

        private static func digit(for event: NSEvent, requiring modifier: NSEvent.ModifierFlags) -> Int? {
            guard normalizedModifiers(for: event) == modifier else { return nil }
            guard
                let characters = event.charactersIgnoringModifiers,
                characters.count == 1,
                let digit = Int(characters),
                (1...9).contains(digit)
            else {
                return nil
            }
            return digit
        }

        private static func matchesKey(_ event: NSEvent, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
            event.keyCode == keyCode && normalizedModifiers(for: event) == modifiers
        }

        private static func matchesZoomKey(_ event: NSEvent, keyCode: UInt16) -> Bool {
            guard event.keyCode == keyCode else { return false }
            let modifiers = normalizedModifiers(for: event)
            return modifiers == .command || modifiers == [.command, .shift]
        }

        private static func normalizedModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
            event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .function, .numericPad])
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

private enum MiniPlayerLayout {
    static let margin: CGFloat = 10
    static let topMargin: CGFloat = margin
    static let resizeHitThickness: CGFloat = 10
    static let resizeCornerLength: CGFloat = 18
    static let aspectRatio: CGFloat = 16.0 / 9.0
    static let defaultExpandedSize = CGSize(width: 430, height: 242)
    static let minimizedSize = CGSize(width: 250, height: 88)
    static let minimumExpandedWidth: CGFloat = 360
    static let maximumExpandedWidth: CGFloat = 760

    static func clampedExpandedSize(_ proposed: CGSize, in availableSize: CGSize) -> CGSize {
        let availableWidth = max(120, availableSize.width - margin * 2)
        let availableHeight = max(80, availableSize.height - margin * 2)
        let maximumWidth = min(maximumExpandedWidth, availableWidth, availableHeight * aspectRatio)
        let minimumWidth = min(minimumExpandedWidth, maximumWidth)
        let width = min(max(proposed.width, minimumWidth), maximumWidth)

        return CGSize(width: width, height: width / aspectRatio)
    }

    static func defaultOrigin(for size: CGSize, in availableSize: CGSize) -> CGPoint {
        CGPoint(
            x: margin,
            y: max(margin, availableSize.height - size.height - margin)
        )
    }

    static func clampedOrigin(_ proposed: CGPoint, size: CGSize, in availableSize: CGSize) -> CGPoint {
        let maxX = max(margin, availableSize.width - size.width - margin)
        let maxY = max(margin, availableSize.height - size.height - margin)

        return CGPoint(
            x: min(max(proposed.x, margin), maxX),
            y: min(max(proposed.y, topMargin), maxY)
        )
    }
}

private struct FloatingMiniPlayerContainer: View {
    @ObservedObject var store: BrowserStore
    let tab: BrowserTab
    let state: TabMediaState
    let availableSize: CGSize
    @Binding var origin: CGPoint?
    @Binding var expandedSize: CGSize

    @State private var dragStartOrigin: CGPoint?
    @State private var resizeStartOrigin: CGPoint?
    @State private var resizeStartSize: CGSize?
    @State private var isProgressScrubbing = false

    private var currentSize: CGSize {
        store.isMiniPlayerMinimized
            ? MiniPlayerLayout.minimizedSize
            : MiniPlayerLayout.clampedExpandedSize(expandedSize, in: availableSize)
    }

    private var currentOrigin: CGPoint {
        let size = currentSize
        let proposed = origin ?? MiniPlayerLayout.defaultOrigin(for: size, in: availableSize)
        return MiniPlayerLayout.clampedOrigin(proposed, size: size, in: availableSize)
    }

    var body: some View {
        let size = currentSize
        let resolvedOrigin = currentOrigin

        ZStack {
            FloatingMiniPlayerView(
                store: store,
                tab: tab,
                state: state,
                size: size,
                isProgressScrubbing: $isProgressScrubbing
            )

            if !store.isMiniPlayerMinimized {
                ForEach(MiniPlayerResizeEdge.allCases) { edge in
                    MiniPlayerResizeHandle(edge: edge)
                        .frame(width: edge.width(in: size), height: edge.height(in: size))
                        .position(edge.position(in: size))
                        .highPriorityGesture(resizeGesture(edge, in: availableSize))
                        .zIndex(edge.isCorner ? 4 : 3)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .position(
            x: resolvedOrigin.x + size.width / 2,
            y: resolvedOrigin.y + size.height / 2
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .gesture(dragGesture(in: availableSize))
        .onAppear {
            clampLayout()
        }
        .onChange(of: availableSize) { _, _ in
            clampLayout()
        }
        .onChange(of: store.isMiniPlayerMinimized) { _, _ in
            clampLayout()
        }
    }

    private func dragGesture(in availableSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isProgressScrubbing else {
                    dragStartOrigin = nil
                    return
                }

                if dragStartOrigin == nil {
                    dragStartOrigin = currentOrigin
                }

                let startOrigin = dragStartOrigin ?? currentOrigin
                let nextOrigin = CGPoint(
                    x: startOrigin.x + value.translation.width,
                    y: startOrigin.y + value.translation.height
                )

                origin = MiniPlayerLayout.clampedOrigin(nextOrigin, size: currentSize, in: availableSize)
            }
            .onEnded { _ in
                dragStartOrigin = nil
                clampLayout()
            }
    }

    private func resizeGesture(_ edge: MiniPlayerResizeEdge, in availableSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if resizeStartSize == nil {
                    resizeStartSize = currentSize
                }
                if resizeStartOrigin == nil {
                    resizeStartOrigin = currentOrigin
                }

                let startSize = resizeStartSize ?? currentSize
                let startOrigin = resizeStartOrigin ?? currentOrigin
                let nextSize = MiniPlayerLayout.clampedExpandedSize(
                    CGSize(width: startSize.width + edge.widthDelta(for: value.translation), height: 0),
                    in: availableSize
                )
                let rightEdge = startOrigin.x + startSize.width
                let bottomEdge = startOrigin.y + startSize.height
                let nextOrigin = CGPoint(
                    x: edge.anchorsTrailing ? rightEdge - nextSize.width : startOrigin.x,
                    y: edge.anchorsBottom ? bottomEdge - nextSize.height : startOrigin.y
                )

                expandedSize = nextSize
                origin = MiniPlayerLayout.clampedOrigin(
                    nextOrigin,
                    size: nextSize,
                    in: availableSize
                )
            }
            .onEnded { _ in
                resizeStartOrigin = nil
                resizeStartSize = nil
                clampLayout()
            }
    }

    private func clampLayout() {
        let size = currentSize
        expandedSize = MiniPlayerLayout.clampedExpandedSize(expandedSize, in: availableSize)
        origin = MiniPlayerLayout.clampedOrigin(currentOrigin, size: size, in: availableSize)
    }
}

private struct FloatingMiniPlayerView: View {
    @ObservedObject var store: BrowserStore
    let tab: BrowserTab
    let state: TabMediaState
    let size: CGSize
    @Binding var isProgressScrubbing: Bool

    @State private var isHovering = false

    var body: some View {
        ZStack {
            MiniPlayerWebViewHost(tabID: tab.id, store: store)
                .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    Color.black.opacity(isHovering ? 0.34 : 0.04),
                    Color.black.opacity(isHovering ? 0.10 : 0.02),
                    Color.black.opacity(isHovering ? 0.30 : 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if store.isMiniPlayerMinimized {
                minimizedControls
            } else {
                expandedControls
                    .opacity(isHovering ? 1 : 0)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(isHovering ? 0.18 : 0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 18, y: 8)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var expandedControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                MiniPlayerChromeIconButton(systemImage: "arrow.up.left", help: "Back to Tab") {
                    store.focusMediaTab()
                }

                Spacer(minLength: 8)

                MiniPlayerChromeButton(title: "Minimize", systemImage: "minus") {
                    store.minimizeMiniPlayer()
                }

                MiniPlayerChromeButton(title: "Close", systemImage: "xmark") {
                    store.dismissMiniPlayer()
                }
            }
            .padding(14)

            Spacer()

            HStack(spacing: 34) {
                MiniPlayerLargeButton(systemImage: "gobackward.15") {
                    store.seekMedia(by: -15)
                }

                MiniPlayerLargeButton(systemImage: state.isPlaying ? "pause.fill" : "play.fill", scale: 1.24) {
                    store.toggleMiniPlayerPlayback()
                }

                MiniPlayerLargeButton(systemImage: "goforward.15") {
                    store.seekMedia(by: 15)
                }
            }

            Spacer()

            MiniPlayerProgressBar(
                currentTime: state.currentTime,
                duration: state.duration,
                onSeek: store.seekMedia(to:),
                onScrubbingChanged: { isProgressScrubbing = $0 }
            )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private var minimizedControls: some View {
        HStack(spacing: 8) {
            favicon

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isHovering ? 0.88 : 0.74))
                    .lineLimit(1)

                Text(sourceText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isHovering ? 0.58 : 0.44))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            MiniPlayerIconButton(systemImage: state.isPlaying ? "pause.fill" : "play.fill") {
                store.toggleMiniPlayerPlayback()
            }

            MiniPlayerIconButton(systemImage: "arrow.up.left.and.arrow.down.right") {
                store.expandMiniPlayer()
            }

            MiniPlayerIconButton(systemImage: "xmark") {
                store.dismissMiniPlayer()
            }
        }
        .padding(10)
        .background(Color.black.opacity(isHovering ? 0.22 : 0.12))
    }

    private var sourceText: String {
        tab.url?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "")
            ?? BrowserCommandTitles.newTab
    }

    @ViewBuilder
    private var favicon: some View {
        if let data = tab.faviconData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: tab.faviconSymbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.white.opacity(isHovering ? 0.78 : 0.58))
                .frame(width: 18, height: 18)
        }
    }
}

private struct MiniPlayerChromeIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.84))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct MiniPlayerChromeButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.84))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct MiniPlayerLargeButton: View {
    let systemImage: String
    var scale: CGFloat = 1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 38 * scale, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.78))
                .frame(width: 58, height: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(systemImage)
    }
}

private struct MiniPlayerIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.74))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private enum MiniPlayerResizeEdge: String, CaseIterable, Identifiable {
    case top
    case bottom
    case leading
    case trailing
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var id: String { rawValue }

    var isCorner: Bool {
        switch self {
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            return true
        case .top, .bottom, .leading, .trailing:
            return false
        }
    }

    var anchorsTrailing: Bool {
        switch self {
        case .leading, .topLeading, .bottomLeading:
            return true
        case .top, .bottom, .trailing, .topTrailing, .bottomTrailing:
            return false
        }
    }

    var anchorsBottom: Bool {
        switch self {
        case .top, .topLeading, .topTrailing:
            return true
        case .bottom, .leading, .trailing, .bottomLeading, .bottomTrailing:
            return false
        }
    }

    var cursor: NSCursor {
        switch self {
        case .top, .bottom:
            return .resizeUpDown
        case .leading, .trailing:
            return .resizeLeftRight
        case .topLeading:
            return MiniPlayerResizeCursor.topLeft
        case .topTrailing:
            return MiniPlayerResizeCursor.topRight
        case .bottomLeading:
            return MiniPlayerResizeCursor.bottomLeft
        case .bottomTrailing:
            return MiniPlayerResizeCursor.bottomRight
        }
    }

    func width(in size: CGSize) -> CGFloat {
        switch self {
        case .top, .bottom:
            return size.width
        case .leading, .trailing:
            return MiniPlayerLayout.resizeHitThickness
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            return MiniPlayerLayout.resizeCornerLength
        }
    }

    func height(in size: CGSize) -> CGFloat {
        switch self {
        case .top, .bottom:
            return MiniPlayerLayout.resizeHitThickness
        case .leading, .trailing:
            return size.height
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            return MiniPlayerLayout.resizeCornerLength
        }
    }

    func position(in size: CGSize) -> CGPoint {
        let edgeInset = MiniPlayerLayout.resizeHitThickness / 2
        let cornerInset = MiniPlayerLayout.resizeCornerLength / 2

        switch self {
        case .top:
            return CGPoint(x: size.width / 2, y: edgeInset)
        case .bottom:
            return CGPoint(x: size.width / 2, y: size.height - edgeInset)
        case .leading:
            return CGPoint(x: edgeInset, y: size.height / 2)
        case .trailing:
            return CGPoint(x: size.width - edgeInset, y: size.height / 2)
        case .topLeading:
            return CGPoint(x: cornerInset, y: cornerInset)
        case .topTrailing:
            return CGPoint(x: size.width - cornerInset, y: cornerInset)
        case .bottomLeading:
            return CGPoint(x: cornerInset, y: size.height - cornerInset)
        case .bottomTrailing:
            return CGPoint(x: size.width - cornerInset, y: size.height - cornerInset)
        }
    }

    func widthDelta(for translation: CGSize) -> CGFloat {
        let candidates: [CGFloat]

        switch self {
        case .top:
            candidates = [-translation.height * MiniPlayerLayout.aspectRatio]
        case .bottom:
            candidates = [translation.height * MiniPlayerLayout.aspectRatio]
        case .leading:
            candidates = [-translation.width]
        case .trailing:
            candidates = [translation.width]
        case .topLeading:
            candidates = [
                -translation.width,
                -translation.height * MiniPlayerLayout.aspectRatio
            ]
        case .topTrailing:
            candidates = [
                translation.width,
                -translation.height * MiniPlayerLayout.aspectRatio
            ]
        case .bottomLeading:
            candidates = [
                -translation.width,
                translation.height * MiniPlayerLayout.aspectRatio
            ]
        case .bottomTrailing:
            candidates = [
                translation.width,
                translation.height * MiniPlayerLayout.aspectRatio
            ]
        }

        return candidates.max { abs($0) < abs($1) } ?? 0
    }
}

private enum MiniPlayerResizeCursor {
    static var topLeft: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: .topLeft, directions: .all)
        }
        return northwestSoutheastFallback
    }

    static var topRight: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: .topRight, directions: .all)
        }
        return northeastSouthwestFallback
    }

    static var bottomLeft: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: .bottomLeft, directions: .all)
        }
        return northeastSouthwestFallback
    }

    static var bottomRight: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: .bottomRight, directions: .all)
        }
        return northwestSoutheastFallback
    }

    nonisolated(unsafe) private static let northwestSoutheastFallback = fallbackResizeCursor(
        from: CGPoint(x: 4, y: 14),
        to: CGPoint(x: 14, y: 4)
    )

    nonisolated(unsafe) private static let northeastSouthwestFallback = fallbackResizeCursor(
        from: CGPoint(x: 14, y: 14),
        to: CGPoint(x: 4, y: 4)
    )

    private static func fallbackResizeCursor(from start: CGPoint, to end: CGPoint) -> NSCursor {
        let size = CGSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            appendLine(to: path, from: start, to: end)
            appendArrowHead(to: path, tip: start, tail: end)
            appendArrowHead(to: path, tip: end, tail: start)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            NSColor.white.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 4
            path.stroke()

            NSColor.black.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 2
            path.stroke()

            return true
        }

        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    private static func appendLine(to path: NSBezierPath, from start: CGPoint, to end: CGPoint) {
        path.move(to: start)
        path.line(to: end)
    }

    private static func appendArrowHead(to path: NSBezierPath, tip: CGPoint, tail: CGPoint) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let headLength: CGFloat = 5
        let spread: CGFloat = 0.72

        for offset in [-spread, spread] {
            let backAngle = angle + .pi + offset
            let point = CGPoint(
                x: tip.x + CGFloat(cos(Double(backAngle))) * headLength,
                y: tip.y + CGFloat(sin(Double(backAngle))) * headLength
            )
            appendLine(to: path, from: tip, to: point)
        }
    }
}

private struct MiniPlayerResizeHandle: View {
    let edge: MiniPlayerResizeEdge

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .lumaCursor(edge.cursor)
            .help("Resize")
    }
}

private struct CursorHoverModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content
            .background(CursorRectView(cursor: cursor))
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

private struct CursorRectView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectNSView {
        let view = CursorRectNSView(frame: .zero)
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorRectNSView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class CursorRectNSView: NSView {
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
    func lumaCursor(_ cursor: NSCursor) -> some View {
        modifier(CursorHoverModifier(cursor: cursor))
    }
}

private struct MiniPlayerProgressBar: View {
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void
    let onScrubbingChanged: (Bool) -> Void

    @State private var isHovering = false
    @State private var isScrubbing = false
    @State private var scrubbedTime: Double?

    private var progress: CGFloat {
        guard duration > 0, displayedTime.isFinite, duration.isFinite else { return 0 }
        return CGFloat(min(max(displayedTime / duration, 0), 1))
    }

    private var displayedTime: Double {
        scrubbedTime ?? currentTime
    }

    private var isSeekable: Bool {
        duration > 0 && duration.isFinite
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))

                Capsule()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: max(4, proxy.size.width * progress))
            }
            .frame(height: isHovering ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(seekGesture(width: proxy.size.width))
        }
        .frame(height: 16)
        .disabled(!isSeekable)
        .lumaCursor(isSeekable ? .pointingHand : .arrow)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovering)
        .onChange(of: currentTime) { _, _ in
            if !isScrubbing, scrubbedTime != nil {
                scrubbedTime = nil
            }
        }
        .onDisappear {
            onScrubbingChanged(false)
        }
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isScrubbing = true
                onScrubbingChanged(true)
                seek(toXPosition: value.location.x, width: width)
            }
            .onEnded { value in
                seek(toXPosition: value.location.x, width: width)
                isScrubbing = false
                onScrubbingChanged(false)
            }
    }

    private func seek(toXPosition xPosition: CGFloat, width: CGFloat) {
        guard isSeekable, width > 0 else { return }

        let ratio = min(max(xPosition / width, 0), 1)
        let targetTime = Double(ratio) * duration
        scrubbedTime = targetTime
        onSeek(targetTime)
    }
}

private struct MouseMoveMonitor: NSViewRepresentable {
    @Binding var isSidebarVisible: Bool
    @Binding var isSidebarHoverRevealed: Bool
    @Binding var isSidebarRevealSuppressed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.installMonitorIfNeeded()
        context.coordinator.installTimerIfNeeded()
        updateCoordinator(context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        updateCoordinator(context.coordinator)
    }

    private func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.isSidebarVisible = $isSidebarVisible
        coordinator.isSidebarHoverRevealed = $isSidebarHoverRevealed
        coordinator.isSidebarRevealSuppressed = $isSidebarRevealSuppressed
    }

    final class Coordinator {
        var isSidebarVisible: Binding<Bool>?
        var isSidebarHoverRevealed: Binding<Bool>?
        var isSidebarRevealSuppressed: Binding<Bool>?
        weak var view: NSView?
        private var monitor: Any?
        private var timer: Timer?

        func installMonitorIfNeeded() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                // Windowless events carry screen coordinates, not window-local
                // ones, so the edge math below would misfire on them.
                guard let self, event.window != nil, isSidebarVisible?.wrappedValue == false else {
                    return event
                }

                let xPosition = event.locationInWindow.x
                if isSidebarRevealSuppressed?.wrappedValue == true {
                    if xPosition > SidebarRevealConfiguration.suppressionResetDistance {
                        isSidebarRevealSuppressed?.wrappedValue = false
                    }
                    return event
                }

                if xPosition <= SidebarRevealConfiguration.revealDistanceFromLeftEdge {
                    isSidebarHoverRevealed?.wrappedValue = true
                } else if isSidebarHoverRevealed?.wrappedValue == true &&
                            xPosition > SidebarRevealConfiguration.hideDistanceFromLeftEdge {
                    isSidebarHoverRevealed?.wrappedValue = false
                }

                return event
            }
        }

        func installTimerIfNeeded() {
            guard timer == nil else { return }

            timer = Timer.scheduledTimer(
                timeInterval: SidebarRevealConfiguration.pollingInterval,
                target: self,
                selector: #selector(pollMouseLocationTimer(_:)),
                userInfo: nil,
                repeats: true
            )
        }

        @MainActor
        @objc private func pollMouseLocationTimer(_ timer: Timer) {
            pollMouseLocation()
        }

        @MainActor
        private func pollMouseLocation() {
            guard isSidebarVisible?.wrappedValue == false else { return }

            // Only react when the pointer is actually inside one of our
            // windows; falling back to an arbitrary window made the sidebar
            // reveal while the mouse was nowhere near the app.
            guard NSApp.isActive else { return }
            let mouseLocation = NSEvent.mouseLocation
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(mouseLocation) }) else {
                return
            }

            let distanceFromLeftEdge = mouseLocation.x - window.frame.minX
            if isSidebarRevealSuppressed?.wrappedValue == true {
                if distanceFromLeftEdge > SidebarRevealConfiguration.suppressionResetDistance {
                    isSidebarRevealSuppressed?.wrappedValue = false
                }
                return
            }

            if distanceFromLeftEdge >= 0 &&
                distanceFromLeftEdge <= SidebarRevealConfiguration.revealDistanceFromLeftEdge {
                isSidebarHoverRevealed?.wrappedValue = true
            } else if isSidebarHoverRevealed?.wrappedValue == true &&
                        distanceFromLeftEdge > SidebarRevealConfiguration.hideDistanceFromLeftEdge {
                isSidebarHoverRevealed?.wrappedValue = false
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            timer?.invalidate()
        }
    }
}

private struct WindowInteractionConfigurator: NSViewRepresentable {
    let autosaveName: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.configure(window: view.window, autosaveName: autosaveName)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.configure(window: nsView.window, autosaveName: autosaveName)
        }
    }

    @MainActor
    final class Coordinator {
        private static let minimumWindowSize = NSSize(
            width: AppConfiguration.minimumWindowWidth,
            height: AppConfiguration.minimumWindowHeight
        )

        private weak var configuredWindow: NSWindow?
        private var configuredAutosaveName: String?

        func configure(window: NSWindow?, autosaveName: String) {
            guard let window else { return }
            configureChrome(for: window)

            guard configuredWindow !== window || configuredAutosaveName != autosaveName else {
                return
            }

            configuredWindow = window
            configuredAutosaveName = autosaveName
            _ = window.setFrameUsingName(autosaveName)
            _ = window.setFrameAutosaveName(autosaveName)
        }

        private func configureChrome(for window: NSWindow) {
            window.minSize = Self.minimumWindowSize
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false

            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
}
