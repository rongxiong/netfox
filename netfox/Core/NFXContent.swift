//
//  NFXContent.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import Foundation

/// Which part of an exchange a body belongs to.
enum NFXBodyType: Int {
    case request  = 0
    case response = 1
}

// MARK: - Content primitives

/// A single `key -> value` pair rendered as a row.
struct NFXContentField: Identifiable {
    let key: String
    let value: String

    var id: String { key }
}

/// A request / response body, already resolved for display.
///
/// Bodies bigger than `NFXContentBuilder.inlineBodyLimit` are not loaded: they
/// are rendered as a "show the whole body" affordance instead, so opening a
/// request never decodes megabytes of data up front.
struct NFXContentBody {
    let type: NFXBodyType
    let byteLength: Int
    let isTruncated: Bool
    /// `nil` when the body is empty or too long to be inlined.
    let text: String?

    var isEmpty: Bool { byteLength == 0 }
}

/// A group of rows (and optionally a body) rendered inside a card.
struct NFXContentSection: Identifiable {
    let id: String
    let title: String?
    let fields: [NFXContentField]
    let body: NFXContentBody?

    init(id: String, title: String? = nil, fields: [NFXContentField] = [], body: NFXContentBody? = nil) {
        self.id = id
        self.title = title
        self.fields = fields
        self.body = body
    }
}

/// Everything the details screen needs for one exchange.
struct NFXDetailsContent {
    let statusCode: Int?
    let info: NFXContentSection
    let request: NFXContentSection
    /// `nil` for requests that have not been answered yet.
    let response: NFXContentSection?
    let hasQueryItems: Bool
}

/// Everything the statistics screen needs, computed once per model set change.
struct NFXStatisticsSummary {
    let totalRequests: Int
    let successfulRequests: Int
    let failedRequests: Int
    let totalRequestSize: Int
    let totalResponseSize: Int
    let averageResponseTime: Float?
    let fastestResponseTime: Float?
    let slowestResponseTime: Float?

    var successRatio: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(successfulRequests) / Double(totalRequests)
    }

    var failureRatio: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(failedRequests) / Double(totalRequests)
    }

    var averageRequestSize: Int {
        guard totalRequests > 0 else { return 0 }
        return totalRequestSize / totalRequests
    }

    var averageResponseSize: Int {
        guard totalRequests > 0 else { return 0 }
        return totalResponseSize / totalRequests
    }
}

// MARK: - Formatting

/// Locale/region used for date and number display formatting.
/// Tests pin this to fixed values so snapshots do not depend on the machine region.
enum NFXFormatConfig {
    static var locale: Locale = .current
    static var timeZone: TimeZone = .current
}

enum NFXFormat {

    static func bytes(_ byteCount: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(byteCount))
    }

    static func duration(_ seconds: Float?) -> String {
        guard let seconds = seconds else { return "-" }
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        }
        return String(format: "%.2f s", seconds)
    }

    static func integer(_ value: Int?) -> String {
        guard let value = value else { return "-" }
        return NumberFormatter.nfxDecimal.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Full calendar date and time precise to the millisecond, used by the
    /// Details "Request date" / "Response date" fields.
    static func date(_ date: Date?) -> String {
        guard let date = date else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = NFXFormatConfig.locale
        formatter.timeZone = NFXFormatConfig.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyyHHmmssSSS")
        return formatter.string(from: date)
    }

    /// Time-of-day with millisecond precision (`HH:mm:ss.SSS`), used by the
    /// request list cards so requests arriving in the same second stay ordered.
    static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter.nfxClockTime
        formatter.locale = NFXFormatConfig.locale
        formatter.timeZone = NFXFormatConfig.timeZone
        return formatter.string(from: date)
    }
}

private extension NumberFormatter {
    static let nfxDecimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()
}

private extension DateFormatter {
    static let nfxClockTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Builder

enum NFXContentBuilder {

    /// Bodies bigger than this are served by the dedicated body screen.
    static let inlineBodyLimit = 1024

    private static let unknownValue = "-"

    // MARK: Details

    static func details(for model: NFXHTTPModel) -> NFXDetailsContent {
        NFXDetailsContent(statusCode: model.noResponse ? nil : model.responseStatus,
                          info: infoSection(for: model),
                          request: requestSection(for: model),
                          response: responseSection(for: model),
                          hasQueryItems: (model.requestURLQueryItems?.count ?? 0) > 0)
    }

    private static func infoSection(for model: NFXHTTPModel) -> NFXContentSection {
        var fields: [NFXContentField] = [
            NFXContentField(key: "URL", value: model.requestURL ?? unknownValue),
            NFXContentField(key: "Method", value: model.requestMethod ?? unknownValue),
            NFXContentField(key: "Request date", value: NFXFormat.date(model.requestDate))
        ]

        if let target = model.mockTargetURL, model.isMocked {
            fields.append(NFXContentField(key: "Mock target", value: target))
        }

        if model.noResponse {
            fields.append(NFXContentField(key: "Status", value: "No response"))
        } else {
            fields.append(NFXContentField(key: "Status", value: NFXFormat.integer(model.responseStatus)))
            fields.append(NFXContentField(key: "Response date", value: NFXFormat.date(model.responseDate)))
            fields.append(NFXContentField(key: "Duration", value: NFXFormat.duration(model.timeInterval)))
        }

        fields.append(NFXContentField(key: "Timeout", value: model.requestTimeout ?? unknownValue))
        fields.append(NFXContentField(key: "Cache policy", value: model.requestCachePolicy ?? unknownValue))

        return NFXContentSection(id: "info", fields: fields)
    }

