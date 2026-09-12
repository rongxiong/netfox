//
//  NFXTheme.swift
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

// MARK: - Semantic colors

extension Color {

    /// Window / screen background behind the cards.
    static var nfxBackground: Color {
        #if os(iOS)
        Color(UIColor.systemGroupedBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    /// Surface of a card sitting on `nfxBackground`.
    static var nfxCard: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemGroupedBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }

    /// Surface used for nested / highlighted elements inside a card.
    static var nfxInsetSurface: Color {
        #if os(iOS)
        Color(UIColor.tertiarySystemFill)
        #else
        Color(NSColor.quaternaryLabelColor).opacity(0.35)
        #endif
    }

    static var nfxSeparator: Color {
        #if os(iOS)
        Color(UIColor.separator)
        #else
        Color(NSColor.separatorColor)
        #endif
    }

    static var nfxPrimaryText: Color {
        #if os(iOS)
        Color(UIColor.label)
        #else
        Color(NSColor.labelColor)
        #endif
    }

    static var nfxSecondaryText: Color {
        #if os(iOS)
        Color(UIColor.secondaryLabel)
        #else
        Color(NSColor.secondaryLabelColor)
        #endif
    }

    static var nfxTertiaryText: Color {
        #if os(iOS)
        Color(UIColor.tertiaryLabel)
        #else
        Color(NSColor.tertiaryLabelColor)
        #endif
    }

    static var nfxAccent: Color { Color(hex: 0x007AFF) }
    static var nfxAccentAlt: Color { Color(hex: 0x5E5CE6) }

    static var nfxSuccess: Color { Color(hex: 0x34C759) }
    static var nfxFailure: Color { Color(hex: 0xFF453A) }
    static var nfxWarning: Color { Color(hex: 0xFF9F0A) }
    static var nfxNeutral: Color { Color(hex: 0x8E8E93) }

    /// Brand-free hex initializer kept for the few tokens that are not covered
    /// by the semantic platform colors.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0

        #if os(iOS)
        self.init(UIColor(red: red, green: green, blue: blue, alpha: opacity))
        #else
        self.init(NSColor(red: red, green: green, blue: blue, alpha: opacity))
        #endif
    }
}

// MARK: - Status semantics

enum NFXStatusTone {
    case success
    case failure
    case warning
    case neutral

    var color: Color {
        switch self {
        case .success: return .nfxSuccess
        case .failure: return .nfxFailure
        case .warning: return .nfxWarning
        case .neutral: return .nfxNeutral
        }
    }

    /// `nil` (or `999`, the marker used for requests without a response) is neutral.
    static func tone(for status: Int?) -> NFXStatusTone {
        guard let status = status, status != 999 else { return .neutral }

        switch status {
        case ..<300: return .success
        case 300..<400: return .warning
        default: return .failure
        }
    }
}

// MARK: - Tokens

enum NFXTheme {

    enum Metrics {
        static let screenPadding: CGFloat = 16
        static let cardPadding: CGFloat = 14
        static let cardRadius: CGFloat = 16
        static let pillRadius: CGFloat = 10
        static let chipRadius: CGFloat = 6
        static let sectionSpacing: CGFloat = 16
        static let rowSpacing: CGFloat = 10
        static let stripeWidth: CGFloat = 4
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Card style

struct NFXCardModifier: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(NFXTheme.Metrics.cardPadding)
            .background(Color.nfxCard, in: RoundedRectangle(cornerRadius: NFXTheme.Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NFXTheme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Color.nfxSeparator.opacity(colorScheme == .dark ? 0.6 : 0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.06),
                    radius: colorScheme == .dark ? 10 : 8,
                    x: 0,
                    y: colorScheme == .dark ? 0 : 2)
    }
}

extension View {
    func nfxCard() -> some View { modifier(NFXCardModifier()) }
}

/// Section titles used above / inside the cards.
struct NFXSectionLabel: View {

    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.nfxTertiaryText)
    }
}

/// Values grow / shrink without jittering the layout.
struct NFXAnimatedNumber: View {

    let value: String

    var body: some View {
        Text(value)
            .monospacedDigit()
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.2), value: value)
    }
}
