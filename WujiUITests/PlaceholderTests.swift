import XCTest
import Network

// MARK: - Launch configuration

/// Debug launch arguments understood by the Wuji app (DEBUG builds only).
struct WujiLaunch {
    /// `-WujiResetState`: wipe the local database + settings before the UI appears.
    var reset = false
    /// `-WujiBypassOnboarding`: skip the onboarding/consent gates.
    var bypassOnboarding = true
    /// `-WujiTab connect|nodes|settings`
    var tab: String?
    /// `-WujiConnectedState`: mock a connected tunnel (never opens a real VPN).
    var connectedMock = false
    /// `-WujiScreenshotRoute <route>`: deep link into a page/sheet.
    var route: String?
    /// `-WujiScreenshotPage <page>`: screenshot harness page hooks.
    var page: String?
    /// `-WujiScreenshotSearch <text>`
    var search: String?
    /// `-WujiScreenshotAction <action>`
    var action: String?
    /// `-WujiScreenshotDetail qr|edit`
    var detail: String?
    /// Extra debug launch arguments (e.g. permission gate hooks).
    var extra: [String] = []

    var arguments: [String] {
        var args = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if reset { args.append("-WujiResetState") }
        if bypassOnboarding { args.append("-WujiBypassOnboarding") }
        if let tab { args += ["-WujiTab", tab] }
        if connectedMock { args.append("-WujiConnectedState") }
        if let route { args += ["-WujiScreenshotRoute", route] }
        if let page { args += ["-WujiScreenshotPage", page] }
        if let search { args += ["-WujiScreenshotSearch", search] }
        if let action { args += ["-WujiScreenshotAction", action] }
        if let detail { args += ["-WujiScreenshotDetail", detail] }
        args += extra
        return args
    }
}

// MARK: - Acceptance test suite

/// Phase-4 interaction coverage for Wuji (iOS). Every test launches the app itself;
/// no test depends on the state left by another test. Debug launch arguments are the
/// only state hooks used (reset / tab shortcut / screenshot deep links); every
/// assertion is about a real consequence in the UI or the persisted data.
final class WujiAcceptanceTests: XCTestCase {

    // MARK: Lifecycle

    override func tearDownWithError() throws {
        // A test may end on a system sheet; terminating keeps later tests hermetic.
        XCUIApplication().terminate()
    }

    // MARK: Launch helpers

    private func launchArguments(_ configuration: WujiLaunch) -> [String] {
        configuration.arguments
    }

