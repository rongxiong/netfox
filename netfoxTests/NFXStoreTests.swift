//
//  NFXStoreTests.swift
//  netfoxTests
//
//  The store is the bridge between the manager and the SwiftUI views: it
//  mirrors the logged models and owns the debounced search.
//

import Foundation
import Testing
@testable import netfox_ios

extension NFXTests {

    @MainActor
    @Suite
    struct NFXStoreTests {

        private let environment = NFXTestEnvironment()

        private func log(url: String, contentType: String = "application/json") {
            NFXHTTPModelManager.shared.add(NFXModelFactory.model(url: url, contentType: contentType))
        }

        @Test
        func storeMirrorsTheLoggedModels() async {
            log(url: "https://api.example.com/v1/users")

            await waitUntil("store received the model") { NFXStore.shared.models.count == 1 }
            #expect(NFXStore.shared.displayedModels.count == 1)
            #expect(NFXStore.shared.models.first?.requestURL == "https://api.example.com/v1/users")
        }

        @Test
        func searchIsDebouncedAndMatchesURLMethodAndType() async {
            log(url: "https://api.example.com/v1/users")
            log(url: "https://api.example.com/v1/orders", contentType: "text/html")
            await waitUntil("both models are mirrored") { NFXStore.shared.models.count == 2 }

            NFXStore.shared.searchText = "orders"
            // The filter only runs after the debounce interval.
            #expect(NFXStore.shared.displayedModels.count == 2)

            await waitUntil("debounced search") { NFXStore.shared.displayedModels.count == 1 }
            #expect(NFXStore.shared.displayedModels.first?.requestURL == "https://api.example.com/v1/orders")

            NFXStore.shared.searchText = "HTML"
            await waitUntil("case insensitive search") { NFXStore.shared.displayedModels.count == 1 }

            NFXStore.shared.searchText = "nothing-matches-this"
            await waitUntil("no results") { NFXStore.shared.displayedModels.isEmpty }

            NFXStore.shared.searchText = ""
            await waitUntil("search cleared") { NFXStore.shared.displayedModels.count == 2 }
        }

        @Test
        func setFilterIsForwardedToTheManager() throws {
            let jsonIndex = try #require(HTTPModelShortType.allCases.firstIndex(of: .JSON))

            NFXStore.shared.setFilter(false, at: jsonIndex)

            #expect(!NFXStore.shared.filters[jsonIndex])
            #expect(!NFXHTTPModelManager.shared.filters[jsonIndex])
        }

        @Test
        func setFilterIgnoresAnOutOfRangeIndex() throws {
            let jsonIndex = try #require(HTTPModelShortType.allCases.firstIndex(of: .JSON))
            NFXStore.shared.setFilter(false, at: jsonIndex)

            NFXStore.shared.setFilter(true, at: NFXStore.shared.filters.count + 10)

            #expect(!NFXStore.shared.filters[jsonIndex])
        }

        @Test
        func unreadFollowsTheLastVisitDate() {
            NFX.sharedInstance().markVisited()

            let answeredBeforeTheVisit = NFXModelFactory.model(status: 200)
            #expect(!NFXStore.shared.isUnread(answeredBeforeTheVisit))

            let answeredAfterTheVisit = NFXModelFactory.model(status: 200,
                                                               requestDate: Date().addingTimeInterval(120))
            #expect(NFXStore.shared.isUnread(answeredAfterTheVisit))

            let stillPending = NFXModelFactory.model(status: nil)
            #expect(NFXStore.shared.isUnread(stillPending))
        }

        @Test
        func clearDropsEveryModel() async {
            log(url: "https://api.example.com/v1/users")
            await waitUntil("store received the model") { NFXStore.shared.models.count == 1 }

            NFXStore.shared.clear()

            #expect(NFXStore.shared.models.isEmpty)
            #expect(NFXStore.shared.displayedModels.isEmpty)
        }
    }
}
