//
//  NFXSettingsView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

#if os(iOS)
import MessageUI
#endif

struct NFXSettingsView: View {

    @EnvironmentObject private var store: NFXStore
    @StateObject private var settings = NFXSettingsStore()

    @State private var showsClearConfirmation = false
    @State private var sharePayload: NFXSharePayload?
    @State private var sessionLogURL: URL?

    #if os(iOS)
    @State private var showsMail = false
    @State private var mailAttachment: Data?
    #endif

    private let projectURL = URL(string: "https://github.com/rongxiong/netfox")!

    var body: some View {
        List {
            Section("Logging") {
                Toggle("Logging", isOn: loggingBinding)
                    .tint(Color.nfxAccent)
            }

            Section {
                Toggle("Mock Server", isOn: mockServerBinding)
                    .tint(Color.nfxAccent)
                mockURLRow
            } header: {
                Text("Mock Server")
            } footer: {
                Text("Requests keep their path and query, only the host is replaced.")
            }

            Section("Response Types") {
                ForEach(store.responseTypes, id: \.rawValue) { type in
                    if let index = store.responseTypes.firstIndex(of: type) {
                        Toggle(type.rawValue, isOn: filterBinding(at: index))
                            .tint(Color.nfxAccent)
                    }
                }
            }

            Section("Session") {
                Button("Share Session Logs", action: shareSessionLog)
            }

            Section("Data") {
                Button(role: .destructive, action: { showsClearConfirmation = true }) {
                    Text("Clear Data")
                }
            }

            Section {
                VStack(spacing: 6) {
                    Text("netfox \(nfxVersion)")
                        .font(.footnote)
                        .foregroundStyle(Color.nfxSecondaryText)
                    Link("github.com/rongxiong/netfox", destination: projectURL)
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
        }
        .nfxListStyle()
        .background(Color.nfxBackground)
        .navigationTitle("Settings")
        .alert("Clear data?", isPresented: $showsClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { store.clear() }
        } message: {
            Text("Every intercepted request and its logged body will be removed.")
        }
        .nfxShareSheet(item: $sharePayload)
        #if os(iOS)
        .sheet(isPresented: $showsMail) {
            NFXMailView(subject: "netfox log - Session Log \(Date())",
                        attachment: mailAttachment,
                        fileName: NFXPath.sessionLogName)
        }
        #endif
    }

    // MARK: - Rows

    private var mockURLRow: some View {
        HStack(spacing: 8) {
            Text("Server URL")
                .foregroundStyle(Color.nfxPrimaryText)
            Spacer(minLength: 8)
            mockURLField
        }
    }

    private var mockURLField: some View {
        let field = TextField("http://localhost:3000", text: $settings.mockServerURL)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(Color.nfxSecondaryText)
            .submitLabel(.done)
            .onSubmit { settings.commitMockServerURL() }
            .frame(minWidth: 160)

        #if os(iOS)
        return field
            .keyboardType(.URL)
            .autocapitalization(.none)
        #else
        return field
            .textFieldStyle(.roundedBorder)
        #endif
    }

    // MARK: - Bindings

    private var loggingBinding: Binding<Bool> {
        Binding(get: { settings.isLoggingEnabled },
                set: { settings.setLoggingEnabled($0) })
    }

    private var mockServerBinding: Binding<Bool> {
        Binding(get: { settings.isMockServerEnabled },
                set: { settings.setMockServerEnabled($0) })
    }

    private func filterBinding(at index: Int) -> Binding<Bool> {
        Binding(get: { store.filters[index] },
                set: { store.setFilter($0, at: index) })
    }

    // MARK: - Session log

    private func shareSessionLog() {
        guard let data = NFX.sharedInstance().getSessionLog(), data.isEmpty == false else { return }

        #if os(iOS)
        if MFMailComposeViewController.canSendMail() {
            mailAttachment = data
            showsMail = true
            return
        }
        sharePayload = NFXSharePayload(title: "Session log", items: [data])
        #else
        NFXSharing.presentMac(items: [data])
        #endif
    }
}
