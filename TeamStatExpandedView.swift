//
//  TeamStatExpandedView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/25/25.
//
//  Updated to match OffStatExpandedView / DefStatExpandedView structure.
//  This view now mirrors the layout and behavior of the Off/Def expanded views,
//  but shows the whole team's contributions (offense + defense) rather than a
//  side-specific panel. It uses AppSelection for centralized team/league/season
//  state, excludes the current week if it's likely incomplete, and respects
//  All Time aggregated stats when available.
//

import SwiftUI

struct TeamStatExpandedView: View {
    @EnvironmentObject var appSelection: AppSelection
    // Closure returns (optional) aggregated all time stats wrapper for this team
    let aggregatedAllTime: (TeamStanding) -> DSDDashboard.AggregatedTeamStats?
    
    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false
    
    // Positions used for the whole-team breakdown (offense + defense)
    private let teamPositions: [String] = ["QB","RB","WR","TE","K","DL","LB","DB"]
    
    // Position color mapping (normalized tokens)
    private var positionColors: [String: Color] {
        [
            PositionNormalizer.normalize("QB"): .red,
            PositionNormalizer.normalize("RB"): .green,
            PositionNormalizer.normalize("WR"): .blue,
            PositionNormalizer.normalize("TE"): .yellow,
            PositionNormalizer.normalize("K"): Color.purple,
            PositionNormalizer.normalize("DL"): .orange,
            PositionNormalizer.normalize("LB"): .purple.opacity(0.7),
            PositionNormalizer.normalize("DB"): .pink
        ]
    }
    
    // Use selected team from AppSelection
    private var team: TeamStanding? { appSelection.selectedTeam }
    private var league: LeagueData? { appSelection.selectedLeague }
    private var isAllTime: Bool { appSelection.isAllTimeMode }
    private var aggregate: DSDDashboard.AggregatedTeamStats? {
        guard isAllTime, let t = team else { return nil }
        return aggregatedAllTime(t)
    }
    
