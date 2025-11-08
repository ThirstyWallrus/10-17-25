//
//  DefensiveBalanceInfoSheet.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 11/8/25.
//


import SwiftUI

/// DefensiveBalanceInfoSheet.swift
/// Standalone defensive balance info sheet to mirror the OffensiveBalanceInfoSheet / OffPositionBalanceDetailSheet
/// Used by DefStatExpandedView to present a detailed explanation of defensive position balance (DL / LB / DB).
///
/// This view intentionally reuses shared components defined in OffPositionBalanceDetailSheet.swift
/// (CircularProgressView, PositionGauge, BalanceGauge) to keep visuals consistent across offense/defense sheets.

struct DefensiveBalanceInfoSheet: View {
    let positionPercents: [String: Double]
    let balancePercent: Double
    let tagline: String

    // Order positions so we always show DL, LB, DB in that order
    private var orderedPositions: [String] { ["DL", "LB", "DB"] }

    // Mirrored color mapping used elsewhere in the app for defensive positions
    private var positionColors: [String: Color] {
        [
            "DL": .orange,
            "LB": .purple,
            "DB": .pink
        ]
    }

    // Computed helpers
    private var valuesOrdered: [Double] { orderedPositions.map { positionPercents[$0] ?? 0.0 } }
    private var mean: Double {
        guard !valuesOrdered.isEmpty else { return 0 }
        return valuesOrdered.reduce(0, +) / Double(valuesOrdered.count)
    }
    private var variance: Double {
        guard !valuesOrdered.isEmpty else { return 0 }
        return valuesOrdered.reduce(0) { $0 + pow($1 - mean, 2) } / Double(valuesOrdered.count)
    }
    private var sd: Double { sqrt(variance) }
    private var recomputedBalance: Double {
        guard mean > 0 else { return 0 }
        return (sd / mean) * 100
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    var body: some View {
        VStack(spacing: 12) {
            // Grab bar
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 40, height: 6)
                .padding(.top, 8)

            Text("Defensive Efficiency Spotlight")
                .font(.headline)
                .foregroundColor(.yellow)

            // Top gauges (DL, LB, DB) using shared PositionGauge
            HStack(spacing: 10) {
                PositionGauge(pos: "DL", pct: positionPercents["DL"] ?? 0, color: positionColors["DL"]!)
                PositionGauge(pos: "LB", pct: positionPercents["LB"] ?? 0, color: positionColors["LB"]!)
                PositionGauge(pos: "DB", pct: positionPercents["DB"] ?? 0, color: positionColors["DB"]!)
            }

            // Balance summary and tagline
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    BalanceGauge(balance: balancePercent)
                    Spacer()
                }
                Text(tagline)
                    .font(.caption2)
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Divider().background(Color.white.opacity(0.12)).padding(.vertical, 6)

            // Explanatory section showing values, mean, SD, and recomputed balance
            VStack(alignment: .leading, spacing: 8) {
                Text("How the balance is derived")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(orderedPositions, id: \.self) { pos in
                        HStack {
                            Text(pos)
                                .font(.caption2).bold()
                                .foregroundColor(.white)
                                .frame(width: 36, alignment: .leading)
                            Text("\(fmt(positionPercents[pos] ?? 0.0)) %")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.95))
                            Spacer()
                            if mean > 0 {
                                let diff = (positionPercents[pos] ?? 0) - mean
                                Text(diff >= 0 ? "+\(fmt(diff)) vs mean" : "\(fmt(diff)) vs mean")
                                    .font(.caption2)
                                    .foregroundColor(diff > 8 ? .green : (diff < -8 ? .orange : .gray))
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Mean (average Mgmt%)")
                            .font(.caption2).foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text("\(fmt(mean)) %")
                            .font(.caption2).bold().foregroundColor(.white)
                    }
                    HStack {
                        Text("Standard deviation (SD)")
                            .font(.caption2).foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text("\(fmt(sd))")
                            .font(.caption2).bold().foregroundColor(.white)
                    }
                    HStack {
                        Text("Balance (SD / Mean × 100)")
                            .font(.caption2).foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text("\(fmt(recomputedBalance)) %")
                            .font(.caption2).bold().foregroundColor(balancePercent < 8 ? .green : (balancePercent < 16 ? .yellow : .red))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal)
                .background(Color.white.opacity(0.02))
                .cornerRadius(8)
            }
            .padding(.horizontal)

            Divider().background(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 8) {
                Text("How to interpret the numbers")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 6) {
                    Text("• balance < 8% — Very balanced: usage is evenly distributed across DL/LB/DB.")
                    Text("• balance 8–16% — Moderately balanced: one group may take more of the load.")
                    Text("• balance > 16% — Unbalanced: one or two groups dominate usage; consider roster or matchup adjustments.")
                }
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal)

            Spacer(minLength: 12)
        }
        .padding(.bottom, 16)
        .background(Color.black)
    }
}