    @discardableResult
    private func launch(_ configuration: WujiLaunch) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = launchArguments(configuration)
        app.launch()
        return app
    }

    @discardableResult
    private func launchToTabs(_ configuration: WujiLaunch,
                              file: StaticString = #filePath,
                              line: UInt = #line) -> XCUIApplication {
        let app = launch(configuration)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30),
                      "Tab bar did not appear (onboarding/consent gate not bypassed?)",
                      file: file, line: line)
        return app
    }

    /// Terminates and relaunches the same app instance with new launch arguments,
    /// keeping whatever the app persisted (used to verify persistence).
    @discardableResult
    private func relaunch(_ app: XCUIApplication,
                          _ configuration: WujiLaunch,
                          file: StaticString = #filePath,
                          line: UInt = #line) -> XCUIApplication {
        app.terminate()
        app.launchArguments = launchArguments(configuration)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30),
                      "Tab bar did not appear after relaunch",
                      file: file, line: line)
        return app
    }

    // MARK: Element helpers

    private func anyElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Prefers the interactive element for a control identifier (SwiftUI attaches the
    /// same identifier to a wrapper and its inner button on some screens).
    private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let button = app.buttons[identifier].firstMatch
        return button.exists ? button : anyElement(app, identifier)
    }

    @discardableResult
    private func waitFor(_ app: XCUIApplication,
                         _ identifier: String,
                         timeout: TimeInterval = 12,
                         file: StaticString = #filePath,
                         line: UInt = #line) -> XCUIElement {
        let element = anyElement(app, identifier)
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Element '\(identifier)' did not appear", file: file, line: line)
        return element
    }

    /// Scrolls the current surface until an element is hittable (no-op when visible).
    /// Forms virtualise their rows, so look downwards first and then back upwards.
    private func scrollIntoView(_ app: XCUIApplication, _ identifier: String) {
        for _ in 0..<5 {
            let element = anyElement(app, identifier)
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<9 {
            let element = anyElement(app, identifier)
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
    }

    private func tap(_ app: XCUIApplication,
                     _ identifier: String,
                     timeout: TimeInterval = 12,
                     file: StaticString = #filePath,
                     line: UInt = #line) {
        // Lists virtualise off-screen rows: scroll first, then wait, then tap.
        if !anyElement(app, identifier).exists {
            scrollIntoView(app, identifier)
        }
        guard anyElement(app, identifier).waitForExistence(timeout: timeout) else {
            XCTFail("Cannot tap '\(identifier)': element never appeared", file: file, line: line)
            return
        }
        if !anyElement(app, identifier).isHittable {
            scrollIntoView(app, identifier)
        }
        let interactive = app.buttons[identifier].firstMatch
        let target = interactive.exists ? interactive : anyElement(app, identifier)
        XCTAssertTrue(target.isHittable, "Element '\(identifier)' is not hittable", file: file, line: line)
        target.tap()
    }

    private func tapButton(_ app: XCUIApplication,
                           _ label: String,
                           timeout: TimeInterval = 10,
                           file: StaticString = #filePath,
                           line: UInt = #line) {
        let button = app.buttons[label].firstMatch
        guard button.waitForExistence(timeout: timeout) else {
            XCTFail("Button '\(label)' never appeared", file: file, line: line)
            return
        }
        button.tap()
    }

    private func assertVisible(_ app: XCUIApplication,
                               _ identifier: String,
                               timeout: TimeInterval = 10,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        if anyElement(app, identifier).waitForExistence(timeout: 1) { return }
        scrollIntoView(app, identifier)
        XCTAssertTrue(anyElement(app, identifier).waitForExistence(timeout: timeout),
                      "Element '\(identifier)' should be visible", file: file, line: line)
    }

    private func assertGone(_ app: XCUIApplication,
                            _ identifier: String,
                            timeout: TimeInterval = 6,
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate,
                                                    object: anyElement(app, identifier))
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "Element '\(identifier)' should disappear", file: file, line: line)
    }

    private func assertText(_ app: XCUIApplication,
                            _ text: String,
                            timeout: TimeInterval = 10,
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout: timeout),
                      "Text '\(text)' should be visible", file: file, line: line)
    }

    private func assertNoText(_ app: XCUIApplication,
                              _ text: String,
                              timeout: TimeInterval = 4,
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate,
                                                    object: app.staticTexts[text].firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "Text '\(text)' should not be visible", file: file, line: line)
    }

    private func textInput(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let textField = app.textFields[identifier].firstMatch
        if textField.exists { return textField }
        let textView = app.textViews[identifier].firstMatch
        if textView.exists { return textView }
        return anyElement(app, identifier)
    }

    private func type(_ app: XCUIApplication,
                      _ identifier: String,
                      _ text: String,
                      file: StaticString = #filePath,
                      line: UInt = #line) {
        for _ in 0..<4 {
            scrollIntoView(app, identifier)
            let field = textInput(app, identifier)
            guard field.waitForExistence(timeout: 5), field.isHittable else { continue }
            field.tap()
            field.typeText(text)
            return
        }
        XCTFail("Text input '\(identifier)' never became editable", file: file, line: line)
    }

    private func clearAndType(_ app: XCUIApplication,
                              _ identifier: String,
                              _ text: String,
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        for _ in 0..<4 {
            scrollIntoView(app, identifier)
            let field = textInput(app, identifier)
            guard field.waitForExistence(timeout: 5), field.isHittable else { continue }
            field.tap()
            let current = (field.value as? String) ?? ""
            let placeholder = field.placeholderValue ?? ""
            if !current.isEmpty && current != placeholder {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            field.typeText(text)
            return
        }
        XCTFail("Text input '\(identifier)' never became editable", file: file, line: line)
    }

    /// Taps the back button of a specific navigation bar (several nav bars can be in
    /// the hierarchy when a sheet hosts its own NavigationStack).
    private func tapBack(_ app: XCUIApplication,
                         _ navigationTitle: String,
                         file: StaticString = #filePath,
                         line: UInt = #line) {
        let bar = app.navigationBars[navigationTitle]
        guard bar.waitForExistence(timeout: 12) else {
            XCTFail("Navigation bar '\(navigationTitle)' missing", file: file, line: line)
            return
        }
        let back = bar.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 6),
                      "Back button missing in '\(navigationTitle)'", file: file, line: line)
        back.tap()
    }

    private func tapTab(_ app: XCUIApplication, _ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Tab '\(title)' missing")
        tab.tap()
    }

    @discardableResult
    private func scrollTo(_ app: XCUIApplication,
                          _ identifier: String,
                          maxSwipes: Int = 8) -> XCUIElement {
        let element = anyElement(app, identifier)
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return element }
            app.swipeUp()
        }
        return element
    }

    // MARK: Node helpers

    private func nodeRowQuery(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "wuji.nodes.row."))
    }

    private func nodeRowLabels(_ app: XCUIApplication) -> [String] {
        nodeRowQuery(app).allElementsBoundByIndex.compactMap { element in
            element.identifier.isEmpty ? nil : element.label
        }
    }

    /// Leaves the active `.searchable` state. While searching, iOS swaps the navigation
    /// bar for the search field + a system Cancel button and hides the screen toolbar.
    private func leaveSearchMode(_ app: XCUIApplication,
                                 toolbarIdentifier: String,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        if anyElement(app, toolbarIdentifier).exists { return }
        let navBar = app.navigationBars["Bypassed Regions"]
        let close = navBar.buttons["Close"]
        if close.waitForExistence(timeout: 5) {
            close.tap()
        } else {
            let cancel = app.buttons["Cancel"].firstMatch
            guard cancel.waitForExistence(timeout: 5) else {
                XCTFail("Search dismiss control missing", file: file, line: line)
                return
            }
            cancel.tap()
        }
        XCTAssertTrue(anyElement(app, toolbarIdentifier).waitForExistence(timeout: 10),
                      "Screen toolbar should return after leaving search", file: file, line: line)
    }

    /// Launches with four nodes imported through the debug paste-import pre-fill.
    /// The import itself is the normal product path (no direct DB seeding).
    @discardableResult
    private func launchWithFourNodes(file: StaticString = #filePath,
                                     line: UInt = #line) -> XCUIApplication {
        var configuration = WujiLaunch()
        configuration.reset = true
        configuration.tab = "nodes"
        configuration.page = "nodes-paste-data"
        let app = launchToTabs(configuration, file: file, line: line)
        let primary = anyElement(app, "wuji.nodes.paste.primaryButton")
        guard primary.waitForExistence(timeout: 25) else {
            XCTFail("Prefilled paste import page did not open", file: file, line: line)
            return app
        }
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any)
                                        .matching(NSPredicate(format: "identifier BEGINSWITH %@", "wuji.nodes.paste.row."))
                                        .count, 4,
                                    "Expected four recognized links",
                                    file: file, line: line)
        primary.tap()
        XCTAssertTrue(nodeRowQuery(app).firstMatch.waitForExistence(timeout: 20),
                      "Node list did not refresh after import", file: file, line: line)
        return app
    }

    private func firstNodeRow(_ app: XCUIApplication) -> XCUIElement {
        nodeRowQuery(app).firstMatch
    }

    private func contextMenuIdentifier(for row: XCUIElement) -> String {
        row.identifier.replacingOccurrences(of: "wuji.nodes.row.", with: "wuji.nodes.rowMenu.")
    }

    private func openAddMenu(_ app: XCUIApplication) {
        tap(app, "wuji.nodes.addButton")
        assertVisible(app, "wuji.nodes.addMenu.manual")
    }

    private func openManualAddForm(_ app: XCUIApplication,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) {
        openAddMenu(app)
        tap(app, "wuji.nodes.addMenu.manual")
        XCTAssertTrue(app.navigationBars["Add Node"].waitForExistence(timeout: 12),
                      "Manual add form did not open", file: file, line: line)
    }

    private func selectProtocol(_ app: XCUIApplication, _ title: String) {
        let picker = app.segmentedControls["wuji.nodes.form.protocolPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Protocol picker missing")
        let segment = picker.buttons[title]
        XCTAssertTrue(segment.waitForExistence(timeout: 6), "Protocol segment '\(title)' missing")
        segment.tap()
    }

    private func pickNavigationOption(_ app: XCUIApplication, _ fieldIdentifier: String, _ option: String) {
        tap(app, fieldIdentifier)
        let choice = app.buttons[option].firstMatch
        if !choice.waitForExistence(timeout: 8) {
            // Some pickers expose options as cells/static texts.
            let fallback = app.staticTexts[option].firstMatch
            XCTAssertTrue(fallback.waitForExistence(timeout: 6), "Picker option '\(option)' missing")
            fallback.tap()
            return
        }
        choice.tap()
    }

    /// Dismisses the software keyboard before tapping a button pinned to the bottom
    /// edge. XCUITest taps the element's cached frame, which can be behind the
    /// keyboard while the button itself is rendered above it.
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        let candidates = [
            app.keyboards.buttons["Done"].firstMatch,
            app.toolbars.buttons["Done"].firstMatch,
            app.buttons["Done"].firstMatch
        ]
        for candidate in candidates where candidate.exists && candidate.isHittable {
            candidate.tap()
            return
        }
        app.keyboards.firstMatch.swipeDown()
    }

    private func saveNodeForm(_ app: XCUIApplication) {
        dismissKeyboard(app)
        tap(app, "wuji.nodes.form.saveButton")
    }

    private func assertNodeNamed(_ app: XCUIApplication,
                                 _ name: String,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "wuji.nodes.row.")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                app.descendants(matching: .any)
                    .matching(predicate).allElementsBoundByIndex
                    .contains { $0.label.hasPrefix(name) }
            },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 12), .completed,
                       "Node '\(name)' should appear in the list", file: file, line: line)
    }

    /// Reads a SwiftUI Toggle value ("1"/"0").
    private func switchValue(_ app: XCUIApplication, _ identifier: String) -> String? {
        app.switches[identifier].firstMatch.value as? String
    }

    /// Taps a SwiftUI Toggle's inner UISwitch (tapping the labelled row itself does
    /// not flip the value in the simulator).
    /// Taps the connection pill button on the Home screen.
    private func tapConnectPill(_ app: XCUIApplication,
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        let pill = app.buttons["wuji.home.connectPill"].firstMatch
        guard pill.waitForExistence(timeout: 10) else {
            XCTFail("Connect pill missing", file: file, line: line)
            return
        }
        pill.tap()
    }

    private func tapSwitch(_ app: XCUIApplication,
                           _ identifier: String,
                           file: StaticString = #filePath,
                           line: UInt = #line) {
        let container = app.switches[identifier].firstMatch
        guard container.waitForExistence(timeout: 10) else {
            XCTFail("Switch '\(identifier)' missing", file: file, line: line)
            return
        }
        let inner = container.switches.firstMatch
        let target = inner.exists ? inner : container
        target.tap()
    }

    // MARK: Sheet / dialog helpers

    /// Taps the confirm button of the app's custom ConfirmationSheet.
    private func confirmCustomSheet(_ app: XCUIApplication,
                                    expectedTitle: String? = nil,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        let title = anyElement(app, "wuji.confirmation.title")
        XCTAssertTrue(title.waitForExistence(timeout: 10),
                      "Custom confirmation sheet did not appear", file: file, line: line)
        if let expectedTitle {
            XCTAssertEqual(title.label, expectedTitle,
                           "Confirmation title mismatch", file: file, line: line)
        }
        tap(app, "wuji.confirmation.confirm")
    }

    private func cancelCustomSheet(_ app: XCUIApplication) {
        tap(app, "wuji.confirmation.cancel")
    }

    /// Waits for the system action sheet / alert used by `confirmationDialog`.
    private func waitForSystemDialog(_ app: XCUIApplication,
                                     timeout: TimeInterval = 10,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        if app.sheets.firstMatch.waitForExistence(timeout: timeout) { return }
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5),
                      "System confirmation dialog did not appear", file: file, line: line)
    }

    /// Taps a button inside the visible system confirmation dialog.
    private func tapSystemDialogButton(_ app: XCUIApplication,
                                       _ label: String,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) {
        let sheetButton = app.sheets.buttons[label].firstMatch
        if sheetButton.waitForExistence(timeout: 10) {
            sheetButton.tap()
            return
        }
        let alertButton = app.alerts.buttons[label].firstMatch
        if alertButton.waitForExistence(timeout: 5) {
            alertButton.tap()
            return
        }
        // Some iOS versions expose action-sheet rows without a queryable label;
        // fall back to the documented order (destructive first, cancel last).
        let sheet = app.sheets.firstMatch
        if sheet.exists && sheet.buttons.count > 0 {
            let index = label == "Cancel" ? sheet.buttons.count - 1 : 0
            sheet.buttons.element(boundBy: index).tap()
            return
        }
        let alert = app.alerts.firstMatch
        if alert.exists && alert.buttons.count > 0 {
            let index = label == "Cancel" ? alert.buttons.count - 1 : 0
            alert.buttons.element(boundBy: index).tap()
            return
        }
        XCTFail("Dialog button '\(label)' never appeared", file: file, line: line)
    }

    // MARK: Paste helper

    private func importLinksByTyping(_ app: XCUIApplication,
                                     _ links: String,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        openAddMenu(app)
        tap(app, "wuji.nodes.addMenu.paste")
        XCTAssertTrue(app.navigationBars["Paste Links"].waitForExistence(timeout: 12),
                      "Paste page did not open", file: file, line: line)
        let editor = app.textViews["wuji.nodes.paste.editor"].firstMatch
        guard editor.waitForExistence(timeout: 10) else {
            XCTFail("Paste editor missing", file: file, line: line)
            return
        }
        editor.tap()
        editor.typeText(links)
    }

    // MARK: - A. Onboarding / consent

    func testOnboardingFlowAndConsentGate() {
        var app = launch(WujiLaunch(reset: true, bypassOnboarding: false))

        // Page 1
        assertVisible(app, "wuji.onboarding.skipButton")
        assertVisible(app, "wuji.onboarding.primaryButton")
        assertText(app, "Your connection, your rules.")
        XCTAssertEqual(anyElement(app, "wuji.onboarding.pageIndicator").label, "Page 1 of 3")

        // Page 2
        tap(app, "wuji.onboarding.primaryButton")
        assertText(app, "Bring your own servers.")
        XCTAssertEqual(anyElement(app, "wuji.onboarding.pageIndicator").label, "Page 2 of 3")

        // Page 3
        tap(app, "wuji.onboarding.primaryButton")
        assertText(app, "Stay local where it matters.")
        XCTAssertEqual(anyElement(app, "wuji.onboarding.pageIndicator").label, "Page 3 of 3")
        XCTAssertEqual(control(app, "wuji.onboarding.primaryButton").label, "Get Started")

        // Consent gate: continue disabled until the checkbox is checked.
        tap(app, "wuji.onboarding.primaryButton")
        assertText(app, "Before We Start")
        let continueButton = control(app, "wuji.consent.continueButton")
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        XCTAssertFalse(continueButton.isEnabled, "Agree & Continue must be disabled before agreeing")
        XCTAssertEqual(anyElement(app, "wuji.consent.checkbox").value as? String, "Not agreed")

        tap(app, "wuji.consent.checkbox")
        XCTAssertEqual(anyElement(app, "wuji.consent.checkbox").value as? String, "Agreed")
        XCTAssertTrue(control(app, "wuji.consent.continueButton").isEnabled)

        tap(app, "wuji.consent.continueButton")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20),
                      "Consent should lead to the main tabs")

        // The onboarding flow must not appear again on the next launch.
        app = relaunch(app, WujiLaunch(reset: false, bypassOnboarding: false))
        XCTAssertFalse(anyElement(app, "wuji.onboarding.skipButton").exists,
                       "Onboarding must only appear once")
    }

    func testOnboardingSkipGoesToConsent() {
        let app = launch(WujiLaunch(reset: true, bypassOnboarding: false))
        assertVisible(app, "wuji.onboarding.skipButton")
        tap(app, "wuji.onboarding.skipButton")

        assertText(app, "Before We Start")
        assertVisible(app, "wuji.consent.checkbox")
        assertVisible(app, "wuji.consent.termsLink")
        XCTAssertFalse(control(app, "wuji.consent.continueButton").isEnabled,
                       "Skipping onboarding must not skip consent")
        XCTAssertFalse(anyElement(app, "wuji.onboarding.primaryButton").exists,
                       "Onboarding should be gone after Skip")
    }

    func testConsentLegalLinksAndCheckedStateRetained() {
        let app = launch(WujiLaunch(reset: true, bypassOnboarding: false))
        assertVisible(app, "wuji.onboarding.skipButton")
        tap(app, "wuji.onboarding.skipButton")
        assertVisible(app, "wuji.consent.checkbox")

        // Check the box, visit Terms, come back: the state must be kept.
        tap(app, "wuji.consent.checkbox")
        XCTAssertEqual(anyElement(app, "wuji.consent.checkbox").value as? String, "Agreed")

        tap(app, "wuji.consent.termsLink")
        assertVisible(app, "wuji.settings.legal.scroll")
        assertText(app, "Terms of Use", timeout: 15)
        tapBack(app, "Terms of Use")
        assertVisible(app, "wuji.consent.checkbox")
        XCTAssertEqual(anyElement(app, "wuji.consent.checkbox").value as? String, "Agreed",
                       "Checkbox state must survive visiting the legal page")

        tap(app, "wuji.consent.privacyLink")
        assertVisible(app, "wuji.settings.legal.scroll")
        assertText(app, "Privacy Policy", timeout: 15)
        tapBack(app, "Privacy Policy")

        tap(app, "wuji.consent.continueButton")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
    }

    // MARK: - B. Home

    func testHomeDisconnectedConnectWithoutNodeNavigatesToNodes() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "connect"))
        XCTAssertEqual(anyElement(app, "wuji.home.statusTitle").label, "Not Connected")
        XCTAssertEqual(anyElement(app, "wuji.home.statusSubtitle").label, "Select a node to start")
        assertVisible(app, "wuji.home.connectPill")
        assertVisible(app, "wuji.home.chooseNode")

        // No node selected -> turning the switch on routes the user to the nodes tab.
        tapConnectPill(app)
        assertText(app, "No Nodes Yet")
        XCTAssertTrue(app.navigationBars["Nodes"].waitForExistence(timeout: 10))
    }

    func testHomeMockConnectedStateAndDisconnect() {
        let app = launchToTabs(WujiLaunch(reset: true, connectedMock: true))
        XCTAssertEqual(anyElement(app, "wuji.home.statusTitle").label, "Connected")
        assertVisible(app, "wuji.home.connectPill")
        // Disconnect from the mock state -> back to Not Connected, no fake traffic left.
        tapConnectPill(app)
        let disconnected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Not Connected"),
            object: anyElement(app, "wuji.home.statusTitle"))
        XCTAssertEqual(XCTWaiter().wait(for: [disconnected], timeout: 25), .completed,
                       "Home should return to Not Connected after disconnecting")
        assertVisible(app, "wuji.home.chooseNode", timeout: 10)
    }

    func testHomeCurrentNodeAndRoutingRows() {
        var app = launchWithFourNodes()
        tapTab(app, "Connect")
        assertText(app, "Tokyo-01")

        // Current Node row -> nodes tab.
        assertVisible(app, "wuji.home.currentNodeRow")
        tap(app, "wuji.home.currentNodeRow")
        XCTAssertTrue(app.navigationBars["Nodes"].waitForExistence(timeout: 10))

        // Routing row -> routing sheet, Done dismisses it.
        tapTab(app, "Connect")
        assertVisible(app, "wuji.home.routingRow")
        tap(app, "wuji.home.routingRow")
        assertVisible(app, "wuji.routing.globalModeToggle")
        tap(app, "wuji.routing.done")
        assertGone(app, "wuji.routing.globalModeToggle")
        assertText(app, "Not Connected")
    }

    func testTabBarSwitchesBetweenAllTabs() {
        let app = launchToTabs(WujiLaunch(reset: true))
        XCTAssertTrue(app.tabBars.buttons["Connect"].isSelected)

        tapTab(app, "Nodes")
        assertText(app, "No Nodes Yet")
        XCTAssertTrue(app.tabBars.buttons["Nodes"].isSelected)

        tapTab(app, "Settings")
        assertVisible(app, "wuji.settings.list")
        assertVisible(app, "wuji.settings.geoipStatus")
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)

        tapTab(app, "Connect")
        assertText(app, "Not Connected")
        XCTAssertTrue(app.tabBars.buttons["Connect"].isSelected)
    }

    // MARK: - D. Nodes list

    func testNodesEmptyStateAndAddMenuEntries() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "nodes"))
        // Empty state: illustration copy + three entry buttons.
        assertText(app, "No Nodes Yet")
        assertVisible(app, "wuji.nodes.empty.addButton")
        assertVisible(app, "wuji.nodes.empty.addSubscriptionButton")
        assertVisible(app, "wuji.nodes.empty.scanButton")
        // Toolbar is reduced while there are no nodes (no sort / test all buttons).
        XCTAssertFalse(anyElement(app, "wuji.nodes.sortMenu").exists)

        // Add menu (from the empty state and from the navigation bar share one sheet).
        tap(app, "wuji.nodes.empty.addButton")
        assertVisible(app, "wuji.nodes.addMenu.manual")
        assertVisible(app, "wuji.nodes.addMenu.scan")
        assertVisible(app, "wuji.nodes.addMenu.paste")
        assertVisible(app, "wuji.nodes.addMenu.subscription")
        tap(app, "wuji.nodes.addMenu.cancel")
        assertGone(app, "wuji.nodes.addMenu.manual")

        tap(app, "wuji.nodes.addButton")
        assertVisible(app, "wuji.nodes.addMenu.manual")

        // Each of the four entries really navigates somewhere.
        tap(app, "wuji.nodes.addMenu.manual")
        XCTAssertTrue(app.navigationBars["Add Node"].waitForExistence(timeout: 12))
        tap(app, "wuji.nodes.form.cancelButton")
        assertText(app, "No Nodes Yet")

        tap(app, "wuji.nodes.addButton")
        tap(app, "wuji.nodes.addMenu.scan")
        assertVisible(app, "wuji.nodes.scan.closeButton")
        tap(app, "wuji.nodes.scan.closeButton")

        tap(app, "wuji.nodes.addButton")
        tap(app, "wuji.nodes.addMenu.paste")
        XCTAssertTrue(app.navigationBars["Paste Links"].waitForExistence(timeout: 12))
        tap(app, "wuji.nodes.paste.cancelButton")

        tap(app, "wuji.nodes.addButton")
        tap(app, "wuji.nodes.addMenu.subscription")
        XCTAssertTrue(app.navigationBars["Add Subscription"].waitForExistence(timeout: 12))
        tap(app, "wuji.subscriptions.add.cancel")
        assertText(app, "No Nodes Yet")
    }

    func testNodesListSearchAndNoResults() {
        let app = launchWithFourNodes()
        XCTAssertEqual(nodeRowQuery(app).count, 4, "Imported four nodes should be listed")
        assertText(app, "Manual")
        assertText(app, "4 nodes")

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field missing")
        searchField.tap()
        searchField.typeText("Tokyo")
        XCTAssertEqual(nodeRowQuery(app).count, 1, "Search should filter down to Tokyo-01")
        assertNodeNamed(app, "Tokyo-01")
        XCTAssertFalse(nodeRowLabels(app).contains { $0.hasPrefix("Frankfurt") })

        // Clear, then a query with no matches -> themed empty state.
        searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Tokyo".count))
        XCTAssertEqual(nodeRowQuery(app).count, 4)
        searchField.typeText("zzzz")
        assertText(app, "No Results")
        assertText(app, "No nodes match your search.")
        XCTAssertEqual(nodeRowQuery(app).count, 0)
    }

    func testNodesSelectRowUpdatesHomeCurrentNode() {
        let app = launchWithFourNodes()
        XCTAssertEqual(nodeRowQuery(app).count, 4)

        // Select a row that is not the active one (Frankfurt sorts first alphabetically).
        let frankfurt = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Frankfurt"))
            .firstMatch
        XCTAssertTrue(frankfurt.waitForExistence(timeout: 10), "Frankfurt row missing")
        frankfurt.tap()

        tapTab(app, "Connect")
        assertVisible(app, "wuji.home.currentNodeRow")
        XCTAssertTrue(anyElement(app, "wuji.home.currentNodeRow").label.contains("Frankfurt"),
                      "Home should show the node selected in the list")
        // The status subtitle also reflects the active node.
        let subtitle = anyElement(app, "wuji.home.statusSubtitle")
        XCTAssertTrue(subtitle.waitForExistence(timeout: 10))
        XCTAssertTrue(subtitle.label.contains("Frankfurt"),
                      "Status subtitle should show the active node, got: \(subtitle.label)")
    }

    func testNodesSortMenuReordersList() {
        let app = launchWithFourNodes()
        let initialOrder = nodeRowLabels(app).map { String($0.split(separator: ",").first ?? "") }
        XCTAssertEqual(initialOrder, ["Frankfurt", "Seoul-02", "Singapore", "Tokyo-01"],
                       "Default sort (latency asc, ties by name) should be alphabetical")

        tap(app, "wuji.nodes.sortMenu")
        let descending = app.buttons["Descending"].firstMatch
        let descendingText = app.staticTexts["Descending"].firstMatch
        if descending.waitForExistence(timeout: 8) {
            descending.tap()
        } else if descendingText.waitForExistence(timeout: 3) {
            descendingText.tap()
        } else {
            XCTFail("Sort menu did not offer the Descending option")
        }

        XCTAssertEqual(nodeRowLabels(app).map { String($0.split(separator: ",").first ?? "") },
                       ["Tokyo-01", "Singapore", "Seoul-02", "Frankfurt"],
                       "Descending sort should reverse the list order")
    }

    func testNodesTestAllRunsAndReenables() {
        let app = launchWithFourNodes()
        let testAll = control(app, "wuji.nodes.testAllButton")
        XCTAssertTrue(testAll.waitForExistence(timeout: 10), "Test All button missing")
        XCTAssertTrue(testAll.isEnabled)
        testAll.tap()

        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == 0"),
                                                 object: control(app, "wuji.nodes.testAllButton"))
        XCTAssertEqual(XCTWaiter().wait(for: [disabled], timeout: 5), .completed,
                       "Test All should disable while the latency tests run")
        let reenabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == 1"),
                                                  object: control(app, "wuji.nodes.testAllButton"))
        XCTAssertEqual(XCTWaiter().wait(for: [reenabled], timeout: 25), .completed,
                       "Test All should re-enable when the run completes")
        XCTAssertEqual(nodeRowQuery(app).count, 4, "Latency run must not remove nodes")
    }

    func testNodesSwipeDeleteWithConfirmation() {
        let app = launchWithFourNodes()
        XCTAssertEqual(nodeRowQuery(app).count, 4)
        let firstName = String(firstNodeRow(app).label.split(separator: ",").first ?? "")

        swipeDeleteByIdentifier(firstRowIn: app)
        waitForSystemDialog(app)
        tapSystemDialogButton(app, "Cancel")
        XCTAssertEqual(nodeRowQuery(app).count, 4, "Cancelling delete must keep the node")

        swipeDeleteByIdentifier(firstRowIn: app)
        waitForSystemDialog(app)
        tapSystemDialogButton(app, "Delete")
        XCTAssertTrue(nodeRowQuery(app).firstMatch.waitForExistence(timeout: 12))
        let remaining = nodeRowLabels(app).map { String($0.split(separator: ",").first ?? "") }
        XCTAssertEqual(remaining.count, 3, "Deleting one node should leave three")
        XCTAssertFalse(remaining.contains(firstName), "The deleted node must be gone")

        // Deletion is persisted, not just removed from the view.
        tapTab(app, "Settings")
        assertVisible(app, "wuji.settings.list")
        tapTab(app, "Nodes")
        XCTAssertEqual(nodeRowQuery(app).count, 3)
    }

    /// Swipes the first node row's cell left and taps its identified Delete action.
    private func swipeDeleteByIdentifier(firstRowIn app: XCUIApplication,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        let row = firstNodeRow(app)
        let profileID = String(row.identifier.dropFirst("wuji.nodes.row.".count))
        let cell = app.cells.containing(.button, identifier: row.identifier).firstMatch
        if cell.exists {
            cell.swipeLeft()
        } else {
            row.swipeLeft()
        }
        let deleteButton = app.buttons["wuji.nodes.swipeDelete.\(profileID)"].firstMatch
        guard deleteButton.waitForExistence(timeout: 10) else {
            XCTFail("Swipe delete action missing for \(profileID)", file: file, line: line)
            return
        }
        deleteButton.tap()
    }

    /// Swipes the first node row's cell left and taps the revealed Delete action.
    private func swipeDelete(firstRowIn app: XCUIApplication,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        let row = firstNodeRow(app)
        let cell = app.cells.containing(.button, identifier: row.identifier).firstMatch
        if cell.exists {
            cell.swipeLeft()
        } else {
            row.swipeLeft()
        }
        let swipeDelete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 10),
                      "Swipe delete action missing", file: file, line: line)
        swipeDelete.tap()
    }

    func testNodeActionsCopyAndQRShare() {
        let app = launchWithFourNodes()
        // Some pasteboard reads may show the system paste permission alert.
        addUIInterruptionMonitor(withDescription: "Paste permission") { alert in
            for label in ["Allow Paste", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        let row = firstNodeRow(app)
        let name = String(row.label.split(separator: ",").first ?? "")
        tap(app, contextMenuIdentifier(for: row))
        assertVisible(app, "wuji.nodes.actions.header")

        // Copy URI. The "Copied" label only lives for 1.6 s, which is shorter than an
        // XCUITest snapshot round-trip, so verify the real effect: the app's paste
        // import page auto-fills from the clipboard and must recognize the URI.
        tap(app, "wuji.nodes.actions.copyURI")
        XCTAssertFalse(anyElement(app, "wuji.nodes.actions.copyError").exists,
                       "Copy URI must not report a missing share link")
        tap(app, "wuji.nodes.actions.cancel")
        assertGone(app, "wuji.nodes.actions.header")

        openAddMenu(app)
        tap(app, "wuji.nodes.addMenu.paste")
        XCTAssertTrue(app.navigationBars["Paste Links"].waitForExistence(timeout: 12))
        app.tap() // let the interruption monitor dismiss a paste-permission alert
        let editor = app.textViews["wuji.nodes.paste.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let pasted = (editor.value as? String) ?? ""
        XCTAssertFalse(pasted.isEmpty,
                       "Paste page should auto-fill the share link copied via Copy URI")
        XCTAssertTrue(pasted.contains("://"),
                      "Clipboard written by Copy URI should contain a share link, got: \(pasted.prefix(80))")
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any)
                                        .matching(NSPredicate(format: "identifier BEGINSWITH %@", "wuji.nodes.paste.row."))
                                        .count, 1,
                                    "Copied URI should be recognized as at least one node")
        tap(app, "wuji.nodes.paste.cancelButton")
        XCTAssertTrue(nodeRowQuery(app).firstMatch.waitForExistence(timeout: 10))

        // Share QR pushes the QR page with a rendered QR image.
        tap(app, contextMenuIdentifier(for: firstNodeRow(app)))
        tap(app, "wuji.nodes.actions.shareQR")
        XCTAssertTrue(app.navigationBars["Share Node"].waitForExistence(timeout: 12))
        assertVisible(app, "wuji.nodes.qr.image")
        XCTAssertEqual(anyElement(app, "wuji.nodes.qr.image").label, "QR code for \(name)")
        XCTAssertTrue(anyElement(app, "wuji.nodes.qr.shareButton").exists)

        // Copy URI from the QR page shows the inline status (visible for 2.5 s).
        tap(app, "wuji.nodes.qr.copyButton")
        assertVisible(app, "wuji.nodes.qr.status", timeout: 6)
        XCTAssertEqual(anyElement(app, "wuji.nodes.qr.status").label, "URI Copied")

        tapBack(app, "Share Node")
        assertVisible(app, "wuji.nodes.actions.cancel")
        tap(app, "wuji.nodes.actions.cancel")
        assertGone(app, "wuji.nodes.actions.header")
        XCTAssertEqual(nodeRowQuery(app).count, 4)
    }

    func testNodeActionsEditRenamesNode() {
        let app = launchWithFourNodes()
        let row = firstNodeRow(app)
        tap(app, contextMenuIdentifier(for: row))
        tap(app, "wuji.nodes.actions.edit")
        XCTAssertTrue(app.navigationBars["Edit Node"].waitForExistence(timeout: 12))

        clearAndType(app, "wuji.nodes.form.name", "Renamed Node")
        saveNodeForm(app)
        assertGone(app, "wuji.nodes.actions.header")
        assertNodeNamed(app, "Renamed Node")
        XCTAssertFalse(nodeRowLabels(app).contains { $0.hasPrefix("Frankfurt") },
                       "The old node name should be replaced")
    }

    func testNodeActionsDeleteWithConfirmation() {
        let app = launchWithFourNodes()
        let row = firstNodeRow(app)
        let name = String(row.label.split(separator: ",").first ?? "")
        tap(app, contextMenuIdentifier(for: row))
        tap(app, "wuji.nodes.actions.delete")
        waitForSystemDialog(app)
        tapSystemDialogButton(app, "Delete")
        XCTAssertTrue(nodeRowQuery(app).firstMatch.waitForExistence(timeout: 12))
        XCTAssertEqual(nodeRowQuery(app).count, 3)
        XCTAssertFalse(nodeRowLabels(app).contains { $0.hasPrefix(name) })
    }

    // MARK: - D. Paste import

    func testPasteImportTypedLinks() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "nodes"))
        let links = """
        vless://b9d3f7e2-6a4c-4f5d-8e91-2c7a0e4b9f3d@203.0.113.24:443?type=ws&security=tls&sni=example.com#Typed-VLESS
        trojan://typed-password@typed.example:443?security=tls#Typed-Trojan
        """
        importLinksByTyping(app, links)
        XCTAssertTrue(app.buttons["Import 2 Nodes"].waitForExistence(timeout: 20),
                      "Two typed links should be recognized and selectable")
        XCTAssertEqual(app.descendants(matching: .any)
                        .matching(NSPredicate(format: "identifier BEGINSWITH %@", "wuji.nodes.paste.row."))
                        .count, 2)
        tap(app, "wuji.nodes.paste.primaryButton")
        assertNodeNamed(app, "Typed-VLESS")
        assertNodeNamed(app, "Typed-Trojan")
        XCTAssertEqual(nodeRowQuery(app).count, 2)
    }

    func testPasteImportInvalidInputShowsError() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "nodes"))
        importLinksByTyping(app, "definitely not a share link")
        assertVisible(app, "wuji.nodes.paste.error", timeout: 15)
        XCTAssertTrue(anyElement(app, "wuji.nodes.paste.error").label.contains("No supported share links"))
        let primary = control(app, "wuji.nodes.paste.primaryButton")
        XCTAssertTrue(primary.waitForExistence(timeout: 8))
        XCTAssertFalse(primary.isEnabled, "Import button must be disabled when nothing is recognized")
        assertText(app, "No supported share links were found.")
    }

    // MARK: - D. Scan QR

    func testScanPageCameraUnavailableFallbackAndClose() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "nodes"))
        tap(app, "wuji.nodes.empty.scanButton")
        assertVisible(app, "wuji.nodes.scan.closeButton")
        // The simulator has no camera: the page must degrade with a clear message
        // and keep the photo / paste fallbacks available.
        assertVisible(app, "wuji.nodes.scan.unavailableMessage", timeout: 15)
        assertVisible(app, "wuji.nodes.scan.choosePhotoButton")
        tap(app, "wuji.nodes.scan.closeButton")
        assertText(app, "No Nodes Yet")
    }

    func testScanPreviewCardCancelAndSave() {
        var app = launchWithFourNodes()
        XCTAssertEqual(nodeRowQuery(app).count, 4)

        // Relaunch (data persists) into the debug scan-preview harness state.
        app = relaunch(app, WujiLaunch(reset: false, tab: "nodes", page: "nodes-scan-preview"))
        assertVisible(app, "wuji.nodes.scan.previewCard", timeout: 20)
        assertVisible(app, "wuji.nodes.scan.saveButton", timeout: 10)
        assertVisible(app, "wuji.nodes.scan.cancelSaveButton", timeout: 10)
        tap(app, "wuji.nodes.scan.cancelSaveButton")
        assertGone(app, "wuji.nodes.scan.previewCard")

        // Relaunch into the preview again and actually save the scanned node.
        app = relaunch(app, WujiLaunch(reset: false, tab: "nodes", page: "nodes-scan-preview"))
        assertVisible(app, "wuji.nodes.scan.previewCard", timeout: 20)
        tap(app, "wuji.nodes.scan.saveButton")
        let added = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.nodeRowQuery(app).count == 5 },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [added], timeout: 20), .completed,
                       "Saving the scanned node should add one node")
    }

    // MARK: - D. Manual add / edit forms

    func testAddNodeVMessValidationAndSave() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "nodes"))
        openManualAddForm(app)
        selectProtocol(app, "VMess")
        XCTAssertTrue(app.textFields["wuji.nodes.form.alterID"].exists)

        // Empty form -> inline validation errors, nothing saved.
        saveNodeForm(app)
        assertVisible(app, "wuji.nodes.form.error.server")
        assertVisible(app, "wuji.nodes.form.error.uuid")
        assertText(app, "Enter a server address.")
        XCTAssertTrue(app.navigationBars["Add Node"].exists)

        // Invalid port -> inline error; cancel the invalid form.
        clearAndType(app, "wuji.nodes.form.port", "70000")
        saveNodeForm(app)
        assertVisible(app, "wuji.nodes.form.error.port")
        assertText(app, "Port must be between 1 and 65535.")
        tap(app, "wuji.nodes.form.cancelButton")
        assertText(app, "No Nodes Yet")

        // Clean form with valid values -> saved and listed with the chosen protocol.
        openManualAddForm(app)
        selectProtocol(app, "VMess")
        type(app, "wuji.nodes.form.name", "UI VMess")
        type(app, "wuji.nodes.form.address", "203.0.113.77")
        type(app, "wuji.nodes.form.uuid", "11111111-2222-3333-4444-555555555555")
        saveNodeForm(app)
        diagnoseFormIfStillOpen(app)
        assertNodeNamed(app, "UI VMess")
        XCTAssertTrue(nodeRowLabels(app).contains { $0.contains("VMess") })

        // Duplicate protection: the same node cannot be added twice.
        openManualAddForm(app)
        selectProtocol(app, "VMess")
        type(app, "wuji.nodes.form.name", "UI VMess dup")
        type(app, "wuji.nodes.form.address", "203.0.113.77")
        type(app, "wuji.nodes.form.uuid", "11111111-2222-3333-4444-555555555555")
        saveNodeForm(app)
        assertVisible(app, "wuji.nodes.form.error.duplicate")
        XCTAssertEqual(nodeRowQuery(app).count, 1, "Duplicate node must not be saved")
    }

    /// Prints the inline field errors when a node form refuses to close, so CI logs
    /// explain a save failure instead of only reporting "node missing".
    private func diagnoseFormIfStillOpen(_ app: XCUIApplication) {
        guard app.navigationBars["Add Node"].exists else { return }
        let errors = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "wuji.nodes.form.error."))
        let descriptions = errors.allElementsBoundByIndex.map { "\($0.identifier)=\($0.label)" }
        print("@@@ FORM-STILL-OPEN errors=\(descriptions) @@@")
        for field in ["name", "address", "port", "uuid"] {
            let element = app.textFields["wuji.nodes.form.\(field)"].firstMatch
            print("@@@ FIELD \(field)=\(String(describing: element.value)) @@@")
        }
        let saveError = anyElement(app, "wuji.nodes.form.saveError")
        if saveError.exists {
            print("@@@ SAVE-ERROR=\(saveError.label) @@@")
        }
    }

    func testAddNodeVLESSSecurityAndRealityValidation() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "nodes"))
        openManualAddForm(app)
        selectProtocol(app, "VLESS")
        XCTAssertTrue(app.buttons["wuji.nodes.form.flow"].exists, "VLESS should expose the Flow picker")
        XCTAssertTrue(app.buttons["wuji.nodes.form.security"].exists)

        // REALITY fields only appear for VLESS + REALITY. The form virtualises its
        // rows, so scroll down to the REALITY section first.
        pickNavigationOption(app, "wuji.nodes.form.security", "REALITY")
        scrollTo(app, "wuji.nodes.form.realityPublicKey")
        assertVisible(app, "wuji.nodes.form.realityPublicKey", timeout: 10)
        assertVisible(app, "wuji.nodes.form.realityShortID")

        saveNodeForm(app)
        assertVisible(app, "wuji.nodes.form.error.realityPublicKey")
        assertGone(app, "wuji.nodes.form.error.realityShortID", timeout: 2)

        // Invalid hex Short ID is rejected after filling the key.
        type(app, "wuji.nodes.form.realityPublicKey", "jNXHt1o0Yp1lGk2sQz8cVb4eRf6tYu7iOp9aS3dF5gH")
        type(app, "wuji.nodes.form.realityShortID", "zzzz")
        saveNodeForm(app)
        assertVisible(app, "wuji.nodes.form.error.realityShortID")
        assertText(app, "Short ID must be hexadecimal.")

        // Fix everything -> saved with REALITY settings.
        clearAndType(app, "wuji.nodes.form.realityShortID", "a1b2c3d4")
        // Address/UUID validation errors above are still visible while the empty
        // address/UUID are rejected by the same save path.
        scrollTo(app, "wuji.nodes.form.error.server")
        assertVisible(app, "wuji.nodes.form.error.server")
        assertVisible(app, "wuji.nodes.form.error.uuid")

        type(app, "wuji.nodes.form.name", "UI REALITY")
        type(app, "wuji.nodes.form.address", "203.0.113.78")
        type(app, "wuji.nodes.form.uuid", "3c1d5e7f-9a2b-4c6d-8e0f-1a3b5c7d9e2f")
        saveNodeForm(app)
        diagnoseFormIfStillOpen(app)
        assertGone(app, "wuji.nodes.form.saveButton", timeout: 8)
        assertNodeNamed(app, "UI REALITY")
    }

    func testAddNodeTrojanValidationAndSave() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "nodes"))
        openManualAddForm(app)
        selectProtocol(app, "Trojan")
        assertVisible(app, "wuji.nodes.form.password")
        XCTAssertFalse(app.buttons["wuji.nodes.form.flow"].exists,
                       "Trojan must not show the VLESS flow picker")

        saveNodeForm(app)
        assertVisible(app, "wuji.nodes.form.error.password")
        assertText(app, "Enter a password.")

        type(app, "wuji.nodes.form.name", "UI Trojan")
        type(app, "wuji.nodes.form.address", "203.0.113.79")
        type(app, "wuji.nodes.form.password", "trojan-pass")
        saveNodeForm(app)
        assertNodeNamed(app, "UI Trojan")
        XCTAssertTrue(nodeRowLabels(app).contains { $0.contains("Trojan") })
    }

    func testAddNodeShadowsocksValidationAndSave() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "nodes"))
        openManualAddForm(app)
        selectProtocol(app, "SS")
        assertVisible(app, "wuji.nodes.form.method")
        assertVisible(app, "wuji.nodes.form.password")
        XCTAssertFalse(app.buttons["wuji.nodes.form.network"].exists,
                       "Shadowsocks must not show the transport picker")

        saveNodeForm(app)
        assertVisible(app, "wuji.nodes.form.error.password")

        type(app, "wuji.nodes.form.name", "UI SS")
        type(app, "wuji.nodes.form.address", "203.0.113.80")
        type(app, "wuji.nodes.form.password", "ss-pass")
        pickNavigationOption(app, "wuji.nodes.form.method", "aes-128-gcm")
        saveNodeForm(app)
        assertNodeNamed(app, "UI SS")
        XCTAssertTrue(nodeRowLabels(app).contains { $0.contains("SS") })
    }

    // MARK: - E. Subscriptions

    private func openSubscriptions(_ app: XCUIApplication) {
        tapTab(app, "Settings")
        tap(app, "wuji.settings.subscriptions")
        XCTAssertTrue(app.navigationBars["Subscriptions"].waitForExistence(timeout: 12))
    }

    private func openAddSubscriptionForm(_ app: XCUIApplication) {
        tap(app, "wuji.subscriptions.addButton")
        XCTAssertTrue(app.navigationBars["Add Subscription"].waitForExistence(timeout: 12))
    }

    private func addSubscriptionFromServer(_ app: XCUIApplication,
                                           url: String,
                                           name: String? = nil,
                                           file: StaticString = #filePath,
                                           line: UInt = #line) {
        openSubscriptions(app)
        openAddSubscriptionForm(app)
        type(app, "wuji.subscriptions.add.urlField", url)
        if let name {
            type(app, "wuji.subscriptions.add.nameField", name)
        }
        dismissKeyboard(app)
        tap(app, "wuji.subscriptions.add.submit")
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "wuji.subscriptions.row."))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 25),
                      "Subscription was not created (server unreachable?)", file: file, line: line)
    }

    func testSubscriptionEmptyStateAndFormCancel() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "settings"))
        openSubscriptions(app)
        assertVisible(app, "wuji.subscriptions.emptyState")
        assertText(app, "No Subscriptions")

        openAddSubscriptionForm(app)
        assertVisible(app, "wuji.subscriptions.add.urlField")
        assertVisible(app, "wuji.subscriptions.add.nameField")
        XCTAssertFalse(control(app, "wuji.subscriptions.add.submit").isEnabled,
                       "Submit must be disabled while the URL is empty")

        // Auto-update interval picker: choose 6 hours and verify the value round-trips
        // into the form.
        tap(app, "wuji.subscriptions.add.autoUpdate")
        assertVisible(app, "wuji.subscriptions.add.interval.off")
        tap(app, "wuji.subscriptions.add.interval.sixHours")
        tapBack(app, "Auto Update")
        XCTAssertTrue(anyElement(app, "wuji.subscriptions.add.autoUpdate").label.contains("Every 6 Hours"),
                      "Chosen interval should be shown on the form")

        tap(app, "wuji.subscriptions.add.cancel")
        assertGone(app, "wuji.subscriptions.add.urlField")
        assertVisible(app, "wuji.subscriptions.emptyState")
    }

    func testSubscriptionAddInvalidURLShowsError() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "settings"))
        openSubscriptions(app)
        openAddSubscriptionForm(app)
        type(app, "wuji.subscriptions.add.urlField", "not-a-url")
        tap(app, "wuji.subscriptions.add.submit")
        assertVisible(app, "wuji.subscriptions.form.error", timeout: 20)
        XCTAssertTrue(anyElement(app, "wuji.subscriptions.form.error").label.count > 0)
        // The form stays open with the entered URL so it can be corrected.
        assertVisible(app, "wuji.subscriptions.add.urlField")
        XCTAssertTrue(app.textFields["wuji.subscriptions.add.urlField"].value as? String == "not-a-url")
    }

    func testSubscriptionAddFromLocalServerDetailAndUpdate() {
        let server = LocalSubscriptionServer(port: 19141, responses: [
            .init(body: WujiSamples.subscriptionBody, userInfo: WujiSamples.subscriptionUserInfo),
            .init(body: WujiSamples.subscriptionBodyUpdated, userInfo: WujiSamples.subscriptionUserInfo)
        ])
        server.start()
        addTeardownBlock { server.stop() }

        let app = launchToTabs(WujiLaunch(reset: true, tab: "settings"))
        addSubscriptionFromServer(app, url: server.url)

        // Card: name (URL host), node count, updated timestamp.
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "127.0.0.1")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Subscription card missing")
        XCTAssertTrue(card.label.contains("3 nodes"), "Expected 3 nodes, got: \(card.label)")
        assertText(app, "Auto-update runs while the app is open.")

        // Detail: statistics + traffic metadata from Subscription-Userinfo.
        card.tap()
        assertVisible(app, "wuji.subscriptions.detail.list")
        assertVisible(app, "wuji.subscriptions.detail.stat.nodes")
        assertVisible(app, "wuji.subscriptions.detail.stat.used")
        assertVisible(app, "wuji.subscriptions.detail.stat.expires")
        assertVisible(app, "wuji.subscriptions.detail.progress")
        let viewAll = scrollTo(app, "wuji.subscriptions.detail.viewAllNodes")
        XCTAssertTrue(viewAll.exists, "View-all-nodes row missing")
        XCTAssertTrue(viewAll.label.contains("3"),
                      "View-all row should count 3 nodes, got: \(viewAll.label)")
        assertVisible(app, "wuji.subscriptions.detail.updateNow")
        assertVisible(app, "wuji.subscriptions.detail.delete")

        // URL row copies and toasts.
        tap(app, "wuji.subscriptions.detail.url")
        assertText(app, "URL copied")

        // A node preview row selects that node.
        let nodeRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "wuji.subscriptions.detail.node."))
            .firstMatch
        XCTAssertTrue(nodeRow.waitForExistence(timeout: 10), "Node preview row missing")
        nodeRow.tap()
        XCTAssertTrue(app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "selected"))
            .firstMatch.waitForExistence(timeout: 10),
                      "Selecting a node from the preview should show a confirmation toast")

        // View all nodes sheet opens and closes.
        tap(app, "wuji.subscriptions.detail.viewAllNodes")
        assertVisible(app, "wuji.subscriptions.nodes.done")
        XCTAssertEqual(app.descendants(matching: .any)
                        .matching(NSPredicate(format: "identifier BEGINSWITH %@", "wuji.subscriptions.nodes.row."))
                        .count, 3)
        tap(app, "wuji.subscriptions.nodes.done")

        // Update Now refetches from the server: the second response has two nodes,
        // so the list card must show the refreshed node count.
        tap(app, "wuji.subscriptions.detail.updateNow")
        assertText(app, "Subscription updated", timeout: 20)
        tapBack(app, "127.0.0.1")
        let refreshed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2 nodes")).firstMatch
        XCTAssertTrue(refreshed.waitForExistence(timeout: 15),
                      "Update Now should replace the node list with the refreshed response")
    }

    func testSubscriptionEditNameAndDelete() {
        let server = LocalSubscriptionServer(port: 19142, responses: [
            .init(body: WujiSamples.subscriptionBody, userInfo: WujiSamples.subscriptionUserInfo)
        ])
        server.start()
        addTeardownBlock { server.stop() }

        var app = launchToTabs(WujiLaunch(reset: true, tab: "settings"))
        addSubscriptionFromServer(app, url: server.url)
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "127.0.0.1")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        assertVisible(app, "wuji.subscriptions.detail.list")

        // Edit: rename, then the navigation title reflects the new name.
        tap(app, "wuji.subscriptions.detail.edit")
        XCTAssertTrue(app.navigationBars["Edit Subscription"].waitForExistence(timeout: 12))
        clearAndType(app, "wuji.subscriptions.add.nameField", "Renamed Subscription")
        tap(app, "wuji.subscriptions.add.save")
        assertGone(app, "wuji.subscriptions.add.nameField", timeout: 15)
        tapBack(app, "Subscriptions")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Renamed Subscription"))
                        .firstMatch.waitForExistence(timeout: 15),
                      "Renamed subscription should appear on the list")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Renamed Subscription"))
            .firstMatch.tap()

        // Delete with confirmation -> back on the list, which is empty again.
        tap(app, "wuji.subscriptions.detail.delete")
        confirmCustomSheet(app, expectedTitle: "Delete Subscription?")
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "wuji.subscriptions.row.")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                app.descendants(matching: .any).matching(predicate).count == 0
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 20), .completed,
                       "Subscription should be gone after deleting")
        assertVisible(app, "wuji.subscriptions.emptyState")

        // The subscription list hides the tab bar; pop back to Settings first.
        tapBack(app, "Subscriptions")

        // The nodes of the deleted subscription are gone from the node list too.
        tapTab(app, "Nodes")
        assertText(app, "No Nodes Yet")

        // Settings counter resets as well.
        tapTab(app, "Settings")
        let subscriptionsRow = control(app, "wuji.settings.subscriptions")
        XCTAssertTrue(subscriptionsRow.waitForExistence(timeout: 10))
        XCTAssertTrue(subscriptionsRow.label.contains("0"))
    }

    // MARK: - F. Routing

    private func openRouting(_ app: XCUIApplication) {
        tapTab(app, "Connect")
        let routingRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Routing"))
            .firstMatch
        XCTAssertTrue(routingRow.waitForExistence(timeout: 10), "Routing summary row missing")
        routingRow.tap()
        assertVisible(app, "wuji.routing.globalModeToggle")
    }

    func testRoutingModeAndBypassLANToggle() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "connect"))
        openRouting(app)

        // Defaults: Rule mode, LAN bypass on, no regions selected.
        XCTAssertTrue(app.switches["wuji.routing.bypassLanToggle"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(switchValue(app, "wuji.routing.bypassLanToggle"), "1")
        XCTAssertTrue(anyElement(app, "wuji.routing.regionsRow").label.contains("0 selected"))

        // Toggling LAN bypass persists immediately for this screen.
        tapSwitch(app, "wuji.routing.bypassLanToggle")
        XCTAssertEqual(switchValue(app, "wuji.routing.bypassLanToggle"), "0")

        // Global mode is one switch inside the rules page; turning it on disables
        // the LAN/region controls below.
        tapSwitch(app, "wuji.routing.globalModeToggle")
        let lanToggle = app.switches["wuji.routing.bypassLanToggle"].firstMatch
        expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: lanToggle, handler: nil)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(lanToggle.isEnabled, "LAN toggle must be disabled in Global mode")
        XCTAssertFalse(anyElement(app, "wuji.routing.addRegion").isEnabled)

        tap(app, "wuji.routing.done")
        assertGone(app, "wuji.routing.globalModeToggle")
        let routingRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Routing"))
            .firstMatch
        XCTAssertTrue(routingRow.waitForExistence(timeout: 10))
        XCTAssertTrue(routingRow.label.contains("Global"), "Home summary should switch to Global, got: \(routingRow.label)")
    }

    func testCountryPickerSearchSelectAndDone() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "connect"))
        openRouting(app)
        tap(app, "wuji.routing.addRegion")
        assertVisible(app, "wuji.routing.picker.list", timeout: 20)

        // Search narrows down to Japan, selecting updates the draft.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15), "Country picker search field missing")
        search.tap()
        search.typeText("Japan")
        let japan = app.buttons["wuji.routing.picker.row.JP"]
        XCTAssertTrue(japan.waitForExistence(timeout: 15), "Japan row should match the search")
        japan.tap()
        XCTAssertEqual(japan.value as? String, "selected")

        // No-results state for a nonsense search.
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Japan".count))
        search.typeText("zzzzzz")
        assertVisible(app, "wuji.routing.picker.noResults")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "zzzzzz".count))

        // Done commits the draft and the routing screen shows the region row.
        leaveSearchMode(app, toolbarIdentifier: "wuji.routing.picker.done")
        tap(app, "wuji.routing.picker.done")
        assertVisible(app, "wuji.routing.region.JP", timeout: 15)
        XCTAssertTrue(anyElement(app, "wuji.routing.regionsRow").label.contains("1 selected"))
        XCTAssertFalse(anyElement(app, "wuji.routing.regionsEmpty").exists)

        // Home summary counts LAN + the selected region.
        tap(app, "wuji.routing.done")
        let routingRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Routing"))
            .firstMatch
        XCTAssertTrue(routingRow.waitForExistence(timeout: 10))
        XCTAssertTrue(routingRow.label.contains("2 bypassed"),
                      "Rule summary should count LAN + Japan, got: \(routingRow.label)")
    }

    func testCountryPickerCancelDiscardsDraft() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "connect"))
        openRouting(app)
        tap(app, "wuji.routing.addRegion")
        assertVisible(app, "wuji.routing.picker.list", timeout: 20)

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("Japan")
        let japan = app.buttons["wuji.routing.picker.row.JP"]
        XCTAssertTrue(japan.waitForExistence(timeout: 15))
        japan.tap()

        // Cancel discards the draft selection.
        leaveSearchMode(app, toolbarIdentifier: "wuji.routing.picker.cancel")
        tap(app, "wuji.routing.picker.cancel")
        assertGone(app, "wuji.routing.picker.list")
        XCTAssertTrue(anyElement(app, "wuji.routing.regionsRow").label.contains("0 selected"))
        assertVisible(app, "wuji.routing.regionsEmpty")
    }

    // MARK: - G. Settings

    func testNetworkPermissionFailurePageBlocksUntilGranted() {
        var configuration = WujiLaunch(reset: true, bypassOnboarding: false)
        configuration.extra = ["-WujiForcePermissionGate", "-WujiForcePermissionFailure"]
        let app = launch(configuration)

        assertVisible(app, "wuji.permission.screen", timeout: 15)
        assertVisible(app, "wuji.permission.failedTitle", timeout: 15)
        assertVisible(app, "wuji.permission.openSettings")
        assertVisible(app, "wuji.permission.retry")
        XCTAssertFalse(anyElement(app, "wuji.consent.checkbox").exists,
                       "The consent gate must stay blocked while permissions are missing")

        // Retrying with permission still denied keeps the failure page visible.
        tap(app, "wuji.permission.retry")
        assertVisible(app, "wuji.permission.failedTitle", timeout: 15)
    }

    func testNetworkPermissionSuccessContinuesToConsent() {
        var configuration = WujiLaunch(reset: true, bypassOnboarding: false)
        configuration.extra = ["-WujiForcePermissionGate"]
        let app = launch(configuration)

        // The simulator grants permissions automatically; the gate must hand over to
        // the consent screen without user interaction.
        assertVisible(app, "wuji.consent.checkbox", timeout: 20)
        XCTAssertFalse(anyElement(app, "wuji.permission.failedTitle").exists)
    }

    func testSettingsTestURLAndTimeout() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "settings"))
        assertVisible(app, "wuji.settings.list")

        // Test URL saves and updates the row value.
        tap(app, "wuji.settings.testURL")
        assertVisible(app, "wuji.settings.latency.urlField")
        clearAndType(app, "wuji.settings.latency.urlField", "https://example.com/generate_204")
        tap(app, "wuji.settings.latency.save")
        XCTAssertTrue(anyElement(app, "wuji.settings.testURL").waitForExistence(timeout: 12))
        XCTAssertTrue(anyElement(app, "wuji.settings.testURL").label.contains("example.com"))

        // Timeout selection pops back and updates the row.
        tap(app, "wuji.settings.timeout")
        tap(app, "wuji.settings.timeout.option.8")
        XCTAssertTrue(anyElement(app, "wuji.settings.timeout").waitForExistence(timeout: 12))
        XCTAssertTrue(anyElement(app, "wuji.settings.timeout").label.contains("8 seconds"))

        // Auto-update toggle flips its value.
        XCTAssertTrue(app.switches["wuji.settings.autoUpdate"].firstMatch.waitForExistence(timeout: 10))
        let before = switchValue(app, "wuji.settings.autoUpdate")
        tapSwitch(app, "wuji.settings.autoUpdate")
        let after = switchValue(app, "wuji.settings.autoUpdate")
        XCTAssertNotEqual(before, after, "Auto-update toggle should change value")
    }

    func testSettingsLatencyURLValidation() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "settings"))
        tap(app, "wuji.settings.testURL")
        assertVisible(app, "wuji.settings.latency.urlField")
        clearAndType(app, "wuji.settings.latency.urlField", "not-a-url")
        tap(app, "wuji.settings.latency.save")
        assertText(app, "Enter a valid http:// or https:// URL.")
        // Still on the editing page; navigating back keeps the old value.
        assertVisible(app, "wuji.settings.latency.urlField")
        tapBack(app, "Test URL")
        XCTAssertTrue(anyElement(app, "wuji.settings.testURL").label.contains("gstatic.com"))
    }

    func testSettingsAutoUpdateTogglePersists() {
        var app = launchToTabs(WujiLaunch(reset: true, tab: "settings"))
        XCTAssertTrue(app.switches["wuji.settings.autoUpdate"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(switchValue(app, "wuji.settings.autoUpdate"), "1", "Auto-update defaults to on")
        tapSwitch(app, "wuji.settings.autoUpdate")
        XCTAssertEqual(switchValue(app, "wuji.settings.autoUpdate"), "0")

        // The value survives a relaunch (persisted settings).
        app = relaunch(app, WujiLaunch(reset: false, tab: "settings"))
        XCTAssertEqual(switchValue(app, "wuji.settings.autoUpdate"), "0",
                       "Auto-update toggle must persist across launches")
    }

    func testSettingsAboutLicensesAndLegal() {
        let app = launchToTabs(WujiLaunch(reset: true, tab: "settings"))
        tap(app, "wuji.settings.about")
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 12))
        assertText(app, "WProxy")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Version "))
                        .firstMatch.waitForExistence(timeout: 8), "About should show the app version")

        // Licenses: three components, each expandable.
        tap(app, "wuji.settings.about.openSource")
        assertVisible(app, "wuji.settings.licenses.xray-core")
        assertVisible(app, "wuji.settings.licenses.libxray")
        assertVisible(app, "wuji.settings.licenses.country-cidrs")
        tap(app, "wuji.settings.licenses.xray-core")
        XCTAssertTrue(app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Mozilla Public License"))
            .firstMatch.waitForExistence(timeout: 10),
                      "Expanding the Xray-core license should reveal the license text")
        tapBack(app, "Open Source Licenses")

        // View all licenses entry.
        tap(app, "wuji.settings.about.openSource")
        assertVisible(app, "wuji.settings.licenses.libxray")
        tapBack(app, "Open Source Licenses")

        tapBack(app, "About")

        // Legal pages are only reachable from Settings (About no longer duplicates them).
        tap(app, "wuji.settings.terms")
        assertVisible(app, "wuji.settings.legal.scroll")
        tapBack(app, "Terms of Use")
        tap(app, "wuji.settings.privacy")
        assertVisible(app, "wuji.settings.legal.scroll")
        tapBack(app, "Privacy Policy")
        tap(app, "wuji.settings.contact")
        XCTAssertEqual(app.state, .runningForeground,
                       "Contact Support should keep the app in the foreground")
    }

    func testSettingsLanguageMenuSelectionAndPersistence() {
        var app = launchToTabs(WujiLaunch(reset: true, tab: "settings"))
        assertVisible(app, "wuji.settings.list")
        scrollTo(app, "wuji.settings.language.followSystem")
        assertVisible(app, "wuji.settings.language.followSystem")
        let chooseRow = anyElement(app, "wuji.settings.language.chooseAnother")
        XCTAssertTrue(chooseRow.waitForExistence(timeout: 10), "Current-language row missing")
        XCTAssertTrue(chooseRow.label.contains("Follow System"),
                      "Current language should show the followed language, got: \(chooseRow.label)")

        tap(app, "wuji.settings.language.chooseAnother")
        assertVisible(app, "wuji.settings.language.picker")
        assertVisible(app, "wuji.settings.language.option.ja")
        assertVisible(app, "wuji.settings.language.option.zh-Hant")

        tap(app, "wuji.settings.language.option.ja")
        // The app rebuilds in Japanese; the picker closes back to the settings root.
        assertVisible(app, "wuji.settings.list", timeout: 15)
        scrollTo(app, "wuji.settings.language.followSystem")
        XCTAssertTrue(anyElement(app, "wuji.settings.language.chooseAnother").label.contains("日本語"),
                      "Language row should show 日本語 after selecting Japanese")

        // Persisted: relaunch without reset keeps Japanese.
        app = relaunch(app, WujiLaunch(reset: false, tab: "settings"))
        assertVisible(app, "wuji.settings.list")
        XCTAssertTrue(app.tabBars.buttons["設定"].waitForExistence(timeout: 15),
                      "UI should still be Japanese after relaunch")

        // Restore English through the same menu so later tests are unaffected.
        scrollTo(app, "wuji.settings.language.chooseAnother")
        tap(app, "wuji.settings.language.chooseAnother")
        assertVisible(app, "wuji.settings.language.picker")
        tap(app, "wuji.settings.language.option.en")
        assertVisible(app, "wuji.settings.list", timeout: 15)
    }

    func testSettingsClearDataConfirmation() {
        var app = launchWithFourNodes()
        tapTab(app, "Settings")
        tap(app, "wuji.settings.clearData")
        confirmCustomSheet(app, expectedTitle: "Clear All Data?")
        assertGone(app, "wuji.confirmation.title")

        // Relaunch: the database and the settings are back to their first-run values.
        app = relaunch(app, WujiLaunch(reset: false, tab: "nodes"))
        assertText(app, "No Nodes Yet", timeout: 20)
        XCTAssertEqual(nodeRowQuery(app).count, 0)

        // Settings were reset to defaults too.
        tapTab(app, "Settings")
        let subscriptionsRow = control(app, "wuji.settings.subscriptions")
        XCTAssertTrue(subscriptionsRow.waitForExistence(timeout: 10))
        XCTAssertTrue(subscriptionsRow.label.contains("0"))
        XCTAssertEqual(switchValue(app, "wuji.settings.autoUpdate"), "1")
    }
}

