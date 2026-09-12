//
//  NFXNavigationContainer.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

/// Wraps the navigation container so netfox can run on iOS 15 / macOS 12 while
/// still using `NavigationStack` on the newer systems that have it.
struct NFXNavigationContainer<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
        }
        #else
        if #available(iOS 16.0, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
                .navigationViewStyle(.stack)
        }
        #endif
    }
}

#if os(macOS)

/// Same idea for the macOS double column layout.
@available(macOS 12.0, *)
struct NFXSplitContainer<Sidebar: View, Detail: View>: View {

    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView(sidebar: sidebar, detail: detail)
        } else {
            NavigationView(content: { sidebar(); detail() })
        }
    }
}

#endif
