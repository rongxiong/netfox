//
//  NetfoxView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

// MARK: - Environment

private struct NFXDismissKey: EnvironmentKey {
    static let defaultValue: () -> Void = { }
}

private struct NFXShowsCloseKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {

    /// Dismisses the whole netfox surface (sheet, panel or window).
    var nfxDismiss: () -> Void {
        get { self[NFXDismissKey.self] }
        set { self[NFXDismissKey.self] = newValue }
    }

    /// macOS windows own their close button, so the in-UI one is hidden there.
    var nfxShowsClose: Bool {
        get { self[NFXShowsCloseKey.self] }
        set { self[NFXShowsCloseKey.self] = newValue }
    }
}

// MARK: - Public root view

/// The whole netfox UI as a SwiftUI view.
///
/// Embed it anywhere - inside your own navigation stack, or presented with the
/// `netfoxPanel(isPresented:)` modifier. It shares its state with the classic
/// `NFX.sharedInstance().show()` entry point.
@available(iOS 15.0, macOS 12.0, *)
public struct NetfoxView: View {

    @StateObject private var store = NFXStore.shared

    public init() { }

    public var body: some View {
        NFXRootContainer()
            .environmentObject(store)
            .environment(\.nfxDismiss, { NFX.sharedInstance().hide() })
    }
}

struct NFXRootContainer: View {

    var body: some View {
        #if os(macOS)
        NFXMacRootView()
        #else
        NFXNavigationContainer {
            NFXRequestListView()
        }
        #endif
    }
}

// MARK: - SwiftUI entry point

@available(iOS 15.0, macOS 12.0, *)
public extension View {

    /// Presents netfox in a sheet bound to `isPresented`.
    func netfoxPanel(isPresented: Binding<Bool>) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented) {
            NetfoxView()
                .frame(minWidth: 940, minHeight: 620)
        }
        #else
        sheet(isPresented: isPresented) {
            NetfoxView()
        }
        #endif
    }
}
