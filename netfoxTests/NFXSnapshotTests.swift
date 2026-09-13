//
//  NFXSnapshotTests.swift
//  netfoxTests
//
//  Image snapshots of the netfox surfaces that are easy to break by accident.
//  Run once to record the references, then every later run compares against
//  them - on the same simulator the references were taken on.
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import netfox_ios

extension NFXTests {

    @MainActor
    @Suite
    struct NFXSnapshotTests {

        nonisolated static let screenSize = CGSize(width: 390, height: 844)
        nonisolated static let rowSize = CGSize(width: 390, height: 84)

        private let environment = NFXTestEnvironment()

        // MARK: - Rows

        @Test
        func requestRow() {
            let success = NFXModelFactory.model(url: "https://api.example.com/v1/users?page=2",
                                                method: "GET",
                                                status: 200,
                                                contentType: "application/json",
                                                responseBodyLength: 2048,
                                                duration: 0.42)
            assertSnapshot(of: hosted(NFXRequestRowView(model: success, isUnread: false), size: Self.rowSize),
                           as: .image,
                           named: "success",
                           testName: "testRequestRow")

            let failure = NFXModelFactory.model(url: "https://api.example.com/v1/orders/7",
                                                method: "POST",
                                                status: 500,
                                                contentType: "application/json",
                                                responseBodyLength: 96,
                                                duration: 1.87)
            assertSnapshot(of: hosted(NFXRequestRowView(model: failure, isUnread: true), size: Self.rowSize),
                           as: .image,
                           named: "failure-unread",
                           testName: "testRequestRow")
        }

        @Test
        func mockedRequestRow() {
            let mocked = NFXModelFactory.model(url: "https://api.example.com/v1/users?page=2",
                                               method: "GET",
                                               status: 201,
                                               contentType: "image/png",
                                               responseBodyLength: 65_536,
                                               duration: 0.08,
                                               isMocked: true,
                                               mockTargetURL: "http://127.0.0.1:8080/v1/users?page=2")
            assertSnapshot(of: hosted(NFXRequestRowView(model: mocked, isUnread: true), size: Self.rowSize),
                           as: .image,
                           named: "mocked",
                           testName: "testMockedRequestRow")
        }

        // MARK: - Screens

        @Test
        func emptyState() {
            let empty = NFXEmptyStateView(systemImage: "tray",
                                          title: "No requests yet",
                                          message: "Every request your app performs shows up here as soon as it is intercepted.")
            assertSnapshot(of: hosted(empty, size: CGSize(width: 390, height: 320)),
                           as: .image,
                           named: "no-requests",
                           testName: "testEmptyState")
        }

        @Test
        func detailsScreen() {
            let model = NFXModelFactory.model(url: "https://api.example.com/v1/users?page=2",
                                              method: "GET",
                                              status: 200,
                                              contentType: "application/json",
                                              requestHeaders: ["Accept": "application/json",
                                                               "Authorization": "Bearer demo-token"],
                                              responseHeaders: ["Content-Type": "application/json",
                                                                "Server": "netfox"],
                                              responseBodyLength: 2048,
                                              duration: 0.42)
            let screen = NFXNavigationContainer {
                NFXDetailsView(model: model)
            }
            assertSnapshot(of: hostedController(screen),
                           as: .image(on: .iPhone13),
                           named: "info",
                           testName: "testDetailsScreen")
        }

        @Test
        func settingsScreen() {
            let screen = NFXNavigationContainer {
                NFXSettingsView()
            }
            assertSnapshot(of: hostedController(screen),
                           as: .image(on: .iPhone13),
                           named: "settings",
                           testName: "testSettingsScreen")
        }

        // MARK: - Rendering

        /// Wraps a full screen (navigation container) in a hosting controller.
        /// SnapshotTesting's view-controller strategy installs it in a real
        /// window, so navigation-bar layout margins and safe-area insets match
        /// what the app renders on device - snapshotting a detached `view`
        /// would pin the large title to x: 0.
        private func hostedController<Content: View>(_ view: Content) -> UIHostingController<AnyView> {
            UIHostingController(rootView: AnyView(view.environmentObject(NFXStore.shared)))
        }

        /// Renders a SwiftUI view into a plain UIView of a fixed size, so the
        /// snapshot never depends on the window the tests happen to run in.
        private func hosted<Content: View>(_ view: Content,
                                           size: CGSize = NFXSnapshotTests.screenSize) -> UIView {
            let hosting = UIHostingController(rootView: AnyView(view.environmentObject(NFXStore.shared)))
            let rendered = hosting.view ?? UIView()
            rendered.frame = CGRect(origin: .zero, size: size)
            rendered.backgroundColor = UIColor(Color.nfxBackground)
            rendered.setNeedsLayout()
            rendered.layoutIfNeeded()
            return rendered
        }
    }
}
