//
//  NFXAccessibility.swift
//  netfox
//
//  Accessibility identifiers used by the automated tests. They carry no
//  visual weight and are safe to ship.
//

import Foundation

public enum NFXAccessibility {

    public static let requestList = "nfx.requestList"
    public static let emptyState = "nfx.emptyState"
    public static let rowPrefix = "nfx.row."

    public static func row(_ hash: String) -> String {
        return rowPrefix + hash
    }

    public enum Toolbar {
        public static let settings = "nfx.toolbar.settings"
        public static let statistics = "nfx.toolbar.statistics"
        public static let info = "nfx.toolbar.info"
        public static let clear = "nfx.toolbar.clear"
        public static let close = "nfx.toolbar.close"
    }

    public enum Details {
        public static let picker = "nfx.details.picker"
        public static let info = "nfx.details.info"
        public static let request = "nfx.details.request"
        public static let response = "nfx.details.response"
    }

    public enum Settings {
        public static let logging = "nfx.settings.logging"
        public static let mockServer = "nfx.settings.mockServer"
        public static let mockServerURL = "nfx.settings.mockServerURL"
        public static let clearData = "nfx.settings.clearData"
    }

    public enum Demo {
        public static let netfoxButton = "demo.netfoxButton"
    }
}
