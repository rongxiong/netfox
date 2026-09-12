//
//  NFXStore.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import Foundation

/// Single source of truth for the whole netfox UI.
///
/// It mirrors `NFXHTTPModelManager` into `@Published` values so the SwiftUI
/// views can bind to it, and owns the (debounced) search filtering so typing
/// never blocks the main thread even with thousands of logged requests.
public final class NFXStore: ObservableObject {

    /// Shared instance keeps every netfox surface (panel, sheet, mac window) in sync.
    public static let shared = NFXStore()

    // MARK: - Published state

    @Published private(set) var models: [NFXHTTPModel] = []
    @Published private(set) var displayedModels: [NFXHTTPModel] = []

    /// Bound to the search field. Filtering is debounced, see `scheduleFiltering`.
    @Published var searchText: String = "" {
        didSet { scheduleFiltering() }
    }

    @Published private(set) var filters: [Bool] = NFXHTTPModelManager.shared.filters

    // MARK: - Private properties

    private var subscription: Subscription<[NFXHTTPModel]>?
    private var debounceItem: DispatchWorkItem?

    private static let debounceInterval: TimeInterval = 0.15

    // MARK: - Lifecycle

    private init() {
        let subscription = Subscription<[NFXHTTPModel]> { [weak self] models in
            self?.updateModels(models)
        }

        NFXHTTPModelManager.shared.publisher.subscribe(subscription)
        self.subscription = subscription

        models = NFXHTTPModelManager.shared.filteredModels
        displayedModels = models
    }

    deinit {
        subscription?.cancel()
    }

    // MARK: - Derived values

    var responseTypes: [HTTPModelShortType] { HTTPModelShortType.allCases }

    /// Requests answered after netfox was opened last are still "unread".
    func isUnread(_ model: NFXHTTPModel) -> Bool {
        guard let responseDate = model.responseDate else { return true }
        return responseDate.isGreaterThanDate(NFX.sharedInstance().getLastVisitDate())
    }

    // MARK: - Actions

    func setFilter(_ isEnabled: Bool, at index: Int) {
        guard filters.indices.contains(index) else { return }

        filters[index] = isEnabled
        NFXHTTPModelManager.shared.filters = filters
    }

    func clear() {
        NFX.sharedInstance().clearOldData()
    }

    // MARK: - Private helpers

    private func updateModels(_ models: [NFXHTTPModel]) {
        let apply = { [weak self] in
            guard let self = self else { return }
            self.models = models
            self.displayedModels = Self.filtered(models, query: self.searchText)
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func scheduleFiltering() {
        debounceItem?.cancel()

        let query = searchText
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.displayedModels = Self.filtered(self.models, query: query)
        }

        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: item)
    }

    private static func filtered(_ models: [NFXHTTPModel], query: String) -> [NFXHTTPModel] {
        guard query.isEmpty == false else { return models }

        let needle = query.lowercased()
        return models.filter { model in
            [model.requestURL, model.requestMethod, model.responseType]
                .contains { value in
                    (value ?? "").lowercased().contains(needle)
                }
        }
    }
}

/// Writable mirror of the toggles shown by the settings screen.
public final class NFXSettingsStore: ObservableObject {

    @Published var isLoggingEnabled: Bool
    @Published var isMockServerEnabled: Bool
    @Published var mockServerURL: String

    init() {
        isLoggingEnabled = NFX.sharedInstance().isEnabled()
        isMockServerEnabled = NFX.sharedInstance().isMockServerEnabled()
        mockServerURL = NFX.sharedInstance().getMockServerURLString() ?? ""
    }

    func setLoggingEnabled(_ enabled: Bool) {
        isLoggingEnabled = enabled
        enabled ? NFX.sharedInstance().enable() : NFX.sharedInstance().disable()
    }

    func setMockServerEnabled(_ enabled: Bool) {
        isMockServerEnabled = enabled
        NFX.sharedInstance().setMockServerEnabled(enabled)
    }

    func commitMockServerURL() {
        NFX.sharedInstance().setMockServerURL(mockServerURL)
        mockServerURL = NFX.sharedInstance().getMockServerURLString() ?? mockServerURL
    }
}
