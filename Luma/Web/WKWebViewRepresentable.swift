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
/// media playback can survive tab switches and move into the mini player.
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

struct MiniPlayerWebViewHost: NSViewRepresentable {
    let tabID: UUID
    @ObservedObject var store: BrowserStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ container: NSView, context: Context) {
        store.webCoordinator.hostMiniPlayerWebView(for: tabID, in: container)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        nsView.subviews.forEach { $0.removeFromSuperview() }
    }
}
