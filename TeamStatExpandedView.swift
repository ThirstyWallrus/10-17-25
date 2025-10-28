//
//  TeamStatExpandedView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/25/25.
//

//
//  DSDDashboard_Subviews.swift
//  DynastyStatDrop
//
//  Subordinate subviews used by DSDDashboard (previously inlined).
//  Extracted for clarity. Logic unchanged except for removal of stray tokens.
//

import SwiftUI

// MARK: - TeamStatExpandedView

struct TeamStatExpandedView: View {
    @EnvironmentObject var appSelection: AppSelection
    // Closure returns (optional) aggregated all time stats wrapper for this team
    let aggregatedAllTime: (TeamStanding) -> DSDDashboard.AggregatedTeamStats?
    
    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false
    
    // Use selected team from AppSelection
    private var team: TeamStanding? { appSelection.selectedTeam }
    
    // MARK: - Stacked Bar Chart Data Preparation

    // Defines all positions to display in the stacked bar chart for TeamStatExpandedView
    private let allPositions: [String] = ["QB", "RB", "WR", "TE", "K", "DL", "LB", "DB"]

    // Maps canonical fantasy positions to their colors (must match app mapping)
    private var positionColors: [String: Color] {
        [
            "QB": .red,
            "RB": .green,
            "WR": .blue,
            "TE": .yellow,
            "K": Color(red: 0.75, green: 0.6, blue: 1.0),
            "DL": .orange,
            "LB": .purple,
            "DB": .pink
        ]
    }

    // Builds stacked bar data for each completed week (oldest to newest)
    private var stackedBarWeekData: [StackedBarWeeklyChart.WeekBarData] {
        guard let team else { return [] }
        // Group PlayerWeeklyScores by week (from all rostered players)
        let grouped = Dictionary(grouping: team.roster.flatMap { $0.weeklyScores }, by: { $0.week })
        let sortedWeeks = grouped.keys.sorted()
        return sortedWeeks.map { week in
            // For each position, sum scores for this week
            let posSums: [String: Double] = allPositions.reduce(into: [:]) { dict, pos in
                dict[pos] = grouped[week]?.filter { matchesPosition($0, pos: pos) }.reduce(0) { $0 + ($1.points_half_ppr ?? $1.points) } ?? 0
            }
            let segments = allPositions.map { pos in
                StackedBarWeeklyChart.WeekBarData.Segment(id: pos, position: pos, value: posSums[pos] ?? 0)
            }
            return StackedBarWeeklyChart.WeekBarData(id: week, segments: segments)
        }
    }

    // Helper: check if a PlayerWeeklyScore's player matches the target position
    private func matchesPosition(_ score: PlayerWeeklyScore, pos: String) -> Bool {
        // Find the player object for this score
        guard let team = team,
              let player = team.roster.first(where: { $0.id == score.player_id }) else { return false }
        return player.position == pos
    }
    
    // Derived weekly totals (actual roster total per week)
    private var weeklyPoints: [Double] {
        stackedBarWeekData.map { $0.total }
    }
    
