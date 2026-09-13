//
//  NFXHTTPModelManagerTests.swift
//  netfoxTests
//
//  Insertion order, filtering and the publisher that drives the UI.
//

import Foundation
import Testing
@testable import netfox_ios

extension NFXTests {

    @MainActor
    @Suite
    struct NFXHTTPModelManagerTests {

        private let environment = NFXTestEnvironment()

        @Test
        func addInsertsTheNewestRequestFirst() async {
            NFXHTTPModelManager.shared.add(NFXModelFactory.model(url: "https://api.example.com/1"))
            await drainMainQueue()
            NFXHTTPModelManager.shared.add(NFXModelFactory.model(url: "https://api.example.com/2"))
            await drainMainQueue()

            #expect(NFXHTTPModelManager.shared.models.count == 2)
            #expect(NFXHTTPModelManager.shared.models.first?.requestURL == "https://api.example.com/2")
        }

        @Test
        func clearRemovesEveryModel() async {
            NFXHTTPModelManager.shared.add(NFXModelFactory.model())
            await drainMainQueue()
            #expect(NFXHTTPModelManager.shared.models.count == 1)

            NFXHTTPModelManager.shared.clear()

            #expect(NFXHTTPModelManager.shared.models.isEmpty)
            #expect(NFXHTTPModelManager.shared.filteredModels.isEmpty)
        }

        @Test
        func filteredModelsFollowTheFilters() async throws {
            NFXHTTPModelManager.shared.add(NFXModelFactory.model(url: "https://api.example.com/json",
                                                                 contentType: "application/json"))
            NFXHTTPModelManager.shared.add(NFXModelFactory.model(url: "https://api.example.com/html",
                                                                 contentType: "text/html"))
            await drainMainQueue()
            #expect(NFXHTTPModelManager.shared.filteredModels.count == 2)

            let jsonIndex = try #require(HTTPModelShortType.allCases.firstIndex(of: .JSON))
            var filters = NFXHTTPModelManager.shared.filters
            filters[jsonIndex] = false
            NFXHTTPModelManager.shared.filters = filters

            let remaining = NFXHTTPModelManager.shared.filteredModels
            #expect(remaining.count == 1)
            #expect(remaining.first?.requestURL == "https://api.example.com/html")
        }

        @Test
        func filtersStartFullyEnabled() {
            #expect(NFXHTTPModelManager.shared.filters.count == HTTPModelShortType.allCases.count)
            #expect(NFXHTTPModelManager.shared.filters.allSatisfy { $0 })
        }

        @Test
        func publisherIsTriggeredWhenAModelIsAdded() async {
            var received: [[NFXHTTPModel]] = []
            let subscription = NFXHTTPModelManager.shared.publisher.subscribe { received.append($0) }
            defer { NFXHTTPModelManager.shared.publisher.unsubscribe(subscription) }

            let model = NFXModelFactory.model(url: "https://api.example.com/published")
            NFXHTTPModelManager.shared.add(model)

            await waitUntil("publisher notification") { received.last?.count == 1 }
            #expect(received.last?.first?.requestURL == model.requestURL)
        }
    }
}
