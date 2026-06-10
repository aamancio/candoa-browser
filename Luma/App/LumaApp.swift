import SwiftUI

@main
struct LumaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(
                    minWidth: AppConfiguration.minimumWindowWidth,
                    minHeight: AppConfiguration.minimumWindowHeight
                )
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            BrowserCommands()
        }
    }
}

private struct BrowserCommands: Commands {
    @FocusedValue(\.browserCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(BrowserCommandTitles.newTab) {
                actions?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.reopenClosedTab) {
                actions?.reopenClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }

        CommandGroup(after: .textEditing) {
            Button(BrowserCommandTitles.findInPage) {
                actions?.findInPage()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.findNext) {
                actions?.findNext()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.findPrevious) {
                actions?.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }

        CommandMenu("Browser") {
            Button(BrowserCommandTitles.focusAddressBar) {
                actions?.focusAddressBar()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.commandBar) {
                actions?.openCommandPalette()
            }
            .disabled(actions == nil)

            Button(BrowserCommandTitles.toggleSidebar) {
                actions?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(actions == nil)

            Divider()

            Button(BrowserCommandTitles.reloadTab) {
                actions?.reloadTab()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.back) {
                actions?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.forward) {
                actions?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.closeCurrentTab) {
                actions?.closeCurrentTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(actions == nil)

            Divider()

            Button(BrowserCommandTitles.pinOrUnpinTab) {
                actions?.pinOrUnpinTab()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.clearUnpinnedTabs) {
                actions?.clearUnpinnedTabs()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button(BrowserCommandTitles.copyURL) {
                actions?.copyURL()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button(BrowserCommandTitles.copyURLAsMarkdown) {
                actions?.copyURLAsMarkdown()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift, .option])
            .disabled(actions == nil)

            Divider()

            Button(BrowserCommandTitles.zoomIn) {
                actions?.zoomIn()
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.zoomOut) {
                actions?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(actions == nil)

            Button(BrowserCommandTitles.resetZoom) {
                actions?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(actions == nil)

            Divider()

            Button(BrowserCommandTitles.addSplitView) {
                actions?.addSplitView()
            }
            .disabled(actions == nil)

            Button(BrowserCommandTitles.closeSplitView) {
                actions?.closeSplitView()
            }
            .disabled(actions == nil)

            Divider()

            Button(BrowserCommandTitles.nextTab) {
                actions?.nextTab()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(actions == nil)

            Button(BrowserCommandTitles.previousTab) {
                actions?.previousTab()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(actions == nil)

            Button(BrowserCommandTitles.nextSpace) {
                actions?.nextSpace()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(actions == nil)

            Button(BrowserCommandTitles.previousSpace) {
                actions?.previousSpace()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(actions == nil)
        }
    }
}

struct BrowserCommandActions {
    var newTab: () -> Void
    var focusAddressBar: () -> Void
    var openCommandPalette: () -> Void
    var toggleSidebar: () -> Void
    var reloadTab: () -> Void
    var goBack: () -> Void
    var goForward: () -> Void
    var closeCurrentTab: () -> Void
    var nextTab: () -> Void
    var previousTab: () -> Void
    var nextSpace: () -> Void
    var previousSpace: () -> Void
    var reopenClosedTab: () -> Void
    var pinOrUnpinTab: () -> Void
    var clearUnpinnedTabs: () -> Void
    var copyURL: () -> Void
    var copyURLAsMarkdown: () -> Void
    var findInPage: () -> Void
    var findNext: () -> Void
    var findPrevious: () -> Void
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var resetZoom: () -> Void
    var addSplitView: () -> Void
    var closeSplitView: () -> Void
}

private struct BrowserCommandActionsKey: FocusedValueKey {
    typealias Value = BrowserCommandActions
}

extension FocusedValues {
    var browserCommandActions: BrowserCommandActions? {
        get { self[BrowserCommandActionsKey.self] }
        set { self[BrowserCommandActionsKey.self] = newValue }
    }
}
