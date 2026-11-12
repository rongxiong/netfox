//
//  NFXNetfoxPanelUITests.swift
//  netfoxUITests
//
//  Walks the panel: list, search, details, settings and dismissal. The data
//  comes from the seeded batch the demo fires at launch, so the tests never
//  depend on a live API.
//

import XCTest
import Foundation

final class NFXNetfoxPanelUITests: NFXUITestBase {

    private var demo: NFXDemoPage { NFXDemoPage(app: app) }

    func testPanelListsTheSeededRequests() {
        let panel = demo.openNetfoxPanel()
        XCTAssertTrue(panel.requestsBar.waitForExistence(timeout: 10), "The request list did not open")

        // "/seed/boom" is the last seeded request - once it is there, the
        // whole batch has been logged.
        panel.waitForRow(containing: seedPath("/seed/boom"))

        XCTAssertTrue(panel.row(containing: seedPath("/seed/users")).exists)
        XCTAssertTrue(panel.row(containing: seedPath("/seed/products/9999")).exists)
        XCTAssertTrue(panel.row(containing: seedPath("/seed/page")).exists)
    }

    func testSearchFiltersTheList() {
        let panel = demo.openNetfoxPanel()
        XCTAssertTrue(panel.requestsBar.waitForExistence(timeout: 10))

        panel.waitForRow(containing: seedPath("/seed/boom"))
        panel.search("products")

        XCTAssertTrue(panel.row(containing: seedPath("/seed/products/9999")).waitForExistence(timeout: 5))
        XCTAssertFalse(panel.row(containing: seedPath("/seed/page")).exists)
    }

    func testDetailsShowRequestAndResponse() {
        let panel = demo.openNetfoxPanel()
        XCTAssertTrue(panel.requestsBar.waitForExistence(timeout: 10))

        panel.openDetails(of: seedPath("/seed/products/9999"))
        panel.selectTab("Response")

        XCTAssertTrue(panel.text("application/json").firstMatch.waitForExistence(timeout: 5))
    }

    func testResponseBodyViewFindsAndNavigatesMatches() {
        let panel = demo.openNetfoxPanel()
        XCTAssertTrue(panel.requestsBar.waitForExistence(timeout: 10))

        panel.openDetails(of: seedPath("/seed/products/9999"))
        panel.selectTab("Response")
        panel.openResponseBody()
        panel.searchResponseBody("found")

        XCTAssertTrue(panel.responseSearchStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.responseSearchStatus.label.contains("of"),
                      "Expected at least one hit, got \"\(panel.responseSearchStatus.label)\"")
        XCTAssertTrue(panel.nextMatchButton.isEnabled)
        panel.nextMatchButton.tap()
        XCTAssertTrue(panel.previousMatchButton.isEnabled)

        panel.closeResponseSearch()
        XCTAssertFalse(panel.responseSearchField.exists)

        let responseText = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS %@", "not found")).firstMatch
        XCTAssertTrue(responseText.waitForExistence(timeout: 5),
                      "The response text disappeared after closing search")
        XCTAssertLessThan(responseText.frame.minY, 560)
    }

    func testResponseBodyViewShowsTheMatchingLine() {
        let panel = demo.openNetfoxPanel()
        XCTAssertTrue(panel.requestsBar.waitForExistence(timeout: 10))

        panel.openDetails(of: seedPath("/seed/products/9999"))
        panel.selectTab("Response")
        panel.openResponseBody()
        panel.searchResponseBody("found")

        XCTAssertTrue(panel.responseSearchStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(panel.responseSearchStatus.label, "1 of 1")

        // The hit is rendered as its own text line, above the keyboard. A short
        // body is already fully visible, so there is nothing to scroll here;
        // long bodies are covered by the line-anchor unit tests.
        let matchingLine = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS %@", "not found")).firstMatch
        XCTAssertTrue(matchingLine.waitForExistence(timeout: 5))
        XCTAssertLessThan(matchingLine.frame.minY, 560)
    }

    func testSettingsExposeTheLoggingAndMockToggles() {
        let panel = demo.openNetfoxPanel()
        XCTAssertTrue(panel.requestsBar.waitForExistence(timeout: 10))

        panel.openSettings()

        XCTAssertTrue(app.switches[NFXUITestID.Settings.logging].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches[NFXUITestID.Settings.mockServer].exists)
        XCTAssertTrue(app.textFields[NFXUITestID.Settings.mockServerURL].exists)
    }

    func testCloseDismissesThePanel() {
        let panel = demo.openNetfoxPanel()
        XCTAssertTrue(panel.requestsBar.waitForExistence(timeout: 10))

        panel.close()

        XCTAssertTrue(panel.requestsBar.waitForNonExistence(timeout: 5))
        XCTAssertTrue(demo.netfoxButton.waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {

    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
