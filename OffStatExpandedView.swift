// https://github.com/ThirstyWallrus/10-17-25/blob/a17b188b627ea4e728bbba5584f5d108dbc557af/OffStatExpandedView.swift
//
//  OffStatExpandedView.swift
//  DynastyStatDrop
//
//  Uses authoritative matchup.players_points when available; sums starters only when starters present.
//  Falls back to deduped roster.weeklyScores when necessary.
//

import SwiftUI

struct OffStatExpandedView: View {
    @EnvironmentObject var appSelection: AppSelection

    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false

    // Offensive positions
    private let offPositions: [String] = ["QB", "RB", "WR", "TE", "K"]

    // Position color mapping
    private var positionColors: [String: Color] {
        [
            "QB": .red,
            "RB": .green,
            "WR": .blue,
            "TE": .yellow,
            "K": Color.purple,
            "DL": .orange,
            "LB": .purple,
            "DB": .pink
        ]
    }

    // MARK: - Team/League/Season State

    private var team: TeamStanding? { appSelection.selectedTeam }
    private var league: LeagueData? { appSelection.selectedLeague }
    private var isAllTime: Bool { appSelection.isAllTimeMode }
    private var aggregate: AggregatedOwnerStats? {
        guard isAllTime, let league, let team else { return nil }
        return league.allTimeOwnerStats?[team.ownerId]
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
        // For all time mode, use the latest season's weeks (for continuity in charts)
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

    // MARK: - Authoritative week points helper
    private func authoritativePointsForWeek(team: TeamStanding, week: Int) -> [String: Double] {
        // 1) players_points from matchup entry if available (prefer starters only)
        if let league = league {
            let season = (!isAllTime)
                ? league.seasons.first(where: { $0.id == appSelection.selectedSeason })
                : league.seasons.sorted { $0.id < $1.id }.last
            if let season {
                if let entries = season.matchupsByWeek?[week],
                   let rosterIdInt = Int(team.id),
                   let myEntry = entries.first(where: { $0.roster_id == rosterIdInt }),
                   let playersPoints = myEntry.players_points, !playersPoints.isEmpty {
                    if let starters = myEntry.starters, !starters.isEmpty {
                        var map: [String: Double] = [:]
                        for pid in starters {
                            if let pts = playersPoints[pid] {
                                map[pid] = pts
                            } else {
                                map[pid] = 0.0
                            }
                        }
                        return map
                    } else {
                        return playersPoints.mapValues { $0 }
                    }
                }
            }
        }
        // 2) fallback: deduplicated roster.weeklyScores
        var result: [String: Double] = [:]
        var preferredMatchupId: Int? = nil
        if let league = league {
            let season = (!isAllTime)
                ? league.seasons.first(where: { $0.id == appSelection.selectedSeason })
                : league.seasons.sorted { $0.id < $1.id }.last
            if let season, let entries = season.matchupsByWeek?[week], let rosterIdInt = Int(team.id) {
                preferredMatchupId = entries.first(where: { $0.roster_id == rosterIdInt })?.matchup_id
            }
        }
        for player in team.roster {
            let scores = player.weeklyScores.filter { $0.week == week }
            if scores.isEmpty { continue }
            if let mid = preferredMatchupId, let matched = scores.first(where: { $0.matchup_id == mid }) {
                result[player.id] = matched.points_half_ppr ?? matched.points
            } else {
                if let best = scores.max(by: { ($0.points_half_ppr ?? $0.points) < ($1.points_half_ppr ?? $1.points) }) {
                    result[player.id] = best.points_half_ppr ?? best.points
                }
            }
        }
        return result
    }

    // MARK: - Stacked Bar Chart Data

    private var stackedBarWeekData: [StackedBarWeeklyChart.WeekBarData] {
        guard let team else { return [] }
        let sortedWeeks = validWeeks
        return sortedWeeks.map { week in
            let playerPoints = authoritativePointsForWeek(team: team, week: week)
            var posSums: [String: Double] = [:]
            for (pid, pts) in playerPoints {
                if let player = team.roster.first(where: { $0.id == pid }) {
                    let norm = PositionNormalizer.normalize(player.position)
                    if ["QB","RB","WR","TE","K"].contains(norm) {
                        posSums[norm, default: 0.0] += pts
                    }
                }
            }
            let segments = offPositions.map { pos in
                let norm = PositionNormalizer.normalize(pos)
                StackedBarWeeklyChart.WeekBarData.Segment(id: pos, position: norm, value: posSums[norm] ?? 0)
            }
            return StackedBarWeeklyChart.WeekBarData(id: week, segments: segments as! [StackedBarWeeklyChart.WeekBarData.Segment])
        }
    }

    // Helper: check if a PlayerWeeklyScore's player matches the target normalized position
    private func matchesNormalizedPosition(_ score: PlayerWeeklyScore, pos: String) -> Bool {
        guard let team = team,
              let player = team.roster.first(where: { $0.id == score.player_id }) else { return false }
        return PositionNormalizer.normalize(player.position) == PositionNormalizer.normalize(pos)
    }

    private var sideWeeklyPoints: [Double] {
        stackedBarWeekData.map { $0.total }
    }

    private var weeksPlayed: Int { sideWeeklyPoints.count }
    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        return sideWeeklyPoints.suffix(3).reduce(0,+)/Double(min(3,weeksPlayed))
    }
    private var seasonAvg: Double {
        guard weeksPlayed > 0 else {
            if let agg = aggregate { return agg.offensivePPW }
            return team?.averageOffensivePPW ?? 0
        }
        return sideWeeklyPoints.reduce(0,+)/Double(weeksPlayed)
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var formDeltaColor: Color {
        if formDelta > 2 { return .green }
        if formDelta < -2 { return .red }
        return .yellow
    }

    // MARK: - Offensive Points and Management %

    private var sidePoints: Double {
        if let agg = aggregate { return agg.totalOffensivePointsFor }
        return team?.offensivePointsFor ?? 0
    }
    private var sideMaxPoints: Double {
        if let agg = aggregate { return agg.totalMaxOffensivePointsFor }
        return team?.maxOffensivePointsFor ?? 0
    }
    private var managementPercent: Double {
        guard sideMaxPoints > 0 else { return 0 }
        return (sidePoints / sideMaxPoints) * 100
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
            if agg.offensiveManagementPercent >= 75 { arr.append("Efficient Usage") }
            if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
            if arr.isEmpty { arr.append("Developing Unit") }
            return arr
        }
        var arr: [String] = []
        if managementPercent >= 75 { arr.append("Efficient Usage") }
        if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
        if arr.isEmpty { arr.append("Developing Unit") }
        return arr
    }
    private var weaknesses: [String] {
        if let agg = aggregate {
            var arr: [String] = []
            if agg.offensiveManagementPercent < 55 { arr.append("Usage Inefficiency") }
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
            sectionHeader("Offensive Weekly Trend")
            StackedBarWeeklyChart(
            weekBars: stackedBarWeekData,
            positionColors: positionColors,
            showPositions: Set(offPositions),
            gridIncrement: 25,
            barSpacing: 4,
            tooltipFont: .caption2.bold(),
            showWeekLabels: true
            )
            .frame(height: 140)
            sectionHeader("Lineup Efficiency")
            lineupEfficiency
            sectionHeader("Recent Form")
            recentForm
            if let team = team, let league = league {
                StatDropAnalysisBox(
                    team: team,
                    league: league,
                    context: .offense,
                    personality: .classicESPN
                )
            }
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

    // Small components omitted for brevity (unchanged from previous file version)
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
