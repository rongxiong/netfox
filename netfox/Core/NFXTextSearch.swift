//
//  NFXTextSearch.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import Foundation

/// One hit inside text that is rendered as a sequence of chunks (body pages,
/// header rows, …). `range` is a UTF-16 range within that chunk - the units
/// `NSRange` and `AttributedString` use for highlighting.
struct NFXTextSearchMatch: Equatable, Sendable, Identifiable {

    let chunkIndex: Int
    let range: NSRange

    var id: String { "\(chunkIndex)-\(range.location)-\(range.length)" }
}

struct NFXTextSearchResult: Equatable, Sendable {

    var matches: [NFXTextSearchMatch] = []
    /// `true` when the match budget was reached, so the count is a lower bound.
    var isTruncated = false

    static let empty = NFXTextSearchResult()

    var count: Int { matches.count }
}

/// Find-in-response engine, shared by the Response tab and the full body screen.
///
/// Big bodies are displayed page by page (`NFXBodyReader`), so a query can
/// straddle two pages. Search runs over a sliding window made of the tail of
/// the previous chunk plus the current one, keeping only the matches - never
/// the whole payload - in memory.
enum NFXTextSearch {

    /// A response full of a very common letter must not produce millions of
    /// ranges: each one would also have to be highlighted in the UI.
    static let matchLimit = 2_000

    /// Case- and diacritic-insensitive, non-overlapping ranges of `query`.
    static func ranges(of query: String, in text: String, limit: Int = matchLimit) -> [NSRange] {
        guard query.isEmpty == false, limit > 0, text.isEmpty == false else { return [] }

        var result: [NSRange] = []
        var searchRange = text.startIndex..<text.endIndex
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        while result.count < limit,
              let found = text.range(of: query, options: options, range: searchRange, locale: nil) {
            result.append(NSRange(found, in: text))
            guard found.upperBound < text.endIndex else { break }
            searchRange = found.upperBound..<text.endIndex
        }

        return result
    }

    /// Searches chunks that are already in memory. `joinsChunks` is `false` for
    /// independent rows (headers) and `true` for consecutive body pages.
    static func find(query: String,
                     in chunks: [String],
                     joinsChunks: Bool = true,
                     limit: Int = matchLimit) -> NFXTextSearchResult {
        var iterator = chunks.makeIterator()
        return find(query: query, joinsChunks: joinsChunks, limit: limit) { iterator.next() }
    }

    /// Streams a body straight from disk with the very same paging rules the
    /// screen uses, so every hit points at an existing `NFXBodyPage.index`.
    static func find(query: String,
                     source: NFXBodySource,
                     limit: Int = matchLimit) -> NFXTextSearchResult {
        let reader = NFXBodyReader(source: source)
        return find(query: query, joinsChunks: true, limit: limit) { reader.nextPage() }
    }

    /// Lazily pulls chunks, so even a multi-megabyte body is searched without
    /// ever being materialised as a single string.
    static func find(query: String,
                     joinsChunks: Bool = true,
                     limit: Int = matchLimit,
                     reading nextChunk: () -> String?) -> NFXTextSearchResult {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              limit > 0 else { return .empty }

        // Carrying `query.count - 1` characters from the previous chunk covers
        // every possible split. Capped because paging never cuts a character,
        // and a pathological query should not drag a huge window around.
        let carry = joinsChunks ? min(max(query.count - 1, 0), 256) : 0

        var matches: [NFXTextSearchMatch] = []
        var chunkIndex = 0
        var carried = ""
        var previousChunkIndex = -1
        var previousChunkUTF16Length = 0

        while let chunk = nextChunk() {
            let window = carried.isEmpty ? chunk : carried + chunk
            let carriedLength = window.utf16.count - chunk.utf16.count
            let windowRanges = ranges(of: query, in: window, limit: limit - matches.count + 1)

            for range in windowRanges {
                let start = range.location
                let end = NSMaxRange(range)

                // Already reported while searching the previous chunk.
                guard end > carriedLength else { continue }
                guard matches.count < limit else {
                    return NFXTextSearchResult(matches: matches, isTruncated: true)
                }

                if start < carriedLength {
                    // The hit straddles the boundary: highlight the part living
                    // on the previous page, and count the hit only once.
                    let previousStart = previousChunkUTF16Length - carriedLength + start
                    matches.append(NFXTextSearchMatch(
                        chunkIndex: previousChunkIndex,
                        range: NSRange(location: previousStart,
                                       length: previousChunkUTF16Length - previousStart)))
                } else {
                    matches.append(NFXTextSearchMatch(
                        chunkIndex: chunkIndex,
                        range: NSRange(location: start - carriedLength, length: range.length)))
                }
            }

            guard matches.count < limit else {
                return NFXTextSearchResult(matches: matches, isTruncated: true)
            }

            if carry > 0 {
                carried = String(chunk.suffix(carry))
                previousChunkIndex = chunkIndex
                previousChunkUTF16Length = chunk.utf16.count
            }
            chunkIndex += 1
        }

        return NFXTextSearchResult(matches: matches, isTruncated: false)
    }
}

// MARK: - Line anchors

/// A display line inside one chunk. `start` is its UTF-16 offset in the chunk.
struct NFXTextLine: Equatable, Sendable, Identifiable {

    let index: Int
    let text: String
    let start: Int

    var id: Int { index }
}

extension NFXTextSearch {

    /// `ScrollViewProxy` anchor for a single text line.
    static func lineID(chunk: Int, line: Int) -> String {
        "nfx.line.\(chunk).\(line)"
    }

    /// Splits a chunk into lines. Empty lines are kept so the offsets stay
    /// truthful; a newline-terminated body simply ends with an empty row.
    static func lines(in text: String) -> [NFXTextLine] {
        let pieces = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [NFXTextLine] = []
        result.reserveCapacity(pieces.count)

        var offset = 0
        for (index, piece) in pieces.enumerated() {
            let line = String(piece)
            result.append(NFXTextLine(index: index, text: line, start: offset))
            offset += line.utf16.count + 1
        }
        return result
    }

    /// Line whose UTF-16 span contains `location`.
    static func line(containing location: Int, in lines: [NFXTextLine]) -> NFXTextLine? {
        guard let first = lines.first, location >= first.start else { return lines.first }

        for (index, line) in lines.enumerated() {
            let nextStart = index + 1 < lines.count ? lines[index + 1].start : Int.max
            if location < nextStart { return line }
        }
        return lines.last
    }

    /// Chunk-level ranges clipped to the line each one starts on.
    static func lineRanges(from ranges: [NSRange], in lines: [NFXTextLine]) -> [Int: [NSRange]] {
        var result: [Int: [NSRange]] = [:]
        for range in ranges {
            guard let line = line(containing: range.location, in: lines),
                  let clipped = clipped(range, to: line) else { continue }
            result[line.index, default: []].append(clipped)
        }
        return result
    }

    static func clipped(_ range: NSRange, to line: NFXTextLine) -> NSRange? {
        let start = max(0, range.location - line.start)
        let end = min(line.text.utf16.count, NSMaxRange(range) - line.start)
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    /// Scroll anchor for a hit: the exact text line it starts on, not the
    /// beginning of the (up to 32 KB) page that contains it.
    static func anchor(for match: NFXTextSearchMatch, in text: String) -> String {
        let line = line(containing: match.range.location, in: lines(in: text))
        return lineID(chunk: match.chunkIndex, line: line?.index ?? 0)
    }
}
