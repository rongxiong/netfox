//
//  ScenariosView.swift
//  netfox_ios_demo
//
//  SwiftUI scenario catalogue: an insetGrouped List whose rows fire their
//  own URLSession request, plus a "Burst" action that simulates loading a
//  webpage with a parallel batch.
//

import SwiftUI
import Observation

// MARK: - View model

@MainActor
@Observable
final class ScenariosViewModel {

    let sections: [ScenarioSection] = ScenarioCatalog.makeSections()

    var footerText: String = "Tap a scenario to fire one request, or Burst to fire a webpage-like batch. Open the netfox panel to inspect them."

    private let runner = ScenarioRunner()

    func run(_ scenario: Scenario) {
        runner.run(scenario)
    }

    func burst() {
        let requests = ScenarioCatalog.makeBurstRequests()
        runner.burst(requests)

        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        footerText = "Burst fired \(requests.count) parallel requests at \(time). Open the netfox panel to inspect them."
    }
}

// MARK: - List

struct ScenariosView: View {

    @State private var model = ScenariosViewModel()

    var body: some View {
        List {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.scenarios) { scenario in
                        Button {
                            model.run(scenario)
                        } label: {
                            ScenarioRow(scenario: scenario)
                        }
                        .buttonStyle(ScenarioRowButtonStyle())
                    }
                } header: {
                    Text(section.name)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("netfox demo")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Burst") {
                    model.burst()
                }
                .fontWeight(.semibold)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(model.footerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                // Keep the last line clear of the trailing floating button.
                .padding(.trailing, 44)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}

// MARK: - Row button style

/// Keeps the label's own colors (the default style tints everything) while
/// dimming the row on press, like a UIKit selection highlight.
private struct ScenarioRowButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Row

struct ScenarioRow: View {

    let scenario: Scenario

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(scenario.method)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 52)
                .padding(.vertical, 5)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.title)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                Text(scenario.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            // Claim all available width; otherwise Text hugs its content and
            // wraps at a break opportunity while the Spacer hoards the space.
            // No Spacer: an infinitely-flexible Spacer would split the leftover
            // space 50/50 with this frame, starving the subtitle.
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hug the actual status content ("200" is far narrower than
            // "Timeout"); a fixed-width column here would steal space and
            // wrap the subtitle while room is still visible.
            trailing
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var trailing: some View {
        switch scenario.state {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
        case .progress(let text):
            HStack(spacing: 6) {
                ProgressView()
                statusText(text, color: .blue)
            }
            .fixedSize()
        case .success(let text):
            statusText(text, color: .green)
        case .httpError(let text):
            statusText(text, color: .orange)
        case .transportError(let text):
            statusText(text, color: .red)
        case .cancelled(let text):
            statusText(text, color: .secondary)
        }
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            // Never let the status shrink or wrap; the subtitle yields first.
            .fixedSize(horizontal: true, vertical: false)
    }

    private var tint: Color {
        switch scenario.method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "PATCH": return Color(red: 0.78, green: 0.56, blue: 0.05)
        case "DELETE": return .red
        default: return .gray
        }
    }
}
