//
//  OffStatExpandedView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 10/25/25.
//


//
//  OffStatExpandedView.swift
//  DynastyStatDrop
//
//  Extracted from DSDDashboard.swift for improved modularity and clarity
//

import SwiftUI

struct OffStatExpandedView: View {
    let team: TeamStanding
    let league: LeagueData
    let personality: StatDropPersonality

    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false

    private var positionSet: Set<String> { ["QB","RB","WR","TE","K"] }

    private var sideWeeklyPoints: [Double] {
        let filteredScores = team.roster
            .filter { positionSet.contains($0.position) }
            .flatMap { $0.weeklyScores }
        let grouped = Dictionary(grouping: filteredScores, by: { $0.week })
        return grouped.keys.sorted().map { wk in
            grouped[wk]?.reduce(0) { $0 + ($1.points_half_ppr ?? $1.points) } ?? 0
        }
    }

    private var weeksPlayed: Int { sideWeeklyPoints.count }
    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        return sideWeeklyPoints.suffix(3).reduce(0,+)/Double(min(3,weeksPlayed))
    }
    private var seasonAvg: Double {
        guard weeksPlayed > 0 else { return team.averageOffensivePPW ?? 0 }
        return sideWeeklyPoints.reduce(0,+)/Double(weeksPlayed)
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var formDeltaColor: Color {
        if formDelta > 2 { return .green }
        if formDelta < -2 { return .red }
        return .yellow
    }

    private var sidePoints: Double { team.offensivePointsFor ?? 0 }
    private var sideMaxPoints: Double { team.maxOffensivePointsFor ?? 0 }
    private var managementPercent: Double {
        guard sideMaxPoints > 0 else { return 0 }
        return (sidePoints / sideMaxPoints) * 100
    }

    private var stdDev: Double {
        guard weeksPlayed > 1 else { return 0 }
        let mean = seasonAvg
        let variance = sideWeeklyPoints.reduce(0) { $0 + pow($1 - mean, 2) } / Double(weeksPlayed)
        return sqrt(variance)
    }
    private var consistencyDescriptor: String {
        switch stdDev {
        case 0..<15: return "Steady"
        case 15..<35: return "Average"
        case 35..<55: return "Swingy"
        default: return "Boom-Bust"
        }
    }

    private var strengths: [String] {
        var arr: [String] = []
        if managementPercent >= 75 { arr.append("Efficient Usage") }
        if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
        if arr.isEmpty { arr.append("Developing Unit") }
        return arr
    }
    private var weaknesses: [String] {
        var arr: [String] = []
        if managementPercent < 55 { arr.append("Usage Inefficiency") }
        if stdDev > 40 { arr.append("Volatility") }
        if weeksPlayed >= 3 && last3Avg < seasonAvg - 5 { arr.append("Recent Dip") }
        if arr.isEmpty { arr.append("No Major Weakness") }
        return arr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            sectionHeader("Offensive Weekly Trend")
            WeeklyPointsTrend(points: sideWeeklyPoints, stroke: .red, accent: .orange)
                .frame(height: 120)
            sectionHeader("Lineup Efficiency")
            lineupEfficiency
            sectionHeader("Recent Form")
            recentForm
            StatDropAnalysisBox(
                team: team,
                league: league,
                context: .offense,
                personality: personality
            )
            sectionHeader("Consistency Score")
            consistencyRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .sheet(isPresented: $showConsistencyInfo) {
            ConsistencyInfoSheet(stdDev: stdDev, descriptor: consistencyDescriptor)
                .presentationDetents([.fraction(0.40)])
        }
        .sheet(isPresented: $showEfficiencyInfo) {
            EfficiencyInfoSheet(managementPercent: managementPercent,
                                pointsFor: sidePoints,
                                maxPointsFor: sideMaxPoints)
            .presentationDetents([.fraction(0.35)])
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("OFF PF \(String(format: "%.2f", sidePoints))")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("Avg \(String(format: "%.2f", seasonAvg))")
        }
        .font(.caption)
        .foregroundColor(.white.opacity(0.85))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.yellow)
            .padding(.top, 4)
    }

    private var lineupEfficiency: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statBlock(title: "PF", value: sidePoints)
                statBlock(title: "Max", value: sideMaxPoints)
                statBlockPercent(title: "Mgmt%", value: managementPercent)
            }
            EfficiencyBar(ratio: managementPercent / 100.0, height: 12)
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    HStack {
                        Spacer()
                        Button { showEfficiencyInfo = true } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.white.opacity(0.75))
                                .font(.caption)
                        }
                        .padding(.trailing, 4)
                    }
                )
        }
    }

    private var recentForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            let arrow = formDelta > 0.5 ? "↑" : (formDelta < -0.5 ? "↓" : "→")
            HStack(alignment: .top, spacing: 12) {
                formStatBlock("Last 3", last3Avg)
                formStatBlock("Season", seasonAvg)
                formDeltaBlock(arrow: arrow, delta: formDelta)
            }
            Text("Compares recent 3 weeks to season average for this unit.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var consistencyRow: some View {
        HStack {
            HStack(spacing: 8) {
                Text(consistencyDescriptor)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Button { showConsistencyInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer()
            ConsistencyMeter(stdDev: stdDev)
                .frame(width: 110, height: 12)
        }
    }

    private func statBlock(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func statBlockPercent(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f%%", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func formStatBlock(_ name: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text(name)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func formDeltaBlock(arrow: String, delta: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(arrow) \(String(format: "%+.2f", delta))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(formDeltaColor)
            Text("Delta")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private struct EfficiencyBar: View {
        let ratio: Double
        let height: CGFloat
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(LinearGradient(colors: [.red, .orange, .yellow, .green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(geo.size.width, geo.size.width * ratio)))
                        .animation(.easeInOut(duration: 0.5), value: ratio)
                }
            }
        }
    }

    private struct ConsistencyMeter: View {
        let stdDev: Double
        private var norm: Double { max(0, min(1, stdDev / 60.0)) }
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .orange, .red],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * norm)
                }
            }
            .clipShape(Capsule())
        }
    }
}