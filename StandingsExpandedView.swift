//
//  StandingsExpandedView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/22/25.
//

//
//  StatCardDetailViews.swift
//  DynastyStatDrop
//
//  Expanded detail panels for each section (index 0..3)
//  Includes data extraction helpers from TeamStanding + DSDStatsService.
//

import SwiftUI

struct StandingsExpandedView: View {
    // Use centralized app selection for all league, season, team state
    @EnvironmentObject var appSelection: AppSelection

    var teams: [TeamStanding] {
        guard let league = appSelection.selectedLeague else { return [] }
        if appSelection.selectedSeason == "All Time" {
            return league.seasons.sorted { $0.id < $1.id }.last?.teams ?? league.teams
        }
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams
            ?? league.seasons.sorted { $0.id < $1.id }.last?.teams
            ?? league.teams
    }

    var selectedTeamId: String? { appSelection.selectedTeamId }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Standings")
                .font(.custom("Phatt", size: 24))
                .foregroundColor(.orange)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(spacing: 6) {
                    HStack {
                        Text("Team").frame(width: 120, alignment: .leading)
                        Text("W-L").frame(width: 60)
                        Text("PF").frame(width: 70)
                        Text("PPW").frame(width: 60)
                        Text("Mgmt%").frame(width: 70)
                        Spacer()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.yellow.opacity(0.8))

                    ForEach(teams.sorted(by: { $0.pointsFor > $1.pointsFor })) { t in
                        HStack {
                            Text(t.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)
                            Text(t.winLossRecord ?? "--")
                                .frame(width: 60)
                            Text(String(format: "%.0f", t.pointsFor))
                                .frame(width: 70)
                            Text(String(format: "%.2f", t.teamPointsPerWeek))
                                .frame(width: 60)
                            Text(String(format: "%.1f%%", t.managementPercent))
                                .frame(width: 70)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(t.id == selectedTeamId ? 0.1 : 0.04))
                        )
                        .onTapGesture {
                            // Centralized update, select team in appSelection
                            appSelection.selectedTeamId = t.id
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Expanded Standings")
    }
}

// MARK: TeamExpandedView

struct TeamExpandedView: View {
    let team: TeamStanding
    let league: LeagueData?
    let aggregatedAllTime: ( (TeamStanding) -> DSDDashboard.AggregatedTeamStats? )
    
    // Derived series (simple example)
    var weeklyPoints: [Double] {
        // Sum roster weekly scores by week
        let grouped = Dictionary(grouping: team.roster.flatMap { $0.weeklyScores }, by: { $0.week })
        let weeks = grouped.keys.sorted()
        return weeks.map { wk in
            grouped[wk]?.reduce(0) { $0 + ($1.points_half_ppr ?? $1.points) } ?? 0
        }
    }
    
    var offenseVsDefenseSegments: [(Color, Double)] {
        let off = team.offensivePointsFor ?? 0
        let def = team.defensivePointsFor ?? 0
        return [
            (.red, off),
            (.blue, def)
        ]
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                sparklineSection
                efficiencySection
                playoffStatsSection
                splitStacked
                recentFormSection
                highlightsSection
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Expanded Team Metrics")
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(team.name)
                .font(.custom("Phatt", size: 26))
                .foregroundColor(.orange)
            Text("Record: \(team.winLossRecord ?? "--") • PF \(String(format: "%.0f", team.pointsFor)) • PPW \(String(format: "%.2f", team.teamPointsPerWeek))")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly Points Trend")
                .font(.headline)
                .foregroundColor(.yellow)
            SparklineChart(
                points: weeklyPoints,
                stroke: .orange,
                gradient: LinearGradient(colors: [.orange, .clear], startPoint: .top, endPoint: .bottom),
                lineWidth: 2
            )
            .frame(height: 60)
        }
    }
    
