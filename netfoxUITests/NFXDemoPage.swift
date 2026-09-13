//
//  NFXDemoPage.swift
//  netfoxUITests
//
//  The demo screen the tests start from.
//

import XCTest

struct NFXDemoPage {

    let app: XCUIApplication

    var netfoxButton: XCUIElement {
        return app.buttons[NFXUITestID.netfoxButton]
    }

    @discardableResult
    func openNetfoxPanel() -> NFXNetfoxPanelPage {
        XCTAssertTrue(netfoxButton.waitForExistence(timeout: 10), "The netfox launcher is missing")
        netfoxButton.tap()
        return NFXNetfoxPanelPage(app: app)
    }
}
