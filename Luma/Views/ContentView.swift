import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = BrowserStore()
    @SceneStorage("luma.windowAutosaveID") private var windowAutosaveID = UUID().uuidString
    @State private var isSidebarVisible = true
    @State private var isSidebarHoverRevealed = false
    @State private var isSidebarRevealSuppressed = false
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
