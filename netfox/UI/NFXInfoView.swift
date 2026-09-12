//
//  NFXInfoView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

struct NFXInfoView: View {

    @State private var ipAddress: String?
    @State private var sharePayload: NFXSharePayload?

    private var sections: [NFXContentSection] {
        NFXContentBuilder.deviceInfo(ipAddress: ipAddress)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NFXTheme.Metrics.sectionSpacing) {
                ForEach(sections) { section in
                    NFXSectionCard(title: section.title) {
                        NFXKeyValueRows(fields: section.fields)
                    }
                }
            }
            .padding(NFXTheme.Metrics.screenPadding)
        }
        .background(Color.nfxBackground.ignoresSafeArea())
        .navigationTitle("Info")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    sharePayload = .text(plainText, title: "netfox info")
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .nfxShareSheet(item: $sharePayload)
        .task { loadIPAddress() }
    }

    private var plainText: String {
        NFXContentBuilder
            .deviceInfo(ipAddress: ipAddress)
            .reduce(into: "") { text, section in
                if let title = section.title {
                    text += "-- \(title) --\n"
                }
                section.fields.forEach { text += "[\($0.key)] \($0.value)\n" }
                text += "\n"
            }
    }

    private func loadIPAddress() {
        guard ipAddress == nil else { return }

        NFXDebugInfo.getNFXIP { result in
            DispatchQueue.main.async {
                ipAddress = result
            }
        }
    }
}
