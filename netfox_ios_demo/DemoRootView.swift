//
//  DemoRootView.swift
//  netfox_ios_demo
//
//  Shows the new SwiftUI entry point on top of the existing storyboard demo UI.
//

import SwiftUI
import netfox_ios

@available(iOS 15.0, *)
struct DemoRootView: View {

    @State private var showsNetfoxPanel = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DemoStoryboardView()

            Button {
                showsNetfoxPanel = true
            } label: {
                Label("netfox", systemImage: "network")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(24)
        }
        .ignoresSafeArea(edges: .bottom)
        .netfoxPanel(isPresented: $showsNetfoxPanel)
    }
}

@available(iOS 15.0, *)
struct DemoStoryboardView: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> UIViewController {
        UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController() ?? UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}
