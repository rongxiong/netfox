//
//  NFXQueryItemsView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

struct NFXQueryItemsView: View {

    private struct Row: Identifiable {
        let id = UUID()
        let name: String
        let value: String
    }

    let model: NFXHTTPModel

    private let rows: [Row]

    init(model: NFXHTTPModel) {
        self.model = model
        self.rows = (model.requestURLQueryItems ?? []).map {
            Row(name: $0.name, value: $0.value ?? "")
        }
    }

    var body: some View {
        ScrollView {
            if rows.isEmpty {
                NFXEmptyStateView(systemImage: "list.bullet",
                                  title: "No query strings",
                                  message: "This request does not carry any URL parameter.")
            } else {
                NFXSectionCard(title: "URL parameters") {
                    NFXKeyValueRows(fields: fields)
                }
                .padding(NFXTheme.Metrics.screenPadding)
            }
        }
        .background(Color.nfxBackground.ignoresSafeArea())
        .navigationTitle("Query Strings")
    }

    private var fields: [NFXContentField] {
        rows.map { NFXContentField(key: $0.name, value: $0.value) }
    }
}
