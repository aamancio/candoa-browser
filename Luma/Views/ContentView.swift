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
        .background(WindowInteractionConfigurator(autosaveName: "Luma.BrowserWindow.\(windowAutosaveID)"))
        .background(
            MouseMoveMonitor(
                isSidebarVisible: $isSidebarVisible,
                isSidebarHoverRevealed: $isSidebarHoverRevealed,
                isSidebarRevealSuppressed: $isSidebarRevealSuppressed
            )
        )
        .background(
            KeyboardShortcutMonitor {
                store.openCommandPalette()
            } onControlTab: {
                store.switchToNextRecentTab(keepsPreviewOpen: true)
            } onControlShiftTab: {
                store.switchToPreviousRecentTab(keepsPreviewOpen: true)
            } onControlReleased: {
                store.finishTabSwitcherInteraction()
            }
        )
        .animation(.easeOut(duration: 0.14), value: store.isCommandPalettePresented)
        .animation(.easeOut(duration: 0.14), value: store.isTabSwitcherPresented)
        .animation(.easeOut(duration: 0.18), value: isSidebarPresented)
        .animation(.easeOut(duration: 0.18), value: isSidebarVisible)
        .onReceive(NotificationCenter.default.publisher(for: .lumaFocusAddressBar)) { _ in
            store.focusAddressBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaOpenCommandPalette)) { _ in
            store.openCommandPalette()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaNewTab)) { _ in
            store.newTab()
            store.focusAddressBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaReloadTab)) { _ in
            store.reloadActiveTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaGoBack)) { _ in
            store.goBack()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaGoForward)) { _ in
            store.goForward()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaCloseCurrentTab)) { _ in
            store.closeCurrentTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaNextTab)) { _ in
            store.switchToNextTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaPreviousTab)) { _ in
            store.switchToPreviousTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaNextSpace)) { _ in
            store.switchToNextSpace()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaPreviousSpace)) { _ in
            store.switchToPreviousSpace()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumaToggleSidebar)) { _ in
            toggleSidebar()
        }
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

}

private struct KeyboardShortcutMonitor: NSViewRepresentable {
    let onCommandT: () -> Void
    let onControlTab: () -> Void
    let onControlShiftTab: () -> Void
    let onControlReleased: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCommandT: onCommandT,
            onControlTab: onControlTab,
            onControlShiftTab: onControlShiftTab,
            onControlReleased: onControlReleased
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitorIfNeeded()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCommandT = onCommandT
        context.coordinator.onControlTab = onControlTab
        context.coordinator.onControlShiftTab = onControlShiftTab
        context.coordinator.onControlReleased = onControlReleased
        context.coordinator.installMonitorIfNeeded()
    }

    final class Coordinator {
        var onCommandT: () -> Void
        var onControlTab: () -> Void
        var onControlShiftTab: () -> Void
        var onControlReleased: () -> Void
        private var monitor: Any?

        init(
            onCommandT: @escaping () -> Void,
            onControlTab: @escaping () -> Void,
            onControlShiftTab: @escaping () -> Void,
            onControlReleased: @escaping () -> Void
        ) {
            self.onCommandT = onCommandT
            self.onControlTab = onControlTab
            self.onControlShiftTab = onControlShiftTab
            self.onControlReleased = onControlReleased
        }

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

                if Self.isControlShiftTab(event) {
                    onControlShiftTab()
                    return nil
                }

                if Self.isControlTab(event) {
                    onControlTab()
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

        private static func isControlTab(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return modifiers == .control && event.keyCode == 48
        }

        private static func isControlShiftTab(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return modifiers == [.control, .shift] && event.keyCode == 48
        }

        private static func isControlPressed(_ event: NSEvent) -> Bool {
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
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
                guard let self, isSidebarVisible?.wrappedValue == false else {
                    return event
                }

                let xPosition = event.locationInWindow.x
                if isSidebarRevealSuppressed?.wrappedValue == true {
                    if xPosition > 96 {
                        isSidebarRevealSuppressed?.wrappedValue = false
                    }
                    return event
                }

                if xPosition <= 64 {
                    isSidebarHoverRevealed?.wrappedValue = true
                } else if isSidebarHoverRevealed?.wrappedValue == true && xPosition > 250 {
                    isSidebarHoverRevealed?.wrappedValue = false
                }

                return event
            }
        }

        func installTimerIfNeeded() {
            guard timer == nil else { return }

            timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                self?.pollMouseLocation()
            }
        }

        private func pollMouseLocation() {
            guard isSidebarVisible?.wrappedValue == false else { return }

            let mouseLocation = NSEvent.mouseLocation
            let visibleWindows = NSApp.windows.filter { $0.isVisible }
            guard let window = visibleWindows.first(where: { $0.frame.contains(mouseLocation) }) ?? visibleWindows.first else {
                return
            }

            let frame = window.frame
            let isVerticallyInsideWindow = mouseLocation.y >= frame.minY && mouseLocation.y <= frame.maxY
            guard isVerticallyInsideWindow else { return }

            let distanceFromLeftEdge = mouseLocation.x - frame.minX
            if isSidebarRevealSuppressed?.wrappedValue == true {
                if distanceFromLeftEdge > 96 {
                    isSidebarRevealSuppressed?.wrappedValue = false
                }
                return
            }

            if distanceFromLeftEdge >= 0 && distanceFromLeftEdge <= 64 {
                isSidebarHoverRevealed?.wrappedValue = true
            } else if isSidebarHoverRevealed?.wrappedValue == true && distanceFromLeftEdge > 250 {
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
        private static let minimumWindowSize = NSSize(width: 980, height: 640)

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
