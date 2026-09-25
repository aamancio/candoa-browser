import AppKit
import CryptoKit
import WebKit
import XCTest
@testable import Talos

/// Unit coverage for pure app logic that needs no window: site-permission
/// origin-key normalization and stored-override parsing.
final class TalosTests: XCTestCase {
    // MARK: - Site permission origin keys (pure normalization)

    func testOriginKeyFoldsDefaultPorts() {
        XCTAssertEqual(
            SitePermissionConfiguration.originKey(for: URL(string: "https://Example.com/page")!),
            "https://example.com:443"
        )
        XCTAssertEqual(
            SitePermissionConfiguration.originKey(for: URL(string: "http://example.com")!),
            "http://example.com:80"
        )
        XCTAssertEqual(
            SitePermissionConfiguration.originKey(for: URL(string: "https://example.com:8443")!),
            "https://example.com:8443"
        )
        XCTAssertNil(SitePermissionConfiguration.originKey(for: URL(string: "file:///tmp/x")!))
        // WKSecurityOrigin reports the default port as 0.
        XCTAssertEqual(
            SitePermissionConfiguration.originKey(scheme: "HTTPS", host: "Example.com", port: 0),
            "https://example.com:443"
        )
    }

    func testPermissionDecisionsParseFromStoredOverrides() {
        let stored = #"{"https://example.com:443":{"popup-windows":"deny","camera":"allow"}}"#
        let url = URL(string: "https://example.com/")!

        XCTAssertEqual(
            SitePermissionConfiguration.decision(for: .popupWindows, url: url, storedOverrides: stored),
            .deny
        )
        XCTAssertEqual(
            SitePermissionConfiguration.decision(for: .camera, url: url, storedOverrides: stored),
            .allow
        )
        // Unstored permissions and garbage payloads fall back to defaults.
        XCTAssertEqual(
            SitePermissionConfiguration.decision(for: .microphone, url: url, storedOverrides: stored),
            .ask
        )
        XCTAssertEqual(
            SitePermissionConfiguration.decision(for: .popupWindows, url: url, storedOverrides: "not json"),
            .allow
        )
    }
}

/// Address-bar scheme selection: bare hosts default to HTTPS, except
/// localhost and loopback hosts, which Safari defaults to plain HTTP.
final class NavigationSchemeTests: XCTestCase {
    private let service = NavigationService()

    private func destination(_ input: String) -> String? {
        service.destinationURL(for: input)?.absoluteString
    }

    func testBareHostsDefaultToHTTPS() {
        XCTAssertEqual(destination("example.com"), "https://example.com")
        XCTAssertEqual(destination("example.com/path"), "https://example.com/path")
    }

    func testLocalhostDefaultsToHTTP() {
        XCTAssertEqual(destination("localhost"), "http://localhost")
        XCTAssertEqual(destination("localhost:3000"), "http://localhost:3000")
        XCTAssertEqual(destination("localhost:8080/admin"), "http://localhost:8080/admin")
        XCTAssertEqual(destination("app.localhost:3000"), "http://app.localhost:3000")
    }

    func testLoopbackAddressesDefaultToHTTP() {
        XCTAssertEqual(destination("127.0.0.1"), "http://127.0.0.1")
        XCTAssertEqual(destination("127.0.0.1:3000"), "http://127.0.0.1:3000")
        XCTAssertEqual(destination("0.0.0.0:8080"), "http://0.0.0.0:8080")
    }

    func testExplicitSchemeIsPreserved() {
        XCTAssertEqual(destination("https://localhost:8443"), "https://localhost:8443")
        XCTAssertEqual(destination("http://example.com"), "http://example.com")
    }

    func testNonLoopbackAddressesStayHTTPS() {
        XCTAssertEqual(destination("192.168.1.10:8080"), "https://192.168.1.10:8080")
        XCTAssertEqual(destination("localhost.example.com"), "https://localhost.example.com")
    }

    // MARK: - Tab switcher thumbnails (issue #340)

    /// A filled snapshot of an explicit point size, backed by `scale` pixels
    /// per point. Built by hand rather than with `lockFocus`, which adopts the
    /// test machine's display scale and would make these assertions depend on
    /// whether the run happens on a Retina Mac.
    private func solidImage(width: Int, height: Int, scale: Int = 1) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width * scale,
            pixelsHigh: height * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    func testThumbnailBitmapDownscalesWideSnapshotsPreservingAspect() throws {
        // Wake snapshots are captured up to 1024pt wide; the disk cache keeps
        // them at switcher width so the launch-time load stays cheap.
        let bitmap = try XCTUnwrap(
            TabSnapshotStore.thumbnailBitmap(from: solidImage(width: 1024, height: 640), maxWidth: 320)
        )
        XCTAssertEqual(bitmap.pixelsWide, 320)
        XCTAssertEqual(bitmap.pixelsHigh, 200)
    }

    func testThumbnailBitmapLeavesNarrowSnapshotsAlone() throws {
        let bitmap = try XCTUnwrap(
            TabSnapshotStore.thumbnailBitmap(from: solidImage(width: 300, height: 180), maxWidth: 320)
        )
        XCTAssertEqual(bitmap.pixelsWide, 300)
        XCTAssertEqual(bitmap.pixelsHigh, 180)
    }

    func testThumbnailBitmapFillsTheThumbnailFromARetinaSnapshot() throws {
        // Regression: measuring the source in pixels but drawing from a point
        // space rect left the page in the bottom-left quadrant (issue #347).
        let bitmap = try XCTUnwrap(
            TabSnapshotStore.thumbnailBitmap(from: solidImage(width: 512, height: 320, scale: 2), maxWidth: 320)
        )
        XCTAssertEqual(bitmap.pixelsWide, 320)
        XCTAssertEqual(bitmap.pixelsHigh, 200)
        for point in [NSPoint(x: 1, y: 1), NSPoint(x: 318, y: 1), NSPoint(x: 1, y: 198), NSPoint(x: 318, y: 198)] {
            let color = try XCTUnwrap(bitmap.colorAt(x: Int(point.x), y: Int(point.y)))
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01, "thumbnail corner \(point) is empty")
        }
    }

    func testPreviewWarmupOnlyLoadsWebPages() {
        XCTAssertTrue(WebViewCoordinator.isWarmable(URL(string: "https://example.com/a")!))
        XCTAssertTrue(WebViewCoordinator.isWarmable(URL(string: "HTTP://example.com")!))
        XCTAssertFalse(WebViewCoordinator.isWarmable(URL(string: "mailto:someone@example.com")!))
        XCTAssertFalse(WebViewCoordinator.isWarmable(URL(string: "file:///tmp/page.html")!))
        XCTAssertFalse(WebViewCoordinator.isWarmable(URL(string: "talos://welcome")!))
    }

    // MARK: - Address display text

    func testDisplayDomainKeepsHostAndPortOnly() {
        // Zen's urlbarTrim under zen.urlbar.show-domain-only-in-sidebar, and
        // what Arc's sidebar field shows.
        XCTAssertEqual(
            URL(string: "https://www.youtube.com/watch?v=abc")!.displayDomainText,
            "youtube.com"
        )
        XCTAssertEqual(
            URL(string: "http://localhost:8080/financial")!.displayDomainText,
            "localhost:8080"
        )
        XCTAssertEqual(
            URL(string: "https://docs.google.com/document/d/1")!.displayDomainText,
            "docs.google.com"
        )
    }

    func testDisplayDomainStripsWWWOnlyAsALeadingLabel() {
        XCTAssertEqual(URL(string: "https://wwwx.example.com/")!.displayDomainText, "wwwx.example.com")
        XCTAssertEqual(URL(string: "https://cdn.www.example.com/")!.displayDomainText, "cdn.www.example.com")
        XCTAssertEqual(URL(string: "https://www.example.com/")!.displayDomainText, "example.com")
    }

    func testDisplayDomainFallsBackForHostlessURLs() {
        XCTAssertEqual(
            URL(string: "file:///tmp/page.html")!.displayDomainText,
            "file:///tmp/page.html"
        )
    }
}

/// Provider search-results pages never lead the command bar's suggestions:
/// retyping a phrase that repeats a past site search must still default to
/// the search engine, not re-run the site search. The predicate that spots
/// those pages is pure logic.
final class ProviderSearchResultsURLTests: XCTestCase {
    private func isResultsURL(_ urlString: String) -> Bool {
        NavigationService.isProviderSearchResultsURL(URL(string: urlString)!)
    }

    func testRecognizesProviderResultsPages() {
        XCTAssertTrue(isResultsURL("https://www.youtube.com/results?search_query=unidad+deportiva+belen"))
        XCTAssertTrue(isResultsURL("https://www.google.com/search?q=weather&hl=en"))
        XCTAssertTrue(isResultsURL("https://duckduckgo.com/?q=swift"))
    }

    func testHostMatchIgnoresWWWAndCase() {
        XCTAssertTrue(isResultsURL("https://youtube.com/results?search_query=x"))
        XCTAssertTrue(isResultsURL("HTTPS://WWW.YOUTUBE.COM/results?search_query=x"))
    }

    func testOrdinaryPagesOnProviderSitesDoNotMatch() {
        XCTAssertFalse(isResultsURL("https://www.youtube.com/watch?v=QHXV3HzdzkE"))
        XCTAssertFalse(isResultsURL("https://www.youtube.com/"))
        XCTAssertFalse(isResultsURL("https://www.google.com/maps?q=bogota"))
        XCTAssertFalse(isResultsURL("https://example.com/search?q=swift"))
    }

    func testResultsPathWithoutTheQueryParameterDoesNotMatch() {
        XCTAssertFalse(isResultsURL("https://www.youtube.com/results"))
        XCTAssertFalse(isResultsURL("https://www.youtube.com/results?search_query="))
        XCTAssertFalse(isResultsURL("https://www.google.com/search?tbm=isch"))
    }

    func testEveryProviderRecognizesItsOwnSearchURL() {
        for provider in NavigationService.searchProviders {
            let url = provider.searchURL(for: "unidad deportiva belen")
            XCTAssertNotNil(url, provider.id)
            if let url {
                XCTAssertTrue(provider.isSearchResultsURL(url), "\(provider.id): \(url)")
                XCTAssertTrue(NavigationService.isProviderSearchResultsURL(url), provider.id)
            }
        }
    }
}

