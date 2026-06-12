import AppKit
import SwiftUI

struct WindowInteractionConfigurator: NSViewRepresentable {
    let autosaveName: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.configure(
                window: view.window,
                autosaveName: autosaveName
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.configure(
                window: nsView.window,
                autosaveName: autosaveName
            )
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

extension SpaceThemeAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

/// Tracks the macOS system appearance so "automatic" can resolve to an
/// explicit color scheme. SwiftUI latches the last non-nil
/// `preferredColorScheme` on its window, so we can never pass nil to mean
/// "follow the system" — we follow it ourselves instead.
@MainActor
final class SystemAppearanceObserver: ObservableObject {
    @Published var colorScheme: ColorScheme

    private var observer: NSObjectProtocol?

    init() {
        colorScheme = Self.currentSystemColorScheme()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.colorScheme = Self.currentSystemColorScheme()
            }
        }
    }


    private static func currentSystemColorScheme() -> ColorScheme {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        return isDark ? .dark : .light
    }
}
