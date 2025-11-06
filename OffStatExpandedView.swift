//
//  OffStatExpandedView.swift
//  DynastyStatDrop
//
//  Uses authoritative matchup.players_points when available; sums starters only when starters present.
//  Falls back to deduped roster.weeklyScores when necessary.
//
//  Updated to match TeamStatExpandedView patterns for app continuity:
//   - Uses League/Sleeper caches when available
//   - Computes grade via TeamGradeComponents + gradeTeams
//   - Excludes empty/future weeks when computing OPPW (uses non-zero weeks like TeamStatExpandedView)
//   - Uses ElectrifiedGrade for grade bubble and consistent fallbacks to aggregated all-time stats
//

import SwiftUI

struct OffStatExpandedView: View {
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var leagueManager: SleeperLeagueManager

    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false

    // Offensive positions
    private let offPositions: [String] = ["QB", "RB", "WR", "TE", "K"]

    // Position color mapping (normalized tokens)
    private var positionColors: [String: Color] {
        [
            PositionNormalizer.normalize("QB"): .red,
            PositionNormalizer.normalize("RB"): .green,
            PositionNormalizer.normalize("WR"): .blue,
            PositionNormalizer.normalize("TE"): .yellow,
            PositionNormalizer.normalize("K"): Color.purple,
            // keep defensive colors present for potential lookups
            PositionNormalizer.normalize("DL"): .orange,
            PositionNormalizer.normalize("LB"): .purple.opacity(0.7),
            PositionNormalizer.normalize("DB"): .pink
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

    // MARK: - Grade computation (use TeamGradeComponents & gradeTeams for consistency)
    private var computedGrade: (grade: String, composite: Double)? {
        guard let lg = league else { return nil }
        let teamsToProcess: [TeamStanding] = {
            if !isAllTime, let season = lg.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
                return season.teams
            }
            return lg.seasons.sorted { $0.id < $1.id }.last?.teams ?? lg.teams
        }()
        var comps: [TeamGradeComponents] = []
        for t in teamsToProcess {
            // For all-time, prefer aggregated owner stats if present
            let aggOwner: AggregatedOwnerStats? = {
                if isAllTime { return lg.allTimeOwnerStats?[t.ownerId] }
                return nil
            }()

            let pf: Double = {
                if isAllTime { return aggOwner?.totalPointsFor ?? t.pointsFor }
                return t.pointsFor
            }()
            let mpf: Double = {
                if isAllTime { return aggOwner?.totalMaxPointsFor ?? t.maxPointsFor }
                return t.maxPointsFor
            }()
            let mgmt = (mpf > 0) ? (pf / mpf * 100) : (t.managementPercent)

            let offMgmt: Double = {
                if isAllTime {
                    if let agg = aggOwner, agg.totalMaxOffensivePointsFor > 0 {
                        return (agg.totalOffensivePointsFor / agg.totalMaxOffensivePointsFor) * 100
                    }
                    return t.offensiveManagementPercent ?? 0
                } else {
                    return t.offensiveManagementPercent ?? 0
                }
            }()

            let defMgmt: Double = {
                if isAllTime {
                    if let agg = aggOwner, agg.totalMaxDefensivePointsFor > 0 {
                        return (agg.totalDefensivePointsFor / agg.totalMaxDefensivePointsFor) * 100
                    }
                    return t.defensiveManagementPercent ?? 0
                } else {
                    return t.defensiveManagementPercent ?? 0
                }
            }()

            let ppwVal: Double = {
                if isAllTime {
                    return aggOwner?.teamPPW ?? t.teamPointsPerWeek
                }
                if let lg2 = lg as LeagueData? {
                    return (DSDStatsService.shared.stat(for: t, type: .teamAveragePPW, league: lg2, selectedSeason: appSelection.selectedSeason) as? Double) ?? t.teamPointsPerWeek
                }
                return t.teamPointsPerWeek
            }()

            let qb = (t.positionAverages?[PositionNormalizer.normalize("QB")] ?? 0)
            let rb = (t.positionAverages?[PositionNormalizer.normalize("RB")] ?? 0)
            let wr = (t.positionAverages?[PositionNormalizer.normalize("WR")] ?? 0)
            let te = (t.positionAverages?[PositionNormalizer.normalize("TE")] ?? 0)
            let k  = (t.positionAverages?[PositionNormalizer.normalize("K")]  ?? 0)
            let dl = (t.positionAverages?[PositionNormalizer.normalize("DL")] ?? 0)
            let lb = (t.positionAverages?[PositionNormalizer.normalize("LB")] ?? 0)
            let db = (t.positionAverages?[PositionNormalizer.normalize("DB")] ?? 0)

            let (w,l,ties) = TeamGradeComponents.parseRecord(t.winLossRecord)
            let recordPct = (w + l + ties) > 0 ? Double(w) / Double(max(1, w + l + ties)) : 0.0

            let comp = TeamGradeComponents(
                pointsFor: pf,
                ppw: ppwVal,
                mgmt: mgmt,
                offMgmt: offMgmt,
                defMgmt: defMgmt,
                recordPct: recordPct,
                qbPPW: qb,
                rbPPW: rb,
                wrPPW: wr,
                tePPW: te,
                kPPW: k,
                dlPPW: dl,
                lbPPW: lb,
                dbPPW: db,
                teamName: t.name,
                teamId: t.id
            )
            comps.append(comp)
        }

        let graded = gradeTeams(comps)
        if let team = team, let found = graded.first(where: { $0.0 == team.name }) {
            return (found.1, found.2)
        }
        return nil
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
                // Prefer roster lookup; fall back to cached player info, and default to WR to preserve totals if unresolved.
                if let player = team.roster.first(where: { $0.id == pid }) {
                    let norm = PositionNormalizer.normalize(player.position)
                    if ["QB","RB","WR","TE","K"].contains(norm) {
                        posSums[norm, default: 0.0] += pts
                    } else {
                        // non-offensive credited to WR bucket for chart totals (conservative)
                        posSums["WR", default: 0.0] += pts
                    }
                } else if let raw = leagueManager.playerCache?[pid] ?? leagueManager.allPlayers[pid] {
                    let pos = PositionNormalizer.normalize(raw.position ?? "WR")
                    if ["QB","RB","WR","TE","K"].contains(pos) {
                        posSums[pos, default: 0.0] += pts
                    } else {
                        posSums["WR", default: 0.0] += pts
                    }
                } else {
                    posSums["WR", default: 0.0] += pts
                }
            }
            // Build segments using offPositions (QB,RB,WR,TE,K) to keep chart consistent
            let segments: [StackedBarWeeklyChart.WeekBarData.Segment] = offPositions.map { pos in
                let norm = PositionNormalizer.normalize(pos)
                return StackedBarWeeklyChart.WeekBarData.Segment(id: pos, position: norm, value: posSums[norm] ?? 0)
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

    private var sideWeeklyPoints: [Double] {
        stackedBarWeekData.map { $0.total }
    }

    // Use only non-zero weeks (completed weeks) for averages — matches TeamStatExpandedView behavior.
    private var sideWeeklyPointsNonZero: [Double] {
        let nonZero = sideWeeklyPoints.filter { $0 > 0.0 }
        if nonZero.isEmpty, let team = team, let weekly = team.weeklyActualLineupPoints {
            let vals = weekly.keys.sorted().map { weekly[$0] ?? 0.0 }.filter { $0 > 0.0 }
            if !vals.isEmpty { return vals }
        }
        return nonZero
    }

    private var weeksPlayed: Int { sideWeeklyPointsNonZero.count }

    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        return sideWeeklyPointsNonZero.suffix(3).reduce(0,+)/Double(min(3,weeksPlayed))
    }

    private var seasonAvg: Double {
        if weeksPlayed > 0 {
            return sideWeeklyPointsNonZero.reduce(0, +) / Double(weeksPlayed)
        }
        if let agg = aggregate { return agg.offensivePPW }
        return team?.averageOffensivePPW ?? 0
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
        let variance = sideWeeklyPointsNonZero.reduce(0) { $0 + pow($1 - mean, 2) } / Double(weeksPlayed)
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

    // MARK: - UI: Top Title + 4 stat bubbles (Grade, OPF, OMPF, OPPW)

    @ViewBuilder
    private func statBubble<Content: View, Caption: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: @escaping () -> Content, @ViewBuilder caption: @escaping () -> Caption) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.02), Color.white.opacity(0.01)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 2)
                    .frame(width: width, height: height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.0)]), startPoint: .top, endPoint: .center))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    )
                content()
            }
            caption()
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Title + bubble row (grade, OPF, OMPF, OPPW)
            VStack(spacing: 8) {
                // Title uses selected team name like TeamStatExpandedView
                let viewerName: String = {
                    if let team = team {
                        return team.name
                    }
                    if let uname = appSelection.currentUsername, !uname.isEmpty { return uname }
                    return appSelection.userTeam.isEmpty ? "Team" : appSelection.userTeam
                }()
                Text("\(viewerName)'s Offense Drop")
                    .font(.custom("Phatt", size: 20))
                    .bold()
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                GeometryReader { geo in
                    let horizontalPadding: CGFloat = 8
                    let spacing: CGFloat = 10
                    let itemCount: CGFloat = 4 // Grade, OPF, OMPF, OPPW
                    let available = max(0, geo.size.width - horizontalPadding * 2 - (spacing * (itemCount - 1)))
                    let bubbleSize = min(72, floor(available / itemCount))
                    HStack(spacing: spacing) {
                        // 1) Grade
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            if let g = computedGrade?.grade {
                                ElectrifiedGrade(grade: g, fontSize: min(28, bubbleSize * 0.6))
                                    .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                            } else {
                                Text("--")
                                    .font(.system(size: bubbleSize * 0.32, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                            }
                        } caption: {
                            Text("Grade")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 2) OPF (Offensive Points For)
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", sidePoints))
                                .font(.system(size: bubbleSize * 0.30, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("OPF")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 3) OMPF (Offensive Max Points For)
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", sideMaxPoints))
                                .font(.system(size: bubbleSize * 0.30, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("OMPF")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 4) OPPW (Offensive PPW)
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", seasonAvg))
                                .font(.system(size: bubbleSize * 0.36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78, alignment: .center)
                        } caption: {
                            Text("OPPW")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(width: geo.size.width, height: bubbleSize + 26, alignment: .center)
                }
                .frame(height: 96)
            }

            sectionHeader("Offensive Weekly Trend")
            StackedBarWeeklyChart(
                weekBars: stackedBarWeekData,
                positionColors: positionColors,
                showPositions: Set(offPositions),
                gridIncrement: 25,
                barSpacing: 4,
                tooltipFont: .caption2.bold(),
                showWeekLabels: true,
                aggregateToOffDef: false,
                showAggregateLegend: false,
                showOffensePositionsLegend: true,
                showDefensePositionsLegend: false
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

    // Small components (copied/consistent with TeamStatExpandedView)
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
