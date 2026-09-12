//
//  DemoRootView.swift
//  netfox_ios_demo
//
//  Shows the SwiftUI entry point on top of the code-based demo UI.
//

import SwiftUI
import netfox_ios

struct DemoRootView: View {

    @State private var showsNetfoxPanel = false
    @State private var tabBarHeight: CGFloat = 49

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DemoTabBarContainer(tabBarHeight: $tabBarHeight)

            Button {
                showsNetfoxPanel = true
            } label: {
                Image(systemName: "network")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .padding(.trailing, 24)
            // Sit above the UITabBar using its runtime-measured height;
            // the outer container ignores the bottom safe area so the
            // measured height (which includes the home-indicator inset)
            // positions the button exactly above the bar.
            .padding(.bottom, tabBarHeight + 24)
        }
        .ignoresSafeArea()
        .netfoxPanel(isPresented: $showsNetfoxPanel)
    }
}

struct DemoTabBarContainer: UIViewControllerRepresentable {

    @Binding var tabBarHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(tabBarHeight: $tabBarHeight)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = DemoTabBarController()
        context.coordinator.observe(controller.tabBar)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }

    final class Coordinator: NSObject {

        private let tabBarHeight: Binding<CGFloat>
        private var frameObservation: NSKeyValueObservation?

        init(tabBarHeight: Binding<CGFloat>) {
            self.tabBarHeight = tabBarHeight
        }

        func observe(_ tabBar: UITabBar) {
            // Fires on initial layout and whenever the bar is resized
            // (orientation changes, iPad split-view, dynamic type, etc.).
            frameObservation = tabBar.observe(\.frame, options: [.initial, .new]) { [weak self] bar, _ in
                let height = bar.frame.height
                guard height > 0 else { return }
                DispatchQueue.main.async {
                    if self?.tabBarHeight.wrappedValue != height {
                        self?.tabBarHeight.wrappedValue = height
                    }
                }
            }
        }
    }
}
