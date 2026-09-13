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
            assertSnapshot(of: hostedController(NFXRequestRowView(model: success, isUnread: false)),
                           as: .image(on: Self.fixedSizeConfig(Self.rowSize), drawHierarchyInKeyWindow: true),
                           named: "success",
                           testName: "testRequestRow")

            let failure = NFXModelFactory.model(url: "https://api.example.com/v1/orders/7",
                                                method: "POST",
                                                status: 500,
                                                contentType: "application/json",
                                                responseBodyLength: 96,
                                                duration: 1.87)
            assertSnapshot(of: hostedController(NFXRequestRowView(model: failure, isUnread: true)),
                           as: .image(on: Self.fixedSizeConfig(Self.rowSize), drawHierarchyInKeyWindow: true),
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
            assertSnapshot(of: hostedController(NFXRequestRowView(model: mocked, isUnread: true)),
                           as: .image(on: Self.fixedSizeConfig(Self.rowSize), drawHierarchyInKeyWindow: true),
                           named: "mocked",
                           testName: "testMockedRequestRow")
        }

        // MARK: - Screens

        @Test
        func emptyState() {
            let empty = NFXEmptyStateView(systemImage: "tray",
                                          title: "No requests yet",
                                          message: "Every request your app performs shows up here as soon as it is intercepted.")
            assertSnapshot(of: hostedController(empty),
                           as: .image(on: Self.fixedSizeConfig(CGSize(width: 390, height: 320)),
                                      drawHierarchyInKeyWindow: true),
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
                           as: .image(on: .iPhone13, drawHierarchyInKeyWindow: true),
                           named: "info",
                           testName: "testDetailsScreen")
        }

        @Test
        func settingsScreen() {
            let screen = NFXNavigationContainer {
                NFXSettingsView()
            }
            assertSnapshot(of: hostedController(screen),
                           as: .image(on: .iPhone13, drawHierarchyInKeyWindow: true),
                           named: "settings",
                           testName: "testSettingsScreen")
        }

        // MARK: - Rendering

        private static func fixedSizeConfig(_ size: CGSize) -> ViewImageConfig {
            ViewImageConfig(safeArea: .zero, size: size, traits: .init())
        }

        /// Wraps a screen (or any SwiftUI view) in a hosting controller.
        ///
        /// Every snapshot goes through the `.image(on:drawHierarchyInKeyWindow:)`
        /// strategy: the default `CALayer.render(in:)` capture path skips the
        /// render-server-composited parts of iOS 16+ controls, which on iOS 26
        /// leaves `Toggle` switches without their white thumb. `drawHierarchy`
        /// in the host app's key window composites them exactly as on device.
        /// That strategy requires a hosted test bundle, so netfoxTests runs
        /// inside netfox_ios_demo.
        private func hostedController<Content: View>(_ view: Content) -> UIHostingController<AnyView> {
            let hosting = UIHostingController(rootView: AnyView(view.environmentObject(NFXStore.shared)))
            hosting.view.backgroundColor = UIColor(Color.nfxBackground)
            return hosting
        }
    }
}
