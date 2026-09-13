//
//  NFXHTTPModelTests.swift
//  netfoxTests
//
//  How a request / response pair is recorded, read back and rendered as a log.
//

import Foundation
import Testing
@testable import netfox_ios

extension NFXTests {

    @MainActor
    @Suite
    struct NFXHTTPModelTests {

        private let environment = NFXTestEnvironment()

        // MARK: - Recording

        @Test
        func saveRequestFillsTheRequestFields() {
            let model = NFXHTTPModel()
            let request = NFXModelFactory.request(url: "https://api.example.com/v1/users?page=2",
                                                  method: "PUT",
                                                  headers: ["Content-Type": "application/json"])

            model.saveRequest(request)

            #expect(model.requestURL == "https://api.example.com/v1/users?page=2")
            #expect(model.requestMethod == "PUT")
            #expect(model.requestType == "application/json")
            #expect(model.requestURLQueryItems?.count == 1)
            #expect(model.requestCachePolicy == "UseProtocolCachePolicy")
            #expect(model.requestDate != nil)
            #expect(model.requestTime != nil)
            #expect(model.requestCurl == request.getCurl())
        }

        @Test
        func saveResponseFillsTheResponseFields() {
            let model = NFXModelFactory.persistedModel(status: 201, responseBody: Data("{\"id\":7}".utf8))

            #expect(!model.noResponse)
            #expect(model.responseStatus == 201)
            #expect(model.responseType == "application/json")
            #expect(model.shortType == .JSON)
            #expect(model.responseBodyLength == 8)
            #expect(model.timeInterval != nil)
        }

        @Test
        func requestBodyLengthIsRecorded() {
            let model = NFXModelFactory.persistedModel(requestBody: Data("12345".utf8))
            #expect(model.requestBodyLength == 5)
        }

        @Test
        func responseBodyIsReadBackPrettyPrinted() {
            let model = NFXModelFactory.persistedModel(responseBody: Data("{\"id\":7}".utf8))
            let body = model.getResponseBody().replacingOccurrences(of: " ", with: "")
                                              .replacingOccurrences(of: "\n", with: "")
            #expect(body == "{\"id\":7}")
        }

        @Test
        func imageBodyIsStoredAsBase64() {
            let data = Data([1, 2, 3, 4])
            let model = NFXModelFactory.persistedModel(contentType: "image/png", responseBody: data)

            #expect(model.shortType == .IMAGE)
            #expect(model.getResponseBody() == data.base64EncodedString(options: .endLineWithLineFeed))
        }

        @Test
        func modelWithoutAFileHasAnEmptyBody() {
            let model = NFXModelFactory.model()
            #expect(model.getRequestBody() == "")
            #expect(model.getResponseBody() == "")
        }

        @Test
        func saveErrorResponseOnlyRecordsTheDate() {
            let model = NFXHTTPModel()
            model.saveErrorResponse()

            #expect(model.noResponse)
            #expect(model.responseDate != nil)
            #expect(model.responseStatus == nil)
        }

        // MARK: - Status

        @Test
        func isSuccessful() {
            #expect(NFXModelFactory.model(status: 200).isSuccessful())
            #expect(NFXModelFactory.model(status: 302).isSuccessful())
            #expect(!NFXModelFactory.model(status: 400).isSuccessful())
            #expect(!NFXModelFactory.model(status: 500).isSuccessful())
            #expect(!NFXModelFactory.model(status: nil).isSuccessful())
        }

        // MARK: - Pretty printing

        @Test
        func prettyPrintOnlyHandlesJSON() {
            let model = NFXHTTPModel()
            let data = Data("{\"b\":1,\"a\":2}".utf8)

            #expect(model.prettyPrint(data, type: .JSON) != nil)
            #expect((model.prettyPrint(data, type: .JSON) ?? "").contains("\n"))
            #expect(model.prettyPrint(Data("not json".utf8), type: .JSON) == nil)
            #expect(model.prettyPrint(data, type: .HTML) == nil)
        }

        // MARK: - Log files

        @Test
        func successLogFileName() {
            let model = NFXModelFactory.model(url: "https://example.com/api/v1/users")
            #expect(model.getSuccessLogFileName() == "api-v1-users.log")

            model.requestURL = "https://example.com/api/v1/users/"
            model.requestURLComponents = URLComponents(string: "https://example.com/api/v1/users/")
            #expect(model.getSuccessLogFileName() == "api-v1-users.log")

            model.requestURL = "https://example.com"
            model.requestURLComponents = URLComponents(string: "https://example.com")
            #expect(model.getSuccessLogFileName() == "example_com.log")

            model.requestURL = nil
            model.requestURLComponents = nil
            #expect(model.getSuccessLogFileName() == nil)
        }

        @Test
        func successfulExchangeIsSavedToDocuments() {
            let model = NFXModelFactory.persistedModel(url: "https://api.example.com/v1/nfx-documents-success",
                                                       status: 200)
            let fileURL = NFXPath.documentsFileURL(model.getSuccessLogFileName()!)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            #expect(FileManager.default.fileExists(atPath: fileURL.path))
        }

        @Test
        func failedExchangeIsNotSavedToDocuments() {
            let model = NFXModelFactory.persistedModel(url: "https://api.example.com/v1/nfx-documents-failure",
                                                       status: 500)
            let fileURL = NFXPath.documentsFileURL(model.getSuccessLogFileName()!)

            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        }

        @Test
        func bodyFileNamesAreUniqueAndSafe() {
            let model = NFXModelFactory.model()
            #expect(model.getRequestBodyFilename().hasPrefix("request_body_"))
            #expect(model.getResponseBodyFilename().hasPrefix("response_body_"))
            #expect(!model.getRequestBodyFilename().contains(":"))
        }

        // MARK: - Log entries

        @Test
        func formattedRequestLogEntry() {
            let log = NFXModelFactory.model(url: "https://api.example.com/v1/users",
                                            method: "DELETE",
                                            requestHeaders: ["Content-Type": "application/json"])
                .formattedRequestLogEntry()

            #expect(log.contains("-------START REQUEST -  https://api.example.com/v1/users -------"))
            #expect(log.contains("[Request Method] DELETE"))
            #expect(log.contains("[Request Type] application/json"))
            #expect(log.contains("-------END REQUEST - https://api.example.com/v1/users -------"))
        }

        @Test
        func mockedRequestIsFlaggedInTheLog() {
            let model = NFXModelFactory.model(isMocked: true, mockTargetURL: "http://127.0.0.1:8080/v1/users")

            #expect(model.formattedRequestLogEntry()
                .contains("[Mocked] redirected to http://127.0.0.1:8080/v1/users"))
        }

        @Test
        func formattedResponseLogEntry() {
            let log = NFXModelFactory.model(status: 500).formattedResponseLogEntry()

            #expect(log.contains("[Response Status] 500"))
            #expect(log.contains("[Response Type] application/json"))
            #expect(log.contains("-------END RESPONSE - https://api.example.com/v1/users?page=2 -------"))
        }

        // MARK: - Time

        @Test
        func timeFromDateZeroPadsTheMinutes() throws {
            var components = DateComponents()
            components.hour = 9
            components.minute = 5
            let early = try #require(Calendar.current.date(from: components))
            components.minute = 35
            let late = try #require(Calendar.current.date(from: components))

            let model = NFXHTTPModel()
            #expect(model.getTimeFromDate(early) == "9:05")
            #expect(model.getTimeFromDate(late) == "9:35")
        }
    }
}
