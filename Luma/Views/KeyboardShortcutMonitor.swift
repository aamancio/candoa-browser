import AppKit
import SwiftUI

struct KeyboardShortcutMonitor: NSViewRepresentable {
    let onCommandT: () -> Void
    let onCommandW: () -> Void
    let onControlTab: () -> Void
    let onControlShiftTab: () -> Void
    let onControlReleased: () -> Void
    let onCommandDigit: (Int) -> Void
    let onControlDigit: (Int) -> Void
    let onGoBack: () -> Void
    let onGoForward: () -> Void
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
        coordinator.onGoBack = onGoBack
        coordinator.onGoForward = onGoForward
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
        var onGoBack: () -> Void = {}
        var onGoForward: () -> Void = {}
        var onZoomIn: () -> Void = {}
        var onZoomOut: () -> Void = {}
        var onAddSplit: () -> Void = {}
        var onCloseSplit: () -> Void = {}
        private var monitor: Any?

        private static let closeBracketKeyCode: UInt16 = 30
        private static let openBracketKeyCode: UInt16 = 33
        private static let equalsKeyCode: UInt16 = 24
        private static let minusKeyCode: UInt16 = 27
        private static let leftArrowKeyCode: UInt16 = 123
        private static let rightArrowKeyCode: UInt16 = 124

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

                if Self.isGoBack(event) {
                    onGoBack()
                    return nil
                }

                if Self.isGoForward(event) {
                    onGoForward()
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

        private static func isGoBack(_ event: NSEvent) -> Bool {
            matchesKey(event, keyCode: openBracketKeyCode, modifiers: .command) ||
                matchesKey(event, keyCode: leftArrowKeyCode, modifiers: .command)
        }

        private static func isGoForward(_ event: NSEvent) -> Bool {
            matchesKey(event, keyCode: closeBracketKeyCode, modifiers: .command) ||
                matchesKey(event, keyCode: rightArrowKeyCode, modifiers: .command)
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