    private var weeksPlayed: Int { weeklyPoints.count }
    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        return weeklyPoints.suffix(3).reduce(0,+) / Double(min(3, weeksPlayed))
    }
    private var seasonAvg: Double {
        guard weeksPlayed > 0 else { return team?.teamPointsPerWeek ?? 0 }
        return weeklyPoints.reduce(0,+) / Double(weeksPlayed)
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var managementPercent: Double {
        guard let team, team.maxPointsFor > 0 else { return 0 }
        return (team.pointsFor / team.maxPointsFor) * 100
    }
    private var stdDev: Double {
        guard weeksPlayed > 1 else { return 0 }
        let mean = seasonAvg
        let variance = weeklyPoints.reduce(0) { $0 + pow($1 - mean, 2) } / Double(weeksPlayed)
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
    
    private var strengthsPills: [String] {
        guard let team else { return [] }
        var pills: [String] = []
        if managementPercent >= 80 { pills.append("Efficient Mgmt") }
        if let off = team.offensivePointsFor, let def = team.defensivePointsFor {
            if off > def + 75 { pills.append("High-Power Offense") }
            if def > off + 75 { pills.append("Stout Defense") }
        }
        if stdDev < 20 && weeksPlayed >= 4 { pills.append("Reliable Output") }
        if pills.isEmpty { pills.append("Developing Roster") }
        return pills
    }
    private var weaknessPills: [String] {
        guard let team else { return [] }
        var pills: [String] = []
        if managementPercent < 55 { pills.append("Mgmt Inefficiency") }
        if stdDev > 55 { pills.append("Volatile") }
        if pills.isEmpty { pills.append("No Major Weakness") }
        return pills
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let team = team {
                header(team: team)
                sectionHeader("Weekly Points by Position")
                // --- REPLACED: Sparkline/WeeklyPointsTrend with StackedBarWeeklyChart ---
                StackedBarWeeklyChart(
                    weekBars: stackedBarWeekData,
                    positionColors: positionColors,
                    gridLines: [100, 200, 300],
                    chartTop: 400,
                    showPositions: Set(allPositions),
                    barSpacing: 4,
                    tooltipFont: .caption2.bold(),
                    showWeekLabels: true
                )
                sectionHeader("Lineup Efficiency")
                lineupEfficiency(team: team)
                sectionHeader("Off vs Def Contribution")
                offDefContribution(team: team)
                sectionHeader("Recent Form (Performance Momentum)")
                recentForm
                sectionHeader("Strengths")
                FlowLayoutCompat(items: strengthsPills) { Pill(text: $0, bg: Color.green.opacity(0.22), stroke: .green) }
                sectionHeader("Weaknesses")
                FlowLayoutCompat(items: weaknessPills) { Pill(text: $0, bg: Color.red.opacity(0.22), stroke: .red) }
                sectionHeader("Consistency Score")
                consistencyRow
            } else {
                Text("No team selected")
                    .foregroundColor(.gray)
                    .font(.headline)
                    .padding()
            }
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
                                pointsFor: team?.pointsFor ?? 0,
                                maxPointsFor: team?.maxPointsFor ?? 0)
            .presentationDetents([.fraction(0.35)])
        }
    }
    
    private func header(team: TeamStanding) -> some View {
        HStack(spacing: 12) {
            Text(team.winLossRecord ?? "0-0-0")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("PF \(Int(team.pointsFor))")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("PPW \(String(format: "%.2f", team.teamPointsPerWeek))")
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
    
    private func lineupEfficiency(team: TeamStanding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statBlock(title: "PF", value: team.pointsFor)
                statBlock(title: "Max PF", value: team.maxPointsFor)
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
    
    private func offDefContribution(team: TeamStanding) -> some View {
        let off = team.offensivePointsFor ?? 0
        let def = team.defensivePointsFor ?? 0
        let total = max(1, off + def)
        return HStack(spacing: 20) {
            contributionBlock(label: "OFF", points: off, pct: off / total * 100, color: .orange)
            contributionBlock(label: "DEF", points: def, pct: def / total * 100, color: .cyan)
        }
        .font(.caption)
    }
    
    private var recentForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            let arrow = formDelta > 0.5 ? "↑" : (formDelta < -0.5 ? "↓" : "→")
            HStack(spacing: 10) {
                formStatBlock(name: "Last 3 Avg", value: last3Avg)
                formStatBlock(name: "Season Avg", value: seasonAvg)
                formDeltaBlock(delta: formDelta, arrow: arrow)
            }
            Text("Shows whether your recent scoring (last 3 weeks) is above or below your overall season average.")
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

    private func contributionBlock(label: String, points: Double, pct: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).bold().foregroundColor(color)
            Text(String(format: "%.2f", points)).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            Text(String(format: "%.1f%%", pct)).font(.caption2).foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formStatBlock(name: String, value: Double) -> some View {
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
    
    private func formDeltaBlock(delta: Double, arrow: String) -> some View {
        VStack(spacing: 2) {
            Text("\(arrow) \(String(format: "%+.2f", delta))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(delta > 3 ? .green : (delta < -3 ? .red : .yellow))
            Text("Delta")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private struct Pill: View {
        let text: String
        let bg: Color
        let stroke: Color
        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(bg))
                .overlay(Capsule().stroke(stroke.opacity(0.7), lineWidth: 1))
                .foregroundColor(.white)
        }
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
        private var norm: Double { max(0, min(1, stdDev / 80.0)) }
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
