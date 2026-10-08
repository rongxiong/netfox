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
    /// Bytes handed to the view so far.
    @Published private(set) var loadedByteCount = 0
    /// Decoded preview of an image response.
    @Published private(set) var image: Image?
    /// `true` when an image response exists but is too large to decode.
    @Published private(set) var isImageTooLarge = false

    /// Size of the payload, shown as the "showing X of Y" denominator.
    let byteLength: Int

    private let source: NFXBodySource
    private var reader: NFXBodyReader?

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

    /// The whole body as a single string, read off the main actor.
    ///
    /// Copy / share only - the result is never rendered, because putting it
    /// into a single `Text` is exactly what used to freeze the screen.
    func entireText() async -> String {
        let source = self.source
        return await Task.detached { NFXBodyReader.entireText(source: source) }.value
    }

    // MARK: - Internals

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
