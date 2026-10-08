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

    private var isImagePreview: Bool {
        bodyType == .response && model.shortType == .IMAGE
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
                    ZStack {
                        Color.nfxBackground.opacity(0.6).ignoresSafeArea()
                        ProgressView("Reading body…")
                    }
                }
            }
            .task { await loader.prepare(isImage: isImagePreview) }
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
            metaBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(loader.pages) { page in
                        Text(page.text)
                            .font(NFXTheme.mono(12))
                            .foregroundStyle(Color.nfxPrimaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onAppear { loader.loadMoreIfNeeded() }
                    }

                    footerView
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .nfxCard()
        .padding(NFXTheme.Metrics.screenPadding)
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

    @ViewBuilder
    private var footerView: some View {
        if loader.isComplete {
            Text("End of body · \(NFXFormat.bytes(loader.loadedByteCount))")
                .font(.caption2)
                .foregroundStyle(Color.nfxTertiaryText)
                .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Showing \(NFXFormat.bytes(loader.loadedByteCount)) of \(NFXFormat.bytes(byteLength))")
                    .font(.caption2)
                    .foregroundStyle(Color.nfxTertiaryText)

                Button("Load more") { loader.loadMore() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Color.nfxAccent)
            }
            .padding(.vertical, 12)
        }
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
