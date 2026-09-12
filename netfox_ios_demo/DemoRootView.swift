//
//  DemoRootView.swift
//  netfox_ios_demo
//
//  Root SwiftUI scene: the scenario catalogue under a NavigationStack, with
//  the floating netfox button overlaying everything.
//

import SwiftUI
import netfox_ios

struct DemoRootView: View {

    @State private var showsNetfoxPanel = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack {
                ScenariosView()
            }

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
            .padding(.bottom, 24)
        }
        .netfoxPanel(isPresented: $showsNetfoxPanel)
    }
}
