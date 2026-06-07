import SwiftUI

@main
struct LumaBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .lumaOpenCommandPalette, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandMenu("Browser") {
                Button("Focus Address Bar") {
                    NotificationCenter.default.post(name: .lumaFocusAddressBar, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Command Bar") {
                    NotificationCenter.default.post(name: .lumaOpenCommandPalette, object: nil)
                }

                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .lumaToggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("Reload Tab") {
                    NotificationCenter.default.post(name: .lumaReloadTab, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Back") {
                    NotificationCenter.default.post(name: .lumaGoBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    NotificationCenter.default.post(name: .lumaGoForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Close Current Tab") {
                    NotificationCenter.default.post(name: .lumaCloseCurrentTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Next Tab") {
                    NotificationCenter.default.post(name: .lumaNextTab, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Previous Tab") {
                    NotificationCenter.default.post(name: .lumaPreviousTab, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Next Space") {
                    NotificationCenter.default.post(name: .lumaNextSpace, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

                Button("Previous Space") {
                    NotificationCenter.default.post(name: .lumaPreviousSpace, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            }
        }
    }
}

extension Notification.Name {
    static let lumaFocusAddressBar = Notification.Name("lumaFocusAddressBar")
    static let lumaOpenCommandPalette = Notification.Name("lumaOpenCommandPalette")
    static let lumaNewTab = Notification.Name("lumaNewTab")
    static let lumaReloadTab = Notification.Name("lumaReloadTab")
    static let lumaGoBack = Notification.Name("lumaGoBack")
    static let lumaGoForward = Notification.Name("lumaGoForward")
    static let lumaCloseCurrentTab = Notification.Name("lumaCloseCurrentTab")
    static let lumaNextTab = Notification.Name("lumaNextTab")
    static let lumaPreviousTab = Notification.Name("lumaPreviousTab")
    static let lumaNextSpace = Notification.Name("lumaNextSpace")
    static let lumaPreviousSpace = Notification.Name("lumaPreviousSpace")
    static let lumaToggleSidebar = Notification.Name("lumaToggleSidebar")
}
