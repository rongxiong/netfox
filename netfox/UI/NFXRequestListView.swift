//
//  NFXRequestListView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

struct NFXRequestListView: View {

    /// Set by the macOS layout, where selecting a row drives the detail column
    /// instead of pushing it on a navigation stack.
    var selection: Binding<NFXHTTPModel?>?

    @EnvironmentObject private var store: NFXStore
    @Environment(\.nfxDismiss) private var dismiss
    @Environment(\.nfxShowsClose) private var showsClose

    @State private var showsClearConfirmation = false

    /// The model whose details are pushed on iOS 16+ / macOS 13+. A single
    /// `navigationDestination` modifier outside the lazy `List` reads this;
    /// rows only flip it through plain buttons.
    @State private var presentedModel: NFXHTTPModel?

    private var isDetailPresented: Binding<Bool> {
        Binding(
            get: { presentedModel != nil },
            set: { presented in if !presented { presentedModel = nil } }
        )
    }

    #if os(macOS)
    @State private var showsSettings = false
    @State private var showsStatistics = false
    @State private var showsInfo = false
    #endif

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.nfxBackground.ignoresSafeArea())
            .nfxListStyle()
            .navigationTitle("Requests")
            .searchable(text: $store.searchText, prompt: Text("Search URL, method or type"))
            .toolbar { toolbarContent }
            .alert("Clear data?", isPresented: $showsClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { store.clear() }
            } message: {
                Text("Every intercepted request and its logged body will be removed.")
            }
            #if os(macOS)
            .sheet(isPresented: $showsSettings) {
                NFXMacSheetPage(title: "Settings") { NFXSettingsView() }
            }
            .sheet(isPresented: $showsStatistics) {
                NFXMacSheetPage(title: "Statistics") { NFXStatisticsView() }
            }
            .sheet(isPresented: $showsInfo) {
                NFXMacSheetPage(title: "Info") { NFXInfoView() }
            }
            #endif
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.models.isEmpty {
            NFXEmptyStateView(systemImage: "tray",
                              title: "No requests yet",
                              message: "Every request your app performs shows up here as soon as it is intercepted.")
            .accessibilityIdentifier(NFXAccessibility.emptyState)
        } else if store.displayedModels.isEmpty {
            NFXEmptyStateView(systemImage: "magnifyingglass",
                              title: "No results",
                              message: "Nothing matches “\(store.searchText)”.",
                              actionTitle: "Clear search",
                              action: { store.searchText = "" })
            .accessibilityIdentifier(NFXAccessibility.emptyState)
        } else {
            list
        }
    }

    @ViewBuilder
    private var list: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            // The destination must live outside the lazy List, otherwise the
            // navigation stack only sees rows that have already rendered and
            // SwiftUI logs a misplaced-modifier warning.
            requestList
                .navigationDestination(isPresented: isDetailPresented) {
                    if let model = presentedModel {
                        NFXDetailsView(model: model)
                    }
                }
        } else {
            requestList
        }
    }

    private var requestList: some View {
        List {
            Section {
                ForEach(store.displayedModels, id: \.randomHash) { model in
                    row(model)
                        .nfxPlainRow(insets: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            } header: {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(Color.nfxSecondaryText)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.displayedModels.count)
        .accessibilityIdentifier(NFXAccessibility.requestList)
    }

    @ViewBuilder
    private func row(_ model: NFXHTTPModel) -> some View {
        let rowBody = NFXRequestRowView(model: model, isUnread: store.isUnread(model))
            .accessibilityIdentifier(NFXAccessibility.row(model.randomHash))

        if let selection {
            Button {
                selection.wrappedValue = model
            } label: {
                rowBody
                    .background(isSelected(model) ? Color.nfxAccent.opacity(0.16) : Color.clear,
                                in: RoundedRectangle(cornerRadius: NFXTheme.Metrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: isSelected(model))
        } else {
            // Plain button + programmatic push so the system list disclosure
            // chevron is not rendered outside the card. On iOS 16+ the push
            // is driven by one `navigationDestination` outside the List;
            // older systems fall back to a per-row hidden NavigationLink.
            if #available(iOS 16.0, macOS 13.0, *) {
                Button {
                    presentedModel = model
                } label: {
                    rowBody
                }
                .buttonStyle(.plain)
            } else {
                NFXPushRow {
                    rowBody
                } destination: {
                    NFXDetailsView(model: model)
                }
            }
        }
    }

    private func isSelected(_ model: NFXHTTPModel) -> Bool {
        guard let selection = selection else { return false }
        return selection.wrappedValue?.randomHash == model.randomHash
    }

    private var summaryText: String {
        let total = store.models.count
        let shown = store.displayedModels.count
        guard shown != total else {
            return "\(NFXFormat.integer(total)) requests"
        }
        return "\(NFXFormat.integer(shown)) of \(NFXFormat.integer(total)) requests"
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showsSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier(NFXAccessibility.Toolbar.settings)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { showsStatistics = true }) {
                    Label("Statistics", systemImage: "chart.bar")
                }
                .accessibilityIdentifier(NFXAccessibility.Toolbar.statistics)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { showsInfo = true }) {
                    Label("Info", systemImage: "info.circle")
                }
                .accessibilityIdentifier(NFXAccessibility.Toolbar.info)
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    NFXSettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier(NFXAccessibility.Toolbar.settings)
            }
            ToolbarItem(placement: .automatic) {
                NavigationLink {
                    NFXStatisticsView()
                } label: {
                    Label("Statistics", systemImage: "chart.bar")
                }
                .accessibilityIdentifier(NFXAccessibility.Toolbar.statistics)
            }
            ToolbarItem(placement: .automatic) {
                NavigationLink {
                    NFXInfoView()
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
                .accessibilityIdentifier(NFXAccessibility.Toolbar.info)
            }
            #endif

            ToolbarItem(placement: .automatic) {
                Button(role: .destructive, action: { showsClearConfirmation = true }) {
                    Label("Clear", systemImage: "trash")
                }
                .accessibilityIdentifier(NFXAccessibility.Toolbar.clear)
            }

            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if showsClose {
            Button(action: { dismiss() }) {
                Label("Close", systemImage: "xmark")
            }
            .accessibilityIdentifier(NFXAccessibility.Toolbar.close)
        }
    }
}

/// List row that pushes `Destination` on tap without rendering the system
/// list disclosure chevron. Legacy path for iOS 15 / macOS 12 only: a hidden
/// isActive `NavigationLink` performs the push. On newer systems
/// `NFXRequestListView` drives a single `navigationDestination` outside the
/// lazy `List` and plain buttons set the presented model.
struct NFXPushRow<Label: View, Destination: View>: View {

    @ViewBuilder let label: () -> Label
    @ViewBuilder let destination: () -> Destination

    @State private var isActive = false

    var body: some View {
        Button {
            isActive = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .background(
            NavigationLink(destination: destination(), isActive: $isActive) {
                EmptyView()
            }
            .hidden()
        )
    }
}

// MARK: - Row styling

extension View {

    func nfxPlainRow(insets: EdgeInsets) -> some View {
        #if os(iOS)
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(insets)
        #else
        self
            .listRowBackground(Color.clear)
            .listRowInsets(insets)
        #endif
    }

    func nfxListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.automatic)
        #endif
    }
}

#if os(macOS)

/// Settings / statistics / info are presented as sheets on macOS.
struct NFXMacSheetPage<Content: View>: View {

    let title: String
    let content: Content

    @Environment(\.dismiss) private var dismiss

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(14)

            Divider()

            content
                .frame(minWidth: 460, minHeight: 340)
        }
        .background(Color.nfxBackground)
    }
}

#endif
