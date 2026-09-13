//
//  NFXUITestBase.swift
//  netfoxUITests
//
//  Launches the demo app with the seeded batch so every test starts from the
//  very same set of logged requests - no network involved.
//

import XCTest

/// Mirrors `NFXAccessibility`; UI tests run in their own process and only
/// need the raw strings.
enum NFXUITestID {

    static let netfoxButton = "demo.netfoxButton"

    enum Toolbar {
        static let settings = "nfx.toolbar.settings"
        static let statistics = "nfx.toolbar.statistics"
        static let info = "nfx.toolbar.info"
        static let clear = "nfx.toolbar.clear"
        static let close = "nfx.toolbar.close"
    }

    enum Settings {
        static let logging = "nfx.settings.logging"
        static let mockServer = "nfx.settings.mockServer"
        static let mockServerURL = "nfx.settings.mockServerURL"
    }
}

class NFXUITestBase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += ["-nfxUITestSeed"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
        try super.tearDownWithError()
    }

    /// The seeded requests are answered by a server on a random loopback
    /// port, so the tests match on the path instead of the whole URL.
    func seedPath(_ path: String) -> String {
        return path
    }
}
