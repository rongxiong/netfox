//
//  NFXSearchViews.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

/// Text with every match tinted and the current one picked out.
///
/// With no ranges this renders exactly like a plain `Text`, so screens that
/// are not being searched stay pixel-identical. Font and foreground colour are
/// left to the caller; only the hit runs carry their own attributes.
struct NFXHighlightedText: View {

    let text: String
    let ranges: [NSRange]
    var currentRange: NSRange? = nil

    var body: some View {
        Group {
            if ranges.isEmpty {
                Text(text)
            } else {
                Text(highlighted)
            }
        }
    }

    private var highlighted: AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex

        for range in ranges {
            guard let swiftRange = Range(range, in: text), swiftRange.lowerBound >= cursor else { continue }

            if cursor < swiftRange.lowerBound {
                result += AttributedString(String(text[cursor..<swiftRange.lowerBound]))
            }

            var hit = AttributedString(String(text[swiftRange]))
            let isCurrent = range == currentRange
            hit.backgroundColor = isCurrent ? Color.nfxWarning.opacity(0.9) : Color.nfxWarning.opacity(0.32)
            hit.foregroundColor = isCurrent ? Color.black : Color.nfxPrimaryText
            result += hit
            cursor = swiftRange.upperBound
        }

        if cursor < text.endIndex {
            result += AttributedString(String(text[cursor...]))
        }
        return result
    }
}

/// Find bar shown above the response content: query, match counter and
/// previous / next navigation.
struct NFXSearchBar: View {

    @Binding var text: String

    var prompt: String = "Search in response body"
    let matchCount: Int
    let isTruncated: Bool
    let isSearching: Bool
    let currentIndex: Int?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @FocusState private var isFocused: Bool

    private var hasQuery: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var status: String {
        guard hasQuery else { return "" }
        if isSearching, matchCount == 0 { return "Searching…" }
        if matchCount == 0 { return "No matches" }
        return "\((currentIndex ?? 0) + 1) of \(matchCount)\(isTruncated ? "+" : "")"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(Color.nfxSecondaryText)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit(onNext)
                .frame(minWidth: 80)
                .accessibilityIdentifier(NFXAccessibility.Search.field)

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(Color.nfxTertiaryText)
                }
                .accessibilityLabel("Clear search")
            }

            if status.isEmpty == false {
                Text(status)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(matchCount == 0 && isSearching == false
                                     ? Color.nfxFailure : Color.nfxSecondaryText)
                    .lineLimit(1)
                    .accessibilityIdentifier(NFXAccessibility.Search.status)
            }

            Button(action: onPrevious) {
                Image(systemName: "chevron.up").imageScale(.small)
            }
            .foregroundStyle(Color.nfxAccent)
            .disabled(matchCount == 0)
            .accessibilityLabel("Previous match")
            .accessibilityIdentifier(NFXAccessibility.Search.previous)

            Button(action: onNext) {
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .foregroundStyle(Color.nfxAccent)
            .disabled(matchCount == 0)
            .accessibilityLabel("Next match")
            .accessibilityIdentifier(NFXAccessibility.Search.next)

            Button(action: onClose) {
                Image(systemName: "xmark").imageScale(.small)
            }
            .foregroundStyle(Color.nfxSecondaryText)
            .accessibilityLabel("Close search")
            .accessibilityIdentifier(NFXAccessibility.Search.close)
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(Color.nfxInsetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { isFocused = true }
    }
}

/// Renders a text block line by line while a search is active.
///
/// A single page can be 32 KB (hundreds of lines), so a page-level anchor is
/// not enough: the hit may sit far below the visible part of the page. Each
/// line carries its own `ScrollViewProxy` id instead.
struct NFXHighlightedLines: View {

    let chunkIndex: Int
    let text: String
    let ranges: [NSRange]
    let currentRange: NSRange?
    var font: Font = NFXTheme.mono(12)
    var color: Color = Color.nfxPrimaryText

    var body: some View {
        let lines = NFXTextSearch.lines(in: text)
        let mapped = NFXTextSearch.lineRanges(from: ranges, in: lines)
        let currentLine = currentRange.flatMap { NFXTextSearch.line(containing: $0.location, in: lines)?.index }

        return ForEach(lines) { line in
            // A single space keeps empty lines at their normal height.
            NFXHighlightedText(text: line.text.isEmpty ? " " : line.text,
                               ranges: mapped[line.index] ?? [],
                               currentRange: line.index == currentLine
                                   ? currentRange.flatMap { NFXTextSearch.clipped($0, to: line) }
                                   : nil)
                .font(font)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(NFXTextSearch.lineID(chunk: chunkIndex, line: line.index))
        }
    }
}

@MainActor
enum NFXSearchScroll {

    /// Anchor that always exists at the very top of a body's scroll content.
    static let topAnchor = "nfx.body.top"

    private static var pending: Task<Void, Never>?

    /// Drop the delayed follow-up scroll - used when the find bar closes, so a
    /// stale anchor cannot move the text after the rows have been collapsed.
    static func cancel() {
        pending?.cancel()
        pending = nil
    }

    /// The target line may only just have been rendered (a newly loaded page,
    /// the find bar appearing, the keyboard animating). Scroll once now and
    /// again when things settle; newer requests cancel older ones. Anchoring at
    /// the top keeps a hit visible without empty space below the body.
    static func perform(_ proxy: ScrollViewProxy, to anchor: String) {
        pending?.cancel()

        // Scroll with the proxy while it is known to be current, then repeat
        // after the keyboard / paging animation has settled.
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }

        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }
}
