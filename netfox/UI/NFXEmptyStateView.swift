//
//  NFXEmptyStateView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

/// Placeholder used instead of `ContentUnavailableView` (iOS 17+) so the very
/// same look ships on iOS 15 and macOS 12.
struct NFXEmptyStateView: View {

    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(
                    LinearGradient(colors: [Color.nfxAccent, Color.nfxAccentAlt],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .padding(.bottom, 2)

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.nfxPrimaryText)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.nfxSecondaryText)
                .frame(maxWidth: 320)

            if let actionTitle = actionTitle {
                Button(actionTitle, action: { action?() })
                    .buttonStyle(.borderedProminent)
                    .tint(Color.nfxAccent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color.nfxBackground)
        .transition(.opacity)
    }
}
