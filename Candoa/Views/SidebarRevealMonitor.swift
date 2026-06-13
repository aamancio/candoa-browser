import AppKit
import SwiftUI

struct MouseMoveMonitor: NSViewRepresentable {
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
