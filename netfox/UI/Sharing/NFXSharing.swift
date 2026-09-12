//
//  NFXSharing.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

#if os(iOS)
import UIKit
import MessageUI
#else
import AppKit
#endif

/// Payload presented by the platform share sheet / picker.
struct NFXSharePayload: Identifiable {

    let id = UUID()
    let title: String
    let items: [Any]

    init(title: String, items: [Any]) {
        self.title = title
        self.items = items
    }

    static func text(_ text: String, title: String) -> NFXSharePayload {
        NFXSharePayload(title: title, items: [text])
    }
}

enum NFXSharing {

    /// macOS has no SwiftUI share sheet, so the AppKit picker is used instead.
    static func presentMac(items: [Any]) {
        #if os(macOS)
        guard let view = NSApp.keyWindow?.contentView, items.isEmpty == false else { return }

        let origin = NSRect(x: view.bounds.midX - 1, y: view.bounds.minY + 1, width: 2, height: 2)
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: origin, of: view, preferredEdge: .minY)
        #endif
    }
}

extension View {

    /// Presents `item` with the native sharing UI of the current platform.
    func nfxShareSheet(item: Binding<NFXSharePayload?>) -> some View {
        #if os(iOS)
        sheet(item: item) { payload in
            NFXActivityView(activityItems: payload.items)
        }
        #else
        onChange(of: item.wrappedValue?.id) { _ in
            guard let payload = item.wrappedValue else { return }
            NFXSharing.presentMac(items: payload.items)
            DispatchQueue.main.async { item.wrappedValue = nil }
        }
        #endif
    }
}

#if os(iOS)

struct NFXActivityView: UIViewControllerRepresentable {

    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }
}

/// Used by "Share session logs" when the device can send mail.
struct NFXMailView: UIViewControllerRepresentable {

    let subject: String
    let attachment: Data?
    let fileName: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.setSubject(subject)

        if let attachment = attachment {
            composer.addAttachmentData(attachment, mimeType: "text/plain", fileName: fileName)
        }

        composer.mailComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true)
        }
    }
}

#endif
