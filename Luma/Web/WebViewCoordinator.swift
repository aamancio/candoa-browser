import Foundation
import WebKit

@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate {
    private weak var store: BrowserStore?
    private var webViews: [UUID: WKWebView] = [:]
    private var tabIDsByWebView = NSMapTable<WKWebView, NSString>.weakToStrongObjects()
    private var observations: [UUID: [NSKeyValueObservation]] = [:]

    func attach(store: BrowserStore) {
        self.store = store
    }

    func webView(for tab: BrowserTab) -> WKWebView {
        if let existingWebView = webViews[tab.id] {
            return existingWebView
        }

        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: store?.dataStoreID(for: tab.spaceID) ?? tab.spaceID)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")

        webViews[tab.id] = webView
        tabIDsByWebView.setObject(tab.id.uuidString as NSString, forKey: webView)
        observe(webView, tabID: tab.id)

        if let url = tab.url {
            load(url, in: tab.id)
        } else {
            webView.loadHTMLString(newTabHTML, baseURL: nil)
        }

        return webView
    }

    func ensureLoaded(_ tab: BrowserTab) {
        let webView = webView(for: tab)

        guard let expectedURL = tab.url else {
            if webView.url == nil {
                webView.loadHTMLString(newTabHTML, baseURL: nil)
            }
            return
        }

        if webView.url?.absoluteString != expectedURL.absoluteString {
            load(expectedURL, in: tab.id)
        }
    }

    func load(_ url: URL, in tabID: UUID) {
        let webView = webViews[tabID]
        let targetWebView: WKWebView

        if let webView {
            targetWebView = webView
        } else {
            let placeholderTab = BrowserTab(title: url.absoluteString, url: url, spaceID: UUID())
            targetWebView = self.webView(for: BrowserTab(id: tabID, title: placeholderTab.title, url: url, spaceID: placeholderTab.spaceID))
        }

        targetWebView.load(URLRequest(url: url))
    }

    func removeWebView(for tabID: UUID) {
        guard let webView = webViews.removeValue(forKey: tabID) else { return }
        observations[tabID] = nil
        webView.navigationDelegate = nil
        webView.stopLoading()
        tabIDsByWebView.removeObject(forKey: webView)
    }

    func goBack(tabID: UUID) {
        webViews[tabID]?.goBack()
    }

    func goForward(tabID: UUID) {
        webViews[tabID]?.goForward()
    }

    func reload(tabID: UUID) {
        webViews[tabID]?.reload()
    }

    func stopLoading(tabID: UUID) {
        webViews[tabID]?.stopLoading()
    }

    func navigationState(for tabID: UUID) -> (canGoBack: Bool, canGoForward: Bool) {
        guard let webView = webViews[tabID] else {
            return (false, false)
        }

        return (webView.canGoBack, webView.canGoForward)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateStore(from: webView, isLoading: true)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateStore(from: webView, isLoading: webView.isLoading)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateStore(from: webView, isLoading: false)
        recordHistoryVisit(for: webView)
        refreshFavicon(for: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateStore(from: webView, isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateStore(from: webView, isLoading: false)
    }

    private func updateStore(from webView: WKWebView, isLoading: Bool) {
        guard
            let tabIDString = tabIDsByWebView.object(forKey: webView) as String?,
            let tabID = UUID(uuidString: tabIDString)
        else {
            return
        }

        store?.updateTabFromWebView(
            tabID: tabID,
            title: webView.title,
            url: webView.url,
            isLoading: isLoading,
            loadingProgress: isLoading ? webView.estimatedProgress : 1,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        )
    }

    private func recordHistoryVisit(for webView: WKWebView) {
        guard
            let tabIDString = tabIDsByWebView.object(forKey: webView) as String?,
            let tabID = UUID(uuidString: tabIDString)
        else {
            return
        }

        store?.recordHistoryVisit(tabID: tabID, title: webView.title, url: webView.url)
    }

    private func observe(_ webView: WKWebView, tabID: UUID) {
        observations[tabID] = [
            webView.observe(\.title, options: [.new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let webView else { return }
                    self?.updateStore(from: webView, isLoading: webView.isLoading)
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let webView else { return }
                    self?.updateStore(from: webView, isLoading: webView.isLoading)
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let webView else { return }
                    self?.updateStore(from: webView, isLoading: webView.isLoading)
                }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let webView else { return }
                    self?.updateStore(from: webView, isLoading: webView.isLoading)
                }
            }
        ]
    }

    private func refreshFavicon(for webView: WKWebView) {
        guard
            let tabIDString = tabIDsByWebView.object(forKey: webView) as String?,
            let tabID = UUID(uuidString: tabIDString)
        else {
            return
        }

        let script = """
        (() => {
          const links = Array.from(document.querySelectorAll("link[rel*='icon'], link[rel='mask-icon']"));
          const first = links.map(link => link.href).find(Boolean);
          return first || "";
        })();
        """

        webView.evaluateJavaScript(script) { [weak self, weak webView] value, _ in
            Task { @MainActor in
                guard let self, let webView else { return }
                let candidateString = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let candidateURL = candidateString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
                let data = await FaviconService.shared.faviconData(for: webView.url, candidateURL: candidateURL)
                self.store?.updateFavicon(tabID: tabID, data: data)
            }
        }
    }

    private var newTabHTML: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: light dark; }
            body {
              align-items: center;
              background: Canvas;
              color: CanvasText;
              display: flex;
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              height: 100vh;
              justify-content: center;
              margin: 0;
            }
            main { max-width: 520px; padding: 32px; text-align: center; }
            h1 { font-size: 30px; font-weight: 650; letter-spacing: 0; margin: 0 0 8px; }
            p { color: color-mix(in srgb, CanvasText 68%, transparent); font-size: 15px; line-height: 1.45; margin: 0; }
          </style>
        </head>
        <body>
          <main>
            <h1>Luma Browser</h1>
            <p>Search or enter a URL from the address bar.</p>
          </main>
        </body>
        </html>
        """
    }
}
