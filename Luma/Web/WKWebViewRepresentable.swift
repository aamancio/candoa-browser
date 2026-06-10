import SwiftUI
import WebKit

struct WKWebViewRepresentable: NSViewRepresentable {
    let tab: BrowserTab
    @ObservedObject var store: BrowserStore

    func makeNSView(context: Context) -> WKWebView {
        store.webCoordinator.webView(for: tab)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        store.webCoordinator.ensureLoaded(tab)
    }
}

/// Persistent host for the active tab's web view. Unlike swapping
/// representables per tab, this keeps background web views parented so
/// picture-in-picture and media playback survive tab switches.
struct ActiveWebViewHost: NSViewRepresentable {
    let tab: BrowserTab
    @ObservedObject var store: BrowserStore

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        store.webCoordinator.ensureLoaded(tab)
        store.webCoordinator.hostActiveWebView(
            for: tab.id,
            in: container,
            excludingTabID: store.splitTabID
        )
    }
}
