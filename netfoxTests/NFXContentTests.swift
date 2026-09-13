//
//  NFXContentTests.swift
//  netfoxTests
//
//  Everything the details and statistics screens render: sections, bodies,
//  aggregates and the small formatters.
//

import Foundation
import Testing
@testable import netfox_ios

extension NFXTests {

    @MainActor
    @Suite
    struct NFXContentTests {

        private let environment = NFXTestEnvironment()

        // MARK: - Details

        @Test
        func detailsOfAnAnsweredRequest() {
            let details = NFXContentBuilder.details(for: NFXModelFactory.model(method: "POST", status: 201))

            #expect(details.statusCode == 201)
            #expect(details.response != nil)
            #expect(details.hasQueryItems)
            #expect(details.info.fields.contains { $0.key == "URL" && $0.value == NFXModelFactory.defaultURL })
            #expect(details.info.fields.contains { $0.key == "Method" && $0.value == "POST" })
            #expect(details.info.fields.contains { $0.key == "Status" && $0.value == "201" })
            #expect(details.info.fields.contains { $0.key == "Duration" })
        }

        @Test
        func detailsOfARequestWithoutAResponse() {
            let details = NFXContentBuilder.details(for: NFXModelFactory.model(status: nil))

            #expect(details.statusCode == nil)
            #expect(details.response == nil)
            #expect(details.info.fields.contains { $0.key == "Status" && $0.value == "No response" })
        }

        @Test
        func mockTargetShowsUpInTheInfoSection() {
            let model = NFXModelFactory.model(isMocked: true, mockTargetURL: "http://127.0.0.1:8080/v1/users")

            #expect(NFXContentBuilder.details(for: model).info.fields.contains { $0.key == "Mock target" })
        }

        @Test
        func headersAreSortedAlphabetically() {
            let model = NFXModelFactory.model(responseHeaders: ["Zebra": "1", "Alpha": "2", "Middle": "3"])
            let fields = NFXContentBuilder.details(for: model).response?.fields ?? []

            #expect(fields.map { $0.key } == ["Alpha", "Middle", "Zebra"])
        }

        @Test
        func emptyHeaderSectionHasNoFields() {
            let model = NFXModelFactory.model(responseHeaders: [:])
            #expect(NFXContentBuilder.details(for: model).response?.fields.isEmpty == true)
        }

        @Test
        func bodiesLongerThanTheInlineLimitAreNotInlined() {
            let model = NFXModelFactory.model(responseBodyLength: NFXContentBuilder.inlineBodyLimit + 1)
            let body = NFXContentBuilder.details(for: model).response?.body

            #expect(body?.isTruncated == true)
            #expect(body?.text == nil)
        }

        @Test
        func emptyBodiesAreFlagged() {
            let body = NFXContentBuilder.details(for: NFXModelFactory.model(responseBodyLength: 0)).response?.body

            #expect(body?.isEmpty == true)
        }

        // MARK: - Statistics

        @Test
        func statisticsAggregateTheWholeSet() {
            let models = [
                NFXModelFactory.model(status: 200, requestBodyLength: 10, responseBodyLength: 100, duration: 0.5),
                NFXModelFactory.model(status: 500, requestBodyLength: 30, responseBodyLength: 300, duration: 1.5),
                NFXModelFactory.model(status: nil, requestBodyLength: 0, responseBodyLength: 0)
            ]

            let stats = NFXContentBuilder.statistics(for: models)

            #expect(stats.totalRequests == 3)
            #expect(stats.successfulRequests == 1)
            #expect(stats.failedRequests == 2)
            #expect(stats.totalRequestSize == 40)
            #expect(stats.totalResponseSize == 400)
            #expect(stats.fastestResponseTime == 0.5)
            #expect(stats.slowestResponseTime == 1.5)
            #expect(stats.averageResponseSize == 133)
            #expect(stats.averageRequestSize == 13)
            #expect(abs(stats.successRatio - 1.0 / 3.0) <= 0.0001)
            #expect(abs(stats.failureRatio - 2.0 / 3.0) <= 0.0001)
        }

        @Test
        func statisticsOfAnEmptySet() {
            let stats = NFXContentBuilder.statistics(for: [])

            #expect(stats.totalRequests == 0)
            #expect(stats.successRatio == 0)
            #expect(stats.failureRatio == 0)
            #expect(stats.averageRequestSize == 0)
            #expect(stats.averageResponseSize == 0)
            #expect(stats.averageResponseTime == nil)
            #expect(stats.fastestResponseTime == nil)
            #expect(stats.slowestResponseTime == nil)
        }

        // MARK: - Formatting

        @Test
        func durations() {
            #expect(NFXFormat.duration(nil) == "-")
            #expect(NFXFormat.duration(0.25) == "250 ms")
            #expect(NFXFormat.duration(2.5) == "2.50 s")
        }

        @Test
        func integersAndDatesFallBackToADash() {
            #expect(NFXFormat.integer(nil) == "-")
            #expect(NFXFormat.date(nil) == "-")
            #expect(NFXFormat.date(Date()) != "-")
        }

        @Test
        func byteCountsAreHumanReadable() {
            #expect(!NFXFormat.bytes(0).isEmpty)
            #expect(NFXFormat.bytes(1024) != NFXFormat.bytes(5 * 1024 * 1024))
        }

        // MARK: - Export

        @Test
        func plainTextLog() {
            let log = NFXContentBuilder.plainTextLog(for: NFXModelFactory.model(status: 200), full: false)

            #expect(log.contains("** INFO **"))
            #expect(log.contains("** REQUEST **"))
            #expect(log.contains("** RESPONSE **"))
            #expect(log.contains("logged via netfox"))
        }

        @Test
        func plainTextLogOfARequestWithoutAResponse() {
            let log = NFXContentBuilder.plainTextLog(for: NFXModelFactory.model(status: nil), full: false)

            #expect(log.contains("** RESPONSE **\nNo response"))
        }
    }
}
