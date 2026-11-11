//
//  NFXDemoSeeder.swift
//  netfox_ios_demo
//
//  Owns the demo's loopback server and, when the UI tests ask for it, the
//  fixed batch of requests fired against it at launch.
//
//  The server runs for the whole session: it serves `big-json.json` out of
//  the app bundle (so that scenario is the same size on every run and needs no
//  internet connection), and it serves the seeded batch under the
//  `-nfxUITestSeed` launch argument, which fires the requests one after
//  another so the netfox list always ends up in the same order.
//

import Foundation
import netfox_ios

enum NFXDemoSeeder {

    static let launchArgument = "-nfxUITestSeed"

    /// Route of the bundled big JSON document.
    private static let bigJSONPath = "/demo/big-json"

    /// A 25 MB JSON document, far past `NFXBodyReader.prettyPrintByteLimit`:
    /// the body viewer streams it in pages instead of pretty printing it, and
    /// the details screen refuses to preview it inline.
    private static let bigJSONResource = "big-json"

    private struct Seed {
        let path: String
        let method: String
        let response: NFXDemoSeedServer.Response
        let requestBody: Data?
    }

    private static let seeds: [Seed] = [
        // The paths are prefixed so they can never be confused with the
        // rows of the demo catalogue when the UI tests query the list.
        Seed(path: "/seed/users",
             method: "GET",
             response: .json(["users": [["id": 1, "name": "Ada"], ["id": 2, "name": "Grace"]]]),
             requestBody: nil),
        Seed(path: "/seed/users",
             method: "POST",
             response: .json(["id": 42, "created": true], status: 201),
             requestBody: "{\"name\":\"Ada\"}".data(using: .utf8)),
        Seed(path: "/seed/products/9999",
             method: "GET",
             response: .json(["error": "not found"], status: 404),
             requestBody: nil),
        Seed(path: "/seed/page",
             method: "GET",
             response: .text("<html><body>netfox</body></html>", contentType: "text/html"),
             requestBody: nil),
        Seed(path: "/seed/boom",
             method: "GET",
             response: .json(["error": "boom"], status: 500),
             requestBody: nil)
    ]

    /// Kept alive for the whole run - a session that goes away cancels the
    /// tasks it still owns.
    private static let session = URLSession(configuration: .default)
    private static let server = NFXDemoSeedServer()

    /// Loopback URL of the bundled big JSON document. The port is only known
    /// once `start()` has bound the socket, which happens during launch, long
    /// before a scenario row can be tapped; the fallback only shows up if the
    /// server never came up at all.
    static var bigJSONURL: URL {
        guard let baseURL = server.baseURL else {
            return URL(string: "http://127.0.0.1\(bigJSONPath)")!
        }
        return URL(string: baseURL.absoluteString + bigJSONPath)!
    }

    /// Starts the loopback server, then fires the seeded batch when the
    /// `-nfxUITestSeed` launch argument is set.
    static func start() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains(launchArgument)

        var routes: [String: NFXDemoSeedServer.Response] = [:]
        if let url = Bundle.main.url(forResource: bigJSONResource, withExtension: "json") {
            routes[bigJSONPath] = .file(at: url, contentType: "application/json")
        }
        for seed in seeds where isUITesting {
            routes[seed.path] = seed.response
        }
        try? server.start(routes: routes)

        guard isUITesting, server.baseURL != nil else { return }
        fireSeededBatch()
    }

    private static func fireSeededBatch() {
        guard let baseURL = server.baseURL else { return }

        var iterator = seeds.makeIterator()

        func fireNext() {
            guard let seed = iterator.next() else { return }

            var request = URLRequest(url: URL(string: baseURL.absoluteString + seed.path)!)
            request.httpMethod = seed.method
            if let body = seed.requestBody {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            session.dataTask(with: request) { _, _, _ in
                DispatchQueue.main.async(execute: fireNext)
            }.resume()
        }

        fireNext()
    }
}