// MARK: - Offline HTTP server for subscription tests

/// A tiny loopback HTTP server that lets subscription flows be exercised without the
/// internet. The UI test runner and the app share the simulator's network stack, so the
/// app can fetch `http://127.0.0.1:<port>/...` served from this process.
final class LocalSubscriptionServer {
    struct Response {
        var body: String
        var userInfo: String?
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "wuji.subscription-server")
    private var connections: [NWConnection] = []
    private var responses: [Response]
    private let ready = DispatchSemaphore(value: 0)

    let port: UInt16

    /// - Parameter responses: bodies served in order; the last one is repeated.
    init(port: UInt16, responses: [Response]) {
        self.port = port
        self.responses = responses
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let endpoint = NWEndpoint.Port(rawValue: port)!
        self.listener = try! NWListener(using: params, on: endpoint)
    }

    var url: String { "http://127.0.0.1:\(port)/wuji-sub" }

    func start() {
        var served = 0
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                self.ready.signal()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                let index = min(served, max(self.responses.count - 1, 0))
                served += 1
                let response = self.responses.isEmpty
                    ? Response(body: "", userInfo: nil)
                    : self.responses[index]
                let payload = Data(response.body.utf8)
                var header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n"
                header += "Content-Length: \(payload.count)\r\nConnection: close\r\n"
                if let userInfo = response.userInfo {
                    header += "Subscription-Userinfo: \(userInfo)\r\n"
                }
                header += "\r\n"
                connection.send(content: Data(header.utf8) + payload,
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 10)
    }

