//
//  NFXStatisticsView.swift
//  netfox
//
//  Copyright © 2016 netfox. All rights reserved.
//

import SwiftUI

struct NFXStatisticsView: View {

    @EnvironmentObject private var store: NFXStore

    private var summary: NFXStatisticsSummary {
        NFXContentBuilder.statistics(for: store.models)
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NFXTheme.Metrics.sectionSpacing) {
                if summary.totalRequests == 0 {
                    NFXEmptyStateView(systemImage: "chart.bar",
                                      title: "No statistics yet",
                                      message: "Numbers appear here once your app performs its first intercepted request.")
                        .frame(minHeight: 260)
                } else {
                    ratioCard

                    LazyVGrid(columns: columns, spacing: 12) {
                        NFXMetricCard(title: "Requests",
                                      value: NFXFormat.integer(summary.totalRequests),
                                      tone: .nfxAccent)
                        NFXMetricCard(title: "Successful",
                                      value: NFXFormat.integer(summary.successfulRequests),
                                      subtitle: percent(summary.successRatio),
                                      tone: .nfxSuccess)
                        NFXMetricCard(title: "Failed",
                                      value: NFXFormat.integer(summary.failedRequests),
                                      subtitle: percent(summary.failureRatio),
                                      tone: .nfxFailure)
                        NFXMetricCard(title: "Avg response time",
                                      value: NFXFormat.duration(summary.averageResponseTime),
                                      tone: .nfxAccentAlt)
                        NFXMetricCard(title: "Fastest response",
                                      value: NFXFormat.duration(summary.fastestResponseTime),
                                      tone: .nfxSuccess)
                        NFXMetricCard(title: "Slowest response",
                                      value: NFXFormat.duration(summary.slowestResponseTime),
                                      tone: .nfxWarning)
                        NFXMetricCard(title: "Request size",
                                      value: NFXFormat.bytes(summary.totalRequestSize),
                                      subtitle: "avg \(NFXFormat.bytes(summary.averageRequestSize))",
                                      tone: .nfxAccent)
                        NFXMetricCard(title: "Response size",
                                      value: NFXFormat.bytes(summary.totalResponseSize),
                                      subtitle: "avg \(NFXFormat.bytes(summary.averageResponseSize))",
                                      tone: .nfxAccent)
                    }
                }
            }
            .padding(NFXTheme.Metrics.screenPadding)
            .animation(.easeOut(duration: 0.25), value: summary.totalRequests)
        }
        .background(Color.nfxBackground.ignoresSafeArea())
        .navigationTitle("Statistics")
    }

    private var ratioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(NFXFormat.integer(summary.successfulRequests)) succeeded")
                    .foregroundStyle(Color.nfxSuccess)
                Spacer()
                Text("\(NFXFormat.integer(summary.failedRequests)) failed")
                    .foregroundStyle(Color.nfxFailure)
            }
            .font(.caption.weight(.semibold))

            NFXRatioBar(successRatio: summary.successRatio)
        }
        .nfxCard()
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}
