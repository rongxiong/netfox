//
//  NFXBodyReaderTests.swift
//  netfoxTests
//
//  A large response must reach the screen in bounded slices: reading the whole
//  file, pretty printing it and rendering it as a single `Text` is what used to
//  freeze the body screen.
//

import Foundation
import Testing
@testable import netfox_ios

extension NFXTests {

    @MainActor
    @Suite
    struct NFXBodyReaderTests {

        private let environment = NFXTestEnvironment()

        // MARK: - Fixtures

        /// Writes `text` to a scratch file and returns its URL.
        private func scratchFile(_ text: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("nfx-body-\(UUID().uuidString).txt")
            try Data(text.utf8).write(to: url)
            return url
        }

        private func jsonFormatter() -> (Data) -> String? {
            let model = NFXModelFactory.model()
            return { model.prettyPrintedBody($0, contentType: "application/json") }
        }

        private func allPages(of reader: NFXBodyReader) -> [String] {
            var pages: [String] = []
            while let page = reader.nextPage() {
                pages.append(page)
            }
            return pages
        }

        // MARK: - Paging

        @Test
        func smallJSONBodyIsPrettyPrintedIntoASinglePage() throws {
            let url = try scratchFile("{\"id\":7}")
            let reader = NFXBodyReader(source: NFXBodySource(url: url,
                                                             byteLength: 8,
                                                             format: jsonFormatter()))

            #expect(reader.isPrettyPrinted)

            let page = try #require(reader.nextPage())
            #expect(page.replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "\n", with: "") == "{\"id\":7}")
            #expect(reader.nextPage() == nil)
        }

        @Test
        func largeBodyIsStreamedInBoundedPages() throws {
            let text = String(repeating: String(repeating: "a", count: 200) + "\n", count: 5_000)
            let url = try scratchFile(text)
            let reader = NFXBodyReader(source: NFXBodySource(url: url, byteLength: text.utf8.count))

            // Too big to be worth reformatting, so it is served as written.
            #expect(reader.isPrettyPrinted == false)

            let pages = allPages(of: reader)
            #expect(pages.count > 1)
            #expect(pages.allSatisfy { $0.utf8.count <= NFXBodyReader.pageByteLimit })
            #expect(pages.joined() == text)
        }

        @Test
        func aSingleVeryLongLineIsStillBrokenUp() throws {
            let text = String(repeating: "x", count: 200_000)
            let url = try scratchFile(text)
            let pages = allPages(of: NFXBodyReader(source: NFXBodySource(url: url,
                                                                        byteLength: text.utf8.count)))

            #expect(pages.count > 1)
            #expect(pages.joined() == text)
        }

        @Test
        func multibyteCharactersAreNeverSplitAcrossPages() throws {
            let text = String(repeating: "汉字", count: 40_000)
            let url = try scratchFile(text)
            let pages = allPages(of: NFXBodyReader(source: NFXBodySource(url: url,
                                                                        byteLength: text.utf8.count)))

            #expect(pages.count > 1)
            // A character cut in half would decode to U+FFFD and break this.
            #expect(pages.joined() == text)
        }

        @Test
        func entireTextReturnsTheWholeBody() throws {
            let text = String(repeating: "{\"id\":1}\n", count: 40_000)
            let url = try scratchFile(text)
            let source = NFXBodySource(url: url, byteLength: text.utf8.count)

            #expect(NFXBodyReader.entireText(source: source) == text)
        }

        // MARK: - Empty / missing files

        @Test
        func anEmptyBodyProducesNoPages() throws {
            let url = try scratchFile("")
            let reader = NFXBodyReader(source: NFXBodySource(url: url,
                                                             byteLength: 0,
                                                             format: jsonFormatter()))

            #expect(reader.nextPage() == nil)
        }

        @Test
        func aMissingFileProducesNoPages() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("nfx-missing-\(UUID().uuidString).txt")
            let reader = NFXBodyReader(source: NFXBodySource(url: url, byteLength: 128))

            #expect(reader.nextPage() == nil)
        }

        // MARK: - Formatting budget

        @Test
        func prettyPrintingIsSkippedAboveTheBudget() {
            let model = NFXModelFactory.model(contentType: "application/json")
            let small = Data("{\"id\":7}".utf8)
            let huge = Data(String(repeating: "a", count: NFXBodyReader.prettyPrintByteLimit + 1).utf8)

            #expect(model.prettyPrintedBody(small, contentType: "application/json") != nil)
            #expect(model.prettyPrintedBody(small, contentType: "text/html") == nil)
            #expect(model.prettyPrintedBody(huge, contentType: "application/json") == nil)
            #expect(model.prettyOutput(huge, contentType: "application/json").utf8.count == huge.count)
        }

        @Test
        func bodySourcePointsAtTheMatchingFile() {
            let model = NFXModelFactory.persistedModel()
            let response = model.bodySource(for: .response)
            let request = model.bodySource(for: .request)

            #expect(response.url == model.getResponseBodyFileURL())
            #expect(response.byteLength == model.responseBodyLength)
            #expect(request.url == model.getRequestBodyFileURL())
            #expect(request.byteLength == model.requestBodyLength)
            #expect(response.format?(Data("{\"id\":7}".utf8)) != nil)
        }

        // MARK: - Loader

        @Test
        func theBodyScreenOnlyHoldsTheFirstPageUpFront() async throws {
            let text = String(repeating: "{\"id\":1}\n", count: 40_000)
            let model = NFXModelFactory.model(contentType: "application/json",
                                              responseBodyLength: text.utf8.count)

            NFXPath.createDirForFileIfNotExist(model.getResponseBodyFileURL())
            try Data(text.utf8).write(to: model.getResponseBodyFileURL())

            let loader = NFXBodyLoader(model: model, bodyType: .response)
            await loader.prepare(isImage: false)

            #expect(loader.isReady)
            #expect(loader.pages.isEmpty == false)
            #expect(loader.isComplete == false)
            // The whole point: only a couple of pages are read up front, never
            // the entire body.
            #expect(loader.loadedByteCount < text.utf8.count / 4)

            // The rest arrives on demand (scrolling / "Load more").
            loader.loadMore()
            #expect(loader.loadedByteCount > NFXBodyReader.pageByteLimit)

            // … and copy / share still gets everything.
            #expect(await loader.entireText() == text)
        }
    }
}