    func stop() {
        listener.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }
}

// MARK: - Offline sample data

enum WujiSamples {
    /// Plain-text subscription body with three supported links.
    static let subscriptionBody = """
    vless://3c1d5e7f-9a2b-4c6d-8e0f-1a3b5c7d9e2f@203.0.113.24:443?type=ws&security=tls&sni=example.com&path=%2Fws#Amsterdam-01
    vmess://eyJ2IjoiMiIsInBzIjoiTmV3LVlvcmsiLCJhZGQiOiIyMDMuMC4xMTMuMjUiLCJwb3J0IjoiNDQzIiwiaWQiOiJiOWQzZjdlMi02YTRjLTRmNWQtOGU5MS0yYzdhMGU0YjlmM2QiLCJhaWQiOiIwIiwibmV0Ijoid3MiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiJueS5leGFtcGxlIiwicGF0aCI6Ii93cyIsInRscyI6InRscyJ9
    trojan://demo-password@203.0.113.25:443?security=tls&sni=example.com#Toronto-01
    """

    /// Updated body served on the second fetch (Update Now) — two nodes.
    static let subscriptionBodyUpdated = """
    vless://3c1d5e7f-9a2b-4c6d-8e0f-1a3b5c7d9e2f@203.0.113.24:443?type=ws&security=tls&sni=example.com&path=%2Fws#Amsterdam-02
    trojan://demo-password@203.0.113.25:443?security=tls&sni=example.com#Toronto-02
    """

    static let subscriptionUserInfo = "upload=1073741824; download=2147483648; total=107374182400; expire=4070908800"
}
