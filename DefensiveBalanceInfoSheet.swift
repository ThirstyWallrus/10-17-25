//
//  DefensiveBalanceInfoSheet.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 11/8/25.
//
//  Updated: compact default view (gauges + tagline) matching OffPositionBalanceDetailSheet,
//  plus an identical "More info" DisclosureGroup that reveals the detailed derivation.
//  Uses shared PositionGauge/BalanceGauge/CircularProgressView from CircularProgressView.swift.
//

import SwiftUI

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

            // Top gauges (DL, LB, DB)
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

            // More info disclosure — identical content & presentation to the offensive sheet's More info
            DisclosureGroup {
                BalanceDetailContent(
                    orderedPositions: orderedPositions,
                    positionPercents: positionPercents,
                    balancePercent: balancePercent
                )
                .padding(.top, 8)
            } label: {
                HStack {
                    Spacer()
                    Text("More info")
                        .font(.caption2).bold()
                        .foregroundColor(.white.opacity(0.9))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal)

            Spacer(minLength: 12)
        }
        .padding(.bottom, 16)
        .background(Color.black)
    }
}
