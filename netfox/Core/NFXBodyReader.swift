//
//  NFXBodyReader.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import Foundation

/// A body file on disk, plus the (optional) formatter applied to it before it
/// reaches the screen.
///
/// `@unchecked Sendable` because it is passed to a background task: it only
/// holds a URL, a length and a formatter, none of which is mutated afterwards.
struct NFXBodySource: @unchecked Sendable {

    /// Where `NFXHTTPModel` wrote the body.
    let url: URL
    /// Size of the original payload. Drives the "is reformatting affordable?"
    /// decision and the "showing X of Y" progress label.
    let byteLength: Int
    /// Turns the raw file bytes into their display form - pretty printed JSON.
    /// `nil`, or a `nil` result, means the file is served exactly as written.
    let format: ((Data) -> String?)?

    init(url: URL, byteLength: Int, format: ((Data) -> String?)? = nil) {
        self.url = url
        self.byteLength = byteLength
        self.format = format
    }
}

/// A slice of a body, small enough to be handed to a single SwiftUI `Text`.
struct NFXBodyPage: Identifiable {

    let index: Int
    let text: String
    let byteCount: Int

    var id: Int { index }
}

/// Reads a body file one page at a time.
///
/// Showing a large response the naive way - read the whole file, pretty print
/// it, then hand the result to a single `Text` - makes the main thread decode
/// and lay out megabytes of text before the first frame can be drawn, which is
/// what used to freeze the body screen. This reader keeps a bounded buffer and
/// returns the body in `pageByteLimit` slices, so the first page is on screen
/// almost immediately and the rest follows as the user scrolls.
final class NFXBodyReader: @unchecked Sendable {

    /// Upper bound for the UTF-8 bytes of a single page.
    static let pageByteLimit = 32 * 1024
    /// Upper bound for the number of lines in a single page.
    static let pageLineLimit = 400
    /// Payloads above this size are streamed as they were written:
    /// `JSONSerialization` builds a complete object tree plus a second,
    /// formatted copy of it, which costs far more than the formatting is worth
    /// once the body gets big.
    static let prettyPrintByteLimit = 512 * 1024

    /// A page is never shrunk below this - otherwise a body made of very short
    /// lines would be chopped into thousands of tiny pages.
    private static let minimumPageBytes = pageByteLimit / 4
    private static let newline = UInt8(0x0A)

    /// `true` when the pages carry the formatted (pretty printed) body.
    let isPrettyPrinted: Bool

    private let source: NFXBodySource
    private var stream: InputStream?
    private var bufferedPages: [String]
    private var bufferedIndex = 0
    private var pending = Data()

    init(source: NFXBodySource) {
        self.source = source

        var pages: [String] = []
        var formatted = false

        if source.byteLength > 0,
           source.byteLength <= Self.prettyPrintByteLimit,
           let data = try? Data(contentsOf: source.url),
           let text = source.format?(data),
           text.isEmpty == false {
            pages = Self.pages(from: text)
            formatted = true
        }

        self.bufferedPages = pages
        self.isPrettyPrinted = formatted

        if pages.isEmpty, source.byteLength > 0 {
            let stream = InputStream(url: source.url)
            stream?.open()
            self.stream = stream
        }
    }

    deinit {
        stream?.close()
    }

    /// The next slice of the body, or `nil` once everything has been served.
    ///
    /// Every call reads at most one buffer, so this stays cheap enough to run
    /// while the user is scrolling.
    func nextPage() -> String? {
        guard let stream = stream else {
            guard bufferedIndex < bufferedPages.count else { return nil }
            defer { bufferedIndex += 1 }
            return bufferedPages[bufferedIndex]
        }

        // Fill strictly past one page so `pageCut` can tell "buffer is full"
        // from "end of file" and never cuts a character in half.
        while pending.count <= Self.pageByteLimit {
            guard readMore(from: stream) else { break }
        }

        return pending.isEmpty ? nil : slicePage()
    }

    /// The whole body as one string.
    ///
    /// Only meant for explicit user actions (copy / share): the result is never
    /// rendered, because putting it into a single `Text` is exactly what used
    /// to freeze the screen.
    static func entireText(source: NFXBodySource) -> String {
        let reader = NFXBodyReader(source: source)
        var text = ""
        while let page = reader.nextPage() {
            text += page
        }
        return text
    }

    // MARK: - Streaming

    private func readMore(from stream: InputStream) -> Bool {
        var buffer = [UInt8](repeating: 0, count: Self.pageByteLimit)
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { return false }
        pending.append(contentsOf: buffer[0..<count])
        return true
    }

    private func slicePage() -> String? {
        let cut = Self.pageCut(in: pending)
        let page = String(decoding: pending[..<cut], as: UTF8.self)
        pending.removeSubrange(0..<cut)
        return page
    }

    /// Splits an already formatted body with the very same rules as the
    /// streaming path.
    private static func pages(from text: String) -> [String] {
        var pending = Data(text.utf8)
        var pages: [String] = []

        while pending.isEmpty == false {
            let cut = pageCut(in: pending)
            pages.append(String(decoding: pending[..<cut], as: UTF8.self))
            pending.removeSubrange(0..<cut)
        }

        return pages
    }

    /// Byte offset at which the next page ends.
    private static func pageCut(in data: Data) -> Int {
        var cut = min(data.count, pageByteLimit)

        // Prefer ending on a line break, but never give back more than half of
        // the budget to get one.
        if cut < data.count,
           let newline = data[..<cut].lastIndex(of: Self.newline),
           newline + 1 >= cut / 2 {
            cut = newline + 1
        }

        cut = trimmedToCharacterBoundary(cut, in: data)

        // A few thousand very short lines are as expensive to lay out as one
        // long one, so the line count is bounded too.
        if cut > minimumPageBytes, let boundary = lineBoundary(in: data, before: cut, limit: pageLineLimit) {
            cut = boundary
        }

        return cut
    }

    /// Steps back over the continuation bytes of a character straddling `cut`.
    private static func trimmedToCharacterBoundary(_ cut: Int, in data: Data) -> Int {
        var cut = cut
        while cut > 1, cut < data.count, (data[cut] & 0xC0) == 0x80 {
            cut -= 1
        }
        return cut
    }

    /// Offset just past the `limit`-th line break before `cut`, if there is one.
    private static func lineBoundary(in data: Data, before cut: Int, limit: Int) -> Int? {
        var lines = 0
        for index in 0..<cut where data[index] == Self.newline {
            lines += 1
            if lines == limit { return index + 1 }
        }
        return nil
    }
}

extension NFXHTTPModel {

    /// Everything the body screen needs to read `type` one page at a time.
    func bodySource(for type: NFXBodyType) -> NFXBodySource {
        let isRequest = type == .request

        return NFXBodySource(
            url: isRequest ? getRequestBodyFileURL() : getResponseBodyFileURL(),
            byteLength: isRequest ? requestBodyLength ?? 0 : responseBodyLength ?? 0,
            format: { [weak self] data in
                guard let self else { return nil }
                return self.prettyPrintedBody(data,
                                              contentType: isRequest ? self.requestType : self.responseType)
            }
        )
    }
}
