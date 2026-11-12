//
//  NFXBodyLoader.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

/// Owns the incremental load of one body and exposes it as pages.
///
/// Everything expensive - opening the file, decoding it, reformatting JSON -
/// runs off the main actor, and the body reaches the view in bounded slices so
/// SwiftUI never has to lay out the whole payload at once.
@MainActor
final class NFXBodyLoader: ObservableObject {

    /// Pages read so far.
    @Published private(set) var pages: [NFXBodyPage] = []
    /// `true` once the first page (or the image preview) is available.
    @Published private(set) var isReady = false
    /// `true` once the whole body has been read.
    @Published private(set) var isComplete = false
    /// `true` when the pages carry pretty printed JSON.
    @Published private(set) var isPrettyPrinted = false
    /// `true` when the user asked for this body to be reformatted, whatever
    /// its size.
    @Published private(set) var isFormattingRequested = false
    /// `true` while a (re)format is running.
    @Published private(set) var isFormatting = false
    /// Bytes handed to the view so far.
    @Published private(set) var loadedByteCount = 0
    /// Decoded preview of an image response.
    @Published private(set) var image: Image?
    /// `true` when an image response exists but is too large to decode.
    @Published private(set) var isImageTooLarge = false

    // MARK: - Find in body

    /// Text typed into the find bar. Local to this screen: the request list's
    /// search text lives in `NFXStore` and must not be disturbed.
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var searchResult: NFXTextSearchResult = .empty
    /// Highlight ranges grouped by page index, ready for the lazy stack.
    @Published private(set) var matchRangesByPage: [Int: [NSRange]] = [:]
    /// Bumped whenever the current hit changes. A token - rather than the
    /// hit's id - guarantees a scroll even if the first hit of a new query
    /// happens to sit at exactly the same position.
    @Published private(set) var searchScrollToken = 0
    @Published private(set) var currentMatchIndex: Int? {
        didSet { searchScrollToken += 1 }
    }
    @Published private(set) var isSearching = false

    /// Size of the payload, shown as the "showing X of Y" denominator.
    let byteLength: Int

    /// Only JSON can be reformatted, so nothing else offers the option.
    var canFormat: Bool { model.canFormatBody(bodyType) }

    private let model: NFXHTTPModel
    private let bodyType: NFXBodyType
    private var source: NFXBodySource
    private var reader: NFXBodyReader?
    private var searchTask: Task<Void, Never>?

    /// Pages are appended while scrolling up to this budget: a huge response
    /// must not end up in memory just because the user scrolled past it.
    private static let autoLoadByteBudget = 2 * 1024 * 1024
    /// Bytes brought in before the first frame is drawn.
    private static let initialByteBudget = NFXBodyReader.pageByteLimit
    /// Bytes brought in by one "Load more" tap.
    private static let batchByteBudget = 512 * 1024
    /// Base64 payloads above this are not decoded into an image preview.
    private static let imagePreviewByteLimit = 16 * 1024 * 1024

    init(model: NFXHTTPModel, bodyType: NFXBodyType) {
        self.model = model
        self.bodyType = bodyType
        self.source = model.bodySource(for: bodyType)
        self.byteLength = bodyType == .request ? model.requestBodyLength ?? 0 : model.responseBodyLength ?? 0
    }

    // MARK: - Loading

    /// Opens the file and reads the first page off the main actor.
    func prepare(isImage: Bool) async {
        guard isReady == false else { return }

        let source = self.source
        reader = await Task.detached { NFXBodyReader(source: source) }.value
        isPrettyPrinted = reader?.isPrettyPrinted ?? false

        if isImage {
            await loadImage()
            if image != nil || isImageTooLarge {
                isReady = true
                isComplete = true
                return
            }
        }

        // A page or two is enough for the first frame - and enough to know right
        // away that a short body is already complete. The rest follows on demand.
        append(upTo: Self.initialByteBudget)
        isReady = true
    }

    /// Appends the next batch. Cheap enough to call from the main actor: the
    /// reader only touches one buffer per page.
    func loadMore() {
        append(upTo: Self.batchByteBudget)
    }

    /// Called when a page scrolls into view.
    func loadMoreIfNeeded() {
        guard isReady, isComplete == false, loadedByteCount < Self.autoLoadByteBudget else { return }
        Task { self.loadMore() }
    }

