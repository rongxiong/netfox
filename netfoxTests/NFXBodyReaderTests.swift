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
        func formattingCanBeForcedAboveTheBudget() throws {
            // Past the budget a JSON body is streamed exactly as it arrived…
            let items = Array(repeating: "{\"id\":1}", count: 90_000)
            let text = "{\"items\":[\(items.joined(separator: ","))]}"
            let model = NFXModelFactory.model(contentType: "application/json",
                                              responseBodyLength: text.utf8.count)
            NFXPath.createDirForFileIfNotExist(model.getResponseBodyFileURL())
            try Data(text.utf8).write(to: model.getResponseBodyFileURL())

            let raw = NFXBodyReader(source: model.bodySource(for: .response))
            #expect(raw.isPrettyPrinted == false)
            #expect(allPages(of: raw).joined() == text)

            // … unless the body screen asks for it, which is what the format
            // toggle does.
            let formatted = NFXBodyReader(source: model.bodySource(for: .response, forcesFormatting: true))
            #expect(formatted.isPrettyPrinted)
            #expect(allPages(of: formatted).joined().contains("\n  "))
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

        // MARK: - Find in response

        @Test
        func rangesAreCaseAndDiacriticInsensitive() {
            let text = "Café CAFE cafe"
            let ranges = NFXTextSearch.ranges(of: "cafe", in: text)

            #expect(ranges.map { (text as NSString).substring(with: $0) } == ["Café", "CAFE", "cafe"])
        }

        @Test
        func overlappingHitsAreCountedOnce() {
            #expect(NFXTextSearch.ranges(of: "aa", in: "aaaa").map(\.location) == [0, 2])
        }

        @Test
        func anEmptyOrWhitespaceQueryMatchesNothing() {
            #expect(NFXTextSearch.find(query: "", in: ["needle"]).count == 0)
            #expect(NFXTextSearch.find(query: "   ", in: ["needle"]).count == 0)
            #expect(NFXTextSearch.ranges(of: "needle", in: "").isEmpty)
        }

        @Test
        func aQuerySplitAcrossTwoPagesIsOneHit() {
            let result = NFXTextSearch.find(query: "needle", in: ["hay NEED", "LE hay"])

            #expect(result.count == 1)
            #expect(result.matches[0].chunkIndex == 0)
            #expect(("hay NEED" as NSString).substring(with: result.matches[0].range) == "NEED")
        }

        @Test
        func independentChunksDoNotCreateFalseHits() {
            let chunks = ["Content-Type", "application/json", "Server", "netfox"]

            #expect(NFXTextSearch.find(query: "json", in: chunks, joinsChunks: false)
                        .matches.map(\.chunkIndex) == [1])
            #expect(NFXTextSearch.find(query: "netfoxSer", in: chunks, joinsChunks: false).count == 0)
            #expect(NFXTextSearch.find(query: "jsonSer", in: chunks, joinsChunks: true).count == 1)
        }

        @Test
        func theMatchBudgetIsReported() {
            let result = NFXTextSearch.find(query: "a", in: [String(repeating: "a", count: 40)], limit: 5)

            #expect(result.count == 5)
            #expect(result.isTruncated)
        }

        @Test
        func streamingSearchPointsAtARealPage() throws {
            let line = String(repeating: "x", count: 200) + "\n"
            let text = String(repeating: line, count: 2_000) + "FINAL-NEEDLE\n"
            let url = try scratchFile(text)
            let source = NFXBodySource(url: url, byteLength: text.utf8.count)
            let result = NFXTextSearch.find(query: "final-needle", source: source)

            #expect(result.count == 1)
            let hit = try #require(result.matches.first)
            let pages = allPages(of: NFXBodyReader(source: source))
            #expect(hit.chunkIndex < pages.count)
            #expect((pages[hit.chunkIndex] as NSString).substring(with: hit.range) == "FINAL-NEEDLE")
        }

        @Test
        func theLoaderSearchesPagesItHasNotDisplayedYet() async throws {
            let line = String(repeating: "x", count: 200) + "\n"
            let text = String(repeating: line, count: 2_000) + "THE-NEEDLE\n"
            let model = NFXModelFactory.model(contentType: "text/plain",
                                              responseBodyLength: text.utf8.count)
            NFXPath.createDirForFileIfNotExist(model.getResponseBodyFileURL())
            try Data(text.utf8).write(to: model.getResponseBodyFileURL())

            let loader = NFXBodyLoader(model: model, bodyType: .response)
            await loader.prepare(isImage: false)
            #expect(loader.isComplete == false)

            loader.searchText = "needle"
            await waitUntil("find in body results") {
                loader.isSearching == false && loader.searchResult.count == 1
            }
            #expect(loader.searchScrollToken > 0)

            let hit = try #require(loader.currentMatch)
            #expect(hit.chunkIndex >= loader.pages.count - 1)
            loader.ensurePageIsLoaded(hit.chunkIndex)
            #expect(loader.pages.count > hit.chunkIndex)
            #expect((loader.pages[hit.chunkIndex].text as NSString).substring(with: hit.range) == "NEEDLE")
            #expect(loader.matchRangesByPage[hit.chunkIndex]?.isEmpty == false)

            let token = loader.searchScrollToken
            loader.nextMatch()
            #expect(loader.currentMatchIndex == 0)
            #expect(loader.searchScrollToken == token + 1)
            loader.previousMatch()
            #expect(loader.currentMatchIndex == 0)

            loader.searchText = ""
            #expect(loader.searchResult.count == 0)
            #expect(loader.matchRangesByPage.isEmpty)
            #expect(loader.currentMatchIndex == nil)
            // Closing the find bar must never drop the body itself.
            #expect(loader.pages.isEmpty == false)
            #expect(loader.isReady)
        }

        @Test
        func linesKeepOffsetsAndMapRangesToRows() {
            let text = "alpha\nbeta NEEDLE\ngamma"
            let lines = NFXTextSearch.lines(in: text)

            #expect(lines.map(\.text) == ["alpha", "beta NEEDLE", "gamma"])
            #expect(lines.map(\.start) == [0, 6, 18])

            let ranges = NFXTextSearch.ranges(of: "NEEDLE", in: text)
            #expect(ranges.count == 1)
            let mapped = NFXTextSearch.lineRanges(from: ranges, in: lines)
            #expect(mapped[1] == [NSRange(location: 5, length: 6)])
            #expect(mapped[0] == nil)
        }

        @Test
        func emptyLinesAndTrailingNewlinesKeepTheirOwnRows() {
            let lines = NFXTextSearch.lines(in: "a\n\nb\n")

            #expect(lines.map(\.text) == ["a", "", "b", ""])
            #expect(lines.map(\.start) == [0, 2, 3, 5])
        }

        @Test
        func aRangeSpanningALineBreakIsClippedToItsFirstLine() {
            let text = "abc\ndef"
            let mapped = NFXTextSearch.lineRanges(from: [NSRange(location: 1, length: 5)],
                                                  in: NFXTextSearch.lines(in: text))

            #expect(mapped[0] == [NSRange(location: 1, length: 2)])
            #expect(mapped[1] == nil)
        }

        @Test
        func scrollAnchorPointsAtTheLineHoldingTheHit() {
            let text = "line one\nline two\nTARGET here\nlast"
            let location = (text as NSString).range(of: "TARGET").location
            let match = NFXTextSearchMatch(chunkIndex: 7, range: NSRange(location: location, length: 6))

            #expect(NFXTextSearch.anchor(for: match, in: text) == NFXTextSearch.lineID(chunk: 7, line: 2))
        }
    }
}
