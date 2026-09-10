//
//  NFXMockServer.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import Foundation

/// Immutable snapshot of the mock server configuration.
///
/// `NFXMockServer` hands out snapshots so that callers running on URLSession's
/// background threads never observe a half-updated state while the settings UI
/// mutates the configuration on the main thread.
internal struct NFXMockConfiguration {
    let isEnabled: Bool
    /// Raw text as entered by the user - used to prefill the settings UI.
    let urlString: String?
    /// Normalized `scheme://host[:port][/pathPrefix]` used to rewrite requests.
    let baseURL: URL?
}

/// Redirects intercepted requests to a mock server.
///
/// Only the scheme, host and port of a request are replaced - path, query,
/// fragment, http method, headers and body are preserved, so a mock server can
/// keep serving the very same endpoints.
internal final class NFXMockServer {

    // MARK: - Constants

    /// Carries the pre-redirect URL so the mock server can route / debug it.
    static let originalURLHeader = "X-Netfox-Original-URL"
    /// Carries the pre-redirect host so the mock server can virtual-host.
    static let originalHostHeader = "X-Netfox-Original-Host"

    private enum DefaultsKey {
        static let enabled = "com.netfox.mockServer.enabled"
        static let url = "com.netfox.mockServer.url"
    }

    // MARK: - Properties

    private let lock = NSLock()
    private let defaults: UserDefaults

    private var isEnabled: Bool
    private var urlString: String?
    private var baseURL: URL?

    // MARK: - Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: DefaultsKey.enabled)
        if let storedURLString = defaults.string(forKey: DefaultsKey.url) {
            self.urlString = storedURLString
            self.baseURL = NFXMockServer.normalizedURL(from: storedURLString)
        }
    }

    // MARK: - Configuration

    var configuration: NFXMockConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return NFXMockConfiguration(isEnabled: isEnabled, urlString: urlString, baseURL: baseURL)
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        isEnabled = enabled
        lock.unlock()

        defaults.set(enabled, forKey: DefaultsKey.enabled)
    }

    /// Stores the mock server address. Invalid input is reported and ignored,
    /// so a typo while typing in the settings UI never breaks interception.
    func setURLString(_ urlString: String?) {
        let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmed = trimmed, trimmed.isEmpty == false else {
            lock.lock()
            self.urlString = nil
            self.baseURL = nil
            lock.unlock()

            defaults.removeObject(forKey: DefaultsKey.url)
            return
        }

        guard let normalized = NFXMockServer.normalizedURL(from: trimmed) else {
            print("[NFX]: Invalid mock server URL \"\(trimmed)\" - expected format is http(s)://host[:port][/path]")
            return
        }

        lock.lock()
        self.urlString = trimmed
        self.baseURL = normalized
        lock.unlock()

        defaults.set(trimmed, forKey: DefaultsKey.url)
    }

    // MARK: - Redirecting

    /// Returns a copy of `request` pointing at the mock server, or `nil` when
    /// the mock server is disabled / misconfigured.
    func redirectedRequest(for request: URLRequest) -> URLRequest? {
        let configuration = self.configuration

        guard configuration.isEnabled, let baseURL = configuration.baseURL else {
            return nil
        }

        guard let originalURL = request.url,
              var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = NFXMockServer.mergedPath(basePath: baseURL.path, requestPath: components.path)

        guard let redirectedURL = components.url, redirectedURL != originalURL else {
            return nil
        }

        var redirectedRequest = request
        redirectedRequest.url = redirectedURL
        redirectedRequest.setValue(originalURL.absoluteString, forHTTPHeaderField: NFXMockServer.originalURLHeader)
        if let originalHost = originalURL.host {
            redirectedRequest.setValue(originalHost, forHTTPHeaderField: NFXMockServer.originalHostHeader)
        }
        return redirectedRequest
    }

    // MARK: - Helpers

    /// Keeps only `scheme://host[:port][/pathPrefix]` out of the user input.
    private static func normalizedURL(from urlString: String) -> URL? {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, host.isEmpty == false else {
            return nil
        }

        var normalized = URLComponents()
        normalized.scheme = scheme
        normalized.host = host
        normalized.port = components.port
        normalized.path = trimmedTrailingSlash(components.path)
        return normalized.url
    }

    private static func trimmedTrailingSlash(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else {
            return path == "/" ? "" : path
        }
        return String(path.dropLast())
    }

    private static func mergedPath(basePath: String, requestPath: String) -> String {
        guard basePath.isEmpty == false else {
            return requestPath
        }
        guard requestPath.isEmpty == false else {
            return basePath
        }
        return basePath + requestPath
    }
}
