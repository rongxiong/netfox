//
//  Scenario.swift
//  netfox_ios_demo
//
//  A catalogue of network scenarios. Each scenario describes how to build
//  one request (or a batch); the SwiftUI list observes its state through the
//  Observation framework.
//

import Foundation
import Observation

// MARK: - Scenario state

enum ScenarioState: Equatable {
    case idle
    case running
    /// Body bytes are arriving; the string is the percent done.
    case progress(String)
    /// 2xx / 3xx - the request succeeded.
    case success(String)
    /// 4xx / 5xx - the server responded with an error status.
    case httpError(String)
    /// Transport error (timeout, DNS, TLS ...).
    case transportError(String)
    /// Request was cancelled on purpose.
    case cancelled(String)
}

// MARK: - Scenario

@Observable
final class Scenario: Identifiable {

    enum Work {
        /// A single request. `cancelAfter` cancels the task to demo cancellation;
        /// `tracksProgress` reports body delivery progress.
        case single(build: () -> URLRequest, timeout: TimeInterval, cancelAfter: TimeInterval?, tracksProgress: Bool)
        /// Several requests fired together (or one after another). The row
        /// shows the aggregated result.
        case batch(build: () -> [URLRequest], sequential: Bool)
    }

    let id = UUID()
    let method: String
    let title: String
    let subtitle: String
    let work: Work

    var state: ScenarioState = .idle
    weak var task: URLSessionTask?

    init(method: String, title: String, subtitle: String, work: Work) {
        self.method = method
        self.title = title
        self.subtitle = subtitle
        self.work = work
    }
}

struct ScenarioSection: Identifiable {

    let id = UUID()
    let name: String
    let scenarios: [Scenario]
}

// MARK: - Request catalogue

enum ScenarioCatalog {

    private static let dummyjson = "https://dummyjson.com"
    private static let echo = "https://postman-echo.com"
    private static let httpbingo = "https://httpbingo.org"
    private static let cloudflareDown = "https://speed.cloudflare.com/__down"

    static func makeSections() -> [ScenarioSection] {
        return [
            ScenarioSection(name: "HTTP Methods", scenarios: methodScenarios()),
            ScenarioSection(name: "Status Codes & Responses", scenarios: statusScenarios()),
            ScenarioSection(name: "Request Body & Headers", scenarios: contentScenarios()),
            ScenarioSection(name: "Failures & Edge Cases", scenarios: failureScenarios()),
            ScenarioSection(name: "Concurrency & Caching", scenarios: concurrencyScenarios())
        ]
    }

    /// The "load a webpage" mix: JSON APIs, redirects, images and compressed
    /// responses, all fired at once.
    static func makeBurstRequests() -> [URLRequest] {
        let apiRequests = (1...4).map { URLRequest(url: URL(string: "\(dummyjson)/products/\($0)")!) }
        let images = [
            URLRequest(url: URL(string: "https://picsum.photos/seed/netfox-a/300/200")!),
            URLRequest(url: URL(string: "https://picsum.photos/seed/netfox-b/300/200")!)
        ]
        let misc = [
            URLRequest(url: URL(string: "\(echo)/gzip")!),
            URLRequest(url: URL(string: "\(echo)/get?source=burst")!),
            URLRequest(url: URL(string: "\(httpbingo)/redirect/2")!)
        ]
        return apiRequests + images + misc
    }

    // MARK: Sections