    // MARK: - Weeks to Include (Exclude Current Week if Incomplete)
    private var validWeeks: [Int] {
        guard let league, let team else { return [] }
        // For season mode, use the selected season
        if !isAllTime, let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
            let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        // For all time mode, use the latest season's weeks (continuity)
        if isAllTime {
            let latest = league.seasons.sorted { $0.id < $1.id }.last
            let allWeeks = latest?.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        return []
    }
    
    // MARK: - Stacked Bar Chart Data (whole team)
    private var stackedBarWeekData: [StackedBarWeeklyChart.WeekBarData] {
        guard let team else { return [] }
        let grouped = Dictionary(grouping: team.roster.flatMap { $0.weeklyScores }, by: { $0.week })
        let sortedWeeks = validWeeks
        return sortedWeeks.map { week in
            // Sum scores by normalized position for this week
            let posSums: [String: Double] = teamPositions.reduce(into: [:]) { dict, pos in
                let norm = PositionNormalizer.normalize(pos)
                dict[norm] = grouped[week]?
                    .filter { matchesNormalizedPosition($0, pos: pos) }
                    .reduce(0) { $0 + ($1.points_half_ppr ?? $1.points) } ?? 0
            }
            let segments = teamPositions.map { pos in
                StackedBarWeeklyChart.WeekBarData.Segment(
                    id: pos,
                    position: PositionNormalizer.normalize(pos),
                    value: posSums[PositionNormalizer.normalize(pos)] ?? 0
                )
            }
            return StackedBarWeeklyChart.WeekBarData(id: week, segments: segments)
        }
    }
    
    // Helper: check if a PlayerWeeklyScore's player matches the target normalized position
    private func matchesNormalizedPosition(_ score: PlayerWeeklyScore, pos: String) -> Bool {
        guard let team = team,
              let player = team.roster.first(where: { $0.id == score.player_id }) else { return false }
        return PositionNormalizer.normalize(player.position) == PositionNormalizer.normalize(pos)
    }
    
    // Derived weekly totals (actual roster total per week)
    private var sideWeeklyPoints: [Double] {
        stackedBarWeekData.map { $0.total }
    }
    
    private var weeksPlayed: Int { sideWeeklyPoints.count }
    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        return sideWeeklyPoints.suffix(3).reduce(0,+) / Double(min(3, weeksPlayed))
    }
    private var seasonAvg: Double {
        guard weeksPlayed > 0 else {
            if let agg = aggregate { return agg.avgTeamPPW }
            return team?.teamPointsPerWeek ?? 0
        }
        return sideWeeklyPoints.reduce(0,+) / Double(weeksPlayed)
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var formDeltaColor: Color {
        if formDelta > 2 { return .green }
        if formDelta < -2 { return .red }
        return .yellow
    }
    
    // MARK: - Team Points and Management %
    private var teamPointsFor: Double {
        if let agg = aggregate { return agg.totalPointsFor }
        return team?.pointsFor ?? 0
    }
    private var teamMaxPointsFor: Double {
        if let agg = aggregate { return agg.totalMaxPointsFor }
        return team?.maxPointsFor ?? 0
    }
    private var managementPercent: Double {
        guard teamMaxPointsFor > 0 else { return 0 }
        return (teamPointsFor / teamMaxPointsFor) * 100
    }
    
    // MARK: - Consistency (StdDev)
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
    
    // MARK: - Strengths/Weaknesses
    private var strengths: [String] {
        if let agg = aggregate {
            var arr: [String] = []
            if agg.aggregatedManagementPercent >= 75 { arr.append("Efficient Usage") }
            if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
            if arr.isEmpty { arr.append("Balanced Roster") }
            return arr
        }
        var arr: [String] = []
        if managementPercent >= 75 { arr.append("Efficient Usage") }
        if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
        if arr.isEmpty { arr.append("Balanced Roster") }
        return arr
    }
    private var weaknesses: [String] {
        if let agg = aggregate {
            var arr: [String] = []
            if agg.aggregatedManagementPercent < 55 { arr.append("Usage Inefficiency") }
            if stdDev > 40 { arr.append("Volatility") }
            if weeksPlayed >= 3 && last3Avg < seasonAvg - 5 { arr.append("Recent Dip") }
            if arr.isEmpty { arr.append("No Major Weakness") }
            return arr
        }
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
            sectionHeader("Team Weekly Trend")
            // Chart: Excludes current week if incomplete, uses normalized positions
            StackedBarWeeklyChart(
                weekBars: stackedBarWeekData,
                positionColors: positionColors,
                gridLines: [50, 100, 150, 200],
                chartTop: max(200, (stackedBarWeekData.map { $0.total }.max() ?? 200) * 1.25),
                showPositions: Set(teamPositions.map(PositionNormalizer.normalize)),
                barSpacing: 4,
                tooltipFont: .caption2.bold(),
                showWeekLabels: true
            )
            .frame(height: 160)
            sectionHeader("Lineup Efficiency")
            lineupEfficiency
            sectionHeader("Recent Form")
            recentForm
            if let team = team, let league = league {
                StatDropAnalysisBox(
                    team: team,
                    league: league,
                    context: .team,
                    personality: .classicESPN
                )
            }
            sectionHeader("Consistency Score")
            consistencyRow
            // Strengths / Weaknesses chips
            sectionHeader("Strengths")
            FlowLayoutCompat(items: strengths) { Pill(text: $0, bg: Color.green.opacity(0.22), stroke: .green) }
            sectionHeader("Weaknesses")
            FlowLayoutCompat(items: weaknesses) { Pill(text: $0, bg: Color.red.opacity(0.22), stroke: .red) }
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
    
    private var header: some View {
        HStack(spacing: 12) {
            Text(team?.winLossRecord ?? "--")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("PF \(String(format: "%.2f", teamPointsFor))")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("PPW \(String(format: "%.2f", seasonAvg))")
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
                statBlock(title: "PF", value: teamPointsFor)
                statBlock(title: "Max", value: teamMaxPointsFor)
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
            Text("Compares recent 3 weeks to season average for this team.")
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
    
    // Small reusable components (mirrored from Off/Def)
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
}