    /// Turns formatting on or off and re-reads the body from scratch.
    ///
    /// Formatting a big body is not free - the whole payload is decoded into
    /// an object tree and formatted into a second copy - so it runs off the
    /// main actor and the caller shows `isFormatting` while it happens.
    func toggleFormatting() {
        guard canFormat, isFormatting == false else { return }

        let requested = isFormattingRequested == false
        isFormatting = true

        Task { @MainActor in
            await reload(forcingFormatting: requested)
            isFormatting = false

            // The payload turned out not to be formattable after all (a body
            // that is not valid JSON, say): leave the toggle where it was.
            if isFormattingRequested, isPrettyPrinted == false {
                isFormattingRequested = false
            }

            // Reformatting changes the page boundaries, so the old hits no
            // longer point at the right text.
            if searchText.isEmpty == false { scheduleSearch() }
        }
    }

    /// The whole body as a single string, read off the main actor.
    ///
    /// Copy / share only - the result is never rendered, because putting it
    /// into a single `Text` is exactly what used to freeze the screen.
    func entireText() async -> String {
        let source = self.source
        return await Task.detached { NFXBodyReader.entireText(source: source) }.value
    }

    // MARK: - Search

    var currentMatch: NFXTextSearchMatch? {
        guard let currentMatchIndex, currentMatchIndex < searchResult.count else { return nil }
        return searchResult.matches[currentMatchIndex]
    }

    func nextMatch() {
        guard searchResult.matches.isEmpty == false else { return }
        currentMatchIndex = ((currentMatchIndex ?? -1) + 1) % searchResult.count
    }

    func previousMatch() {
        guard searchResult.matches.isEmpty == false else { return }
        let count = searchResult.count
        currentMatchIndex = ((currentMatchIndex ?? 0) - 1 + count) % count
    }

    /// Makes sure the page holding a hit exists before the view scrolls to it.
    /// Jumping to a hit is an explicit action, and the lazy stack still only
    /// renders the visible pages.
    func ensurePageIsLoaded(_ pageIndex: Int) {
        while pages.count <= pageIndex, isComplete == false {
            if appendNextPage() == 0 { break }
        }
    }

    /// Debounces typing, then searches a freshly opened reader off the main
    /// actor. Using the same source guarantees the same page boundaries as the
    /// pages already on screen.
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText

        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            searchResult = .empty
            matchRangesByPage = [:]
            currentMatchIndex = nil
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard Task.isCancelled == false else { return }
            await self?.performSearch(query)
        }
    }

    private func performSearch(_ query: String) async {
        let source = self.source
        let result = await Task.detached {
            NFXTextSearch.find(query: query, source: source)
        }.value

        // Typing continued while the file was being read.
        guard searchText == query else { return }

        searchResult = result
        matchRangesByPage = Dictionary(grouping: result.matches, by: \.chunkIndex)
            .mapValues { $0.map(\.range) }
        currentMatchIndex = result.matches.isEmpty ? nil : 0
        isSearching = false
    }

    // MARK: - Internals

    /// Reopens the body file, dropping whatever was served so far.
    private func reload(forcingFormatting: Bool) async {
        let newSource = model.bodySource(for: bodyType, forcesFormatting: forcingFormatting)
        let newReader = await Task.detached { NFXBodyReader(source: newSource) }.value

        source = newSource
        reader = newReader
        isFormattingRequested = forcingFormatting
        isPrettyPrinted = newReader.isPrettyPrinted

        pages.removeAll()
        loadedByteCount = 0
        isComplete = false
        searchResult = .empty
        matchRangesByPage = [:]
        currentMatchIndex = nil

        append(upTo: Self.initialByteBudget)
    }

    private func append(upTo budget: Int) {
        var added = 0

        while added < budget {
            let byteCount = appendNextPage()
            guard byteCount > 0 else { break }
            added += byteCount
        }
    }

    /// Appends a single page and returns how many bytes it added (`0` at the end
    /// of the body).
    @discardableResult
    private func appendNextPage() -> Int {
        guard let page = reader?.nextPage() else {
            isComplete = true
            return 0
        }

        let byteCount = page.utf8.count
        pages.append(NFXBodyPage(index: pages.count, text: page, byteCount: byteCount))
        loadedByteCount += byteCount
        return byteCount
    }

    private func loadImage() async {
        let source = self.source
        let limit = Self.imagePreviewByteLimit
        let decoded = await Task.detached { () -> Data? in
            guard source.byteLength <= limit else { return nil }
            guard let encoded = try? Data(contentsOf: source.url) else { return nil }
            return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
        }.value

        if let decoded {
            image = NFXImageFactory.image(from: decoded)
        } else if source.byteLength > Self.imagePreviewByteLimit {
            isImageTooLarge = true
        }
    }
}
