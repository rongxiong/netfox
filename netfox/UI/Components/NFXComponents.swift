//
//  NFXComponents.swift
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

// MARK: - Clipboard

enum NFXClipboard {

    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Status

struct NFXStatusPill: View {

    let status: Int?

    private var tone: NFXStatusTone { NFXStatusTone.tone(for: status) }

    private var label: String {
        guard let status = status, status != 999 else { return "—" }
        return "\(status)"
    }

    var body: some View {
        Text(label)
            .font(NFXTheme.mono(11, weight: .semibold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.color.opacity(0.16), in: Capsule())
            .accessibilityLabel("Status \(label)")
    }
}

struct NFXUnreadDot: View {

    var body: some View {
        Circle()
            .fill(Color.nfxAccent)
            .frame(width: 7, height: 7)
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Method

struct NFXMethodBadge: View {

    let method: String

    private var tint: Color {
        switch method.uppercased() {
        case "GET": return .nfxAccent
        case "POST": return .nfxSuccess
        case "PUT", "PATCH": return .nfxWarning
        case "DELETE": return .nfxFailure
        default: return .nfxNeutral
        }
    }

    var body: some View {
        Text(method.uppercased())
            .font(NFXTheme.mono(10, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: NFXTheme.Metrics.chipRadius, style: .continuous))
    }
}

// MARK: - Tag

struct NFXTagView: View {

    let text: String
    let tone: Color

    init(_ text: String, tone: Color = .nfxWarning) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(NFXTheme.mono(9, weight: .bold))
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tone.opacity(0.14), in: RoundedRectangle(cornerRadius: NFXTheme.Metrics.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NFXTheme.Metrics.chipRadius, style: .continuous)
                    .strokeBorder(tone.opacity(0.45), lineWidth: 1)
            )
    }
}

// MARK: - Copy

struct NFXCopyButton: View {

    let text: String
    var showsLabel = false

    @State private var didCopy = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 4) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .imageScale(.small)
                if showsLabel {
                    Text(didCopy ? "Copied" : "Copy")
                        .font(.caption.weight(.medium))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(didCopy ? Color.nfxSuccess : Color.nfxSecondaryText)
        .animation(.easeInOut(duration: 0.15), value: didCopy)
    }

    private func copy() {
        NFXClipboard.copy(text)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopy = false
        }
    }
}

// MARK: - Rows

struct NFXKeyValueRow: View {

    let field: NFXContentField

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(field.key)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.nfxTertiaryText)
                Spacer(minLength: 8)
                NFXCopyButton(text: field.value)
            }

            Text(field.value)
                .font(.subheadline)
                .foregroundStyle(Color.nfxPrimaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button {
                NFXClipboard.copy(field.value)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

struct NFXKeyValueRows: View {

    let fields: [NFXContentField]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fields) { field in
                NFXKeyValueRow(field: field)

                if field.id != fields.last?.id {
                    Divider().overlay(Color.nfxSeparator.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - Cards

struct NFXSectionCard<Content: View>: View {

    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NFXTheme.Metrics.rowSpacing) {
            if let title = title {
                HStack {
                    NFXSectionLabel(title: title)
                    Spacer()
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nfxCard()
    }
}

struct NFXMetricCard: View {

    let title: String
    let value: String
    let subtitle: String?
    let tone: Color

    init(title: String, value: String, subtitle: String? = nil, tone: Color = .nfxAccent) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.tone = tone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.nfxSecondaryText)

            NFXAnimatedNumber(value: value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.nfxPrimaryText)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.nfxTertiaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NFXTheme.Metrics.cardPadding)
        .background(Color.nfxCard, in: RoundedRectangle(cornerRadius: NFXTheme.Metrics.cardRadius, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tone)
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: NFXTheme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.nfxSeparator.opacity(0.25), lineWidth: 1)
        )
    }
}

struct NFXRatioBar: View {

    let successRatio: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.nfxNeutral.opacity(0.2))

                Capsule()
                    .fill(LinearGradient(colors: [Color.nfxSuccess, Color.nfxSuccess.opacity(0.65)],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(width: max(0, proxy.size.width * successRatio))
            }
        }
        .frame(height: 8)
        .animation(.easeInOut(duration: 0.35), value: successRatio)
    }
}

/// Rounded, monospaced body container used by the details and body screens.
struct NFXCodeBlock: View {

    let text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(NFXTheme.mono(12))
                .foregroundStyle(Color.nfxPrimaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.nfxInsetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
