//
//  OffStatExpandedView.swift
//  DynastyStatDrop
//
//  Refactored for centralized state management, all-time compliance, and position normalization.
//  - All stats use AppSelection (selectedLeague, selectedTeam, selectedSeason)
//  - Weekly charts exclude incomplete/current week if >1 week present
//  - "All Time" mode uses aggregate stats from league.allTimeOwnerStats
//  - All positions are normalized
//

import SwiftUI

struct OffStatExpandedView: View {
    // Centralized state management
    @EnvironmentObject var appSelection: AppSelection

    // MARK: - Derived State Helpers

    private var league: LeagueData? { appSelection.selectedLeague }
    private var season: SeasonData? {
        guard let league else { return nil }
        if appSelection.selectedSeason == "All Time" {
            return league.seasons.sorted { $0.id < $1.id }.last
        }
        return league.seasons.first { $0.id == appSelection.selectedSeason }
    }

    private var team: TeamStanding? { appSelection.selectedTeam }

    // All Time aggregate stats for current franchise
    private var aggregate: AggregatedOwnerStats? {
        guard appSelection.isAllTimeMode,
              let league,
              let team else { return nil }
        return league.allTimeOwnerStats?[team.ownerId]
    }

    private let offensePositions: [String] = ["QB", "RB", "WR", "TE", "K"]

    // MARK: - Weekly Points Calculation (Exclude Current Week if Incomplete)

    /// Helper: Returns completed weeks for charts and averages (excludes current if >1 week present)
    private var completedWeeks: [Int] {
        guard let season else { return [] }
        let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
        if allWeeks.count <= 1 { return allWeeks }
        if let currentWeek = allWeeks.max() {
            // Exclude current only if more than 1 week present
            return allWeeks.filter { $0 != currentWeek }
        }
        return allWeeks
    }

    /// Returns weekly offensive points for completed weeks (actual starters, normalized positions)
    private var weeklyOffensivePoints: [Double] {
        guard let team, let season else { return [] }
        let weeks = completedWeeks
        var points: [Double] = []
        for week in weeks {
            guard let weekEntries = season.matchupsByWeek?[week],
                  let rosterId = Int(team.id),
                  let entry = weekEntries.first(where: { $0.roster_id == rosterId }),
                  let starters = entry.starters,
                  let playersPoints = entry.players_points else {
                points.append(0)
                continue
            }
            let lineupConfig = team.lineupConfig ?? inferredLineupConfig(from: team.roster)
            let slots = expandSlots(lineupConfig: lineupConfig)
            let paddedStarters: [String] = {
                if starters.count < slots.count {
                    return starters + Array(repeating: "0", count: slots.count - starters.count)
                } else if starters.count > slots.count {
                    return Array(starters.prefix(slots.count))
                }
                return starters
            }()
            var weekOff = 0.0
            for idx in 0..<slots.count {
                let pid = paddedStarters[idx]
                guard pid != "0" else { continue }
                let player = team.roster.first(where: { $0.id == pid })
                let candidatePositions = ([player?.position ?? ""] + (player?.altPositions ?? [])).filter { !$0.isEmpty }
                let credited = SlotPositionAssigner.countedPosition(
                    for: slots[idx],
                    candidatePositions: candidatePositions,
                    base: player?.position ?? ""
                )
                let normPos = PositionNormalizer.normalize(credited)
                let pts = playersPoints[pid] ?? 0
                if offensePositions.contains(normPos) {
                    weekOff += pts
                }
            }
            points.append(weekOff)
        }
        return points
    }

    // MARK: - Aggregate Stats (All Time Mode)

    private var totalOffPF: Double {
        if let agg = aggregate { return agg.totalOffensivePointsFor }
        return team?.offensivePointsFor ?? 0
    }
    private var totalMaxOffPF: Double {
        if let agg = aggregate { return agg.totalMaxOffensivePointsFor }
        return team?.maxOffensivePointsFor ?? 0
    }
    private var managementPercent: Double {
        if let agg = aggregate { return agg.offensiveManagementPercent }
        if let tm = team, let max = tm.maxOffensivePointsFor, max > 0 {
            return (tm.offensivePointsFor ?? 0) / max * 100
        }
        return 0
    }
    private var avgPPW: Double {
        if let agg = aggregate { return agg.offensivePPW }
        return team?.averageOffensivePPW ?? 0
    }

