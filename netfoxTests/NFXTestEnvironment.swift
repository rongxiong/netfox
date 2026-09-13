//
//  NFXTestEnvironment.swift
//  netfoxTests
//
//  Swift Testing support shared by every netfox suite.
//
//  netfox keeps its state in singletons (`NFX`, `NFXHTTPModelManager`,
//  `NFXStore`), swizzles `URLSessionConfiguration` once per process and writes
//  to the temporary directory, so each test has to start from - and leave
//  behind - a clean slate.
//
//  All suites nest inside `NFXTests`, a serialized suite: Swift Testing runs
//  tests in parallel by default, but netfox's process-wide singletons make the
//  tests inherently serial.
//

import Foundation
import Testing
@testable import netfox_ios

/// Root suite for every netfox unit test. The `.serialized` trait is applied
/// recursively, so suites nested in it (in any file) never run concurrently.
@Suite(.serialized)
enum NFXTests {}

/// Restores netfox's global state before and after every test.
///
/// Declare `private let environment = NFXTestEnvironment()` as the first
/// stored property of a suite: Swift Testing creates a fresh suite instance
/// for each test, which runs this initializer (setUp), and destroys it as soon
/// as the test ends (tearDown).
final class NFXTestEnvironment {

    private static let mockEnabledKey = "com.netfox.mockServer.enabled"
    private static let mockURLKey = "com.netfox.mockServer.url"

    /// `NFX.start()` and `URLSessionConfiguration.implementNetfox()` are
    /// one-shot: run them once for the whole test process.
    private static let bootstrap: Void = {
        // Pin display formatting so date strings (and snapshots) are identical
        // regardless of the developer machine / CI runner region and time zone.
        NFXFormatConfig.locale = Locale(identifier: "en_US_POSIX")
        NFXFormatConfig.timeZone = TimeZone(identifier: "UTC")!

        if NFX.sharedInstance().isStarted() == false {
            NFX.sharedInstance().start()
        }
    }()

    private let storedMockEnabled: Any?
    private let storedMockURL: Any?

    init() {
        _ = Self.bootstrap
        storedMockEnabled = UserDefaults.standard.object(forKey: Self.mockEnabledKey)
        storedMockURL = UserDefaults.standard.object(forKey: Self.mockURLKey)
        Self.resetNetfox()
    }

    deinit {
        // XCTest used to run tearDown on the main thread; keep that guarantee
        // so the singletons are never reset off the main thread.
        if Thread.isMainThread {
            Self.resetNetfox()
        } else {
            DispatchQueue.main.sync(execute: Self.resetNetfox)
        }
        UserDefaults.standard.set(storedMockEnabled, forKey: Self.mockEnabledKey)
        UserDefaults.standard.set(storedMockURL, forKey: Self.mockURLKey)
    }

    /// A private suite, so the mock server tests cannot see - or leak into -
    /// `UserDefaults.standard`.
    func isolatedDefaults() -> UserDefaults {
        return UserDefaults(suiteName: "com.netfox.tests.\(UUID().uuidString)")!
    }

    /// Drops every logged request, restores the filters and empties the
    /// working directory.
    static func resetNetfox() {
        NFX.sharedInstance().setMockServerMappings([:])
        NFX.sharedInstance().setMockServerURL(nil)
        NFX.sharedInstance().setMockServerEnabled(false)

        NFXHTTPModelManager.shared.filters = [Bool](repeating: true, count: HTTPModelShortType.allCases.count)
        NFXHTTPModelManager.shared.clear()

        NFXStore.shared.searchText = ""

        NFXPath.deleteNFXDir()
        NFXPath.createNFXDirIfNotExist()
    }
}

// MARK: - Waiting

/// `NFXHTTPModelManager.add` hops to the main queue, so anything it inserts
/// is only visible after that block has run.
@MainActor
func drainMainQueue() async {
    await MainActor.run { }
}

/// Polls `condition` until it becomes true or `timeout` elapses, recording an
/// issue on timeout.
@MainActor
func waitUntil(_ message: String = "condition",
               timeout: TimeInterval = 3.0,
               sourceLocation: SourceLocation = #_sourceLocation,
               condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    Issue.record("Timed out waiting for \(message)", sourceLocation: sourceLocation)
}
