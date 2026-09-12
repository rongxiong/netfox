//
//  NFXMacRootView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

#if os(macOS)

import SwiftUI

/// Sidebar + detail layout used by the macOS window.
struct NFXMacRootView: View {

    @State private var selection: NFXHTTPModel?

    var body: some View {
        NFXSplitContainer {
            NFXRequestListView(selection: $selection)
                .frame(minWidth: 320)
        } detail: {
            detail
                .frame(minWidth: 420)
        }
        .frame(minWidth: 900, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        if let model = selection {
            NFXDetailsView(model: model)
                .id(model.randomHash)
        } else {
            NFXEmptyStateView(systemImage: "sidebar.left",
                              title: "No request selected",
                              message: "Pick a request on the left to inspect its headers, body and timing.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.nfxBackground)
        }
    }
}

#endif
