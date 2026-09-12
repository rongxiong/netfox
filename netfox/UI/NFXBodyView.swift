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

    @State private var text: String = ""
    @State private var image: Image?
    @State private var didLoad = false
    @State private var sharePayload: NFXSharePayload?

    private var isImagePreview: Bool {
        bodyType == .response && model.shortType == .IMAGE
    }

    private var byteLength: Int {
        bodyType == .request ? model.requestBodyLength ?? 0 : model.responseBodyLength ?? 0
    }

    private var title: String {
        switch bodyType {
        case .request: return "Request body"
        case .response: return isImagePreview ? "Image preview" : "Response body"
        }
    }

    var body: some View {
        content
            .background(Color.nfxBackground.ignoresSafeArea())
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Copy") { NFXClipboard.copy(text) }
                        Button("Share") { sharePayload = .text(text, title: title) }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(text.isEmpty)
                }
            }
            .nfxShareSheet(item: $sharePayload)
            .task { loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if didLoad == false {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image = image {
            imagePreview(image)
        } else if text.isEmpty {
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
                    NFXTagView(model.responseType ?? "image", tone: .nfxAccent)
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
        ScrollView {
            HStack {
                Text(text)
                    .font(NFXTheme.mono(12))
                    .foregroundStyle(Color.nfxPrimaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(NFXTheme.Metrics.cardPadding)
        }
        .nfxCard()
        .padding(NFXTheme.Metrics.screenPadding)
    }

    // MARK: - Loading

    private func loadIfNeeded() {
        guard didLoad == false else { return }

        let rawText = bodyType == .request ? model.getRequestBody() : model.getResponseBody()
        text = rawText
        didLoad = true

        guard isImagePreview, rawText.isEmpty == false else { return }

        if let data = Data(base64Encoded: rawText, options: .ignoreUnknownCharacters) {
            image = NFXImageFactory.image(from: data)
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
