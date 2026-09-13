//
//  NFXDemoSeeder.swift
//  netfox_ios_demo
//
//  Fires a fixed batch of requests against the local seed server at launch,
//  but only when the app is launched by the UI tests. Requests are fired one
//  after another, so the netfox list always ends up in the same order.
//

import Foundation
import netfox_ios

enum NFXDemoSeeder {

    static let launchArgument = "-nfxUITestSeed"

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

    /// Fires the seeded batch when the `-nfxUITestSeed` launch argument is set.
    static func seedIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }

        var routes: [String: NFXDemoSeedServer.Response] = [:]
        for seed in seeds {
            routes[seed.path] = seed.response
        }
        try? server.start(routes: routes)

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
