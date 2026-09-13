//
//  NFXMockServerTests.swift
//  netfoxTests
//
//  Covers URL normalization, mapping resolution and request rewriting.
//  Every test gets its own `UserDefaults` suite, so nothing leaks.
//

import Foundation
import Testing
@testable import netfox_ios

extension NFXTests {

    @MainActor
    @Suite
    struct NFXMockServerTests {

        private let environment = NFXTestEnvironment()

        private func makeServer(defaults: UserDefaults? = nil) -> NFXMockServer {
            return NFXMockServer(defaults: defaults ?? environment.isolatedDefaults())
        }

        private func request(_ url: String, method: String = "GET", body: Data? = nil) -> URLRequest {
            return NFXModelFactory.request(url: url, method: method, headers: [:], body: body)
        }

        // MARK: - Configuration

        @Test
        func invalidURLIsIgnored() {
            let server = makeServer()
            server.setURLString("not a url")

            #expect(server.configuration.baseURL == nil)
        }

        @Test
        func nonHTTPSchemeIsIgnored() {
            let server = makeServer()
            server.setURLString("ftp://localhost:21")

            #expect(server.configuration.baseURL == nil)
        }

        @Test
        func urlIsNormalizedToSchemeHostPortAndPath() {
            let server = makeServer()
            server.setURLString("http://localhost:3000/api/")

            #expect(server.configuration.baseURL?.absoluteString == "http://localhost:3000/api")
        }

        @Test
        func hostOnlyURLKeepsNoTrailingSlash() {
            let server = makeServer()
            server.setURLString("https://mock.example.com")

            #expect(server.configuration.baseURL?.absoluteString == "https://mock.example.com")
        }

        @Test
        func emptyURLClearsTheConfiguration() {
            let server = makeServer()
            server.setURLString("http://localhost:3000")
            server.setURLString("   ")

            #expect(server.configuration.baseURL == nil)
            #expect(server.configuration.urlString == nil)
        }

        @Test
        func enabledFlagIsPersisted() {
            let defaults = environment.isolatedDefaults()
            let server = makeServer(defaults: defaults)
            server.setEnabled(true)

            #expect(makeServer(defaults: defaults).configuration.isEnabled)
        }

        // MARK: - Redirect

        @Test
        func redirectReplacesSchemeHostAndPortButKeepsPathAndQuery() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(true)

            let redirected = server.redirectedRequest(for: request("https://api.example.com/v1/users?page=2"))

            #expect(redirected?.url?.absoluteString == "http://127.0.0.1:8080/v1/users?page=2")
        }

        @Test
        func redirectMergesTheBasePath() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080/mock")
            server.setEnabled(true)

            let redirected = server.redirectedRequest(for: request("https://api.example.com/v1/users"))

            #expect(redirected?.url?.absoluteString == "http://127.0.0.1:8080/mock/v1/users")
        }

        @Test
        func redirectKeepsMethodHeadersAndBody() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(true)

            let original = request("https://api.example.com/v1/users",
                                   method: "POST",
                                   body: Data("{\"a\":1}".utf8))
            var originalWithHeaders = original
            originalWithHeaders.setValue("bearer 123", forHTTPHeaderField: "Authorization")

            let redirected = server.redirectedRequest(for: originalWithHeaders)

            #expect(redirected?.httpMethod == "POST")
            #expect(redirected?.httpBody == Data("{\"a\":1}".utf8))
            #expect(redirected?.value(forHTTPHeaderField: "Authorization") == "bearer 123")
        }

        @Test
        func redirectCarriesTheOriginalAddressInHeaders() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(true)

            let redirected = server.redirectedRequest(for: request("https://api.example.com/v1/users"))

            #expect(redirected?.value(forHTTPHeaderField: NFXMockServer.originalURLHeader)
                    == "https://api.example.com/v1/users")
            #expect(redirected?.value(forHTTPHeaderField: NFXMockServer.originalHostHeader)
                    == "api.example.com")
        }

        @Test
        func nothingIsRedirectedWhenDisabled() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(false)

            #expect(server.redirectedRequest(for: request("https://api.example.com/v1/users")) == nil)
            #expect(!server.shouldRedirect(request("https://api.example.com/v1/users")))
        }

        @Test
        func nothingIsRedirectedWithoutABaseURL() {
            let server = makeServer()
            server.setEnabled(true)

            #expect(server.redirectedRequest(for: request("https://api.example.com/v1/users")) == nil)
            #expect(!server.shouldRedirect(request("https://api.example.com/v1/users")))
        }

        @Test
        func requestAlreadyOnTheMockHostIsNotRewritten() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(true)

            #expect(server.redirectedRequest(for: request("http://127.0.0.1:8080/v1/users")) == nil)
        }

        // MARK: - Mappings

        @Test
        func longestMatchingKeyWins() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(true)
            server.setMappings(["api.example.com": "/default.json",
                                "api.example.com/v1/users": "/users.json"])

            let redirected = server.redirectedRequest(for: request("https://api.example.com/v1/users?page=2"))

            #expect(redirected?.url?.absoluteString == "http://127.0.0.1:8080/users.json")
        }

        @Test
        func mappingValueIsResolvedAgainstTheBasePath() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080/mock")
            server.setEnabled(true)
            server.setMappings(["api.example.com": "/users.json?state=mock"])

            let redirected = server.redirectedRequest(for: request("https://api.example.com/v1/users"))

            #expect(redirected?.url?.absoluteString == "http://127.0.0.1:8080/mock/users.json?state=mock")
        }

        @Test
        func mappingValueMayBeAnAbsoluteURL() {
            let server = makeServer()
            server.setEnabled(true)
            server.setMappings(["api.example.com": "https://other.example.com/fixtures/users.json"])

            let redirected = server.redirectedRequest(for: request("https://api.example.com/v1/users"))

            #expect(redirected?.url?.absoluteString == "https://other.example.com/fixtures/users.json")
        }

        @Test
        func unmatchedRequestIsNotMockedWhenMappingsExist() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(true)
            server.setMappings(["api.example.com": "/users.json"])

            #expect(server.redirectedRequest(for: request("https://other.example.com/v1/orders")) == nil)
            #expect(!server.shouldRedirect(request("https://other.example.com/v1/orders")))
        }

        @Test
        func matchedRequestIsMocked() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(true)
            server.setMappings(["api.example.com": "/users.json"])

            #expect(server.shouldRedirect(request("https://api.example.com/v1/users")))
        }

        @Test
        func invalidMappingsAreIgnored() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(true)
            server.setMappings(["": "/users.json", "api.example.com": ""])

            // Nothing survived the validation, so the server falls back to
            // redirecting every request instead of only the mapped ones.
            #expect(server.configuration.mappings.isEmpty)
            #expect(server.shouldRedirect(request("https://api.example.com/v1/users")))
        }

        @Test
        func relativeMappingWithoutABaseURLIsIgnored() {
            let server = makeServer()
            server.setEnabled(true)
            server.setMappings(["api.example.com": "/users.json"])

            #expect(server.configuration.mappings.isEmpty)
        }

        @Test
        func emptyMappingsFallBackToMockingEveryRequest() {
            let server = makeServer()
            server.setURLString("http://127.0.0.1:8080")
            server.setEnabled(true)
            server.setMappings(["api.example.com": "/users.json"])
            server.setMappings([:])

            #expect(server.shouldRedirect(request("https://any.example.com/v1/anything")))
        }
    }
}