/// An extension's manifest shortcut round-trips through the stored string
/// the Shortcuts pane records, so a rebinding lands on the command exactly
/// as WebKit expects it (activation key plus modifier flags).
final class WebExtensionShortcutTests: XCTestCase {
    func testManifestKeyReadsAsTheStoredSpelling() {
        XCTAssertEqual(WebExtensionShortcut.string(activationKey: "e", modifierFlags: .command), "Command-E")
        XCTAssertEqual(
            WebExtensionShortcut.string(activationKey: "y", modifierFlags: [.command, .shift, .option]),
            "Option-Shift-Command-Y"
        )
        XCTAssertEqual(
            WebExtensionShortcut.string(
                activationKey: String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!),
                modifierFlags: [.control]
            ),
            "Control-Up"
        )
        XCTAssertEqual(WebExtensionShortcut.string(activationKey: nil, modifierFlags: .command), "None")
        XCTAssertEqual(WebExtensionShortcut.string(activationKey: "", modifierFlags: []), "None")
    }

    func testStoredSpellingBecomesTheCommandsKey() {
        let rebinding = WebExtensionShortcut.components(from: "Shift-Command-E")
        XCTAssertEqual(rebinding.activationKey, "e")
        XCTAssertEqual(rebinding.modifierFlags, [.shift, .command])

        let named = WebExtensionShortcut.components(from: "Control-F5")
        XCTAssertEqual(named.activationKey, String(UnicodeScalar(UInt32(NSF5FunctionKey))!))
        XCTAssertEqual(named.modifierFlags, [.control])

        let dash = WebExtensionShortcut.components(from: "Command--")
        XCTAssertEqual(dash.activationKey, "-")
        XCTAssertEqual(dash.modifierFlags, [.command])
    }

    func testRemovedAndUnreadableSpellingsClearTheKey() {
        for stored in ["", "None", WebExtensionShortcut.removedValue, "Hyper-E", "Command-Escape", "E"] {
            let components = WebExtensionShortcut.components(from: stored)
            XCTAssertNil(components.activationKey, stored)
            XCTAssertEqual(components.modifierFlags, [], stored)
        }
    }

    /// WebKit parses a manifest's `suggested_key` into the command; the
    /// pane must read that back as the spelling it would record itself.
    @MainActor
    func testManifestSuggestedKeyReadsBackAsTheStoredSpelling() async throws {
        guard #available(macOS 15.4, *) else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("talos-command-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = """
        {"manifest_version": 3, "name": "Fixture", "version": "1.0",
         "commands": {"toggle-side-panel": {"suggested_key": {"default": "Ctrl+E", "mac": "Command+E"},
                                            "description": "Toggle the panel"}}}
        """
        try manifest.write(to: root.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let webExtension = try await WKWebExtension(resourceBaseURL: root)
        let context = WKWebExtensionContext(for: webExtension)
        let command = try XCTUnwrap(context.commands.first { $0.id == "toggle-side-panel" })
        XCTAssertEqual(command.title, "Toggle the panel")
        XCTAssertEqual(
            WebExtensionShortcut.string(activationKey: command.activationKey, modifierFlags: command.modifierFlags),
            "Command-E"
        )

        // A rebinding lands on the command in the form WebKit matches events against.
        let rebinding = WebExtensionShortcut.components(from: "Shift-Command-E")
        command.activationKey = rebinding.activationKey
        command.modifierFlags = rebinding.modifierFlags
        XCTAssertEqual(command.activationKey, "e")
        XCTAssertEqual(command.modifierFlags, [.shift, .command])

        // Loaded, the command claims exactly its key event — the check the
        // window's key monitor relies on — and no other.
        let controller = WKWebExtensionController(configuration: .default())
        try controller.load(context)
        defer { try? controller.unload(context) }
        func keyEvent(_ characters: String, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 14
            )!
        }
        XCTAssertTrue(context.performCommand(for: keyEvent("E", [.shift, .command])))
        XCTAssertFalse(context.performCommand(for: keyEvent("e", [.command])))
        XCTAssertFalse(context.performCommand(for: keyEvent("E", [.shift, .option])))

        command.activationKey = nil
        XCTAssertFalse(context.performCommand(for: keyEvent("E", [.shift, .command])))
    }

    func testEveryNamedKeyRoundTrips() {
        for name in ["Tab", "Space", "Left", "Right", "Up", "Down", "Home", "End", "PageUp", "PageDown", "F1", "F12"] {
            let stored = "Option-Command-\(name)"
            let components = WebExtensionShortcut.components(from: stored)
            XCTAssertEqual(
                WebExtensionShortcut.string(activationKey: components.activationKey, modifierFlags: components.modifierFlags),
                stored
            )
        }
    }
}

/// The command palette teaches shortcuts by mapping each row's action back to
/// its rebindable `ShortcutDefinition` (issue #370). Pure logic: no palette
/// UI or persistence involved.
final class PaletteShortcutTests: XCTestCase {
    func testBaseActionsMapToTheirShortcutDefinitions() {
        XCTAssertEqual(PaletteAction.newTab.shortcutDefinition, .newTab)
        XCTAssertEqual(PaletteAction.closeCurrentTab.shortcutDefinition, .closeCurrentTab)
        XCTAssertEqual(PaletteAction.reloadTab.shortcutDefinition, .reloadTab)
        XCTAssertEqual(PaletteAction.focusAddressBar.shortcutDefinition, .focusAddressBar)
        XCTAssertEqual(PaletteAction.toggleSplitView.shortcutDefinition, .toggleSplitView)
        XCTAssertEqual(PaletteAction.toggleSplitPaneZoom.shortcutDefinition, .zoomSplitPane)
        XCTAssertEqual(PaletteAction.focusSplitPane(1).shortcutDefinition, .focusNextSplitPane)
        XCTAssertEqual(PaletteAction.focusSplitPane(-1).shortcutDefinition, .focusPreviousSplitPane)
        XCTAssertEqual(PaletteAction.unsplitPane.shortcutDefinition, .unsplitPane)
        XCTAssertEqual(PaletteAction.togglePinTab.shortcutDefinition, .pinOrUnpinTab)
    }

    func testPaletteOnlyActionsHaveNoShortcut() {
        XCTAssertNil(PaletteAction.duplicateCurrentTab.shortcutDefinition)
        XCTAssertNil(PaletteAction.createSpace.shortcutDefinition)
        XCTAssertNil(PaletteAction.setDeveloperMode(true).shortcutDefinition)
        XCTAssertNil(PaletteAction.navigate("https://example.com").shortcutDefinition)
        XCTAssertNil(PaletteAction.switchTab(UUID()).shortcutDefinition)
        XCTAssertNil(PaletteAction.switchSpace(UUID()).shortcutDefinition)
    }

    func testCommandKeysFollowTheStoredRebind() {
        let key = ShortcutDefinition.reloadTab.storageKey
        let previous = UserDefaults.standard.string(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let command = PaletteCommand(title: "Reload", symbolName: "arrow.clockwise", action: .reloadTab)

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(command.shortcutKeys, ["⌘", "R"])

        UserDefaults.standard.set("Shift-Command-R", forKey: key)
        XCTAssertEqual(command.shortcutKeys, ["⇧", "⌘", "R"])

        UserDefaults.standard.set(ShortcutDefinition.removedValue, forKey: key)
        XCTAssertEqual(command.shortcutKeys, [])
    }

    // MARK: - Split membership survives a reorder

    private func regularTab(folderID: UUID? = nil) -> BrowserTab {
        BrowserTab(
            title: "Tab",
            url: URL(string: "https://example.com")!,
            isFavorite: false,
            isPinned: false,
            folderID: folderID,
            spaceID: UUID()
        )
    }

    /// Dragging a split tab within its own section used to detach it, which
    /// made split tabs impossible to reorder without losing the split.
    func testReorderingWithinTheSameSectionKeepsSplitMembership() {
        let tab = regularTab()
        XCTAssertFalse(
            BrowserStore.splitMemberLeavesItsSection(
                current: tab,
                isFavorite: false,
                isPinned: false,
                folderID: nil
            )
        )
    }

    func testMovingASplitMemberToAnotherSectionDetachesIt() {
        let tab = regularTab()
        let folder = UUID()
        for (favorite, pinned, folderID) in [
            (true, false, nil as UUID?),
            (false, true, nil as UUID?),
            (false, false, folder as UUID?)
        ] {
            XCTAssertTrue(
                BrowserStore.splitMemberLeavesItsSection(
                    current: tab,
                    isFavorite: favorite,
                    isPinned: pinned,
                    folderID: folderID
                ),
                "favorite=\(favorite) pinned=\(pinned) folder=\(String(describing: folderID))"
            )
        }
    }

    func testAFolderMemberReorderedInsideThatFolderStaysSplit() {
        let folder = UUID()
        let tab = regularTab(folderID: folder)
        XCTAssertFalse(
            BrowserStore.splitMemberLeavesItsSection(
                current: tab,
                isFavorite: false,
                isPinned: false,
                folderID: folder
            )
        )
    }

    // MARK: - Dropping onto the split pair's row

    private func tabs(_ n: Int) -> [BrowserTab] {
        (0..<n).map { i in
            BrowserTab(
                title: "Tab \(i)",
                url: URL(string: "https://example.com/\(i)")!,
                spaceID: UUID()
            )
        }
    }

    /// The pair's row anchors on whichever member comes first, so a drop on
    /// its top edge has to land before that member and a drop on its bottom
    /// edge after it. The row carried no delegate at all before, so neither
    /// of these was reachable.
    func testDroppingAboveThePairLandsBeforeItsFirstMember() {
        let list = tabs(5)
        let dragged = list[4]
        XCTAssertEqual(
            insertionBeforeID(
                targetTabID: list[1].id,
                edge: .before,
                tabs: list,
                draggedID: dragged.id
            ),
            list[1].id
        )
    }

    func testDroppingBelowThePairLandsAfterItsFirstMember() {
        let list = tabs(5)
        let dragged = list[4]
        XCTAssertEqual(
            insertionBeforeID(
                targetTabID: list[1].id,
                edge: .after,
                tabs: list,
                draggedID: dragged.id
            ),
            list[2].id
        )
    }

    /// Dropping after the last row appends rather than naming a neighbour.
    func testDroppingAfterTheLastRowAppends() {
        let list = tabs(3)
        let dragged = list[0]
        XCTAssertNil(
            insertionBeforeID(
                targetTabID: list[2].id,
                edge: .after,
                tabs: list,
                draggedID: dragged.id
            )
        )
    }

    /// The dragged tab is not its own neighbour: without filtering it out, a
    /// drop just below it would resolve to itself and no-op.
    func testTheDraggedTabIsExcludedFromNeighbourLookup() {
        let list = tabs(4)
        XCTAssertEqual(
            insertionBeforeID(
                targetTabID: list[0].id,
                edge: .after,
                tabs: list,
                draggedID: list[1].id
            ),
            list[2].id
        )
    }

    // MARK: - A split pair moves as a block

    /// Moving one member used to leave the other behind, and the pair's row
    /// redrew at the member that had not moved — so the drag ran correctly
    /// and the list looked unchanged.
    func testMovingAMemberBringsItsPartner() {
        let ids = (0..<6).map { _ in UUID() }
        let group: Set<UUID> = [ids[0], ids[1]]
        // The pair started at the front; the dragged member landed at index 4.
        let dropped = [ids[1], ids[2], ids[3], ids[4], ids[0], ids[5]]
        XCTAssertEqual(
            BrowserStore.keepingSplitPartnersAdjacent(to: ids[0], in: dropped, splitGroup: group),
            [ids[2], ids[3], ids[4], ids[0], ids[1], ids[5]]
        )
    }

    func testMovingANonMemberChangesNothing() {
        let ids = (0..<4).map { _ in UUID() }
        let order = [ids[0], ids[1], ids[2], ids[3]]
        XCTAssertEqual(
            BrowserStore.keepingSplitPartnersAdjacent(
                to: ids[2],
                in: order,
                splitGroup: [ids[0], ids[1]]
            ),
            order
        )
    }

    func testPartnersKeepTheirRelativeOrder() {
        let ids = (0..<5).map { _ in UUID() }
        let group: Set<UUID> = [ids[0], ids[1], ids[2]]
        let dropped = [ids[1], ids[2], ids[3], ids[0], ids[4]]
        XCTAssertEqual(
            BrowserStore.keepingSplitPartnersAdjacent(to: ids[0], in: dropped, splitGroup: group),
            [ids[3], ids[0], ids[1], ids[2], ids[4]]
        )
    }

    // MARK: - Web pane geometry

    /// The page card an attached inspector is laid out in, and the insets the
    /// page is left with, both come out of the pane host's own geometry.
    @MainActor
    private func makePaneHost(laneLeading: CGFloat, laneTrailing: CGFloat) -> WebPaneHostView {
        let host = WebPaneHostView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        host.layoutHostedSubviews(
            laneInsets: BrowserInterfaceInsets(leading: laneLeading, trailing: laneTrailing)
        )
        return host
    }

    @MainActor
    func testPageAreaInsetsAreTheReservedLanesWithoutAnInspector() {
        let host = makePaneHost(laneLeading: 280, laneTrailing: 60)

        // WebKit reads the stand-in's frame to decide whether it can dock at
        // all, so laying the host out has to size it there and then — waiting
        // for AppKit's next layout pass leaves docking refused.
        XCTAssertEqual(host.inspectorLane.pageArea.frame, host.inspectorLane.bounds)

        let insets = host.pageAreaInsets
        XCTAssertEqual(insets.left, 280, accuracy: 0.5)
        XCTAssertEqual(insets.right, 60, accuracy: 0.5)
        XCTAssertEqual(insets.top, 0, accuracy: 0.5)
        XCTAssertEqual(insets.bottom, 0, accuracy: 0.5)
    }

    /// WebKit shrinks the stand-in to whatever the docked inspector leaves —
    /// that rectangle is what the page's obscured insets have to describe.
    @MainActor
    func testPageAreaInsetsFollowADockedInspector() {
        let host = makePaneHost(laneLeading: 280, laneTrailing: 0)
        let inspectorHeight: CGFloat = 300
        host.inspectorLane.addSubview(NSView(frame: NSRect(x: 0, y: 0, width: 920, height: inspectorHeight)))
        host.inspectorLane.pageArea.frame = NSRect(x: 0, y: inspectorHeight, width: 920, height: 500)

        let insets = host.pageAreaInsets
        XCTAssertEqual(insets.left, 280, accuracy: 0.5)
        XCTAssertEqual(insets.bottom, inspectorHeight, accuracy: 0.5)
        XCTAssertEqual(insets.right, 0, accuracy: 0.5)
        XCTAssertEqual(insets.top, 0, accuracy: 0.5)
    }

    /// The lane sits over the page, so it has to be invisible to the pointer
    /// everywhere the inspector is not.
    @MainActor
    func testTheInspectorLanePassesClicksThroughWhileEmpty() {
        let host = makePaneHost(laneLeading: 280, laneTrailing: 0)
        let insideTheCard = NSPoint(x: 600, y: 400)
        XCTAssertNil(host.inspectorLane.hitTest(insideTheCard))
        XCTAssertNil(host.inspectorLane.pageArea.hitTest(insideTheCard))
    }

    /// A hosted web view spans the whole host, lanes included, and stays under
    /// the lane so a docked inspector paints over the page.
    @MainActor
    func testHostedWebViewsSpanTheHostBeneathTheInspectorLane() {
        let host = makePaneHost(laneLeading: 280, laneTrailing: 60)
        let page = NSView(frame: .zero)
        host.hostSubview(page)
        host.layoutHostedSubviews(laneInsets: BrowserInterfaceInsets(leading: 280, trailing: 60))

        XCTAssertEqual(page.frame, host.bounds)
        XCTAssertEqual(host.inspectorLane.frame, NSRect(x: 280, y: 0, width: 860, height: 800))
        XCTAssertLessThan(
            host.subviews.firstIndex(of: page) ?? -1,
            host.subviews.firstIndex(of: host.inspectorLane) ?? -1
        )
    }
}

/// The Chrome Web Store's item pages are the only input to Talos's install
/// path, and its download endpoint the only output — both are pure string
/// work, so both are checked here.
final class ChromeWebStoreTests: XCTestCase {
    func testStoreItemIDIsReadFromEveryDetailPageShape() {
        let expected = "ddkjiahejlhfcafbddmgiahcphecmpfh"
        let urls = [
            "https://chromewebstore.google.com/detail/ublock-origin-lite/\(expected)",
            "https://chromewebstore.google.com/detail/\(expected)",
            "https://chromewebstore.google.com/detail/ublock-origin-lite/\(expected)/reviews",
            "https://chromewebstore.google.com/detail/ublock-origin-lite/\(expected)?hl=fr",
            "https://chrome.google.com/webstore/detail/ublock-origin-lite/\(expected)"
        ]
        for string in urls {
            let url = URL(string: string) ?? URL(fileURLWithPath: "/")
            XCTAssertEqual(ChromeWebStore.itemID(from: url), expected, string)
        }
    }

    func testPagesWithoutAnItemAreNotInstallable() {
        let urls = [
            "https://chromewebstore.google.com/category/extensions",
            "https://chromewebstore.google.com/search/ublock",
            "https://example.com/detail/ublock/ddkjiahejlhfcafbddmgiahcphecmpfh",
            "https://chromewebstore.google.com/detail/ublock-origin-lite/short"
        ]
        for string in urls {
            let url = URL(string: string) ?? URL(fileURLWithPath: "/")
            XCTAssertNil(ChromeWebStore.itemID(from: url), string)
        }
    }

    func testDownloadURLCarriesTheItemAndAVersionTheStoreAccepts() throws {
        let itemID = "ddkjiahejlhfcafbddmgiahcphecmpfh"
        let url = try XCTUnwrap(ChromeWebStore.downloadURL(forItemID: itemID))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try XCTUnwrap(components.queryItems)

        XCTAssertEqual(components.host, "clients2.google.com")
        XCTAssertEqual(queryItems.first { $0.name == "x" }?.value, "id=\(itemID)&installsource=ondemand&uc")
        XCTAssertEqual(queryItems.first { $0.name == "acceptformat" }?.value, "crx2,crx3")
        XCTAssertNotNil(queryItems.first { $0.name == "prodversion" }?.value)
    }
}

/// Themes are the one thing the extension install path turns away: Chrome and
/// Firefox both ship them as extensions, and Talos dresses its windows from
/// its own Spaces.
final class WebExtensionInstallerTests: XCTestCase {
    private func stagedResult(manifest: String) throws -> Result<URL, Error> {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-\(UUID().uuidString)", isDirectory: true)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("staged-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: source.appendingPathComponent("manifest.json"))
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        do {
            // Read the staged tree before the defer above clears it.
            let root = try WebExtensionInstaller.stage(source, to: destination)
            return .success(
                FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path)
                    ? root : URL(fileURLWithPath: "/nonexistent")
            )
        } catch {
            return .failure(error)
        }
    }

    func testChromeAndFirefoxThemesAreRefused() throws {
        let manifests = [
            #"{"manifest_version": 3, "name": "Deep Dark", "version": "1", "theme": {"colors": {"frame": [0, 0, 0]}}}"#,
            #"{"manifest_version": 2, "name": "Firefox Look", "version": "1", "theme": {"images": {"theme_frame": "f.png"}}}"#
        ]
        for manifest in manifests {
            switch try stagedResult(manifest: manifest) {
            case .success:
                XCTFail("A browser theme should never stage as an extension.")
            case .failure(let error):
                XCTAssertEqual(error as? WebExtensionInstaller.InstallError, .browserTheme)
            }
        }
    }

    func testOrdinaryExtensionsStillStage() throws {
        let manifest = #"{"manifest_version": 3, "name": "Blocker", "version": "1", "permissions": ["storage"]}"#
        switch try stagedResult(manifest: manifest) {
        case .success(let root):
            XCTAssertNotEqual(root.path, "/nonexistent", "The staged tree should hold the manifest.")
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }
    }
}

/// The words the install prompt puts in front of someone: no API names, host
/// access first, and silence for the permissions that tell nobody anything.
final class WebExtensionPermissionCopyTests: XCTestCase {
    func testHostAccessReadsLikeChromesDialog() {
        XCTAssertEqual(
            WebExtensionPermissionCopy.websiteWarning(
                allHosts: false,
                hosts: ["*.youtube.com", "sponsor.ajay.app", "www.youtube-nocookie.com"]
            ),
            "Read and change your data on all youtube.com sites, sponsor.ajay.app, and www.youtube-nocookie.com"
        )
        XCTAssertEqual(
            WebExtensionPermissionCopy.websiteWarning(allHosts: true, hosts: ["example.com"]),
            "Read and change all your data on all websites"
        )
        XCTAssertNil(WebExtensionPermissionCopy.websiteWarning(allHosts: false, hosts: []))
    }

    func testLongHostListsEndInACount() {
        let hosts = (1...8).map { "site\($0).com" }
        let warning = try? XCTUnwrap(
            WebExtensionPermissionCopy.websiteWarning(allHosts: false, hosts: hosts)
        )
        XCTAssertEqual(warning?.contains("3 more sites"), true)
        XCTAssertEqual(warning?.contains("site6.com"), false)
    }

    func testUninformativePermissionsAreLeftUnsaid() {
        let warnings = WebExtensionPermissionCopy.warnings(
            permissions: ["storage", "alarms", "contextMenus", "activeTab", "scripting", "unlimitedStorage"],
            allHosts: false,
            hosts: []
        )
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(
            WebExtensionPermissionCopy.informativeText(for: warnings),
            "It doesn't ask for access to your data."
        )
    }

    func testWebsiteAccessLeadsAndDuplicatesCollapse() {
        let warnings = WebExtensionPermissionCopy.warnings(
            permissions: ["tabs", "webNavigation", "downloads", "storage"],
            allHosts: true,
            hosts: []
        )
        XCTAssertEqual(warnings, [
            "Read and change all your data on all websites",
            "Manage your downloads",
            "Read your browsing history"
        ])
        XCTAssertTrue(WebExtensionPermissionCopy.informativeText(for: warnings).hasPrefix("It can:"))
    }
}

/// Command bar learning ("typed this, opened that"): the ranking and
/// retention rules behind the address bar reordering suggestions around the
/// row a person actually picks.
final class CommandBarSelectionMemoryTests: XCTestCase {

    private func selection(
        typed: String,
        url: String,
        count: Int = 1,
        secondsAgo: TimeInterval = 0
    ) -> CommandBarSelection {
        CommandBarSelection(
            typedText: typed,
            title: url,
            urlString: url,
            count: count,
            lastSelectedAt: Date(timeIntervalSince1970: 1_700_000_000 - secondsAgo)
        )
    }

    func testTheChosenRowLeadsTheNextTimeTheSameTextIsTyped() {
        let selections = CommandBarSelectionRanking.recording(
            [],
            typedText: "sls",
            title: "SwingLifeStyle.com",
            urlString: "https://www.swinglifestyle.com",
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let matches = CommandBarSelectionRanking.matches(selections, for: "sls")
        XCTAssertEqual(matches.map(\.urlString), ["https://www.swinglifestyle.com"])
    }

    func testRepeatedPicksOutrankASingleStrayOne() {
        let selections = [
            selection(typed: "news", url: "https://stray.example.com", count: 1, secondsAgo: 0),
            selection(typed: "news", url: "https://daily.example.com", count: 4, secondsAgo: 600)
        ]
        XCTAssertEqual(
            CommandBarSelectionRanking.matches(selections, for: "news").map(\.urlString),
            ["https://daily.example.com", "https://stray.example.com"]
        )
    }

    func testTheMostRecentPickWinsATie() {
        let selections = [
            selection(typed: "sls", url: "https://www.google.com/search?q=sls", secondsAgo: 600),
            selection(typed: "sls", url: "https://www.swinglifestyle.com", secondsAgo: 0)
        ]
        XCTAssertEqual(
            CommandBarSelectionRanking.matches(selections, for: "sls").first?.urlString,
            "https://www.swinglifestyle.com"
        )
    }

    func testATypedPrefixRecallsTheLongerPhraseButNotTheOtherWayAround() {
        let selections = [selection(typed: "swing", url: "https://www.swinglifestyle.com")]
        XCTAssertEqual(CommandBarSelectionRanking.matches(selections, for: "sw").count, 1)
        XCTAssertEqual(CommandBarSelectionRanking.matches(selections, for: "SWING").count, 1)
        XCTAssertEqual(CommandBarSelectionRanking.matches(selections, for: "swings").count, 0)
        XCTAssertEqual(CommandBarSelectionRanking.matches(selections, for: " ").count, 0)
    }

    func testPickingTheSamePageAgainReinforcesOneEntry() {
        var selections: [CommandBarSelection] = []
        for offset in 0..<3 {
            selections = CommandBarSelectionRanking.recording(
                selections,
                typedText: "  SLS ",
                title: "SwingLifeStyle",
                urlString: "https://www.swinglifestyle.com/",
                at: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(offset))
            )
        }
        XCTAssertEqual(selections.count, 1)
        XCTAssertEqual(selections.first?.count, 3)
        XCTAssertEqual(selections.first?.typedText, "sls")
    }

    func testTheListStaysCappedAndDropsTheLeastUsedPairing() {
        var selections = (0..<CommandBarSelectionRanking.maximumSelections).map {
            selection(typed: "q\($0)", url: "https://site\($0).example.com", count: 5)
        }
        selections[0].count = 1
        selections = CommandBarSelectionRanking.recording(
            selections,
            typedText: "fresh",
            title: "Fresh",
            urlString: "https://fresh.example.com",
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(selections.count, CommandBarSelectionRanking.maximumSelections)
        XCTAssertEqual(CommandBarSelectionRanking.matches(selections, for: "q0"), [])
        XCTAssertEqual(CommandBarSelectionRanking.matches(selections, for: "fresh").count, 1)
    }

    func testClearingHistoryTakesThePicksLearnedFromIt() {
        let selections = [
            selection(typed: "sls", url: "https://www.swinglifestyle.com", secondsAgo: 0),
            selection(typed: "old", url: "https://old.example.com", secondsAgo: 10_000)
        ]
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000 - 5_000)
        XCTAssertEqual(
            CommandBarSelectionRanking.forgetting(selections, selectedAfter: cutoff).map(\.urlString),
            ["https://old.example.com"]
        )
        XCTAssertEqual(CommandBarSelectionRanking.forgetting(selections, selectedAfter: nil), [])
        XCTAssertEqual(
            CommandBarSelectionRanking.forgetting(
                selections,
                urls: ["https://www.swinglifestyle.com/"]
            ).map(\.urlString),
            ["https://old.example.com"]
        )
    }

    func testPicksAgeOutWithTheRetentionWindow() {
        let selections = [
            selection(typed: "sls", url: "https://www.swinglifestyle.com", secondsAgo: 0),
            selection(typed: "sls", url: "https://stale.example.com", secondsAgo: 100_000)
        ]
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000 - 50_000)
        XCTAssertEqual(
            CommandBarSelectionRanking.pruned(selections, before: cutoff).map(\.urlString),
            ["https://www.swinglifestyle.com"]
        )
        XCTAssertEqual(CommandBarSelectionRanking.pruned(selections, before: nil).count, 2)
    }

    @MainActor
    func testPrivateWindowsLearnNothingAndRecallNothing() throws {
        let memory = CommandBarSelectionMemory.makeEphemeral()
        memory.record(
            typedText: "sls",
            title: "SwingLifeStyle",
            url: try XCTUnwrap(URL(string: "https://www.swinglifestyle.com"))
        )
        XCTAssertEqual(memory.selections(matching: "sls"), [])
    }

    @MainActor
    func testLearnedPicksSurviveAReadBackFromDefaults() throws {
        let suiteName = "CommandBarSelectionMemoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let memory = CommandBarSelectionMemory(defaults: defaults)
        memory.record(
            typedText: "sls",
            title: "SwingLifeStyle",
            url: try XCTUnwrap(URL(string: "https://www.swinglifestyle.com"))
        )
        XCTAssertEqual(
            CommandBarSelectionMemory(defaults: defaults).selections(matching: "sl").first?.title,
            "SwingLifeStyle"
        )

        memory.removeAll()
        XCTAssertEqual(CommandBarSelectionMemory(defaults: defaults).selections(matching: "sl"), [])
    }
}

/// The floating mini player's shape and size math: portrait shorts, the
/// long-edge size it carries across a change of clip, and the resize drag.
final class MiniPlayerLayoutTests: XCTestCase {
    private let window = CGSize(width: 1440, height: 900)

    func testPlayerTakesTheVideoShapeForPortraitClips() {
        let short = MiniPlayerLayout.clampedSize(longEdge: 430, aspectRatio: 9.0 / 16.0, in: window)
        XCTAssertEqual(short.height, 430, accuracy: 0.5, "the long edge is the height for a portrait clip")
        XCTAssertEqual(short.width, 430 * 9 / 16, accuracy: 0.5)

        let wide = MiniPlayerLayout.clampedSize(longEdge: 430, aspectRatio: 16.0 / 9.0, in: window)
        XCTAssertEqual(wide.width, 430, accuracy: 0.5)
        XCTAssertEqual(wide.height, 430 * 9 / 16, accuracy: 0.5)
    }

    func testPlayerFallsBackToWidescreenWithoutAReportedShape() {
        XCTAssertEqual(MiniPlayerLayout.normalizedAspectRatio(nil), 16.0 / 9.0)
        XCTAssertEqual(MiniPlayerLayout.normalizedAspectRatio(0), 16.0 / 9.0)
        XCTAssertEqual(MiniPlayerLayout.normalizedAspectRatio(.nan), 16.0 / 9.0)
    }

    func testPlayerShapeStaysWithinItsLimits() {
        let sliver = MiniPlayerLayout.normalizedAspectRatio(40)
        XCTAssertEqual(sliver, MiniPlayerLayout.aspectRatioLimits.upperBound)
        let tower = MiniPlayerLayout.normalizedAspectRatio(0.05)
        XCTAssertEqual(tower, MiniPlayerLayout.aspectRatioLimits.lowerBound)
    }

    func testPortraitPlayerFitsAShortWindow() {
        let shortWindow = CGSize(width: 1440, height: 420)
        let size = MiniPlayerLayout.clampedSize(longEdge: 430, aspectRatio: 9.0 / 16.0, in: shortWindow)
        XCTAssertLessThanOrEqual(size.height, shortWindow.height - MiniPlayerLayout.margin * 2)
        XCTAssertEqual(size.width / size.height, 9.0 / 16.0, accuracy: 0.01, "clamping keeps the video's shape")
    }

    func testResizeDragFollowsTheShapeItIsGiven() {
        let drag = CGSize(width: 0, height: 80)
        let wide = MiniPlayerResizeEdge.bottom.widthDelta(for: drag, aspectRatio: 16.0 / 9.0)
        XCTAssertEqual(wide, 80 * 16 / 9, accuracy: 0.5)
        let tall = MiniPlayerResizeEdge.bottom.widthDelta(for: drag, aspectRatio: 9.0 / 16.0)
        XCTAssertEqual(tall, 80 * 9 / 16, accuracy: 0.5, "a portrait player widens by less than it grows")
    }

    func testLongEdgeSurvivesAShapeChange() {
        let wide = MiniPlayerLayout.clampedSize(longEdge: 520, aspectRatio: 16.0 / 9.0, in: window)
        let carried = MiniPlayerLayout.longEdge(of: wide)
        let tall = MiniPlayerLayout.clampedSize(longEdge: carried, aspectRatio: 9.0 / 16.0, in: window)
        XCTAssertEqual(tall.height, 520, accuracy: 0.5, "the player keeps its stature across a swipe to a short")
    }

    func testResizeHandlesStraddleThePlayerBorder() {
        let size = CGSize(width: 430, height: 430 * 9 / 16)

        for edge in MiniPlayerResizeEdge.allCases {
            let rect = CGRect(
                x: edge.position(in: size).x - edge.width(in: size) / 2,
                y: edge.position(in: size).y - edge.height(in: size) / 2,
                width: edge.width(in: size),
                height: edge.height(in: size)
            )
            XCTAssertTrue(
                rect.intersects(CGRect(origin: .zero, size: size)),
                "\(edge.rawValue) reaches inside the player"
            )
        }

        // Overshooting a corner or an edge by a few points still lands.
        let overshoot = MiniPlayerLayout.resizeOutwardGrab - 2
        let bottomRight = MiniPlayerResizeEdge.bottomTrailing
        let cornerRect = CGRect(
            x: bottomRight.position(in: size).x - bottomRight.width(in: size) / 2,
            y: bottomRight.position(in: size).y - bottomRight.height(in: size) / 2,
            width: bottomRight.width(in: size),
            height: bottomRight.height(in: size)
        )
        XCTAssertTrue(cornerRect.contains(CGPoint(x: size.width + overshoot, y: size.height + overshoot)))

        let trailing = MiniPlayerResizeEdge.trailing
        let edgeRect = CGRect(
            x: trailing.position(in: size).x - trailing.width(in: size) / 2,
            y: trailing.position(in: size).y - trailing.height(in: size) / 2,
            width: trailing.width(in: size),
            height: trailing.height(in: size)
        )
        XCTAssertTrue(edgeRect.contains(CGPoint(x: size.width + overshoot, y: size.height / 2)))
    }
}

// MARK: - Hibernation unsaved-input guard (issue #485)

/// Runs `WebPageScripts.unsavedInputCheckScript` against real pages in an
/// off-screen WKWebView: the guard's whole job is DOM semantics — shadow
/// roots, frames, `contenteditable` variants — so only a real WebKit DOM
/// can vouch for it. Everything loads from strings; no network.
@MainActor
final class UnsavedInputGuardTests: XCTestCase {
    private func checkUnsavedInput(
        in html: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Bool {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        webView.loadHTMLString(
            "<!doctype html><html><body data-talos-fixture='1'>\(html)</body></html>", baseURL: nil
        )

        // Wait for the fixture — subframes included — to finish loading. The
        // marker attribute keeps the initial about:blank document, which is
        // already "complete" before the HTML string commits, from answering.
        var loaded = false
        for _ in 0..<400 {
            let ready = try? await webView.evaluateJavaScript(
                "document.body?.dataset?.talosFixture === '1' && document.readyState === 'complete' && Array.from(document.querySelectorAll('iframe')).every(f => { try { return f.contentDocument?.readyState === 'complete' && f.contentDocument.body !== null; } catch { return true; } })"
            )
            if (ready as? Bool) == true {
                loaded = true
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(loaded, "fixture page must finish loading", file: file, line: line)

        let verdict = try await webView.evaluateJavaScript(WebPageScripts.unsavedInputCheckScript)
        let result = try XCTUnwrap(verdict as? Bool, "guard script must return a Bool", file: file, line: line)
        return result
    }

    func testCleanPageHibernates() async throws {
        let dirty = try await checkUnsavedInput(in: "<p>article text</p><input type='text' value=''>")
        XCTAssertFalse(dirty)
    }

    func testDirtyPlainFieldKeepsPageAlive() async throws {
        let dirty = try await checkUnsavedInput(in: """
        <input type='text'><script>document.querySelector('input').value = 'draft';</script>
        """)
        XCTAssertTrue(dirty)
    }

    func testExplicitContentEditableWithTextKeepsPageAlive() async throws {
        let dirty = try await checkUnsavedInput(in: "<div contenteditable='true'>a reply</div>")
        XCTAssertTrue(dirty)
    }

    func testBareContentEditableAttributeCounts() async throws {
        let dirty = try await checkUnsavedInput(in: "<div contenteditable>a reply</div>")
        XCTAssertTrue(dirty)
    }

    func testUppercaseAndPlaintextOnlyVariantsCount() async throws {
        let uppercase = try await checkUnsavedInput(in: "<div contenteditable='TRUE'>a reply</div>")
        XCTAssertTrue(uppercase)
        let plaintext = try await checkUnsavedInput(in: "<div contenteditable='plaintext-only'>a reply</div>")
        XCTAssertTrue(plaintext)
    }

    func testContentEditableFalseDoesNotCount() async throws {
        let dirty = try await checkUnsavedInput(in: "<div contenteditable='false'>page copy</div>")
        XCTAssertFalse(dirty)
    }

    func testEmptyEditorHibernates() async throws {
        let dirty = try await checkUnsavedInput(in: "<div contenteditable='true'>   </div>")
        XCTAssertFalse(dirty)
    }

    func testEditorInsideShadowRootKeepsPageAlive() async throws {
        let dirty = try await checkUnsavedInput(in: """
        <div id='host'></div>
        <script>
          const root = document.getElementById('host').attachShadow({ mode: 'open' });
          root.innerHTML = "<div contenteditable='true'>shadow draft</div>";
        </script>
        """)
        XCTAssertTrue(dirty)
    }

    func testDirtyFieldInsideNestedShadowRootKeepsPageAlive() async throws {
        let dirty = try await checkUnsavedInput(in: """
        <div id='host'></div>
        <script>
          const outer = document.getElementById('host').attachShadow({ mode: 'open' });
          const inner = document.createElement('div');
          outer.appendChild(inner);
          const innerRoot = inner.attachShadow({ mode: 'open' });
          innerRoot.innerHTML = "<textarea></textarea>";
          innerRoot.querySelector('textarea').value = 'draft';
        </script>
        """)
        XCTAssertTrue(dirty)
    }

    func testCleanShadowRootHibernates() async throws {
        let dirty = try await checkUnsavedInput(in: """
        <div id='host'></div>
        <script>
          const root = document.getElementById('host').attachShadow({ mode: 'open' });
          root.innerHTML = "<div contenteditable='true'></div><input type='text'>";
        </script>
        """)
        XCTAssertFalse(dirty)
    }

    func testEditorInsideSameOriginFrameKeepsPageAlive() async throws {
        let dirty = try await checkUnsavedInput(in: """
        <iframe srcdoc="<div contenteditable>frame draft</div>"></iframe>
        """)
        XCTAssertTrue(dirty)
    }

    func testCleanSameOriginFrameHibernates() async throws {
        let dirty = try await checkUnsavedInput(in: """
        <iframe srcdoc="<p>embed copy</p><input type='text'>"></iframe>
        """)
        XCTAssertFalse(dirty)
    }
}

// MARK: - Web notification shim (issue #170)

/// Runs `WebPageScripts.notificationShimScript` in a real WKWebView and
/// asserts both directions of the bridge: what the page sees
/// (`window.Notification`, permission state, events) and what the native
/// side would receive (the posted messages). The native prompt itself and
/// Notification Center delivery are exercised by hand — they need system
/// UI — but everything scriptable is pinned here.
@MainActor
final class WebNotificationShimTests: XCTestCase {
    private final class MessageRecorder: NSObject, WKScriptMessageHandler {
        var bodies: [[String: Any]] = []
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if let body = message.body as? [String: Any] {
                bodies.append(body)
            }
        }
        func actions() -> [String] { bodies.compactMap { $0["action"] as? String } }
    }

    private func makeLoadedWebView(
        recorder: MessageRecorder,
        bodyHTML: String = "<p>page</p>",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(
            recorder, name: WebPageScripts.webNotificationMessageName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: WebPageScripts.notificationShimScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        webView.loadHTMLString(
            "<!doctype html><html><body data-talos-fixture='1'>\(bodyHTML)</body></html>",
            baseURL: nil
        )
        let loaded = try await poll(webView, until: "document.body?.dataset?.talosFixture === '1'")
        XCTAssertTrue(loaded, "fixture page must finish loading", file: file, line: line)
        return webView
    }

    /// Evaluates `expression` until it is true. Expressions must be
    /// side-effect free; the return value reports the final state.
    private func poll(_ webView: WKWebView, until expression: String) async throws -> Bool {
        for _ in 0..<400 {
            if (try? await webView.evaluateJavaScript("(\(expression)) === true")) as? Bool == true {
                return true
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

    func testShimDefinesNotificationAndQueriesState() async throws {
        let recorder = MessageRecorder()
        let webView = try await makeLoadedWebView(recorder: recorder)

        let kind = try await webView.evaluateJavaScript("typeof Notification") as? String
        XCTAssertEqual(kind, "function")
        let permission = try await webView.evaluateJavaScript("Notification.permission") as? String
        XCTAssertEqual(permission, "default")
        XCTAssertEqual(recorder.actions(), ["query"], "the shim asks for its origin's stored state")
    }

    func testGrantedNotificationPostsShowWithItsContent() async throws {
        let recorder = MessageRecorder()
        let webView = try await makeLoadedWebView(recorder: recorder)

        _ = try await webView.evaluateJavaScript(
            "window.__talosNotificationPermissionUpdate('granted'); Notification.permission"
        )
        _ = try await webView.evaluateJavaScript(
            "window.__n = new Notification('Hello', { body: 'World', tag: 'thread-1' }); true"
        )

        guard let show = recorder.bodies.first(where: { $0["action"] as? String == "show" }) else {
            return XCTFail("granted notification must post a show message")
        }
        XCTAssertEqual(show["title"] as? String, "Hello")
        XCTAssertEqual(show["body"] as? String, "World")
        XCTAssertEqual(show["tag"] as? String, "thread-1")
        let id = show["id"] as? String ?? ""
        XCTAssertNotNil(WebViewCoordinator.pageNotificationID(from: id), "ids are digit strings")
    }

    func testDeniedNotificationFiresErrorAndPostsNothing() async throws {
        let recorder = MessageRecorder()
        let webView = try await makeLoadedWebView(recorder: recorder)

        _ = try await webView.evaluateJavaScript(
            "window.__talosNotificationPermissionUpdate('denied'); true"
        )
        _ = try await webView.evaluateJavaScript(
            "window.__sawError = false; const n = new Notification('x'); n.onerror = () => { window.__sawError = true; }; true"
        )
        let sawError = try await poll(webView, until: "window.__sawError")
        XCTAssertTrue(sawError, "a denied notification reports itself failed")
        XCTAssertEqual(recorder.actions(), ["query"], "nothing is posted for a denied notification")
    }

    func testRequestPermissionWithoutGestureReportsCurrentState() async throws {
        // evaluateJavaScript runs with implicit user activation, so the
        // no-gesture path only shows itself to the page's own load-time
        // script — exactly where notification prompt spam comes from.
        let recorder = MessageRecorder()
        let webView = try await makeLoadedWebView(
            recorder: recorder,
            bodyHTML: "<script>window.__resolved = null; Notification.requestPermission().then(v => { window.__resolved = v; });</script>"
        )
        let resolved = try await poll(webView, until: "window.__resolved === 'default'")
        XCTAssertTrue(resolved, "no user gesture: the request settles to the current state")
        XCTAssertFalse(
            recorder.actions().contains("requestPermission"),
            "no prompt reaches the native side without a gesture"
        )
    }

    func testPermissionsQueryReportsTheShimState() async throws {
        let recorder = MessageRecorder()
        let webView = try await makeLoadedWebView(recorder: recorder)

        _ = try await webView.evaluateJavaScript(
            "navigator.permissions.query({ name: 'notifications' }).then(s => { window.__state = s.state; }); true"
        )
        let prompted = try await poll(webView, until: "window.__state === 'prompt'")
        XCTAssertTrue(prompted)

        _ = try await webView.evaluateJavaScript(
            "window.__talosNotificationPermissionUpdate('granted'); navigator.permissions.query({ name: 'notifications' }).then(s => { window.__state = s.state; }); true"
        )
        let granted = try await poll(webView, until: "window.__state === 'granted'")
        XCTAssertTrue(granted)
    }

    func testCloseRetractsByTheSameID() async throws {
        let recorder = MessageRecorder()
        let webView = try await makeLoadedWebView(recorder: recorder)

        _ = try await webView.evaluateJavaScript(
            "window.__talosNotificationPermissionUpdate('granted'); window.__n = new Notification('Hi'); window.__n.close(); true"
        )
        let show = recorder.bodies.first { $0["action"] as? String == "show" }
        let close = recorder.bodies.first { $0["action"] as? String == "close" }
        XCTAssertNotNil(show)
        XCTAssertNotNil(close)
        XCTAssertEqual(show?["id"] as? String, close?["id"] as? String)
    }

    func testClickCallbackDispatchesTheClickEvent() async throws {
        let recorder = MessageRecorder()
        let webView = try await makeLoadedWebView(recorder: recorder)

        _ = try await webView.evaluateJavaScript(
            "window.__talosNotificationPermissionUpdate('granted'); window.__clicked = false; window.__n = new Notification('Hi'); window.__n.onclick = () => { window.__clicked = true; }; true"
        )
        guard
            let show = recorder.bodies.first(where: { $0["action"] as? String == "show" }),
            let id = show["id"] as? String
        else {
            return XCTFail("show message must carry the id the click routes back on")
        }
        _ = try await webView.evaluateJavaScript(
            "window.__talosNotificationActivated('\(id)'); true"
        )
        let clicked = try await poll(webView, until: "window.__clicked")
        XCTAssertTrue(clicked)
    }
}

/// Runs `WebPageScripts.pageColorObserverScript` in a real WKWebView and
/// asserts the verdict it posts for pages that author their colors in
/// modern CSS spaces. WebKit serializes those computed backgrounds as
/// lab()/oklch() — never rgb() — and the observer's legacy-rgb parser used
/// to fail on every probe and land on its white fallback, so a Tailwind v4
/// dark page (ui.shadcn.com) got a white top bar over black pixels.
@MainActor
final class PageColorObserverTests: XCTestCase {
    private final class VerdictRecorder: NSObject, WKScriptMessageHandler {
        var colors: [String] = []
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if let body = message.body as? [String: Any], let color = body["color"] as? String {
                colors.append(color)
            }
        }
    }

    private func makeLoadedWebView(
        recorder: VerdictRecorder,
        html: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(
            recorder, name: WebPageScripts.pageColorMessageName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: WebPageScripts.pageColorObserverScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)
        let loaded = try await poll(webView, until: "window.__talosPageColorInstalled === true")
        XCTAssertTrue(loaded, "observer script must install", file: file, line: line)
        return webView
    }

    private func poll(_ webView: WKWebView, until expression: String) async throws -> Bool {
        for _ in 0..<400 {
            if (try? await webView.evaluateJavaScript("(\(expression)) === true")) as? Bool == true {
                return true
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

    private func reportedVerdict(
        _ webView: WKWebView,
        _ recorder: VerdictRecorder
    ) async throws -> String? {
        _ = try await webView.evaluateJavaScript("window.__talosPageColorReport(); true")
        for _ in 0..<400 {
            if let verdict = recorder.colors.last { return verdict }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return nil
    }

    func testLegacyRGBBackgroundReportsExactly() async throws {
        let recorder = VerdictRecorder()
        let webView = try await makeLoadedWebView(
            recorder: recorder,
            html: "<!doctype html><html><body style='margin:0;background-color:rgb(18,52,86)'><p>page</p></body></html>"
        )
        let verdict = try await reportedVerdict(webView, recorder)
        XCTAssertEqual(verdict, "18,52,86")
    }

    /// The shadcn shape: transparent html/body, an oklch-dark wrapper
    /// painting the whole viewport. The verdict must be that dark color,
    /// not the white no-base fallback.
    func testOKLCHBackgroundOnWrapperReportsItsDarkColor() async throws {
        let recorder = VerdictRecorder()
        let webView = try await makeLoadedWebView(
            recorder: recorder,
            html: """
            <!doctype html><html><body style='margin:0'>
            <div style='position:fixed;inset:0;background-color:oklch(0.145 0 0)'><p>page</p></div>
            </body></html>
            """
        )
        guard let verdict = try await reportedVerdict(webView, recorder) else {
            return XCTFail("observer must post a verdict")
        }
        let channels = verdict.split(separator: ",").compactMap { Int($0) }
        XCTAssertEqual(channels.count, 3, "verdict is r,g,b — got \(verdict)")
        XCTAssertTrue(
            channels.allSatisfy { $0 < 60 },
            "oklch(0.145 0 0) is near-black, not the white fallback — got \(verdict)"
        )
    }

    /// The Radix-modal shape (shadcn's ⌘K palette): the open dialog sets
    /// `pointer-events: none` on the body, so `elementFromPoint` falls
    /// through to the bare root while the dark page still paints. The
    /// probe must report inconclusive ("" — the app holds the worn color),
    /// never the white fallback that made the bar flap white.
    func testBodyWithoutPointerEventsReportsInconclusiveNotWhite() async throws {
        let recorder = VerdictRecorder()
        let webView = try await makeLoadedWebView(
            recorder: recorder,
            html: """
            <!doctype html><html><body style='margin:0'>
            <div style='position:fixed;inset:0;background-color:rgb(10,10,10)'><p>page</p></div>
            </body></html>
            """
        )
        let before = try await reportedVerdict(webView, recorder)
        XCTAssertEqual(before, "10,10,10", "the page's own color is worn while hit-testing works")

        _ = try await webView.evaluateJavaScript("document.body.style.pointerEvents = 'none'; true")
        let during = try await reportedVerdict(webView, recorder)
        XCTAssertEqual(during, "", "a blinded probe is inconclusive, not the white fallback")

        _ = try await webView.evaluateJavaScript("document.body.style.pointerEvents = ''; true")
        let after = try await reportedVerdict(webView, recorder)
        XCTAssertEqual(after, "10,10,10", "closing the modal restores the page's color")
    }
}

/// Native-side helpers around the shim: id validation (anything but the
/// shim's digit ids must be dropped before it reaches evaluateJavaScript)
/// and reopening a site from a stored origin key.
final class WebNotificationRoutingTests: XCTestCase {
    func testPageNotificationIDsAreDigitStringsOnly() {
        XCTAssertEqual(WebViewCoordinator.pageNotificationID(from: "42"), "42")
        XCTAssertNil(WebViewCoordinator.pageNotificationID(from: ""))
        XCTAssertNil(WebViewCoordinator.pageNotificationID(from: "1'); alert('x"))
        XCTAssertNil(WebViewCoordinator.pageNotificationID(from: "1234567890123"), "length capped")
        XCTAssertNil(WebViewCoordinator.pageNotificationID(from: 42), "numbers must arrive as strings")
        XCTAssertNil(WebViewCoordinator.pageNotificationID(from: nil))
    }

    func testOriginKeysReopenWithoutDefaultPorts() {
        XCTAssertEqual(
            WebNotificationService.originURL(fromOriginKey: "https://mail.example.com:443")?.absoluteString,
            "https://mail.example.com/"
        )
        XCTAssertEqual(
            WebNotificationService.originURL(fromOriginKey: "http://localhost:8080")?.absoluteString,
            "http://localhost:8080/"
        )
        XCTAssertNil(WebNotificationService.originURL(fromOriginKey: "file://local:0"))
        XCTAssertNil(WebNotificationService.originURL(fromOriginKey: "not a url"))
    }

    // MARK: - Page chrome tint (pure hex math)

    /// WCAG relative luminance, re-derived here so the tests measure the
    /// production math against the spec instead of against itself.
    private func luminance(ofHex hex: String) -> Double {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(cleaned, radix: 16)!
        func linear(_ byte: Int) -> Double {
            let c = Double(byte) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((value >> 16) & 0xFF)
            + 0.7152 * linear((value >> 8) & 0xFF)
            + 0.0722 * linear(value & 0xFF)
    }

    func testNearWhiteDeclarationsAreNotChromeworthy() {
        // The chromeworthy gate applies only to DECLARED colors: boilerplate
        // white declarations never stand in for the painted pixels, while
        // sampled near-white pixels are worn directly (no gate).
        XCTAssertFalse(PageChromeTint.isChromeworthy(hex: "#FFFFFF"))
        XCTAssertFalse(PageChromeTint.isChromeworthy(hex: "#F5F5F5"))
        XCTAssertTrue(PageChromeTint.isChromeworthy(hex: "#17697A"), "saturated teal")
        XCTAssertTrue(PageChromeTint.isChromeworthy(hex: "#000000"), "dark headers count")
        XCTAssertTrue(PageChromeTint.isChromeworthy(hex: "#F0E68C"), "light but saturated")
        XCTAssertFalse(PageChromeTint.isChromeworthy(hex: "not-a-color"))
    }

    func testDarkPageColorIsWornExactlyWithLightForegrounds() throws {
        // A dark site header must match the page exactly — that pixel
        // identity is the whole Dia-style blend — and it picks light labels
        // regardless of the window appearance.
        let resolved = try XCTUnwrap(PageChromeTint.resolve(hex: "#17697A"))
        XCTAssertEqual(resolved.hex, "#17697A")
        XCTAssertFalse(resolved.usesDarkForeground)
    }

    func testWhitePageColorIsWornExactlyWithDarkForegrounds() throws {
        // A white page gets a white bar even in a dark window — that IS the
        // blend — with the labels flipped dark to survive on it.
        let resolved = try XCTUnwrap(PageChromeTint.resolve(hex: "#FFFFFF"))
        XCTAssertEqual(resolved.hex, "#FFFFFF")
        XCTAssertTrue(resolved.usesDarkForeground)
    }

    func testMidLuminanceColorIsNudgedTowardTheNearerSide() throws {
        // #808080 sits between the two readable ranges; the nearer side is
        // the light one, so it lightens just enough for dark labels.
        let resolved = try XCTUnwrap(PageChromeTint.resolve(hex: "#808080"))
        XCTAssertTrue(resolved.usesDarkForeground)
        XCTAssertGreaterThanOrEqual(luminance(ofHex: resolved.hex), 0.225 - 0.005)
        XCTAssertLessThanOrEqual(luminance(ofHex: resolved.hex), 0.26, "nudged, not washed")
    }

    func testChromeShadesDarkenInLinearLight() throws {
        // The bar's border and hover fills are darker shades of the worn
        // color (Dia's treatment); a shade must actually lose luminance.
        let base = "#17697A"
        let border = try XCTUnwrap(PageChromeTint.shadedHex(for: base, fraction: 0.35))
        let control = try XCTUnwrap(PageChromeTint.shadedHex(for: base, fraction: 0.18))
        XCTAssertLessThan(luminance(ofHex: border), luminance(ofHex: control))
        XCTAssertLessThan(luminance(ofHex: control), luminance(ofHex: base))
        XCTAssertEqual(luminance(ofHex: border), luminance(ofHex: base) * 0.65, accuracy: 0.01)
    }

    func testVeiledHexDimsLikeCSSCompositing() {
        // A 50% black scrim over the LUMM header must land on the same
        // value the page shows through it — plain gamma-space compositing.
        XCTAssertEqual(
            PageChromeTint.veiledHex(base: "#2F6E90", scrimRed: 0, scrimGreen: 0, scrimBlue: 0, scrimAlpha: 0.5),
            "#183748"
        )
        // Alpha 0 leaves the base untouched; out-of-range scrims are refused.
        XCTAssertEqual(
            PageChromeTint.veiledHex(base: "#17697A", scrimRed: 255, scrimGreen: 255, scrimBlue: 255, scrimAlpha: 0),
            "#17697A"
        )
        XCTAssertNil(PageChromeTint.veiledHex(base: "#17697A", scrimRed: 300, scrimGreen: 0, scrimBlue: 0, scrimAlpha: 0.5))
        XCTAssertNil(PageChromeTint.veiledHex(base: "not-a-color", scrimRed: 0, scrimGreen: 0, scrimBlue: 0, scrimAlpha: 0.5))
    }

    func testSampledRGBStringsParseAndReject() {
        XCTAssertEqual(PageChromeTint.hex(fromRGBString: "23,105,122"), "#17697A")
        XCTAssertEqual(PageChromeTint.hex(fromRGBString: "23, 105, 122"), "#17697A")
        XCTAssertNil(PageChromeTint.hex(fromRGBString: "300,0,0"), "out-of-range channel")
        XCTAssertNil(PageChromeTint.hex(fromRGBString: "23,105"), "missing channel")
        XCTAssertNil(PageChromeTint.hex(fromRGBString: ""))
        // A veil verdict must never collapse into a color: dropping the
        // unparseable component once left "veil:0,0,0,0.50" reading as
        // #000001 and the bar went black under LUMM's drawer.
        XCTAssertNil(PageChromeTint.hex(fromRGBString: "veil:0,0,0,0.50"))
        XCTAssertNil(PageChromeTint.hex(fromRGBString: "x,0,0"), "unparseable channel")
    }
}

/// Unit coverage for the built-in passkey authenticator's pure ceremony logic
/// (issue #506): relying-party scoping, authenticator-data layout, the "none"
/// attestation object, and assertion signatures that verify against the
/// credential public key the way a relying party would check them.
final class PasskeyCeremonyTests: XCTestCase {
    private let origin = URL(string: "https://accounts.example.com/signin")!

    // MARK: - Relying-party scope

    func testRelyingPartyDefaultsToHost() throws {
        XCTAssertEqual(
            try PasskeyCeremony.effectiveRelyingParty(requested: nil, origin: origin),
            "accounts.example.com"
        )
    }

    func testRelyingPartyAcceptsRegistrableSuffix() throws {
        XCTAssertEqual(
            try PasskeyCeremony.effectiveRelyingParty(requested: "example.com", origin: origin),
            "example.com"
        )
    }

    func testRelyingPartyRejectsUnrelatedDomain() {
        XCTAssertThrowsError(
            try PasskeyCeremony.effectiveRelyingParty(requested: "evil.com", origin: origin)
        )
    }

    func testRelyingPartyRejectsBareTopLevelDomain() {
        XCTAssertThrowsError(
            try PasskeyCeremony.effectiveRelyingParty(requested: "com", origin: origin)
        )
    }

    func testRelyingPartyRejectsMultiPartPublicSuffix() {
        let origin = URL(string: "https://shop.example.co.uk/")!
        XCTAssertThrowsError(
            try PasskeyCeremony.effectiveRelyingParty(requested: "co.uk", origin: origin)
        )
        XCTAssertEqual(
            try? PasskeyCeremony.effectiveRelyingParty(requested: "example.co.uk", origin: origin),
            "example.co.uk"
        )
    }

    func testRelyingPartyRejectsInsecureOrigins() {
        XCTAssertThrowsError(
            try PasskeyCeremony.effectiveRelyingParty(requested: nil, origin: URL(string: "http://example.com/")!)
        )
        XCTAssertEqual(
            try? PasskeyCeremony.effectiveRelyingParty(requested: nil, origin: URL(string: "http://localhost:8977/")!),
            "localhost"
        )
    }

    // MARK: - Authenticator data

    func testAuthenticatorDataLayoutForAssertion() {
        let data = PasskeyCeremony.authenticatorData(
            relyingParty: "example.com",
            flags: [.userPresent, .userVerified, .backupEligible, .backedUp]
        )
        XCTAssertEqual(data.count, 37)
        XCTAssertEqual(Data(data.prefix(32)), Data(SHA256.hash(data: Data("example.com".utf8))))
        XCTAssertEqual(data[32], 0x1D)
        XCTAssertEqual(Data(data.suffix(4)), Data([0, 0, 0, 0]), "sign counter stays zero for synced passkeys")
    }

    func testAuthenticatorDataEmbedsAttestedCredential() throws {
        let key = P256.Signing.PrivateKey()
        let credentialID = Data((0..<16).map { UInt8($0) })
        let data = PasskeyCeremony.authenticatorData(
            relyingParty: "example.com",
            flags: [.userPresent, .userVerified, .attestedCredentialIncluded],
            attestedCredential: (id: credentialID, publicKey: key.publicKey)
        )
        XCTAssertEqual(data[32] & 0x40, 0x40)
        XCTAssertEqual(Data(data[37..<53]), Data(count: 16), "zero AAGUID for none attestation")
        XCTAssertEqual(Int(data[53]) << 8 | Int(data[54]), credentialID.count)
        XCTAssertEqual(Data(data[55..<71]), credentialID)

        let cose = Data(data[71...])
        XCTAssertEqual(cose.first, 0xA5)
        let raw = key.publicKey.rawRepresentation
        XCTAssertNotNil(cose.range(of: raw.prefix(32)), "x coordinate present")
        XCTAssertNotNil(cose.range(of: raw.suffix(32)), "y coordinate present")
    }

    func testAttestationObjectShape() {
        let authData = PasskeyCeremony.authenticatorData(relyingParty: "example.com", flags: [.userPresent])
        let object = PasskeyCeremony.attestationObject(authenticatorData: authData)
        var expectedPrefix = Data([0xA3, 0x63]); expectedPrefix.append(Data("fmt".utf8))
        expectedPrefix.append(0x64); expectedPrefix.append(Data("none".utf8))
        expectedPrefix.append(0x67); expectedPrefix.append(Data("attStmt".utf8))
        expectedPrefix.append(0xA0)
        expectedPrefix.append(0x68); expectedPrefix.append(Data("authData".utf8))
        XCTAssertTrue(object.starts(with: expectedPrefix))
        XCTAssertTrue(object.suffix(authData.count) == authData)
    }

    // MARK: - Assertion signature

    func testAssertionSignatureVerifiesLikeARelyingParty() throws {
        let key = P256.Signing.PrivateKey()
        let clientData = PasskeyCeremony.clientDataJSON(
            type: "webauthn.get",
            challenge: "dGVzdC1jaGFsbGVuZ2U",
            origin: URL(string: "https://example.com")!
        )
        let authData = PasskeyCeremony.authenticatorData(
            relyingParty: "example.com",
            flags: [.userPresent, .userVerified]
        )
        let signature = try PasskeyCeremony.assertionSignature(
            privateKey: key,
            authenticatorData: authData,
            clientDataJSON: clientData
        )

        var signed = authData
        signed.append(Data(SHA256.hash(data: clientData)))
        let parsed = try P256.Signing.ECDSASignature(derRepresentation: signature)
        XCTAssertTrue(key.publicKey.isValidSignature(parsed, for: signed))
    }

    func testClientDataJSONParsesWithExpectedFields() throws {
        let data = PasskeyCeremony.clientDataJSON(
            type: "webauthn.create",
            challenge: "YQ",
            origin: URL(string: "https://example.com/path?query=1")!
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "webauthn.create")
        XCTAssertEqual(object["challenge"] as? String, "YQ")
        XCTAssertEqual(object["origin"] as? String, "https://example.com", "origin only, never the full URL")
        XCTAssertEqual(object["crossOrigin"] as? Bool, false)

        let withPort = PasskeyCeremony.clientDataJSON(
            type: "webauthn.get",
            challenge: "YQ",
            origin: URL(string: "http://localhost:8977/probe")!
        )
        let portObject = try XCTUnwrap(JSONSerialization.jsonObject(with: withPort) as? [String: Any])
        XCTAssertEqual(portObject["origin"] as? String, "http://localhost:8977")
    }

    func testBase64URLRoundTrip() {
        let data = Data((0..<64).map { _ in UInt8.random(in: .min ... .max) })
        let encoded = PasskeyCeremony.base64URLEncode(data)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(PasskeyCeremony.base64URLDecode(encoded), data)
    }
}

/// The passkey shim's page-side behavior (issue #506): WebAuthn calls are
/// marshaled to the `talosPasskeys` handler with buffers as base64url, and
/// native replies delivered through `__talosPasskeyResult` come back as
/// real-looking `PublicKeyCredential` objects. Native consent, keychain, and
/// signing stay covered by `PasskeyCeremonyTests` plus the fixture run; here
/// the native half is played by the test.
@MainActor
final class PasskeyShimTests: XCTestCase {
    private final class MessageRecorder: NSObject, WKScriptMessageHandler {
        var bodies: [[String: Any]] = []
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if let body = message.body as? [String: Any] {
                bodies.append(body)
            }
        }
    }

    private func makeLoadedWebView(
        recorder: MessageRecorder,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, name: WebPageScripts.passkeyMessageName)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: WebPageScripts.passkeyShimScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        // A secure-context base URL, so WebKit defines the WebAuthn
        // interfaces the shim wraps.
        webView.loadHTMLString(
            "<!doctype html><html><body data-talos-fixture='1'></body></html>",
            baseURL: URL(string: "https://example.com/")
        )
        let loaded = try await poll(webView, until: "document.body?.dataset?.talosFixture === '1'")
        XCTAssertTrue(loaded, "fixture page must finish loading", file: file, line: line)
        return webView
    }

    private func poll(_ webView: WKWebView, until expression: String) async throws -> Bool {
        for _ in 0..<400 {
            if (try? await webView.evaluateJavaScript("(\(expression)) === true")) as? Bool == true {
                return true
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

    private func waitForMessage(
        in recorder: MessageRecorder,
        action: String
    ) async throws -> [String: Any]? {
        for _ in 0..<400 {
            if let body = recorder.bodies.first(where: { $0["action"] as? String == action }) {
                return body
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return nil
    }

    func testCreateMarshalsOptionsAndDeliversCredential() async throws {
        let recorder = MessageRecorder()
        let webView = try await makeLoadedWebView(recorder: recorder)

        let shimInstalled = try await poll(webView, until: "window.__talosPasskeyShimInstalled === true")
        XCTAssertTrue(shimInstalled)
        let available = try await webView.evaluateJavaScript(
            "PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable.name"
        ) as? String
        XCTAssertEqual(available, "isUserVerifyingPlatformAuthenticatorAvailable")

        _ = try await webView.evaluateJavaScript("""
        window.__result = null; window.__error = null;
        navigator.credentials.create({ publicKey: {
            challenge: new Uint8Array([1, 2, 3, 4]),
            rp: { name: "Test", id: "example.com" },
            user: { id: new Uint8Array([9, 9]), name: "probe@example.com", displayName: "Probe" },
            pubKeyCredParams: [{ type: "public-key", alg: -257 }, { type: "public-key", alg: -7 }]
        }}).then((c) => { window.__result = c; }, (e) => { window.__error = e.name; });
        true
        """)

        let createMessage = try await waitForMessage(in: recorder, action: "create")
        let body = try XCTUnwrap(createMessage)
        XCTAssertEqual(body["challenge"] as? String, "AQIDBA")
        XCTAssertEqual(body["rpId"] as? String, "example.com")
        XCTAssertEqual(body["userId"] as? String, "CQk")
        XCTAssertEqual(body["userName"] as? String, "probe@example.com")
        XCTAssertEqual(body["algorithms"] as? [Int], [-257, -7])
        let requestID = try XCTUnwrap(WebViewCoordinator.passkeyRequestID(from: body["requestID"]))

        // Play the native side with the real ceremony pieces.
        let key = P256.Signing.PrivateKey()
        let credentialID = Data("unit-test-credential".utf8)
        let authenticatorData = PasskeyCeremony.authenticatorData(
            relyingParty: "example.com",
            flags: [.userPresent, .userVerified, .attestedCredentialIncluded],
            attestedCredential: (id: credentialID, publicKey: key.publicKey)
        )
        let reply: [String: Any] = [
            "credentialId": PasskeyCeremony.base64URLEncode(credentialID),
            "clientDataJSON": PasskeyCeremony.base64URLEncode(PasskeyCeremony.clientDataJSON(
                type: "webauthn.create", challenge: "AQIDBA", origin: URL(string: "https://example.com/")!
            )),
            "attestationObject": PasskeyCeremony.base64URLEncode(
                PasskeyCeremony.attestationObject(authenticatorData: authenticatorData)
            ),
            "authenticatorData": PasskeyCeremony.base64URLEncode(authenticatorData),
            "publicKey": PasskeyCeremony.base64URLEncode(key.publicKey.derRepresentation),
            "publicKeyAlgorithm": PasskeyCeremony.supportedAlgorithm
        ]
        let arguments = String(
            data: try JSONSerialization.data(withJSONObject: [requestID, reply]),
            encoding: .utf8
        )!
        _ = try await webView.evaluateJavaScript(
            "window.__talosPasskeyResult.apply(null, \(arguments)); true"
        )

        let resolved = try await poll(webView, until: "window.__result !== null")
        XCTAssertTrue(resolved, "create promise must resolve from the native reply")
        let shape = try await webView.evaluateJavaScript("""
        [
            window.__result instanceof PublicKeyCredential,
            window.__result.type,
            window.__result.id,
            window.__result.authenticatorAttachment,
            window.__result.response.getPublicKeyAlgorithm(),
            new Uint8Array(window.__result.response.attestationObject).length
        ]
        """) as? [Any]
        XCTAssertEqual(shape?[0] as? Bool, true)
        XCTAssertEqual(shape?[1] as? String, "public-key")
        XCTAssertEqual(shape?[2] as? String, PasskeyCeremony.base64URLEncode(credentialID))
        XCTAssertEqual(shape?[3] as? String, "platform")
        XCTAssertEqual(shape?[4] as? Int, -7)
        XCTAssertEqual(
            shape?[5] as? Int,
            PasskeyCeremony.attestationObject(authenticatorData: authenticatorData).count
        )
    }

    func testErrorRepliesRejectWithNamedDOMException() async throws {
        let recorder = MessageRecorder()
        let webView = try await makeLoadedWebView(recorder: recorder)

        _ = try await webView.evaluateJavaScript("""
        window.__error = null;
        navigator.credentials.get({ publicKey: { challenge: new Uint8Array([7]) } })
            .catch((e) => { window.__error = e.name; });
        true
        """)
        let getMessage = try await waitForMessage(in: recorder, action: "get")
        let body = try XCTUnwrap(getMessage)
        let requestID = try XCTUnwrap(WebViewCoordinator.passkeyRequestID(from: body["requestID"]))
        _ = try await webView.evaluateJavaScript(
            "window.__talosPasskeyResult('\(requestID)', { error: 'NotAllowedError' }); true"
        )
        let rejected = try await poll(webView, until: "window.__error === 'NotAllowedError'")
        XCTAssertTrue(rejected)
    }

    func testRequestIDValidationDropsNonNumericIDs() {
        XCTAssertEqual(WebViewCoordinator.passkeyRequestID(from: "42"), "42")
        XCTAssertNil(WebViewCoordinator.passkeyRequestID(from: "42; alert(1)"))
        XCTAssertNil(WebViewCoordinator.passkeyRequestID(from: ""))
        XCTAssertNil(WebViewCoordinator.passkeyRequestID(from: "1234567890123"))
        XCTAssertNil(WebViewCoordinator.passkeyRequestID(from: 42))
    }
}

/// The UI-test defaults reset runs in the real domain; these prove a test
/// run parks the person's values and the next normal launch puts them back
/// exactly — including keys that were unset — instead of factory-resetting
/// their choices (the "Above the Page" toolbar kept reverting this way).
@MainActor
final class UITestingDefaultsPreservationTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "TalosTests.UITestingDefaultsPreservation"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testTestLaunchParksValuesAndClearsKeys() {
        defaults.set("top", forKey: SettingsOption.addressBarPlacement)
        defaults.set(true, forKey: SettingsOption.openSafeDownloads)

        UITestingDefaultsPreservation.backUpAndClearForUITesting(defaults: defaults)

        for key in UITestingDefaultsPreservation.resetKeys {
            XCTAssertNil(defaults.object(forKey: key))
        }
        XCTAssertNotNil(defaults.dictionary(forKey: UITestingDefaultsPreservation.backupKey))
    }

    func testNormalLaunchRestoresParkedValuesAndShedsTestResidue() {
        defaults.set("top", forKey: SettingsOption.addressBarPlacement)
        UITestingDefaultsPreservation.backUpAndClearForUITesting(defaults: defaults)

        // A test writes into keys the person had set and hadn't set.
        defaults.set("sidebar", forKey: SettingsOption.addressBarPlacement)
        defaults.set("one-day", forKey: SettingsOption.historyRetention)

        UITestingDefaultsPreservation.restoreAfterUITestingIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: SettingsOption.addressBarPlacement), "top")
        XCTAssertNil(defaults.object(forKey: SettingsOption.historyRetention))
        XCTAssertNil(defaults.object(forKey: UITestingDefaultsPreservation.backupKey))
    }

    func testBackToBackTestRunsKeepTheOriginalBackup() {
        defaults.set("top", forKey: SettingsOption.addressBarPlacement)
        UITestingDefaultsPreservation.backUpAndClearForUITesting(defaults: defaults)

        // A test leaves residue; the next test launch must not park it.
        defaults.set("sidebar", forKey: SettingsOption.addressBarPlacement)
        UITestingDefaultsPreservation.backUpAndClearForUITesting(defaults: defaults)

        UITestingDefaultsPreservation.restoreAfterUITestingIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsOption.addressBarPlacement), "top")
    }

    func testNormalLaunchWithoutPriorTestRunIsUntouched() {
        defaults.set("top", forKey: SettingsOption.addressBarPlacement)
        UITestingDefaultsPreservation.restoreAfterUITestingIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsOption.addressBarPlacement), "top")
    }
}

/// The Manage Website Data sheet's pure logic (issue #538): folding
/// per-store data records into one row per site, and captioning what kinds
/// of data a site stores. Fetch/removal against real WKWebsiteDataStores
/// stays out of the unit target.
@MainActor
final class WebsiteDataInventoryTests: XCTestCase {
    private let storeA = UUID()
    private let storeB = UUID()

    func testMergeFoldsSameSiteAcrossStores() {
        let entries = WebsiteDataInventory.mergedEntries(from: [
            (storeID: storeA, displayName: "capitalone.com", dataTypes: [WKWebsiteDataTypeCookies], record: "a"),
            (storeID: storeB, displayName: "capitalone.com", dataTypes: [WKWebsiteDataTypeLocalStorage], record: "b")
        ])

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].displayName, "capitalone.com")
        XCTAssertEqual(entries[0].dataTypes, [WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage])
        XCTAssertEqual(entries[0].records.map(\.record).sorted(), ["a", "b"])
        XCTAssertEqual(Set(entries[0].records.map(\.storeID)), [storeA, storeB])
    }

    func testMergeSortsSitesLikeFinder() {
        let entries = WebsiteDataInventory.mergedEntries(from: [
            (storeID: storeA, displayName: "example.com", dataTypes: [WKWebsiteDataTypeCookies], record: "a"),
            (storeID: storeA, displayName: "apple.com", dataTypes: [WKWebsiteDataTypeCookies], record: "b"),
            (storeID: storeA, displayName: "Capitalone.com", dataTypes: [WKWebsiteDataTypeCookies], record: "c")
        ])

        XCTAssertEqual(entries.map(\.displayName), ["apple.com", "Capitalone.com", "example.com"])
    }

    func testTypeSummaryUsesFixedOrderAndFoldsCacheKinds() {
        let summary = WebsiteDataInventory.typeSummary(for: [
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeCookies
        ])

        XCTAssertEqual(summary, "Cookies, Cache, Local Storage")
    }

    func testTypeSummaryFallsBackWhenNothingIsRecognizable() {
        XCTAssertEqual(
            WebsiteDataInventory.typeSummary(for: [WKWebsiteDataTypeHashSalt]),
            "Website Data"
        )
    }
}

/// Round-trips the inventory's removal against a real, throwaway
/// WKWebsiteDataStore: a planted cookie must surface as a data record and
/// vanish once its entry is removed. The store is identifier-backed like a
/// Space's, created fresh and deleted on the way out so nothing lingers in
/// the app container.
@MainActor
final class WebsiteDataRemovalTests: XCTestCase {
    func testRemovingAnEntryDeletesItsRecords() async throws {
        let identifier = UUID()
        let dataStore = WKWebsiteDataStore(forIdentifier: identifier)
        defer {
            WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in }
        }

        var cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .domain: "stale-session.example",
            .path: "/",
            .name: "wedged",
            .value: "token",
            .expires: Date().addingTimeInterval(3600)
        ]
        cookieProperties[.secure] = "TRUE"
        let cookie = try XCTUnwrap(HTTPCookie(properties: cookieProperties))
        await dataStore.httpCookieStore.setCookie(cookie)

        let records = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let entries = WebsiteDataInventory.mergedEntries(from: records.map {
            (storeID: identifier, displayName: $0.displayName, dataTypes: $0.dataTypes, record: $0)
        })
        let planted = try XCTUnwrap(entries.first { $0.displayName.contains("stale-session.example") })
        XCTAssertTrue(planted.dataTypes.contains(WKWebsiteDataTypeCookies))

        for (_, record) in planted.records {
            await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: [record])
        }

        let remaining = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        XCTAssertFalse(remaining.contains { $0.displayName.contains("stale-session.example") })
    }
}

/// The external-scheme handoff's routing rules (issue #540): which URLs
/// leave the web view for the OS, and which of those open without a
/// consent prompt. The alert/LaunchServices side stays manual — it talks
/// to real windows and real handler registrations.
final class ExternalSchemePolicyTests: XCTestCase {
    func testWebSchemesStayInTheWebView() {
        for url in ["https://claude.ai/login", "http://localhost:3000", "about:blank",
                    "blob:https://example.com/x", "data:text/plain,hi", "javascript:void(0)"] {
            XCTAssertFalse(
                ExternalSchemePolicy.requiresSystemHandoff(URL(string: url)!),
                url
            )
        }
    }

    func testAppSchemesLeaveForTheSystem() {
        for url in ["claude://auth/callback?code=abc", "zoom://join", "slack://open",
                    "mailto:someone@example.com", "CLAUDE://mixed-case"] {
            XCTAssertTrue(
                ExternalSchemePolicy.requiresSystemHandoff(URL(string: url)!),
                url
            )
        }
    }

    func testRelativeURLWithoutSchemeStaysPut() {
        XCTAssertFalse(ExternalSchemePolicy.requiresSystemHandoff(URL(string: "/path/only")!))
    }

    func testConsentIsRequiredForAppSchemesButNotCommunication() {
        XCTAssertTrue(ExternalSchemePolicy.requiresConsent(URL(string: "claude://auth")!))
        XCTAssertTrue(ExternalSchemePolicy.requiresConsent(URL(string: "spotify://track")!))
        XCTAssertFalse(ExternalSchemePolicy.requiresConsent(URL(string: "mailto:a@b.c")!))
        XCTAssertFalse(ExternalSchemePolicy.requiresConsent(URL(string: "tel:5551234")!))
    }
}
