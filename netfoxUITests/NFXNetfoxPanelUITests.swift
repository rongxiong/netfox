//
//  NFXNetfoxPanelUITests.swift
//  netfoxUITests
//
//  Walks the panel: list, search, details, settings and dismissal. The data
//  comes from the seeded batch the demo fires at launch, so the tests never
//  depend on a live API.
//

import XCTest

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
