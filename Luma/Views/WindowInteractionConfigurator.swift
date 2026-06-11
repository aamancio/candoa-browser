import AppKit
import SwiftUI

struct WindowInteractionConfigurator: NSViewRepresentable {
    let autosaveName: String
    let appearanceName: NSAppearance.Name?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.configure(
                window: view.window,
                autosaveName: autosaveName,
                appearanceName: appearanceName
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.configure(
                window: nsView.window,
                autosaveName: autosaveName,
                appearanceName: appearanceName
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
        private var configuredAppearanceName: NSAppearance.Name?

        func configure(window: NSWindow?, autosaveName: String, appearanceName: NSAppearance.Name?) {
            guard let window else { return }
            configureChrome(for: window)
            configureAppearance(for: window, appearanceName: appearanceName)

            guard configuredWindow !== window || configuredAutosaveName != autosaveName else {
                return
            }

            configuredWindow = window
            configuredAutosaveName = autosaveName
            _ = window.setFrameUsingName(autosaveName)
            _ = window.setFrameAutosaveName(autosaveName)
        }

        private func configureAppearance(for window: NSWindow, appearanceName: NSAppearance.Name?) {
            guard configuredWindow !== window || configuredAppearanceName != appearanceName else { return }
            configuredAppearanceName = appearanceName
            window.appearance = appearanceName.flatMap(NSAppearance.init(named:))
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

    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .automatic:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }
}
