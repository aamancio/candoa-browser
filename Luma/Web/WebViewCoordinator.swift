import AppKit
import Foundation
import WebKit

@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private struct PendingWebAppPrompt {
        let providerID: String
        let query: String
    }

    private static let acceptLanguageHeader = "en-US,en;q=0.9"
    private static let googleLocaleCookieNames: Set<String> = ["PREF", "NID", "SOCS"]
    private static let pageZoomLevels: [CGFloat] = [0.5, 0.65, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    private weak var store: BrowserStore?
    private var webViews: [UUID: WKWebView] = [:]
    private var tabIDsByWebView = NSMapTable<WKWebView, NSString>.weakToStrongObjects()
    private var observations: [UUID: [NSKeyValueObservation]] = [:]
    private var pendingWebAppPrompts: [UUID: PendingWebAppPrompt] = [:]
    private var cleanedLocaleCookieDataStoreIDs = Set<UUID>()
    private var popupTabIDsAwaitingFirstLoad = Set<UUID>()
    private var activeDownloads = Set<WKDownload>()
    private var downloadDestinations: [WKDownload: URL] = [:]
    private var hostedActiveTabID: UUID?

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
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.websiteDataStore = dataStore
        resetGoogleLocaleCookiesIfNeeded(in: dataStore, id: dataStoreID)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        register(webView, for: tab.id)

        if let url = tab.url {
            load(url, in: tab.id)
        } else {
            webView.loadHTMLString(newTabHTML, baseURL: nil)
        }

        return webView
    }

    private func register(_ webView: WKWebView, for tabID: UUID) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")

        webViews[tabID] = webView
        tabIDsByWebView.setObject(tabID.uuidString as NSString, forKey: webView)
        observe(webView, tabID: tabID)
    }

    func ensureLoaded(_ tab: BrowserTab) {
        // Popup web views own their first navigation; loading here would sever window.opener.
        guard !popupTabIDsAwaitingFirstLoad.contains(tab.id) else { return }

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
        popupTabIDsAwaitingFirstLoad.remove(tabID)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
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

    func find(_ query: String, forward: Bool, in tabID: UUID, completion: ((Bool) -> Void)? = nil) {
        guard let webView = webViews[tabID], !query.isEmpty else {
            completion?(false)
            return
        }

        let configuration = WKFindConfiguration()
        configuration.wraps = true
        configuration.caseSensitive = false
        configuration.backwards = !forward

        webView.find(query, configuration: configuration) { result in
            completion?(result.matchFound)
        }
    }

    func clearFindSelection(in tabID: UUID) {
        webViews[tabID]?.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }

    func zoomIn(tabID: UUID) {
        adjustZoom(tabID: tabID, direction: 1)
    }

    func zoomOut(tabID: UUID) {
        adjustZoom(tabID: tabID, direction: -1)
    }

    func resetZoom(tabID: UUID) {
        webViews[tabID]?.pageZoom = 1
    }

    private func adjustZoom(tabID: UUID, direction: Int) {
        guard let webView = webViews[tabID] else { return }
        let levels = Self.pageZoomLevels
        let currentIndex = levels.enumerated().min {
            abs($0.element - webView.pageZoom) < abs($1.element - webView.pageZoom)
        }?.offset ?? levels.firstIndex(of: 1) ?? 0
        let nextIndex = min(max(currentIndex + direction, 0), levels.count - 1)
        webView.pageZoom = levels[nextIndex]
    }

    // MARK: - Auto Picture-in-Picture

    /// Pops a currently-playing video out into the system PiP window when the
    /// user leaves the tab. Videos are tagged so the matching exit call only
    /// reverses PiP sessions this app started, never user-initiated ones.
    func beginAutoPictureInPicture(for tabID: UUID) {
        webViews[tabID]?.evaluateJavaScript(Self.enterAutoPiPScript)
    }

    /// Brings an auto-PiP video back inline when the user returns to its tab.
    func endAutoPictureInPicture(for tabID: UUID) {
        webViews[tabID]?.evaluateJavaScript(Self.exitAutoPiPScript)
    }

    private static let enterAutoPiPScript = """
    (() => {
      const candidates = Array.from(document.querySelectorAll("video")).filter((video) =>
        !video.paused &&
        !video.ended &&
        video.readyState >= 2 &&
        !video.disablePictureInPicture &&
        typeof video.webkitSetPresentationMode === "function" &&
        typeof video.webkitSupportsPresentationMode === "function" &&
        video.webkitSupportsPresentationMode("picture-in-picture") &&
        video.webkitPresentationMode === "inline"
      );
      if (candidates.length === 0) { return false; }

      const video = candidates.sort((a, b) =>
        (b.clientWidth * b.clientHeight) - (a.clientWidth * a.clientHeight)
      )[0];
      video.__lumaAutoPiP = true;
      video.webkitSetPresentationMode("picture-in-picture");
      return true;
    })();
    """

    private static let exitAutoPiPScript = """
    (() => {
      const video = Array.from(document.querySelectorAll("video")).find((candidate) =>
        candidate.__lumaAutoPiP === true &&
        candidate.webkitPresentationMode === "picture-in-picture"
      );
      if (!video) { return false; }

      delete video.__lumaAutoPiP;
      video.webkitSetPresentationMode("inline");
      return true;
    })();
    """

    func navigationState(for tabID: UUID) -> (canGoBack: Bool, canGoForward: Bool) {
        guard let webView = webViews[tabID] else {
            return (false, false)
        }

        return (webView.canGoBack, webView.canGoForward)
    }

    func snapshotImage(for tabID: UUID, width: CGFloat, completion: @escaping (NSImage?) -> Void) {
        guard
            let webView = webViews[tabID],
            !webView.bounds.isEmpty
        else {
            completion(nil)
            return
        }

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: webView.bounds.size)
        configuration.snapshotWidth = NSNumber(value: Double(width))

        webView.takeSnapshot(with: configuration) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
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

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        navigationAction.shouldPerformDownload ? .download : .allow
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        configureDownload(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        configureDownload(download)
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let store else { return nil }

        let sourceSpaceID = tabID(for: webView)
            .flatMap { sourceTabID in store.tabs.first { $0.id == sourceTabID }?.spaceID }
            ?? store.activeSpaceID
        let popupTab = store.createPopupTab(url: navigationAction.request.url, in: sourceSpaceID)

        // WebKit drives the popup's first navigation through the returned web view,
        // which must be created with the configuration it hands us.
        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        register(popupWebView, for: popupTab.id)
        popupTabIDsAwaitingFirstLoad.insert(popupTab.id)
        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let tabID = tabID(for: webView) else { return }
        store?.closeTab(tabID)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        let alert = javaScriptPanelAlert(message: message, frame: frame)
        _ = await presentPanel(alert, for: webView)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        let alert = javaScriptPanelAlert(message: message, frame: frame)
        alert.addButton(withTitle: "Cancel")
        return await presentPanel(alert, for: webView) == .alertFirstButtonReturn
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        let alert = javaScriptPanelAlert(message: prompt, frame: frame)
        alert.addButton(withTitle: "Cancel")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        inputField.stringValue = defaultText ?? ""
        alert.accessoryView = inputField
        alert.window.initialFirstResponder = inputField

        let response = await presentPanel(alert, for: webView)
        return response == .alertFirstButtonReturn ? inputField.stringValue : nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo
    ) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection

        let response: NSApplication.ModalResponse
        if let window = webView.window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }

        return response == .OK ? panel.urls : nil
    }

    private func javaScriptPanelAlert(message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        let host = frame.securityOrigin.host
        alert.messageText = host.isEmpty ? "This page says:" : "\(host) says:"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        return alert
    }

    private func presentPanel(_ alert: NSAlert, for webView: WKWebView) async -> NSApplication.ModalResponse {
        if let window = webView.window {
            return await alert.beginSheetModal(for: window)
        }
        return alert.runModal()
    }

    // MARK: - Downloads

    private func configureDownload(_ download: WKDownload) {
        download.delegate = self
        activeDownloads.insert(download)
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return nil
        }

        let destination = Self.uniqueDestination(for: suggestedFilename, in: downloadsDirectory)
        downloadDestinations[download] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        activeDownloads.remove(download)
        guard let destination = downloadDestinations.removeValue(forKey: download) else { return }

        // Bounces the Downloads stack in the Dock, matching native browser behavior.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.DownloadFileFinished"),
            object: destination.path,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        activeDownloads.remove(download)
        downloadDestinations[download] = nil
    }

    private static func uniqueDestination(for suggestedFilename: String, in directory: URL) -> URL {
        let baseName = (suggestedFilename as NSString).deletingPathExtension
        let fileExtension = (suggestedFilename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(suggestedFilename)
        var attempt = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            let numberedName = fileExtension.isEmpty
                ? "\(baseName) \(attempt)"
                : "\(baseName) \(attempt).\(fileExtension)"
            candidate = directory.appendingPathComponent(numberedName)
            attempt += 1
        }

        return candidate
    }

    private func tabID(for webView: WKWebView) -> UUID? {
        guard let tabIDString = tabIDsByWebView.object(forKey: webView) as String? else { return nil }
        return UUID(uuidString: tabIDString)
    }

    private func updateStore(from webView: WKWebView, isLoading: Bool) {
        guard
            let tabIDString = tabIDsByWebView.object(forKey: webView) as String?,
            let tabID = UUID(uuidString: tabIDString)
        else {
            return
        }

        if webView.url != nil {
            popupTabIDsAwaitingFirstLoad.remove(tabID)
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

// In an extension to avoid a spurious near-match warning against the
// deprecated decideMediaCapturePermissionsFor requirement.
extension WebViewCoordinator {
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        .prompt
    }
}