    private static func requestSection(for model: NFXHTTPModel) -> NFXContentSection {
        NFXContentSection(id: "request",
                          fields: headerFields(from: model.requestHeaders),
                          body: body(for: .request, model: model))
    }

    private static func responseSection(for model: NFXHTTPModel) -> NFXContentSection? {
        guard model.noResponse == false else { return nil }
        return NFXContentSection(id: "response",
                                 fields: headerFields(from: model.responseHeaders),
                                 body: body(for: .response, model: model))
    }

    private static func headerFields(from headers: [AnyHashable: Any]?) -> [NFXContentField] {
        guard let headers = headers, headers.isEmpty == false else { return [] }

        let keys = headers.keys.compactMap { $0 as? String }.sorted()
        return keys.map { key in
            NFXContentField(key: key, value: String(describing: headers[key] ?? ""))
        }
    }

    private static func body(for type: NFXBodyType, model: NFXHTTPModel) -> NFXContentBody {
        switch type {
        case .request:
            return NFXContentBody(type: type,
                                  byteLength: model.requestBodyLength ?? 0,
                                  isTruncated: (model.requestBodyLength ?? 0) > inlineBodyLimit,
                                  text: inlineText(for: .request, model: model))
        case .response:
            return NFXContentBody(type: type,
                                  byteLength: model.responseBodyLength ?? 0,
                                  isTruncated: (model.responseBodyLength ?? 0) > inlineBodyLimit,
                                  text: inlineText(for: .response, model: model))
        }
    }

    private static func inlineText(for type: NFXBodyType, model: NFXHTTPModel) -> String? {
        let length = type == .request ? model.requestBodyLength ?? 0 : model.responseBodyLength ?? 0
        guard length > 0, length <= inlineBodyLimit else { return nil }
        return type == .request ? model.getRequestBody() : model.getResponseBody()
    }

    // MARK: Export

    /// Plain text used by the share sheet. `full` additionally inlines both bodies.
    static func plainTextLog(for model: NFXHTTPModel, full: Bool) -> String {
        var log = ""
        log += "** INFO **\n\(plainText(from: infoSection(for: model)))\n\n"
        log += "** REQUEST **\nHeaders\n\(plainText(from: requestSection(for: model)))\n\n"

        if let response = responseSection(for: model) {
            log += "** RESPONSE **\nHeaders\n\(plainText(from: response))\n\n"
        } else {
            log += "** RESPONSE **\nNo response\n\n"
        }

        if full {
            let requestURL = model.getRequestBodyFileURL()
            if let requestData = try? String(contentsOf: requestURL, encoding: .utf8) {
                log += "\(requestData)\n"
            }

            let responseURL = model.getResponseBodyFileURL()
            if let responseData = try? String(contentsOf: responseURL, encoding: .utf8) {
                log += "\(responseData)\n"
            }
        }

        log += "logged via netfox - [https://github.com/rongxiong/netfox]\n"
        return log
    }

    private static func plainText(from section: NFXContentSection) -> String {
        section.fields.reduce(into: "") { log, field in
            log += "[\(field.key)] \(field.value)\n"
        }
    }

    // MARK: Statistics

    static func statistics(for models: [NFXHTTPModel]) -> NFXStatisticsSummary {
        var successful = 0
        var failed = 0
        var requestSize = 0
        var responseSize = 0
        var totalTime: Float = 0
        var fastest: Float?
        var slowest: Float?

        for model in models {
            if model.isSuccessful() {
                successful += 1
            } else {
                failed += 1
            }

            requestSize += model.requestBodyLength ?? 0
            responseSize += model.responseBodyLength ?? 0

            guard let interval = model.timeInterval else { continue }
            totalTime += interval
            fastest = min(fastest ?? interval, interval)
            slowest = max(slowest ?? interval, interval)
        }

        let total = models.count
        let averageTime: Float? = total > 0 ? totalTime / Float(total) : nil

        return NFXStatisticsSummary(totalRequests: total,
                                    successfulRequests: successful,
                                    failedRequests: failed,
                                    totalRequestSize: requestSize,
                                    totalResponseSize: responseSize,
                                    averageResponseTime: averageTime,
                                    fastestResponseTime: fastest,
                                    slowestResponseTime: slowest)
    }

    // MARK: Device information

    static func deviceInfo(ipAddress: String?) -> [NFXContentSection] {
        let app = NFXContentSection(id: "app", title: "Application", fields: [
            NFXContentField(key: "Name", value: NFXDebugInfo.getNFXAppName()),
            NFXContentField(key: "Version", value: "\(NFXDebugInfo.getNFXAppVersionNumber()) (\(NFXDebugInfo.getNFXAppBuildNumber()))"),
            NFXContentField(key: "Bundle identifier", value: NFXDebugInfo.getNFXBundleIdentifier())
        ])

        let device = NFXContentSection(id: "device", title: "Device", fields: [
            NFXContentField(key: "OS", value: NFXDebugInfo.getNFXOSVersion()),
            NFXContentField(key: "Model", value: NFXDebugInfo.getNFXDeviceType()),
            NFXContentField(key: "Screen resolution", value: NFXDebugInfo.getNFXDeviceScreenResolution())
        ])

        let network = NFXContentSection(id: "network", title: "Network", fields: [
            NFXContentField(key: "IP address", value: ipAddress ?? "Retrieving…")
        ])

        return [app, device, network]
    }
}