    // MARK: - Position PPW/IndividualPPW (Normalized)

    private func posPPW(_ pos: String) -> Double {
        let norm = PositionNormalizer.normalize(pos)
        if let agg = aggregate { return agg.positionAvgPPW[norm] ?? 0 }
        return team?.positionAverages?[norm] ?? 0
    }
    private func posIndPPW(_ pos: String) -> Double {
        let norm = PositionNormalizer.normalize(pos)
        if let agg = aggregate { return agg.individualPositionPPW[norm] ?? 0 }
        return team?.individualPositionAverages?[norm] ?? 0
    }

    // MARK: - UI

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            sectionHeader("Offensive Weekly Trend")
            SparklineChart(
                points: weeklyOffensivePoints,
                stroke: .orange,
                gradient: LinearGradient(colors: [.orange, .clear], startPoint: .top, endPoint: .bottom),
                lineWidth: 2
            )
            .frame(height: 60)
            sectionHeader("Lineup Efficiency")
            lineupEfficiency
            sectionHeader("Recent Form")
            recentForm
            positionBreakdown
            if let league = league, let tm = team {
                StatDropAnalysisBox(team: tm, league: league, context: .offense, personality: .classicESPN)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("OFF PF \(String(format: "%.2f", totalOffPF))")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("Avg \(String(format: "%.2f", avgPPW))")
        }
        .font(.caption)
        .foregroundColor(.white.opacity(0.85))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.orange)
            .padding(.top, 4)
    }

    private var lineupEfficiency: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statBlock(title: "PF", value: totalOffPF)
                statBlock(title: "Max", value: totalMaxOffPF)
                statBlockPercent(title: "Mgmt%", value: managementPercent)
            }
            EfficiencyBar(ratio: managementPercent / 100.0, height: 12)
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var recentForm: some View {
        let pts = weeklyOffensivePoints
        let weeksPlayed = pts.count
        let last3Avg = weeksPlayed > 0 ? pts.suffix(3).reduce(0,+)/Double(min(3,weeksPlayed)) : 0
        let seasonAvg = weeksPlayed > 0 ? pts.reduce(0,+)/Double(weeksPlayed) : avgPPW
        let formDelta = last3Avg - seasonAvg
        let arrow = formDelta > 0.5 ? "↑" : (formDelta < -0.5 ? "↓" : "→")
        let formDeltaColor: Color = {
            if formDelta > 2 { return .green }
            if formDelta < -2 { return .red }
            return .yellow
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                formStatBlock("Last 3", last3Avg)
                formStatBlock("Season", seasonAvg)
                formDeltaBlock(arrow: arrow, delta: formDelta, color: formDeltaColor)
            }
            Text("Compares recent 3 weeks to season average for this unit.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var positionBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Positions")
                .font(.headline).foregroundColor(.yellow)
            ForEach(offensePositions, id: \.self) { pos in
                let normPos = PositionNormalizer.normalize(pos)
                HStack {
                    Text("\(normPos):")
                        .foregroundColor(colorFor(normPos)).bold()
                    Text("Avg/Wk: \(String(format: "%.2f", posPPW(normPos)))")
                        .foregroundColor(.white)
                    Text("Per Slot: \(String(format: "%.2f", posIndPPW(normPos)))")
                        .foregroundColor(.cyan)
                }
                .font(.caption.bold())
            }
        }
    }

    // MARK: - UI Helpers

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

    private func formDeltaBlock(arrow: String, delta: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(arrow) \(String(format: "%+.2f", delta))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            Text("Delta")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func colorFor(_ pos: String) -> Color {
        switch PositionNormalizer.normalize(pos) {
        case "QB": return .red
        case "RB": return .green
        case "WR": return .blue
        case "TE": return .yellow
        case "K": return .purple
        default: return .white
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

    // MARK: - Utility Functions (copied from Position.swift & AllTimeAggregator.swift for continuity)

    private func expandSlots(lineupConfig: [String: Int]) -> [String] {
        lineupConfig.flatMap { Array(repeating: $0.key, count: $0.value) }
    }

    private func inferredLineupConfig(from roster: [Player]) -> [String:Int] {
        var counts: [String:Int] = [:]
        for p in roster {
            let normalized = PositionNormalizer.normalize(p.position)
            counts[normalized, default: 0] += 1
        }
        return counts.mapValues { min($0, 3) }
    }
}
