//
//  NFXModelFactory.swift
//  netfoxTests
//
//  Builds deterministic models so the tests stay short and readable.
//

import Foundation
@testable import netfox_ios

enum NFXModelFactory {

    static let defaultURL = "https://api.example.com/v1/users?page=2"

    static func request(url: String = defaultURL,
                        method: String = "GET",
                        headers: [String: String] = ["Content-Type": "application/json"],
                        body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        return request
    }

    /// A model filled in directly - nothing is written to disk, so it is safe
    /// for the pure content / statistics tests.
    static func model(url: String = defaultURL,
                      method: String = "GET",
                      status: Int? = 200,
                      contentType: String = "application/json",
                      requestHeaders: [String: String] = ["Accept": "application/json"],
                      responseHeaders: [String: String] = ["Server": "netfox"],
                      requestBodyLength: Int = 0,
                      responseBodyLength: Int = 128,
                      duration: Float = 0.42,
                      isMocked: Bool = false,
                      mockTargetURL: String? = nil,
                      requestDate: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> NFXHTTPModel {
        let model = NFXHTTPModel()
        model.requestURL = url
        model.requestURLComponents = URLComponents(string: url)
        model.requestURLQueryItems = model.requestURLComponents?.queryItems
        model.requestMethod = method
        model.requestCachePolicy = "UseProtocolCachePolicy"
        model.requestTimeout = "30.0"
        model.requestHeaders = requestHeaders
        model.requestType = requestHeaders["Content-Type"]
        model.requestDate = requestDate
        model.requestTime = "10:00"
        model.requestBodyLength = requestBodyLength

        if let status = status {
            model.noResponse = false
            model.responseStatus = status
            model.responseType = contentType
            model.responseHeaders = responseHeaders
            model.responseDate = requestDate.addingTimeInterval(TimeInterval(duration))
            model.responseTime = "10:00"
            model.responseBodyLength = responseBodyLength
            model.timeInterval = duration
            model.shortType = HTTPModelShortType(contentType: contentType)
        } else {
            model.noResponse = true
            model.shortType = .OTHER
        }

        model.isMocked = isMocked
        model.mockTargetURL = mockTargetURL
        return model
    }

    /// A model that really saved its bodies through `saveRequest` /
    /// `saveResponse`, so the file backed getters can be exercised.
    @discardableResult
    static func persistedModel(url: String = "https://api.example.com/v1/orders",
                               method: String = "POST",
                               status: Int = 200,
                               contentType: String = "application/json",
                               requestBody: Data = Data("{\"sku\":\"nfx\"}".utf8),
                               responseBody: Data = Data("{\"id\":7}".utf8)) -> NFXHTTPModel {
        let model = NFXHTTPModel()
        // netfox reads the body from `httpBodyStream` or from the
        // `NFXBodyData` property, never from `httpBody`, so it is attached
        // the very same way here.
        let request = self.request(url: url,
                                   method: method,
                                   headers: ["Content-Type": "application/json"],
                                   body: requestBody)
        let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(requestBody, forKey: "NFXBodyData", in: mutable)
        let prepared = mutable as URLRequest

        model.saveRequest(prepared)
        model.saveRequestBody(prepared)

        let response = HTTPURLResponse(url: URL(string: url)!,
                                       statusCode: status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": contentType])!
        model.saveResponse(response, data: responseBody)
        return model
    }
}
