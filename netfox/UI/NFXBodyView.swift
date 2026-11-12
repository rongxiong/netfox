//
//  NFXBodyView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct NFXBodyView: View {

    let model: NFXHTTPModel
    let bodyType: NFXBodyType

    @StateObject private var loader: NFXBodyLoader
    @State private var sharePayload: NFXSharePayload?
    @State private var isExporting = false
    @State private var showsSearch = false
    @State private var resetScrollToken = 0

    private var isImagePreview: Bool {
        bodyType == .response && model.shortType == .IMAGE
    }

    /// Find is offered on text responses only - image previews and request
    /// bodies have no response text lines to search.
    private var canSearch: Bool {
        bodyType == .response && isImagePreview == false && loader.image == nil
    }

    private var byteLength: Int { loader.byteLength }

    private var title: String {
        switch bodyType {
        case .request: return "Request body"
        case .response: return isImagePreview ? "Image preview" : "Response body"
        }
    }

    init(model: NFXHTTPModel, bodyType: NFXBodyType) {
        self.model = model
        self.bodyType = bodyType
        _loader = StateObject(wrappedValue: NFXBodyLoader(model: model, bodyType: bodyType))
    }

    var body: some View {
        content
            .background(Color.nfxBackground.ignoresSafeArea())
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showsSearch = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .disabled(canSearch == false || loader.pages.isEmpty)
                    .keyboardShortcut("f", modifiers: .command)
                    .accessibilityIdentifier(NFXAccessibility.Search.toggle)
                }
                ToolbarItem(placement: .automatic) {
                    formatButton
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Copy") { export { NFXClipboard.copy($0) } }
                        Button("Share") { export { sharePayload = .text($0, title: title) } }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(loader.pages.isEmpty && loader.image == nil)
                }
            }
            .nfxShareSheet(item: $sharePayload)
            .overlay {
                if isExporting {
                    overlay(message: "Reading body…")
                } else if loader.isFormatting {
                    overlay(message: "Formatting body…")
                }
            }
            .task { await loader.prepare(isImage: isImagePreview) }
    }

    // MARK: - Formatting

    /// Formatting is opt-in: bodies past `prettyPrintByteLimit` are streamed
    /// as they arrived, and reformatting one is the user's call.
    private var formatButton: some View {
        Button {
            loader.toggleFormatting()
        } label: {
            Label(loader.isFormattingRequested ? "Raw" : "Format",
                  systemImage: loader.isFormattingRequested ? "text.alignleft" : "curlybraces")
        }
        .disabled(loader.canFormat == false)
        .accessibilityIdentifier(NFXAccessibility.Body.format)
    }

    private func overlay(message: String) -> some View {
        return ZStack {
            Color.nfxBackground.opacity(0.6).ignoresSafeArea()
            ProgressView(message)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loader.isReady == false {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image = loader.image {
            imagePreview(image)
        } else if loader.isImageTooLarge {
            NFXEmptyStateView(systemImage: "photo",
                              title: "Image is too large",
                              message: "This response is \(NFXFormat.bytes(byteLength)). Only images up to a few megabytes are previewed.")
        } else if loader.pages.isEmpty {
            NFXEmptyStateView(systemImage: "doc.text",
                              title: "Body is empty",
                              message: "This \(bodyType == .request ? "request" : "response") did not carry any body data.")
        } else {
            textContent
        }
    }

    private func imagePreview(_ image: Image) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NFXTheme.Metrics.rowSpacing) {
                HStack(spacing: 10) {
                    NFXTagView(contentType ?? "image", tone: .nfxAccent)
                    Text(NFXFormat.bytes(byteLength))
                        .font(.caption)
                        .foregroundStyle(Color.nfxTertiaryText)
                    Spacer()
                }

                image
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .nfxCard()
            }
            .padding(NFXTheme.Metrics.screenPadding)
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The find bar is a separate toolbar above the body card, not part
            // of the text container itself.
            if showsSearch && canSearch {
                NFXSearchBar(text: $loader.searchText,
                             prompt: "Search in response body",
                             matchCount: loader.searchResult.count,
                             isTruncated: loader.searchResult.isTruncated,
                             isSearching: loader.isSearching,
                             currentIndex: loader.currentMatchIndex,
                             onPrevious: { loader.previousMatch() },
                             onNext: { loader.nextMatch() },
                             onClose: closeSearch)
            }

            VStack(alignment: .leading, spacing: 10) {
                metaBar

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // Stable anchor for returning to the first line
                            // when the find bar closes.
                            Color.clear
                                .frame(height: 1)
                                .id(NFXSearchScroll.topAnchor)

                            // Rows are always rendered line by line. Switching
                            // between one big `Text` per page and per-line
                            // views left the lazy stack with a stale layout, so
                            // the body looked empty once search was closed.
                            ForEach(loader.pages) { page in
                                NFXHighlightedLines(chunkIndex: page.index,
                                                    text: page.text,
                                                    ranges: loader.matchRangesByPage[page.index] ?? [],
                                                    currentRange: loader.currentMatch?.chunkIndex == page.index
                                                        ? loader.currentMatch?.range : nil)
                                    .onAppear { loader.loadMoreIfNeeded() }
                            }

                            footerView
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: loader.searchScrollToken) { _ in
                        scrollToCurrentMatch(proxy)
                    }
                    .onChange(of: resetScrollToken) { _ in
                        NFXSearchScroll.perform(proxy, to: NFXSearchScroll.topAnchor)
                    }
                }
            }
            .nfxCard()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(NFXTheme.Metrics.screenPadding)
    }

    private func closeSearch() {
        // Cancel the delayed follow-up scroll before collapsing the rows. The
        // body is brought back to its first line only after the rows have
        // switched back and the keyboard started dismissing - scrolling in the
        // middle of that relayout can leave the text off-screen.
        NFXSearchScroll.cancel()
        showsSearch = false
        loader.searchText = ""
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            resetScrollToken += 1
        }
    }

    /// A hit may sit on a page that has not been read yet. Load up to it, then
    /// scroll to the exact line (not the beginning of its 32 KB page).
    private func scrollToCurrentMatch(_ proxy: ScrollViewProxy) {
        guard let match = loader.currentMatch else { return }
        loader.ensurePageIsLoaded(match.chunkIndex)
        guard match.chunkIndex < loader.pages.count else { return }

        let anchor = NFXTextSearch.anchor(for: match, in: loader.pages[match.chunkIndex].text)
        NFXSearchScroll.perform(proxy, to: anchor)
    }

    private var contentType: String? {
        bodyType == .request ? model.requestType : model.responseType
    }

    private var metaBar: some View {
        HStack(spacing: 8) {
            NFXTagView(contentType ?? (bodyType == .request ? "request" : "response"), tone: .nfxAccent)

            if loader.isPrettyPrinted {
                NFXTagView("PRETTY", tone: .nfxSuccess)
            }

            Spacer(minLength: 8)

            Text(NFXFormat.bytes(byteLength))
                .font(.caption)
                .foregroundStyle(Color.nfxTertiaryText)
        }
    }

    private var footerView: some View {
        VStack(spacing: 8) {
            if loader.isComplete {
                Text("End of body · \(NFXFormat.bytes(loader.loadedByteCount))")
                    .font(.caption2)
                    .foregroundStyle(Color.nfxTertiaryText)
            } else {
                Text("Showing \(NFXFormat.bytes(loader.loadedByteCount)) of \(NFXFormat.bytes(byteLength))")
                    .font(.caption2)
                    .foregroundStyle(Color.nfxTertiaryText)

                Button("Load more") { loader.loadMore() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Color.nfxAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    /// Copy / share need the whole body, which is read in one go - but off the
    /// main actor and without ever being rendered.
    private func export(_ action: @escaping (String) -> Void) {
        guard isExporting == false else { return }
        isExporting = true

        Task { @MainActor in
            let text = await loader.entireText()
            isExporting = false
            guard text.isEmpty == false else { return }
            action(text)
        }
    }
}

enum NFXImageFactory {

    static func image(from data: Data) -> Image? {
        #if os(iOS)
        guard let platformImage = UIImage(data: data) else { return nil }
        return Image(uiImage: platformImage)
        #else
        guard let platformImage = NSImage(data: data) else { return nil }
        return Image(nsImage: platformImage)
        #endif
    }
}
