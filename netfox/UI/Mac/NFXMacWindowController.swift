//
//  NFXMacWindowController.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

#if os(macOS)

import AppKit
import SwiftUI

/// Replaces the old `NetfoxWindow.xib`: the macOS UI is now SwiftUI, hosted in a
/// window built in code.
final class NFXMacWindowController: NSWindowController, NSWindowDelegate {

    convenience init(rootView: some View) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "netfox"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 480)
        window.center()

        self.init(window: window)

        window.delegate = self
        window.contentViewController = NSHostingController(rootView: rootView)
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        NFX.sharedInstance().windowDidClose()
    }
}

/// Host view injecting the shared store and hiding the iOS-only close button.
struct NFXMacHostView: View {

    @StateObject private var store = NFXStore.shared

    var body: some View {
        NFXMacRootView()
            .environmentObject(store)
            .environment(\.nfxShowsClose, false)
    }
}

#endif
