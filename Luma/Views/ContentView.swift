import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = BrowserStore()
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

            sidebarLayout
                .offset(x: isSidebarPresented ? 0 : -sidebarTotalWidth)
                .zIndex(2)

            if store.isCommandPalettePresented {
                CommandPaletteView(store: store)
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .background(WindowInteractionConfigurator())
        .background(
            MouseMoveMonitor(
                isSidebarVisible: $isSidebarVisible,
                isSidebarHoverRevealed: $isSidebarHoverRevealed,
                isSidebarRevealSuppressed: $isSidebarRevealSuppressed
            )
        )
        .animation(.easeOut(duration: 0.14), value: store.isCommandPalettePresented)
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
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
