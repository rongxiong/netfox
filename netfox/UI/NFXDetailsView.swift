//
//  NFXDetailsView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

struct NFXDetailsView: View {

    private enum Tab: String, CaseIterable, Identifiable {
        case info = "Info"
        case request = "Request"
        case response = "Response"

        var id: String { rawValue }
    }

    let model: NFXHTTPModel

    @State private var selection: Tab = .info
    @State private var content: NFXDetailsContent
    @State private var sharePayload: NFXSharePayload?

    init(model: NFXHTTPModel) {
        self.model = model
        _content = State(initialValue: NFXContentBuilder.details(for: model))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NFXTheme.Metrics.sectionSpacing) {
                overviewCard

                Picker("Section", selection: $selection) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(NFXAccessibility.Details.picker)

                tabContent
            }
            .padding(NFXTheme.Metrics.screenPadding)
            .animation(.easeOut(duration: 0.2), value: selection)
        }
        .background(Color.nfxBackground.ignoresSafeArea())
        .navigationTitle("Details")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                shareMenu
            }
        }
        .nfxShareSheet(item: $sharePayload)
    }

    // MARK: - Overview

    private var overviewCard: some View {
        HStack(alignment: .center, spacing: 12) {
            NFXStatusPill(status: content.statusCode)
            NFXMethodBadge(method: model.requestMethod ?? "-")

            if model.isMocked {
                NFXTagView("MOCK")
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(NFXFormat.duration(model.noResponse ? nil : model.timeInterval))
                    .font(NFXTheme.mono(13, weight: .semibold))
                    .foregroundStyle(Color.nfxPrimaryText)
                Text(model.requestDate.map { NFXFormat.clockTime($0) } ?? "--:--")
                    .font(.caption2)
                    .foregroundStyle(Color.nfxTertiaryText)
                    .monospacedDigit()
            }
        }
        .nfxCard()
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .info:
            infoTab
                .accessibilityIdentifier(NFXAccessibility.Details.info)
        case .request:
            sectionView(content.request)
                .accessibilityIdentifier(NFXAccessibility.Details.request)
        case .response:
            responseTab
                .accessibilityIdentifier(NFXAccessibility.Details.response)
        }
    }

    private var infoTab: some View {
        VStack(alignment: .leading, spacing: NFXTheme.Metrics.sectionSpacing) {
            NFXSectionCard(title: "Request information") {
                NFXKeyValueRows(fields: content.info.fields)
            }

            if content.hasQueryItems {
                NFXSectionCard {
                    NFXNavigationRow(icon: "list.bullet",
                                     title: "Query strings",
                                     detail: "\(model.requestURLQueryItems?.count ?? 0) items") {
                        NFXQueryItemsView(model: model)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var responseTab: some View {
        if let response = content.response {
            sectionView(response)
        } else {
            NFXEmptyStateView(systemImage: "exclamationmark.bubble",
                              title: "No response",
                              message: "This request has not been answered yet, or it failed before a response was received.")
                .frame(minHeight: 220)
                .nfxCard()
        }
    }

    private func sectionView(_ section: NFXContentSection) -> some View {
        VStack(alignment: .leading, spacing: NFXTheme.Metrics.sectionSpacing) {
            NFXSectionCard(title: "Headers") {
                if section.fields.isEmpty {
                    NFXPlaceholderRow(text: "Headers are empty")
                } else {
                    NFXKeyValueRows(fields: section.fields)
                }
            }

            if let body = section.body {
                bodyCard(body)
            }
        }
    }

    private func bodyCard(_ body: NFXContentBody) -> some View {
        NFXSectionCard(title: body.type == .request ? "Request body" : "Response body") {
            VStack(alignment: .leading, spacing: 10) {
                if body.isEmpty {
                    NFXPlaceholderRow(text: "Body is empty")
                } else if body.isTruncated {
                    Label("Too long to preview (\(NFXFormat.bytes(body.byteLength)))",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.nfxWarning)

                    NFXNavigationRow(icon: "text.alignleft", title: "Show full body", detail: nil) {
                        NFXBodyView(model: model, bodyType: body.type)
                    }
                } else if let text = body.text {
                    NFXCodeBlock(text: text)

                    HStack(spacing: 12) {
                        NFXCopyButton(text: text, showsLabel: true)
                        Spacer()
                        NFXNavigationRow(icon: "arrow.up.left.and.arrow.down.right",
                                         title: "Open full body",
                                         detail: nil) {
                            NFXBodyView(model: model, bodyType: body.type)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Sharing

    private var shareMenu: some View {
        Menu {
            Button("Simple log") {
                sharePayload = .text(NFXContentBuilder.plainTextLog(for: model, full: false), title: "Simple log")
            }
            Button("Full log") {
                sharePayload = .text(NFXContentBuilder.plainTextLog(for: model, full: true), title: "Full log")
            }
            if let curl = model.requestCurl, curl.isEmpty == false {
                Button("Export request as curl") {
                    sharePayload = .text(curl, title: "curl")
                }
            }
            Button("Copy URL") {
                NFXClipboard.copy(model.requestURL ?? "")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}

// MARK: - Small helpers

/// Disclosure-style row pushing `destination`.
struct NFXNavigationRow<Destination: View>: View {

    let icon: String
    let title: String
    let detail: String?
    let destination: Destination

    init(icon: String, title: String, detail: String? = nil, @ViewBuilder destination: () -> Destination) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.nfxAccent)
                    .frame(width: 20)
                Text(title)
                    .foregroundStyle(Color.nfxPrimaryText)
                Spacer(minLength: 8)
                if let detail = detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.nfxTertiaryText)
                }
            }
            .font(.subheadline)
        }
        .tint(Color.nfxAccent)
    }
}

struct NFXPlaceholderRow: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.nfxTertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
