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
    /// Key: fuzzy (substring) match against the request URL. Value: URL to call instead.
    let mappings: [String: String]
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
    private var mappings: [String: String] = [:]

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
        return NFXMockConfiguration(isEnabled: isEnabled, urlString: urlString, baseURL: baseURL, mappings: mappings)
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
    
    /// Fuzzy, per-URL mappings. Each key is matched as a substring of the
    /// request URL, and the matching value is the path served by the mock
    /// server - e.g. "/users.json" - resolved against the mock server URL.
    /// A value may also be a full absolute URL when a mapping has to point
    /// somewhere else entirely.
    ///
    /// As long as at least one mapping is configured, only the requests matching
    /// one of its keys are mocked - everything else hits the real server.
    func setMappings(_ mappings: [String: String]) {
        let currentBaseURL = configuration.baseURL
        
        let validated = mappings.filter { key, value in
            guard key.isEmpty == false else {
                print("[NFX]: Ignored mock mapping with an empty key")
                return false
            }
            guard value.isEmpty == false else {
                print("[NFX]: Ignored mock mapping with an empty value for key \"\(key)\"")
                return false
            }
            guard NFXMockServer.isValidMockURL(value) || currentBaseURL != nil else {
                print("[NFX]: Mock mapping \"\(key)\": \"\(value)\" is a path, but no mock server URL is set - call setMockServerURL first")
                return false
            }
            return true
        }
        
        lock.lock()
        self.mappings = validated
        lock.unlock()
    }
    
    // MARK: - Redirecting

    /// Whether the request would actually be redirected. Used to keep netfox out
    /// of the loading chain for the requests it does not touch, so that their
    /// caching behaviour stays untouched.
    func shouldRedirect(_ request: URLRequest) -> Bool {
        let configuration = self.configuration
        
        guard configuration.isEnabled, let url = request.url else {
            return false
        }
        
        guard configuration.mappings.isEmpty else {
            guard let value = NFXMockServer.bestMatch(in: configuration.mappings, for: url.absoluteString) else {
                return false
            }
            return NFXMockServer.resolvedURL(for: value, baseURL: configuration.baseURL) != nil
        }
        
        return configuration.baseURL != nil
    }
    
    /// Returns a copy of `request` pointing at the mock server, or `nil` when
    /// the request must not be redirected.
    func redirectedRequest(for request: URLRequest) -> URLRequest? {
        let configuration = self.configuration

        guard configuration.isEnabled, let originalURL = request.url else {
            return nil
        }
        
        if configuration.mappings.isEmpty == false {
            guard let mappedValue = NFXMockServer.bestMatch(in: configuration.mappings, for: originalURL.absoluteString),
                  let mappedURL = NFXMockServer.resolvedURL(for: mappedValue, baseURL: configuration.baseURL) else {
                // Mappings are configured but nothing matches - hit the real server.
                return nil
            }
            return mockedRequest(from: request, originalURL: originalURL, targetURL: mappedURL)
        }
        
        guard let baseURL = configuration.baseURL else {
            return nil
        }
        
        guard var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = NFXMockServer.mergedPath(basePath: baseURL.path, requestPath: components.path)

        guard let redirectedURL = components.url else {
            return nil
        }

        return mockedRequest(from: request, originalURL: originalURL, targetURL: redirectedURL)
    }

    // MARK: - Helpers

    /// Builds the redirected request, carrying the original address along so the
    /// mock server can route / debug it. Returns `nil` when nothing changed.
    private func mockedRequest(from request: URLRequest, originalURL: URL, targetURL: URL) -> URLRequest? {
        guard targetURL != originalURL else {
            return nil
        }
        
        var mockedRequest = request
        mockedRequest.url = targetURL
        mockedRequest.setValue(originalURL.absoluteString, forHTTPHeaderField: NFXMockServer.originalURLHeader)
        if let originalHost = originalURL.host {
            mockedRequest.setValue(originalHost, forHTTPHeaderField: NFXMockServer.originalHostHeader)
        }
        return mockedRequest
    }
    
    /// Picks the most specific mapping, so the longest matching key always wins
    /// and the result does not depend on the dictionary ordering.
    private static func bestMatch(in mappings: [String: String], for urlString: String) -> String? {
        var bestKey: String?
        
        for key in mappings.keys where urlString.contains(key) {
            if let currentBest = bestKey {
                if key.count > currentBest.count {
                    bestKey = key
                }
            } else {
                bestKey = key
            }
        }
        
        return bestKey.flatMap { mappings[$0] }
    }
    
    /// Turns a mapping value into the URL to call.
    ///
    /// Absolute values are used as-is; anything else is treated as a path (and
    /// optional query / fragment) served by the mock server.
    private static func resolvedURL(for value: String, baseURL: URL?) -> URL? {
        if isValidMockURL(value), let absoluteURL = URL(string: value) {
            return absoluteURL
        }
        
        guard let baseURL = baseURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        let parts = splitPathComponents(value)
        components.path = mergedPath(basePath: baseURL.path, requestPath: parts.path)
        components.query = parts.query
        components.fragment = parts.fragment
        
        return components.url
    }
    
    /// Splits "/users.json?state=mock#top" into its path, query and fragment,
    /// tolerating a missing leading slash.
    private static func splitPathComponents(_ value: String) -> (path: String, query: String?, fragment: String?) {
        var remainder = value
        var fragment: String?
        var query: String?
        
        if let range = remainder.range(of: "#") {
            fragment = String(remainder[remainder.index(after: range.lowerBound)...])
            remainder = String(remainder[..<range.lowerBound])
        }
        
        if let range = remainder.range(of: "?") {
            query = String(remainder[remainder.index(after: range.lowerBound)...])
            remainder = String(remainder[..<range.lowerBound])
        }
        
        let path = remainder.hasPrefix("/") ? remainder : "/" + remainder
        return (path, query?.isEmpty == true ? nil : query, fragment?.isEmpty == true ? nil : fragment)
    }
    
    /// Whether the value is a complete, absolute http(s) URL.
    private static func isValidMockURL(_ urlString: String) -> Bool {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, host.isEmpty == false else {
            return false
        }
        return true
    }
    
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