    private var efficiencySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lineup Efficiency")
                .font(.headline)
                .foregroundColor(.yellow)
            Text(String(format: "Management %%: %.1f%%", team.managementPercent))
                .font(.caption)
            if let offPct = team.offensiveManagementPercent {
                Text(String(format: "Off Eff: %.1f%%", offPct)).font(.caption2)
            }
            if let defPct = team.defensiveManagementPercent {
                Text(String(format: "Def Eff: %.1f%%", defPct)).font(.caption2)
            }
        }
    }
    
    private var splitStacked: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Off vs Def Contribution")
                .font(.headline)
                .foregroundColor(.yellow)
            StackedBarPercent(segments: offenseVsDefenseSegments.map { ($0.0, $0.1) })
                .frame(height: 14)
            HStack {
                Text("OFF \(Int(offenseVsDefenseSegments[0].1))").foregroundColor(.red).font(.caption2)
                Text("DEF \(Int(offenseVsDefenseSegments[1].1))").foregroundColor(.blue).font(.caption2)
            }
        }
    }
    
    private var recentFormSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Form (Last 3 vs Prev 3)")
                .font(.headline)
                .foregroundColor(.yellow)
            let last3 = Array(weeklyPoints.suffix(3))
            let prev3 = Array(weeklyPoints.dropLast().suffix(3))
            let lastAvg = average(last3)
            let prevAvg = average(prev3)
            let delta = lastAvg - prevAvg
            Text(String(format: "Last 3 Avg: %.1f • Prev 3 Avg: %.1f • Δ %.1f", lastAvg, prevAvg, delta))
                .font(.caption2)
                .foregroundColor(delta >= 0 ? .green : .red)
        }
    }
    
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Highlights")
                .font(.headline)
                .foregroundColor(.yellow)
            Text("Best Game: \(team.bestGameDescription ?? "--")")
                .font(.caption2)
            Text("Biggest Rival: \(team.biggestRival ?? "--")")
                .font(.caption2)
            highlightChips
        }
    }
    
    private var highlightChips: some View {
        let strengths = team.strengths ?? []
        let weaknesses = team.weaknesses ?? []
        return VStack(alignment: .leading, spacing: 4) {
            if !strengths.isEmpty {
                Text("Strengths").font(.caption.bold()).foregroundColor(.green)
                WrapHStack(items: strengths, color: .green)
            }
            if !weaknesses.isEmpty {
                Text("Weaknesses").font(.caption.bold()).foregroundColor(.red)
                WrapHStack(items: weaknesses, color: .red)
            }
        }
    }
    
    private func average(_ arr: [Double]) -> Double {
        guard !arr.isEmpty else { return 0 }
        return arr.reduce(0,+)/Double(arr.count)
    }
    private var playoffStatsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Playoff Stats")
                .font(.headline)
                .foregroundColor(.yellow)
            if let playoff = aggregatedAllTime(team)?.playoffStats {  // <-- Use the correct property name!
                Text("Record: \(playoff.recordString)")
                Text("Points For: \(String(format: "%.0f", playoff.pointsFor))")
                Text("PPW: \(String(format: "%.2f", playoff.ppw))")
                if let mgmt = playoff.managementPercent {
                    Text("Mgmt%: \(String(format: "%.1f", mgmt))")
                }
                if let off = playoff.offensivePointsFor {
                    Text("Off Points: \(String(format: "%.0f", off))")
                }
                if let def = playoff.defensivePointsFor {
                    Text("Def Points: \(String(format: "%.0f", def))")
                }
            } else {
                Text("No playoff data").font(.caption)
            }
        }
    }
}
struct OffDefExpandedView: View {
    enum Mode { case offense, defense }
    let team: TeamStanding
    let mode: Mode

    // Build small arrays for charts
    var weeklySidePoints: [Double] {
        let posSet: Set<String> = mode == .offense
            ? ["QB","RB","WR","TE","K"]
            : ["DL","LB","DB"]
        let wkGrouped = Dictionary(grouping: team.roster.filter { posSet.contains($0.position) }.flatMap { $0.weeklyScores }, by: { $0.week })
        let weeks = wkGrouped.keys.sorted()
        return weeks.map { wkGrouped[$0]?.reduce(0) { $0 + ($1.points_half_ppr ?? $1.points) } ?? 0 }
    }

