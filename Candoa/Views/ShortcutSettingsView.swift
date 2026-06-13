import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @State private var searchText = ""

    private var filteredDefinitions: [CandoaShortcutDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CandoaShortcutDefinition.allCases }
        return CandoaShortcutDefinition.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.category.localizedCaseInsensitiveContains(query) ||
                $0.searchText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search shortcuts", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .padding(16)

            List(filteredDefinitions) { definition in
                ShortcutSettingsRow(definition: definition)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            .listStyle(.inset)
        }
        .frame(width: 620, height: 520)
    }
}

private struct ShortcutSettingsRow: View {
    let definition: CandoaShortcutDefinition

    @AppStorage private var storedShortcut: String
    @State private var isRecording = false

    private var displayShortcut: String {
        if storedShortcut == CandoaShortcutDefinition.removedValue {
            return "None"
        }

        return storedShortcut.isEmpty ? definition.defaultShortcut : storedShortcut
    }

    private var isRemoved: Bool {
        storedShortcut == CandoaShortcutDefinition.removedValue
    }

    init(definition: CandoaShortcutDefinition) {
        self.definition = definition
        _storedShortcut = AppStorage(wrappedValue: "", definition.storageKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: definition.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(definition.title)
                    .font(.system(size: 13, weight: .medium))

                Text(definition.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isRecording = true
            } label: {
                Text(isRecording ? "Press Keys" : displayShortcut)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 112)
            }
            .buttonStyle(.bordered)
            .help("Set Shortcut")

            Button {
                storedShortcut = isRemoved ? "" : CandoaShortcutDefinition.removedValue
            } label: {
                Image(systemName: isRemoved ? "plus" : "minus")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(isRemoved ? "Restore Shortcut" : "Remove Shortcut")

            Button {
                storedShortcut = ""
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(storedShortcut.isEmpty)
            .help("Reset to Default")
        }
        .background {
            if isRecording {
                ShortcutCaptureView { shortcut in
                    storedShortcut = shortcut
                    isRecording = false
                } onCancel: {
                    isRecording = false
                }
            }
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        private let onCapture: (String) -> Void
        private let onCancel: () -> Void
        private var monitor: Any?

        init(onCapture: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func install() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }

                if event.keyCode == 53 {
                    onCancel()
                    return nil
                }

                guard let shortcut = Self.shortcutString(for: event) else {
                    NSSound.beep()
                    return nil
                }

                onCapture(shortcut)
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private static func shortcutString(for event: NSEvent) -> String? {
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .function, .numericPad])

            guard !modifiers.isEmpty else { return nil }

            var parts: [String] = []
            if modifiers.contains(.control) { parts.append("Control") }
            if modifiers.contains(.option) { parts.append("Option") }
            if modifiers.contains(.shift) { parts.append("Shift") }
            if modifiers.contains(.command) { parts.append("Command") }

            let key = keyString(for: event)
            guard !key.isEmpty else { return nil }
            parts.append(key)
            return parts.joined(separator: "-")
        }

        private static func keyString(for event: NSEvent) -> String {
            switch event.keyCode {
            case 123: return "Left"
            case 124: return "Right"
            case 125: return "Down"
            case 126: return "Up"
            default:
                return event.charactersIgnoringModifiers?.uppercased() ?? ""
            }
        }
    }
}

enum CandoaShortcutDefinition: String, CaseIterable, Identifiable {
    static let removedValue = "none"

    case newTab
    case focusAddressBar
    case copyURL
    case copyURLAsMarkdown
    case captureFullPage
    case pinOrUnpinTab
    case toggleSidebar
    case addSplitView
    case closeSplitView
    case findInPage
    case reloadTab

    var id: String { rawValue }
    var storageKey: String { "CandoaShortcut.\(rawValue)" }

    var title: String {
        switch self {
        case .newTab: return BrowserCommandTitles.newTab
        case .focusAddressBar: return BrowserCommandTitles.focusAddressBar
        case .copyURL: return BrowserCommandTitles.copyURL
        case .copyURLAsMarkdown: return BrowserCommandTitles.copyURLAsMarkdown
        case .captureFullPage: return "Capture Page"
        case .pinOrUnpinTab: return BrowserCommandTitles.pinOrUnpinTab
        case .toggleSidebar: return BrowserCommandTitles.toggleSidebar
        case .addSplitView: return BrowserCommandTitles.addSplitView
        case .closeSplitView: return BrowserCommandTitles.closeSplitView
        case .findInPage: return BrowserCommandTitles.findInPage
        case .reloadTab: return BrowserCommandTitles.reloadTab
        }
    }

    var category: String {
        switch self {
        case .captureFullPage:
            return "Capture"
        case .addSplitView, .closeSplitView:
            return "Split View"
        default:
            return "Browser"
        }
    }

    var defaultShortcut: String {
        switch self {
        case .newTab: return "Command-T"
        case .focusAddressBar: return "Command-L"
        case .copyURL: return "Shift-Command-C"
        case .copyURLAsMarkdown: return "Option-Shift-Command-C"
        case .captureFullPage: return "None"
        case .pinOrUnpinTab: return "Command-D"
        case .toggleSidebar: return "Command-S"
        case .addSplitView: return "Control-Shift-="
        case .closeSplitView: return "Control-Shift--"
        case .findInPage: return "Command-F"
        case .reloadTab: return "Command-R"
        }
    }

    var symbolName: String {
        switch self {
        case .captureFullPage: return "camera"
        case .addSplitView, .closeSplitView: return "rectangle.split.1x2"
        case .copyURL, .copyURLAsMarkdown: return "link"
        case .findInPage: return "magnifyingglass"
        case .reloadTab: return "arrow.clockwise"
        case .pinOrUnpinTab: return "pin"
        case .toggleSidebar: return "sidebar.left"
        case .focusAddressBar: return "text.cursor"
        case .newTab: return "plus"
        }
    }

    var searchText: String {
        "\(title) \(category) \(defaultShortcut)"
    }
}
