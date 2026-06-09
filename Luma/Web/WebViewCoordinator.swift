import Foundation
import WebKit

@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate {
    private struct PendingWebAppPrompt {
        let providerID: String
        let query: String
    }

    private static let acceptLanguageHeader = "en-US,en;q=0.9"
    private static let googleLocaleCookieNames: Set<String> = ["PREF", "NID", "SOCS"]

    private weak var store: BrowserStore?
    private var webViews: [UUID: WKWebView] = [:]
    private var tabIDsByWebView = NSMapTable<WKWebView, NSString>.weakToStrongObjects()
    private var observations: [UUID: [NSKeyValueObservation]] = [:]
    private var pendingWebAppPrompts: [UUID: PendingWebAppPrompt] = [:]
    private var cleanedLocaleCookieDataStoreIDs = Set<UUID>()

    func attach(store: BrowserStore) {
        self.store = store
    }

    func webView(for tab: BrowserTab) -> WKWebView {
        if let existingWebView = webViews[tab.id] {
            return existingWebView
        }

        let dataStoreID = store?.dataStoreID(for: tab.spaceID) ?? tab.spaceID
        let dataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)

        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = dataStore
        resetGoogleLocaleCookiesIfNeeded(in: dataStore, id: dataStoreID)

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
        let url = store?.navigationService.preferredLocaleURL(for: url) ?? url
        let webView = webViews[tabID]
        let targetWebView: WKWebView

        if let target = store?.navigationService.webAppPromptForwardingTarget(for: url) {
            pendingWebAppPrompts[tabID] = PendingWebAppPrompt(providerID: target.providerID, query: target.query)
        } else {
            pendingWebAppPrompts[tabID] = nil
        }

        if let webView {
            targetWebView = webView
        } else {
            let placeholderTab = BrowserTab(title: url.absoluteString, url: url, spaceID: UUID())
            targetWebView = self.webView(for: BrowserTab(id: tabID, title: placeholderTab.title, url: url, spaceID: placeholderTab.spaceID))
        }

        targetWebView.load(request(for: url))
    }

    func removeWebView(for tabID: UUID) {
        guard let webView = webViews.removeValue(forKey: tabID) else { return }
        pendingWebAppPrompts[tabID] = nil
        observations[tabID] = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
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
        forwardWebAppPromptIfNeeded(for: webView)
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

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.acceptLanguageHeader, forHTTPHeaderField: "Accept-Language")
        return request
    }

    private func resetGoogleLocaleCookiesIfNeeded(in dataStore: WKWebsiteDataStore, id: UUID) {
        guard !cleanedLocaleCookieDataStoreIDs.contains(id) else { return }
        cleanedLocaleCookieDataStoreIDs.insert(id)

        dataStore.httpCookieStore.getAllCookies { cookies in
            let localeCookies = cookies.filter { cookie in
                let domain = cookie.domain.lowercased()
                let isGoogleDomain = domain == "google.com" || domain == ".google.com" || domain.hasSuffix(".google.com")
                return isGoogleDomain && Self.googleLocaleCookieNames.contains(cookie.name)
            }

            localeCookies.forEach { dataStore.httpCookieStore.delete($0) }
        }
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

    private func forwardWebAppPromptIfNeeded(for webView: WKWebView) {
        guard
            let tabIDString = tabIDsByWebView.object(forKey: webView) as String?,
            let tabID = UUID(uuidString: tabIDString),
            let pendingPrompt = pendingWebAppPrompts[tabID],
            store?.navigationService.canForwardWebAppPrompt(to: webView.url, providerID: pendingPrompt.providerID) == true
        else {
            return
        }

        let promptLiteral = javaScriptStringLiteral(for: pendingPrompt.query)
        let script = """
        (() => {
          const prompt = \(promptLiteral);
          const selectors = [
            "textarea",
            "[contenteditable='true']",
            "[role='textbox']"
          ];

          const isVisible = (element) => {
            const rect = element.getBoundingClientRect();
            const style = window.getComputedStyle(element);
            return rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none";
          };

          const setPlainInputValue = (element, value) => {
            const prototype = Object.getPrototypeOf(element);
            const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
            if (descriptor && descriptor.set) {
              descriptor.set.call(element, value);
            } else {
              element.value = value;
            }
          };

          const setPromptText = (element) => {
            element.focus();
            if (element.isContentEditable) {
              const selection = window.getSelection();
              const range = document.createRange();
              range.selectNodeContents(element);
              selection.removeAllRanges();
              selection.addRange(range);
              document.execCommand("insertText", false, prompt);
            } else {
              setPlainInputValue(element, prompt);
            }

            element.dispatchEvent(new InputEvent("input", {
              bubbles: true,
              cancelable: true,
              data: prompt,
              inputType: "insertText"
            }));
            element.dispatchEvent(new Event("change", { bubbles: true }));
          };

          const submitPrompt = (element) => {
            const buttons = Array.from(document.querySelectorAll("button, [role='button']"));
            const sendButton = buttons.find((button) => {
              const label = [
                button.getAttribute("aria-label"),
                button.getAttribute("data-tooltip"),
                button.title,
                button.textContent
              ].filter(Boolean).join(" ").toLowerCase();
              return !button.disabled && !button.getAttribute("aria-disabled") && /send|submit/.test(label);
            });

            if (sendButton) {
              sendButton.click();
              return;
            }

            element.dispatchEvent(new KeyboardEvent("keydown", {
              bubbles: true,
              cancelable: true,
              key: "Enter",
              code: "Enter"
            }));
          };

          const findPromptBox = () => {
            return selectors
              .flatMap((selector) => Array.from(document.querySelectorAll(selector)))
              .filter(isVisible)
              .find((element) => !element.closest("[aria-hidden='true']"));
          };

          const deadline = Date.now() + 10000;
          return new Promise((resolve) => {
            const attempt = () => {
              const promptBox = findPromptBox();
              if (!promptBox) {
                if (Date.now() < deadline) {
                  window.setTimeout(attempt, 250);
                } else {
                  resolve(false);
                }
                return;
              }

              setPromptText(promptBox);
              window.setTimeout(() => {
                submitPrompt(promptBox);
                resolve(true);
              }, 200);
            };

            attempt();
          });
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] value, error in
            Task { @MainActor in
                self?.pendingWebAppPrompts[tabID] = nil
            }
        }
    }

    private func javaScriptStringLiteral(for value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value]),
            let arrayLiteral = String(data: data, encoding: .utf8),
            arrayLiteral.first == "[",
            arrayLiteral.last == "]"
        else {
            return "\"\""
        }

        return String(arrayLiteral.dropFirst().dropLast())
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
            <h1>Luma</h1>
            <p>Search or enter a URL from the address bar.</p>
          </main>
        </body>
        </html>
        """
    }
}
