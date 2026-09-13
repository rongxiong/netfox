//
//  NFXHelperTests.swift
//  netfoxTests
//
//  The small helpers everything else builds on: content type detection,
//  the URLRequest / URLResponse extensions, curl generation, safe file names
//  and the tiny Publisher.
//

import Foundation
import Testing
@testable import netfox_ios

extension NFXTests {

    @MainActor
    @Suite
    struct NFXHelperTests {

        private let environment = NFXTestEnvironment()

        // MARK: - Content types

        @Test
        func shortTypeIsDerivedFromTheContentType() {
            #expect(HTTPModelShortType(contentType: "application/json") == .JSON)
            #expect(HTTPModelShortType(contentType: "application/vnd.api+json") == .JSON)
            #expect(HTTPModelShortType(contentType: "application/xml") == .XML)
            #expect(HTTPModelShortType(contentType: "text/xml") == .XML)
            #expect(HTTPModelShortType(contentType: "text/html") == .HTML)
            #expect(HTTPModelShortType(contentType: "image/png") == .IMAGE)
            #expect(HTTPModelShortType(contentType: "image/jpeg") == .IMAGE)
            #expect(HTTPModelShortType(contentType: "application/octet-stream") == .OTHER)
            #expect(HTTPModelShortType(contentType: "text/plain; charset=utf-8") == .OTHER)
        }

        // MARK: - URLRequest

        @Test
        func requestAccessors() {
            var request = URLRequest(url: URL(string: "https://api.example.com/v1/users?page=2")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 12.5
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            #expect(request.getNFXURL() == "https://api.example.com/v1/users?page=2")
            #expect(request.getNFXMethod() == "POST")
            #expect(request.getNFXTimeout() == "12.5")
            #expect(request.getNFXCachePolicy() == "ReloadIgnoringLocalCacheData")
            #expect(request.getNFXURLComponents()?.queryItems?.count == 1)
            #expect(request.getNFXHeaders()["Content-Type"] as? String == "application/json")
        }

        @Test
        func requestAccessorsFallBackToPlaceholders() {
            var request = URLRequest(url: URL(string: "https://api.example.com")!)
            request.url = nil

            #expect(request.getNFXURL() == "-")
            #expect(request.getNFXURLComponents() == nil)
            #expect(request.getNFXHeaders().isEmpty)
        }

        @Test
        func everyCachePolicyHasAName() {
            let policies: [URLRequest.CachePolicy] = [.useProtocolCachePolicy,
                                                      .reloadIgnoringLocalCacheData,
                                                      .reloadIgnoringLocalAndRemoteCacheData,
                                                      .returnCacheDataElseLoad,
                                                      .returnCacheDataDontLoad,
                                                      .reloadRevalidatingCacheData]
            for policy in policies {
                var request = URLRequest(url: URL(string: "https://api.example.com")!)
                request.cachePolicy = policy
                #expect(!request.getNFXCachePolicy().isEmpty)
            }
        }

        @Test
        func requestBodyIsReadFromTheNFXBodyDataProperty() {
            #expect(requestCarryingBody(Data("{\"a\":1}".utf8)).getNFXBody() == Data("{\"a\":1}".utf8))
        }

        @Test
        func bodyIsEmptyWhenTheRequestCarriesNone() {
            #expect(NFXModelFactory.request().getNFXBody().isEmpty)
        }

        @Test
        func curlCarriesMethodHeadersAndBody() {
            let curl = requestCarryingBody(Data("{\"a\":1}".utf8)).getCurl()

            #expect(curl.hasPrefix("curl \"https://api.example.com/v1/users\""))
            #expect(curl.contains("-X POST"))
            #expect(curl.contains("-H \u{22}Content-Type: application/json\u{22}"))
            #expect(curl.contains("-d \u{22}{\u{22}a\u{22}:1}\u{22}"))
        }

        // MARK: - URLResponse

        @Test
        func responseAccessors() {
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com")!,
                                           statusCode: 204,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Server": "netfox"])!

            #expect(response.getNFXStatus() == 204)
            #expect(response.getNFXHeaders()["Server"] as? String == "netfox")
        }

        @Test
        func plainResponseHasNoStatus() {
            let response = URLResponse(url: URL(string: "https://api.example.com")!,
                                       mimeType: nil,
                                       expectedContentLength: 0,
                                       textEncodingName: nil)

            #expect(response.getNFXStatus() == 999)
            #expect(response.getNFXHeaders().isEmpty)
        }

        // MARK: - Misc helpers

        @Test
        func inputStreamIsReadFully() {
            let data = Data("hello netfox".utf8)
            #expect(InputStream(data: data).readfully() == data)
        }

        @Test
        func dateComparison() {
            let older = Date(timeIntervalSince1970: 1_000)
            let newer = Date(timeIntervalSince1970: 2_000)

            #expect(newer.isGreaterThanDate(older))
            #expect(!older.isGreaterThanDate(newer))
        }

        @Test
        func unsafeCharactersAreReplacedInFileNames() {
            #expect("a/b".nfxSafeFileName == "a-b")
            #expect("10:30 /users".nfxSafeFileName == "10-30 -users")
            #expect("C:\\tmp\\log".nfxSafeFileName == "C--tmp-log")
            #expect("".nfxSafeFileName == "nfx")
        }

        @Test
        func appendToFileURLCreatesTheFileThenAppendsToIt() throws {
            let fileURL = NFXPath.tmpDirURL.appendingPathComponent("nfx-append-\(UUID().uuidString).log")
            defer { try? FileManager.default.removeItem(at: fileURL) }

            "first\n".appendToFileURL(fileURL)
            "second\n".appendToFileURL(fileURL)

            #expect(try String(contentsOf: fileURL, encoding: .utf8) == "first\nsecond\n")
        }

        @Test
        func workingDirectoryIsCreatedAndRemoved() {
            NFXPath.deleteNFXDir()
            #expect(!FileManager.default.fileExists(atPath: NFXPath.nfxDirURL.path))

            NFXPath.createNFXDirIfNotExist()
            #expect(FileManager.default.fileExists(atPath: NFXPath.nfxDirURL.path))
            #expect(NFXPath.pathURLToFile("a.log").lastPathComponent == "a.log")
        }

        // MARK: - Publisher

        @Test
        func publisherNotifiesItsSubscribers() {
            let publisher = Publisher<Int>()
            var received: [Int] = []
            publisher.subscribe { received.append($0) }

            publisher(1)
            publisher(2)

            #expect(received == [1, 2])
        }

        @Test
        func unsubscribeStopsTheNotifications() {
            let publisher = Publisher<Int>()
            var count = 0
            let subscription = publisher.subscribe { _ in count += 1 }

            publisher.trigger(1)
            publisher.unsubscribe(subscription)
            publisher.trigger(2)

            #expect(count == 1)
            #expect(!publisher.hasSubscribers)
        }

        // MARK: - Private

        /// netfox hands the body over through a URLProtocol property, so the tests
        /// have to do the same.
        private func requestCarryingBody(_ body: Data) -> URLRequest {
            let request = NFXModelFactory.request(url: "https://api.example.com/v1/users",
                                                  method: "POST",
                                                  headers: ["Content-Type": "application/json"])
            let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.setProperty(body, forKey: "NFXBodyData", in: mutable)
            return mutable as URLRequest
        }
    }
}
