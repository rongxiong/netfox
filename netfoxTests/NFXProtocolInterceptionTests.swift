//
//  NFXProtocolInterceptionTests.swift
//  netfoxTests
//
//  Drives `NFXProtocol` end to end against a local HTTP server: a real
//  request goes out through a real socket and comes back as a logged model.
//  Nothing here touches the internet.
//

import Foundation
import Testing
@testable import netfox_ios

extension NFXTests {

    @MainActor
    @Suite
    struct NFXProtocolInterceptionTests {

        private let environment = NFXTestEnvironment()
        // The server closes its socket in `deinit`, i.e. after each test.
        private let server = NFXLocalHTTPServer()

        // MARK: - Interception

        @Test
        func getIsInterceptedAndLogged() async throws {
            try server.start()
            server.register(path: "/users", response: .json(["users": ["ada", "grace"]]))

            await perform(URLRequest(url: server.url(for: "/users")))
            let model = try #require(await loggedModel())

            #expect(model.requestURL == server.url(for: "/users").absoluteString)
            #expect(model.requestMethod == "GET")
            #expect(model.responseStatus == 200)
            #expect(model.shortType == .JSON)
            #expect(!model.noResponse)
            #expect(model.responseBodyLength == 25)
            #expect(model.getResponseBody().contains("ada"))
        }

        @Test
        func postKeepsMethodAndBody() async throws {
            try server.start()
            server.register(path: "/orders", response: .json(["id": 7], status: 201))

            var request = URLRequest(url: server.url(for: "/orders"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{\"sku\":\"nfx\"}".utf8)

            await perform(request)
            let model = try #require(await loggedModel())

            #expect(model.requestMethod == "POST")
            #expect(model.requestType == "application/json")
            #expect(model.requestBodyLength == 13)
            #expect(model.getRequestBody().contains("sku"))
            #expect(model.responseStatus == 201)
        }

        @Test
        func serverErrorIsRecorded() async throws {
            try server.start()
            server.register(path: "/boom", response: .json(["error": "boom"], status: 500))

            await perform(URLRequest(url: server.url(for: "/boom")))
            let model = try #require(await loggedModel())

            #expect(model.responseStatus == 500)
            #expect(!model.isSuccessful())
        }

        @Test
        func sessionLogIsWritten() async throws {
            try server.start()
            server.register(path: "/logged", response: .text("hello netfox"))

            await perform(URLRequest(url: server.url(for: "/logged")))
            await waitUntil("session log is written") {
                (NFX.sharedInstance().getSessionLog()?.isEmpty ?? true) == false
            }

            let sessionLog = try #require(NFX.sharedInstance().getSessionLog())
            let log = String(data: sessionLog, encoding: .utf8) ?? ""
            #expect(log.contains("-------START REQUEST"))
            #expect(log.contains(server.url(for: "/logged").absoluteString))
        }

        @Test
        func ignoredURLIsNotLogged() async throws {
            try server.start()
            server.register(path: "/ignored", response: .text("nope"))

            let url = server.url(for: "/ignored").absoluteString
            NFX.sharedInstance().ignoreURL(url)

            await perform(URLRequest(url: URL(string: url)!))
            await drainMainQueue()

            #expect(NFXHTTPModelManager.shared.models.isEmpty)
        }

        // MARK: - Mock server

        @Test
        func mockServerRedirectIsRecordedAndKeepsTheOriginalURL() async throws {
            try server.start()
            server.register(path: "/mock/users", response: .json(["mocked": true]))

            NFX.sharedInstance().setMockServerURL(server.baseURL!.absoluteString + "/mock")
            NFX.sharedInstance().setMockServerEnabled(true)

            await perform(URLRequest(url: URL(string: "https://api.example.com/users")!))
            let model = try #require(await loggedModel())

            #expect(model.isMocked)
            #expect(model.mockTargetURL == server.url(for: "/mock/users").absoluteString)
            // The log always keeps the address the app asked for.
            #expect(model.requestURL == "https://api.example.com/users")
            #expect(model.responseStatus == 200)
            #expect(model.getResponseBody().contains("mocked"))
        }

        @Test
        func redirectedRequestCarriesTheOriginalAddress() async throws {
            try server.start()
            server.register(path: "/mock/users", response: .json(["mocked": true]))

            NFX.sharedInstance().setMockServerURL(server.baseURL!.absoluteString + "/mock")
            NFX.sharedInstance().setMockServerEnabled(true)

            await perform(URLRequest(url: URL(string: "https://api.example.com/users")!))
            await waitUntil("the mock server answered") { !server.recordedRequests().isEmpty }

            let recorded = server.recordedRequests()
            #expect(recorded.contains { $0.target == "/mock/users" })
            #expect(recorded.first?.headers["x-netfox-original-url"] == "https://api.example.com/users")
            #expect(recorded.first?.headers["x-netfox-original-host"] == "api.example.com")
        }

        // MARK: - Helpers

        /// Fires the request through a session netfox has hooked into. The
        /// local server answers immediately, so transport failures are
        /// irrelevant - the assertions only inspect what netfox logged.
        private func perform(_ request: URLRequest) async {
            let session = URLSession(configuration: .default)
            _ = try? await session.data(for: request)
        }

        /// Waits for netfox to publish the model it just recorded.
        private func loggedModel(timeout: TimeInterval = 5.0) async -> NFXHTTPModel? {
            await waitUntil("the model to be logged", timeout: timeout) {
                !NFXHTTPModelManager.shared.models.isEmpty
            }
            await drainMainQueue()
            return NFXHTTPModelManager.shared.models.first
        }
    }
}
