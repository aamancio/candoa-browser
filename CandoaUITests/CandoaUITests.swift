import XCTest

@MainActor
final class CandoaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesMainWindow() throws {
        let app = launchApp()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    func testFirstRunNewTabFindAndSidebarShortcuts() throws {
        let app = launchApp()

        completeInitialSpaceSetup(in: app, spaceName: "Personal")

        let newTabButton = element("sidebar-new-tab-button", in: app)
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 5))
        app.typeKey("t", modifierFlags: .command)

        XCTAssertTrue(waitForState(in: app, containing: "newTabPalette=true"), currentState(in: app))
        let firstRunURL = e2eURL(path: "/first-run.html")
        submitCommandPaletteText(firstRunURL, in: app)

        XCTAssertTrue(waitForState(in: app, containing: "url=\(firstRunURL)"), currentState(in: app))
        XCTAssertTrue(element("sidebar-address-button", in: app).waitForExistence(timeout: 5))

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(waitForState(in: app, containing: "find=true"), currentState(in: app))
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(waitForState(in: app, containing: "sidebar=false"), currentState(in: app))

        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(waitForState(in: app, containing: "sidebar=true"), currentState(in: app))
    }

    func testWorkspaceFixtureCoversAddressAndCommandPaletteTabCreation() throws {
        let app = launchApp(fixture: "workspace")

        XCTAssertTrue(waitForState(in: app, containing: "folders=Work|Second"), currentState(in: app))
        XCTAssertTrue(waitForState(in: app, containing: "tabs=amazon.com|Granola|SideKick Stag|Home / X|"), currentState(in: app))

        let addressButton = element("sidebar-address-button", in: app)
        XCTAssertTrue(addressButton.waitForExistence(timeout: 5))
        addressButton.click()

        XCTAssertTrue(waitForState(in: app, containing: "palette=true"), currentState(in: app))
        let addressURL = e2eURL(path: "/address.html")
        submitCommandPaletteText(addressURL, in: app)

        XCTAssertTrue(waitForState(in: app, containing: "url=\(addressURL)"), currentState(in: app))

        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(waitForState(in: app, containing: "newTabPalette=true"), currentState(in: app))
        let newTabURL = e2eURL(path: "/new-tab.html")
        submitCommandPaletteText(newTabURL, in: app)

        XCTAssertTrue(waitForState(in: app, containing: "url=\(newTabURL)"), currentState(in: app))

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(waitForState(in: app, containing: "find=true"), currentState(in: app))
    }

    func testAskContextCarriesForwardAndRescansVisibleControls() throws {
        let app = launchApp()

        completeInitialSpaceSetup(in: app, spaceName: "Personal")

        app.typeKey("t", modifierFlags: .command)
        let youtubeURL = e2eURL(path: "/youtube.html")
        submitCommandPaletteText(youtubeURL, in: app)
        XCTAssertTrue(waitForState(in: app, containing: "url=\(youtubeURL)", timeout: 8), currentState(in: app))
        XCTAssertTrue(waitForState(in: app, containing: "active=YouTube Fixture", timeout: 8), currentState(in: app))

        app.typeKey("b", modifierFlags: [.command, .option])
        XCTAssertTrue(element("ask-sidebar", in: app).waitForExistence(timeout: 5), currentState(in: app))
        XCTAssertTrue(waitForAskState(in: app, containing: "composerChips=[YouTube Fixture|", timeout: 8), askState(in: app))

        submitAskText("what is this page about", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[- YouTube Fixture", timeout: 10),
            askState(in: app)
        )
        XCTAssertTrue(
            waitForAskState(in: app, containing: "YouTube fixture is a video-sharing test page", timeout: 10),
            askState(in: app)
        )
        XCTAssertTrue(waitForAskState(in: app, containing: "0:user:chips=[YouTube Fixture|", timeout: 5), askState(in: app))
        XCTAssertTrue(waitForAskState(in: app, containing: "composerChips=[]", timeout: 5), askState(in: app))

        submitAskText("what about this", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[- YouTube Fixture", timeout: 10),
            askState(in: app)
        )
        XCTAssertTrue(
            waitForAskState(in: app, containing: "YouTube fixture is a video-sharing test page", timeout: 10),
            askState(in: app)
        )

        app.typeKey("l", modifierFlags: .command)
        let ebayURL = e2eURL(path: "/ebay.html")
        submitCommandPaletteText(ebayURL, in: app)
        XCTAssertTrue(waitForState(in: app, containing: "url=\(ebayURL)", timeout: 8), currentState(in: app))
        XCTAssertTrue(waitForState(in: app, containing: "active=eBay Fixture", timeout: 8), currentState(in: app))
        XCTAssertTrue(waitForAskState(in: app, containing: "composerChips=[eBay Fixture|", timeout: 8), askState(in: app))

        submitAskText("what about this", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[- eBay Fixture", timeout: 10),
            askState(in: app)
        )
        XCTAssertTrue(
            waitForAskState(in: app, containing: "eBay fixture is a marketplace test page", timeout: 10),
            askState(in: app)
        )
        XCTAssertTrue(waitForAskState(in: app, containing: "4:user:chips=[eBay Fixture|", timeout: 5), askState(in: app))
        XCTAssertTrue(waitForAskState(in: app, containing: "composerChips=[]", timeout: 5), askState(in: app))

        submitAskText("what about this website", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[- eBay Fixture", timeout: 10),
            askState(in: app)
        )
        XCTAssertTrue(
            waitForAskState(in: app, containing: "eBay fixture is a marketplace test page", timeout: 10),
            askState(in: app)
        )

        submitAskText("where is the sign in button", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[I found this visible control: a: Sign in", timeout: 10),
            askState(in: app)
        )
        XCTAssertTrue(
            waitForAskState(in: app, containing: "visible: top left", timeout: 10),
            askState(in: app)
        )
    }

    private func launchApp(fixture: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CANDOA_UI_TESTING"] = "1"
        app.launchEnvironment["CANDOA_UI_TESTING_STORE_ID"] = UUID().uuidString

        if let fixture {
            app.launchEnvironment["CANDOA_UI_TESTING_FIXTURE"] = fixture
        }

        app.launch()
        return app
    }

    private func e2eURL(path: String) -> String {
        let baseURL = ProcessInfo.processInfo.environment["CANDOA_E2E_BASE_URL"] ?? "http://127.0.0.1:18765"
        return "\(baseURL)\(path)"
    }

    private func completeInitialSpaceSetup(in app: XCUIApplication, spaceName: String) {
        let spaceNameField = element("space-name-field", in: app)
        XCTAssertTrue(spaceNameField.waitForExistence(timeout: 5))
        spaceNameField.click()
        spaceNameField.typeText(spaceName)

        let primaryButton = element("space-primary-button", in: app)
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 5))
        primaryButton.click()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func submitCommandPaletteText(_ text: String, in app: XCUIApplication) {
        let field = element("command-palette-field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), currentState(in: app))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
        field.typeKey(.return, modifierFlags: [])
    }

    private func submitAskText(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["ask-sidebar"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), currentState(in: app))
        field.click()
        field.typeText(text)
        field.typeKey(.return, modifierFlags: [])
    }

    private func waitForState(in app: XCUIApplication, containing expectedText: String, timeout: TimeInterval = 5) -> Bool {
        guard element("ui-testing-state", in: app).waitForExistence(timeout: timeout) else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if currentState(in: app).contains(expectedText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTContext.runActivity(named: "Current UI testing state") { activity in
            let attachment = XCTAttachment(string: currentState(in: app))
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        return false
    }

    private func currentState(in app: XCUIApplication) -> String {
        let stateElement = element("ui-testing-state", in: app)
        if let value = stateElement.value as? String, !value.isEmpty {
            return value
        }
        if !stateElement.label.isEmpty {
            return stateElement.label
        }
        return stateElement.debugDescription
    }

    private func waitForAskState(in app: XCUIApplication, containing expectedText: String, timeout: TimeInterval = 5) -> Bool {
        guard element("ask-ui-testing-state", in: app).waitForExistence(timeout: timeout) else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if askState(in: app).contains(expectedText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTContext.runActivity(named: "Current Ask UI testing state") { activity in
            let attachment = XCTAttachment(string: askState(in: app))
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        return false
    }

    private func askState(in app: XCUIApplication) -> String {
        let stateElement = element("ask-ui-testing-state", in: app)
        if let value = stateElement.value as? String, !value.isEmpty {
            return value
        }
        if !stateElement.label.isEmpty {
            return stateElement.label
        }
        return stateElement.debugDescription
    }
}

@MainActor
final class CandoaAskUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAskRefusesCurrentPageQuestionsWithoutContext() throws {
        let app = launchAskApp()
        openAskSidebar(in: app)

        submitAskText("what about this", in: app)

        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[I can't see what you're currently looking at", timeout: 10),
            askState(in: app)
        )
    }

    func testAskUsesCurrentPageAndDoesNotLeakPreviousPageContext() throws {
        let app = launchAskApp()

        openURL(e2eURL(path: "/youtube.html"), in: app)
        XCTAssertTrue(waitForState(in: app, containing: "active=YouTube Fixture", timeout: 8), currentState(in: app))

        openAskSidebar(in: app)
        XCTAssertTrue(waitForAskState(in: app, containing: "composerChips=[YouTube Fixture|", timeout: 8), askState(in: app))

        submitAskText("what is this page about", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "YouTube fixture is a video-sharing test page", timeout: 10),
            askState(in: app)
        )

        submitAskText("what about this", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[- YouTube Fixture", timeout: 10),
            askState(in: app)
        )

        openURL(e2eURL(path: "/ebay.html"), in: app)
        XCTAssertTrue(waitForState(in: app, containing: "active=eBay Fixture", timeout: 8), currentState(in: app))
        XCTAssertTrue(waitForAskState(in: app, containing: "composerChips=[eBay Fixture|", timeout: 8), askState(in: app))

        submitAskText("what about this", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[- eBay Fixture", timeout: 10),
            askState(in: app)
        )
        XCTAssertTrue(
            waitForAskState(in: app, containing: "eBay fixture is a marketplace test page", timeout: 10),
            askState(in: app)
        )
    }

    func testAskFindsVisibleSignInControlsFromTextAndImageLabels() throws {
        let app = launchAskApp()

        openURL(e2eURL(path: "/ebay.html"), in: app)
        openAskSidebar(in: app)
        submitAskText("where is the sign in button", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[I found this visible control: a: Sign in", timeout: 10),
            askState(in: app)
        )
        XCTAssertTrue(
            waitForAskState(in: app, containing: "visible: top left", timeout: 10),
            askState(in: app)
        )

        openURL(e2eURL(path: "/image-signin.html"), in: app)
        XCTAssertTrue(waitForAskState(in: app, containing: "composerChips=[Image Sign In Fixture|", timeout: 8), askState(in: app))

        submitAskText("where can I log in", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[I found this visible control: a: Sign in with secure account", timeout: 10),
            askState(in: app)
        )
    }

    func testAskRetryRescansCurrentPageAndIgnoresHiddenSignIn() throws {
        let app = launchAskApp()

        openURL(e2eURL(path: "/ebay.html"), in: app)
        openAskSidebar(in: app)
        submitAskText("where is the sign in button", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[I found this visible control: a: Sign in", timeout: 10),
            askState(in: app)
        )

        openURL(e2eURL(path: "/hidden-signin.html"), in: app)
        XCTAssertTrue(waitForState(in: app, containing: "active=Hidden Sign In Fixture", timeout: 8), currentState(in: app))

        submitAskText("check again", in: app)
        XCTAssertTrue(
            waitForAskState(in: app, containing: "lastAssistant=[I do not see a visible Sign in or login control", timeout: 10),
            askState(in: app)
        )
    }

    private func launchAskApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CANDOA_UI_TESTING"] = "1"
        app.launchEnvironment["CANDOA_UI_TESTING_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["CANDOA_UI_TESTING_FIXTURE"] = "ask"
        app.launch()
        return app
    }

    private func e2eURL(path: String) -> String {
        let baseURL = ProcessInfo.processInfo.environment["CANDOA_E2E_BASE_URL"] ?? "http://127.0.0.1:18765"
        return "\(baseURL)\(path)"
    }

    private func openURL(_ url: String, in app: XCUIApplication) {
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(waitForState(in: app, containing: "newTabPalette=true", timeout: 5), currentState(in: app))
        submitCommandPaletteText(url, in: app)
        XCTAssertTrue(waitForState(in: app, containing: "url=\(url)", timeout: 8), currentState(in: app))
    }

    private func openAskSidebar(in app: XCUIApplication) {
        if !element("ask-sidebar", in: app).exists {
            app.typeKey("b", modifierFlags: [.command, .option])
        }
        XCTAssertTrue(element("ask-sidebar", in: app).waitForExistence(timeout: 5), currentState(in: app))
        XCTAssertTrue(element("ask-ui-testing-state", in: app).waitForExistence(timeout: 8), currentState(in: app))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func submitCommandPaletteText(_ text: String, in app: XCUIApplication) {
        let field = element("command-palette-field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), currentState(in: app))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
        field.typeKey(.return, modifierFlags: [])
    }

    private func submitAskText(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["ask-sidebar"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), currentState(in: app))
        field.click()
        field.typeText(text)
        field.typeKey(.return, modifierFlags: [])
    }

    private func waitForState(in app: XCUIApplication, containing expectedText: String, timeout: TimeInterval = 5) -> Bool {
        guard element("ui-testing-state", in: app).waitForExistence(timeout: timeout) else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if currentState(in: app).contains(expectedText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTContext.runActivity(named: "Current UI testing state") { activity in
            let attachment = XCTAttachment(string: currentState(in: app))
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        return false
    }

    private func currentState(in app: XCUIApplication) -> String {
        let stateElement = element("ui-testing-state", in: app)
        if let value = stateElement.value as? String, !value.isEmpty {
            return value
        }
        if !stateElement.label.isEmpty {
            return stateElement.label
        }
        return stateElement.debugDescription
    }

    private func waitForAskState(in app: XCUIApplication, containing expectedText: String, timeout: TimeInterval = 5) -> Bool {
        guard element("ask-ui-testing-state", in: app).waitForExistence(timeout: timeout) else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if askState(in: app).contains(expectedText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTContext.runActivity(named: "Current Ask UI testing state") { activity in
            let attachment = XCTAttachment(string: askState(in: app))
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        return false
    }

    private func askState(in app: XCUIApplication) -> String {
        let stateElement = element("ask-ui-testing-state", in: app)
        if let value = stateElement.value as? String, !value.isEmpty {
            return value
        }
        if !stateElement.label.isEmpty {
            return stateElement.label
        }
        return stateElement.debugDescription
    }
}
