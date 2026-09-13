//
//  NFXRequestRowView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

/// Card used by the request list. Kept intentionally flat (no nested stacks with
/// expensive layout) so scrolling through thousands of rows stays smooth.
struct NFXRequestRowView: View {

    let model: NFXHTTPModel
    let isUnread: Bool

    private var tone: NFXStatusTone {
        NFXStatusTone.tone(for: model.noResponse ? nil : model.responseStatus)
    }

    private var url: String { model.requestURL ?? "-" }
    private var method: String { model.requestMethod ?? "-" }
    private var responseType: String? { model.noResponse ? nil : model.responseType }

    private var durationText: String {
        NFXFormat.duration(model.noResponse ? nil : model.timeInterval)
    }

    private var timeText: String {
        guard let date = model.requestDate else { return "--:--" }
        return NFXFormat.clockTime(date)
    }

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(tone.color)
                .frame(width: NFXTheme.Metrics.stripeWidth)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    NFXMethodBadge(method: method)
                    NFXStatusPill(status: model.noResponse ? nil : model.responseStatus)

                    Spacer(minLength: 4)

                    if model.isMocked {
                        NFXTagView("MOCK")
                    }
                    if isUnread {
                        NFXUnreadDot()
                    }
                }

                Text(url)
                    .font(.footnote)
                    .foregroundStyle(Color.nfxPrimaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    meta(icon: "timer", text: durationText)

                    if let responseType = responseType {
                        meta(icon: "doc.text", text: responseType)
                    }

                    Spacer(minLength: 0)

                    Text(timeText)
                        .font(NFXTheme.mono(11))
                        .foregroundStyle(Color.nfxTertiaryText)
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 10)
        .padding(.trailing, 12)
        .padding(.leading, 6)
        .background(Color.nfxCard, in: RoundedRectangle(cornerRadius: NFXTheme.Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NFXTheme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.nfxSeparator.opacity(0.25), lineWidth: 1)
        )
    }

    private func meta(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(text)
                .lineLimit(1)
        }
        .foregroundStyle(Color.nfxSecondaryText)
    }
}
