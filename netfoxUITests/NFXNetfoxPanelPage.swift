//
//  NFXNetfoxPanelPage.swift
//  netfoxUITests
//
//  Queries and actions for the netfox panel.
//

import XCTest

struct NFXNetfoxPanelPage {

    let app: XCUIApplication

    // MARK: - Chrome

    var requestsBar: XCUIElement { app.navigationBars["Requests"] }
    var detailsBar: XCUIElement { app.navigationBars["Details"] }
    var responseBodyBar: XCUIElement { app.navigationBars["Response body"] }
    var settingsBar: XCUIElement { app.navigationBars["Settings"] }

    var searchField: XCUIElement { app.searchFields.firstMatch }
    var settingsButton: XCUIElement { app.buttons[NFXUITestID.Toolbar.settings] }
    var closeButton: XCUIElement { app.buttons[NFXUITestID.Toolbar.close] }

    /// The find bar on the Response body screen (not the request list search).
    var responseSearchButton: XCUIElement { app.buttons[NFXUITestID.Search.toggle] }
    var responseSearchField: XCUIElement { app.textFields[NFXUITestID.Search.field] }
    var responseSearchStatus: XCUIElement { app.staticTexts[NFXUITestID.Search.status] }
    var previousMatchButton: XCUIElement { app.buttons[NFXUITestID.Search.previous] }
    var nextMatchButton: XCUIElement { app.buttons[NFXUITestID.Search.next] }
    var closeSearchButton: XCUIElement { app.buttons[NFXUITestID.Search.close] }

    // MARK: - Rows

    /// The row whose content contains `url`. Rows are plain buttons, so the
    /// label of the button carries the whole card text.
    func row(containing url: String) -> XCUIElement {
        let buttons = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", url))
        return buttons.firstMatch
    }

    @discardableResult
    func waitForRow(containing url: String, timeout: TimeInterval = 15) -> XCUIElement {
        let element = row(containing: url)
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "No row for \(url) showed up within \(timeout) seconds")
        return element
    }

    func text(_ value: String) -> XCUIElement {
        return app.staticTexts[value]
    }

    // MARK: - Actions

    @discardableResult
    func openDetails(of url: String) -> XCUIElement {
        waitForRow(containing: url).tap()
        XCTAssertTrue(detailsBar.waitForExistence(timeout: 5), "The details screen did not open")
        return detailsBar
    }

    func selectTab(_ name: String) {
        let tab = app.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "The \(name) tab is missing")
        tab.tap()
    }

    func openSettings() {
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "The settings button is missing")
        settingsButton.tap()
        XCTAssertTrue(settingsBar.waitForExistence(timeout: 5), "The settings screen did not open")
    }

    func search(_ query: String) {
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "The search field is missing")
        searchField.tap()
        searchField.typeText(query)
    }

    func openResponseBody() {
        let row = app.staticTexts["Open full body"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The full body row is missing")
        row.tap()
        XCTAssertTrue(responseBodyBar.waitForExistence(timeout: 5), "The response body screen did not open")
    }

    func searchResponseBody(_ query: String) {
        XCTAssertTrue(responseSearchButton.waitForExistence(timeout: 5), "The response search button is missing")
        responseSearchButton.tap()
        XCTAssertTrue(responseSearchField.waitForExistence(timeout: 5), "The find bar did not open")
        responseSearchField.tap()
        responseSearchField.typeText(query)
    }

    func closeResponseSearch() {
        XCTAssertTrue(closeSearchButton.waitForExistence(timeout: 5), "The find bar's close button is missing")
        closeSearchButton.tap()
    }

    func close() {
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "The close button is missing")
        closeButton.tap()
    }

    func goBack() {
        app.navigationBars.buttons.firstMatch.tap()
    }
}