    var positionAverages: [(String, Double)] {
        guard let posAvg = team.positionAverages else { return [] }
        let allowed: Set<String> = mode == .offense
            ? ["QB","RB","WR","TE","K"]
            : ["DL","LB","DB"]
        return posAvg.filter { allowed.contains($0.key) }.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    var usageSegments: [(Color, Double)] {
        positionAverages.map { (colorForPosition($0.0), $0.1) }
    }

    var heatMatrix: [[Double]] {
        // Single row -> positions; create pseudo weekly dimension (average only)
        [positionAverages.map { $0.1 }]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(mode == .offense ? "Offensive Breakdown" : "Defensive Breakdown")
                    .font(.custom("Phatt", size: 24))
                    .foregroundColor(mode == .offense ? .red : .blue)
                sparkline
                positionGrid
                usageDonut
                strengthsWeaknesses
                boomRate
            }
            .padding(.vertical, 4)
        }
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weekly \(mode == .offense ? "Offense" : "Defense") Points")
                .font(.headline)
                .foregroundColor(.yellow)
            SparklineChart(points: weeklySidePoints, stroke: mode == .offense ? .red : .blue)
                .frame(height: 60)
        }
    }

    private var positionGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Position Averages")
                .font(.headline)
                .foregroundColor(.yellow)
            HeatGrid(
                matrix: heatMatrix,
                rowLabels: ["Avg"],
                colLabels: positionAverages.map { $0.0 },
                color: mode == .offense ? .red : .blue
            )
            .frame(height: 70)
        }
    }

    private var usageDonut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position Usage (Weighted Avg)")
                .font(.headline).foregroundColor(.yellow)
            HStack {
                DonutChartMini(segments: usageSegments)
                    .frame(width: 90, height: 90)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(positionAverages, id: \.0) { item in
                        HStack {
                            Circle().fill(colorForPosition(item.0)).frame(width: 10, height: 10)
                            Text("\(item.0): \(String(format: "%.1f", item.1))")
                                .font(.caption2)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private var strengthsWeaknesses: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mode == .offense {
                if let strengths = team.offensiveStrengths, !strengths.isEmpty {
                    Text("Strengths").font(.headline).foregroundColor(.green)
                    WrapHStack(items: strengths, color: .green)
                }
                if let weaknesses = team.offensiveWeaknesses, !weaknesses.isEmpty {
                    Text("Weaknesses").font(.headline).foregroundColor(.red)
                    WrapHStack(items: weaknesses, color: .red)
                }
            } else {
                if let strengths = team.defensiveStrengths, !strengths.isEmpty {
                    Text("Strengths").font(.headline).foregroundColor(.green)
                    WrapHStack(items: strengths, color: .green)
                }
                if let weaknesses = team.defensiveWeaknesses, !weaknesses.isEmpty {
                    Text("Weaknesses").font(.headline).foregroundColor(.red)
                    WrapHStack(items: weaknesses, color: .red)
                }
            }
        }
    }

    private var boomRate: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Boom Rate")
                .font(.headline)
                .foregroundColor(.yellow)
            let threshold = percentile(weeklySidePoints, pct: 0.75)
            let booms = weeklySidePoints.filter { $0 >= threshold }.count
            let rate = weeklySidePoints.isEmpty ? 0 : Double(booms)/Double(weeklySidePoints.count)*100
            Text(String(format: "≥ 75th pct threshold (%.0f pts): %.1f%% (%d of %d weeks)", threshold, rate, booms, weeklySidePoints.count))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func percentile(_ arr: [Double], pct: Double) -> Double {
        guard !arr.isEmpty else { return 0 }
        let sorted = arr.sorted()
        let idx = Int((Double(sorted.count) - 1) * pct)
        return sorted[max(0, min(sorted.count - 1, idx))]
    }

    private func colorForPosition(_ pos: String) -> Color {
        switch pos {
        case "QB": return .red
        case "RB": return .green
        case "WR": return .blue
        case "TE": return .yellow
        case "K": return .purple
        case "DL": return .orange
        case "LB": return .purple.opacity(0.6)
        case "DB": return .pink
        default: return .gray
        }
    }
}

// MARK: - Utility Wrapping Layout

struct WrapHStack: View {
    let items: [String]
    let color: Color
    @State private var totalHeight: CGFloat = 0

    var body: some View {
        VStack {
            GeometryReader { geo in
                self.generateContent(in: geo)
            }
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                chip(item)
                    .padding([.horizontal, .vertical], 4)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > g.size.width {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if item == items.last {
                            width = 0 // last
                        } else {
                            width -= d.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color.opacity(0.75))
            .clipShape(Capsule())
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo -> Color in
            DispatchQueue.main.async {
                binding.wrappedValue = -geo.frame(in: .local).origin.y
            }
            return Color.clear
        }
    }
}