    private static func methodScenarios() -> [Scenario] {
        func jsonRequest(_ method: String, _ path: String, body: [String: Any]) -> URLRequest {
            var request = URLRequest(url: URL(string: dummyjson + path)!)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("netfox-demo", forHTTPHeaderField: "X-Demo-Client")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return request
        }

        return [
            Scenario(method: "GET", title: "Read a resource",
                     subtitle: "dummyjson.com/products/1",
                     work: .single(build: { URLRequest(url: URL(string: "\(dummyjson)/products/1")!) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "POST", title: "Create a resource",
                     subtitle: "dummyjson.com/products/add · JSON body",
                     work: .single(build: { jsonRequest("POST", "/products/add", body: ["title": "netfox mug", "price": 12.5]) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "PUT", title: "Replace a resource",
                     subtitle: "dummyjson.com/products/1 · JSON body",
                     work: .single(build: { jsonRequest("PUT", "/products/1", body: ["title": "netfox mug", "price": 12.5]) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "PATCH", title: "Update one field",
                     subtitle: "dummyjson.com/products/1 · JSON body",
                     work: .single(build: { jsonRequest("PATCH", "/products/1", body: ["price": 9.99]) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "DELETE", title: "Delete a resource",
                     subtitle: "dummyjson.com/products/1",
                     work: .single(build: {
                         var request = URLRequest(url: URL(string: "\(dummyjson)/products/1")!)
                         request.httpMethod = "DELETE"
                         return request
                     }, timeout: 30, cancelAfter: nil, tracksProgress: false))
        ]
    }

    private static func statusScenarios() -> [Scenario] {
        return [
            Scenario(method: "GET", title: "404 Not Found",
                     subtitle: "dummyjson.com/products/9999",
                     work: .single(build: { URLRequest(url: URL(string: "\(dummyjson)/products/9999")!) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "GET", title: "401 Unauthorized",
                     subtitle: "postman-echo.com/status/401",
                     work: .single(build: { URLRequest(url: URL(string: "\(echo)/status/401")!) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "GET", title: "500 Server Error",
                     subtitle: "postman-echo.com/status/500",
                     work: .single(build: { URLRequest(url: URL(string: "\(echo)/status/500")!) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "GET", title: "Redirect chain (3 hops)",
                     subtitle: "httpbingo.org/redirect/3",
                     work: .single(build: { URLRequest(url: URL(string: "\(httpbingo)/redirect/3")!) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "GET", title: "Image via 302 (binary)",
                     subtitle: "picsum.photos/seed/netfox/300/200",
                     work: .single(build: { URLRequest(url: URL(string: "https://picsum.photos/seed/netfox/300/200")!) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "GET", title: "Gzipped response",
                     subtitle: "postman-echo.com/gzip · Content-Encoding",
                     work: .single(build: { URLRequest(url: URL(string: "\(echo)/gzip")!) },
                                   timeout: 30, cancelAfter: nil, tracksProgress: false))
        ]
    }

    private static func contentScenarios() -> [Scenario] {
        return [
            Scenario(method: "POST", title: "Form URL-encoded",
                     subtitle: "postman-echo.com/post · application/x-www-form-urlencoded",
                     work: .single(build: {
                         var request = URLRequest(url: URL(string: "\(echo)/post")!)
                         request.httpMethod = "POST"
                         request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                         request.httpBody = "name=netfox&rating=5&review=great".data(using: .utf8)
                         return request
                     }, timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "POST", title: "Multipart file upload",
                     subtitle: "postman-echo.com/post · multipart/form-data",
                     work: .single(build: Self.makeMultipartRequest,
                                   timeout: 30, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "GET", title: "Custom headers & bearer token",
                     subtitle: "postman-echo.com/get",
                     work: .single(build: {
                         var request = URLRequest(url: URL(string: "\(echo)/get")!)
                         request.setValue("Bearer demo-token-12345", forHTTPHeaderField: "Authorization")
                         request.setValue("netfox-demo", forHTTPHeaderField: "X-Demo-Client")
                         request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
                         return request
                     }, timeout: 30, cancelAfter: nil, tracksProgress: false))
        ]
    }

    private static func failureScenarios() -> [Scenario] {
        return [
            Scenario(method: "GET", title: "Timeout (3 s limit)",
                     subtitle: "httpbingo.org/delay/10",
                     work: .single(build: { URLRequest(url: URL(string: "\(httpbingo)/delay/10")!) },
                                   timeout: 3, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "GET", title: "Cancelled after 0.5 s",
                     subtitle: "httpbingo.org/delay/3",
                     work: .single(build: { URLRequest(url: URL(string: "\(httpbingo)/delay/3")!) },
                                   timeout: 30, cancelAfter: 0.5, tracksProgress: false)),
            Scenario(method: "GET", title: "Unreachable host",
                     subtitle: "https://no-such-host-netfox.invalid",
                     work: .single(build: { URLRequest(url: URL(string: "https://no-such-host-netfox.invalid")!) },
                                   timeout: 15, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "GET", title: "Untrusted TLS certificate",
                     subtitle: "self-signed.badssl.com",
                     work: .single(build: { URLRequest(url: URL(string: "https://self-signed.badssl.com")!) },
                                   timeout: 15, cancelAfter: nil, tracksProgress: false)),
            Scenario(method: "GET", title: "5 MB download with progress",
                     subtitle: "speed.cloudflare.com · octet-stream",
                     work: .single(build: { URLRequest(url: URL(string: "\(cloudflareDown)?bytes=5242880")!) },
                                   timeout: 60, cancelAfter: nil, tracksProgress: true))
        ]
    }

    private static func concurrencyScenarios() -> [Scenario] {
        return [
            Scenario(method: "GET", title: "6 parallel requests",
                     subtitle: "dummyjson.com/products/1 … /6",
                     work: .batch(build: {
                         (1...6).map { URLRequest(url: URL(string: "\(dummyjson)/products/\($0)")!) }
                     }, sequential: false)),
            Scenario(method: "GET", title: "Same URL fired 3 times",
                     subtitle: "dummyjson.com/products/1",
                     work: .batch(build: {
                         Array(repeating: URLRequest(url: URL(string: "\(dummyjson)/products/1")!), count: 3)
                     }, sequential: false)),
            Scenario(method: "GET", title: "Cache policy comparison",
                     subtitle: "default vs. reloadIgnoringLocalCacheData",
                     work: .batch(build: {
                         let url = URL(string: "\(dummyjson)/products/1")!
                         var cached = URLRequest(url: url)
                         cached.cachePolicy = .useProtocolCachePolicy
                         var forced = URLRequest(url: url)
                         forced.cachePolicy = .reloadIgnoringLocalCacheData
                         return [cached, forced]
                     }, sequential: true))
        ]
    }

    // MARK: Body helpers

    private static func makeMultipartRequest() -> URLRequest {
        let boundary = "netfox-boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"description\"\r\n\r\n")
        append("Uploaded from the netfox demo\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"notes.txt\"\r\n")
        append("Content-Type: text/plain\r\n\r\n")
        append("Hello from netfox, multipart!\r\n")
        append("--\(boundary)--\r\n")

        var request = URLRequest(url: URL(string: "\(echo)/post")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}
