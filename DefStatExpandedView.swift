//
//  DefStatExpandedView.swift
//  DynastyStatDrop
//
//  Uses authoritative matchup.players_points when available; sums starters only when starters present.
//  Falls back to deduped roster.weeklyScores when necessary.
//
//  Patched to compute DPF/DPPW from authoritative per-week defensive totals, include started-then-dropped
//  players via SleeperLeagueManager caches, use non-zero completed weeks for averages, and apply
//  defense-only grading via gradeTeamsDefense.
//

import SwiftUI

struct DefStatExpandedView: View {
    @EnvironmentObject var appSelection: AppSelection
    // NEW: access to global player caches to resolve players not present in TeamStanding.roster
    @EnvironmentObject var leagueManager: SleeperLeagueManager

    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false

    // Defensive positions
    private let defPositions: [String] = ["DL", "LB", "DB"]

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

    // MARK: - Grade computation (defense-only)
    // Build TeamGradeComponents for teams in current league/season (or use all-time owner aggregates when available).
    // Use gradeTeamsDefense and populate TeamGradeComponents with defensive-specific fields.
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
            // Prefer aggregated owner stats in all-time mode
            let aggOwner: AggregatedOwnerStats? = {
                if isAllTime { return lg.allTimeOwnerStats?[t.ownerId] }
                return nil
            }()

            // Defensive-specific values to populate TeamGradeComponents correctly for defense-only grading
            let defPF: Double = {
                if isAllTime {
                    return aggOwner?.totalDefensivePointsFor ?? (t.defensivePointsFor ?? 0)
                }
                return t.defensivePointsFor ?? 0
            }()

            let defPPW: Double = {
                if isAllTime {
                    return aggOwner?.defensivePPW ?? (t.averageDefensivePPW ?? 0)
                }
                return t.averageDefensivePPW ?? t.teamPointsPerWeek
            }()

            // Overall mgmt — keep existing behavior (season/all-time fallback)
            let pf: Double = {
                if isAllTime { return aggOwner?.totalPointsFor ?? t.pointsFor }
                return t.pointsFor
            }()
            let mpf: Double = {
                if isAllTime { return aggOwner?.totalMaxPointsFor ?? t.maxPointsFor }
                return t.maxPointsFor
            }()
            let mgmt = (mpf > 0) ? (pf / mpf * 100) : (t.managementPercent)

            // Off/Def mgmt (keep previous logic)
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

            // Position averages (fallback to 0)
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

            // IMPORTANT: For defense grading, set pointsFor = defensive points for and ppw = defensivePPW
            let comp = TeamGradeComponents(
                pointsFor: defPF,
                ppw: defPPW,
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

        // Use defense-specific grading helper
        let graded = gradeTeamsDefense(comps)
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
        // For all time mode, use the latest season's weeks (for continuity)
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
    // Returns mapping playerId -> points for the given team & week using:
    // 1) matchup.players_points if available for that week & roster entry (PREFERRED)
    //    - if matchup.starters exist: returns players_points filtered to starters only
    //    - else returns the full players_points mapping
    // 2) fallback to deduplicated roster.weeklyScores (prefer matchup_id match or highest points)
    private func authoritativePointsForWeek(team: TeamStanding, week: Int) -> [String: Double] {
        // Try matchup.players_points (authoritative)
        if let lg = league {
            // pick season (selected or latest for All Time)
            let season = (!isAllTime)
                ? lg.seasons.first(where: { $0.id == appSelection.selectedSeason })
                : lg.seasons.sorted { $0.id < $1.id }.last
            if let season {
                if let entries = season.matchupsByWeek?[week],
                   let rosterIdInt = Int(team.id),
                   let myEntry = entries.first(where: { $0.roster_id == rosterIdInt }),
                   let playersPoints = myEntry.players_points,
                   !playersPoints.isEmpty {
                    // If starters present, return players_points filtered to starters only
                    if let starters = myEntry.starters, !starters.isEmpty {
                        var map: [String: Double] = [:]
                        for pid in starters {
                            if let p = playersPoints[pid] {
                                map[pid] = p
                            } else {
                                // starter not present in players_points -> treat as 0.0
                                map[pid] = 0.0
                            }
                        }
                        return map
                    } else {
                        return playersPoints.mapValues { $0 }
                    }
                }
                // else fall through to roster fallback
            }
        }
        // Fallback: build mapping from roster.weeklyScores but deduplicate per player/week
        var result: [String: Double] = [:]
        // If we can find the matchup_id for this team/week, prefer that matchup_id when picking entries
        var preferredMatchupId: Int? = nil
        if let lg = league {
            let season = (!isAllTime)
                ? lg.seasons.first(where: { $0.id == appSelection.selectedSeason })
                : lg.seasons.sorted { $0.id < $1.id }.last
            if let season, let entries = season.matchupsByWeek?[week], let rosterIdInt = Int(team.id) {
                if let myEntry = entries.first(where: { $0.roster_id == rosterIdInt }) {
                    preferredMatchupId = myEntry.matchup_id
                }
            }
        }
        // For each player on roster, collect weeklyScores for this week and pick one entry
        for player in team.roster {
            let scores = player.weeklyScores.filter { $0.week == week }
            if scores.isEmpty { continue }
            // If a preferredMatchupId exists, prefer an entry with that matchup_id
            if let mid = preferredMatchupId, let matched = scores.first(where: { $0.matchup_id == mid }) {
                result[player.id] = matched.points_half_ppr ?? matched.points
            } else {
                // otherwise pick the entry with max points to avoid double-counting duplicates
                if let best = scores.max(by: { ($0.points_half_ppr ?? $0.points) < ($1.points_half_ppr ?? $1.points) }) {
                    result[player.id] = best.points_half_ppr ?? best.points
                }
            }
        }
        return result
    }

    // MARK: - Stacked Bar Chart Data (defense)
    private var stackedBarWeekData: [StackedBarWeeklyChart.WeekBarData] {
        guard let team else { return [] }
        let sortedWeeks = validWeeks
        return sortedWeeks.map { week in
            let playerPoints = authoritativePointsForWeek(team: team, week: week)
            var posSums: [String: Double] = [:]
            var unresolvedIds: [String] = []
            for (pid, pts) in playerPoints {
                // Prefer position from team roster if present
                if let player = team.roster.first(where: { $0.id == pid }) {
                    let norm = PositionNormalizer.normalize(player.position)
                    if ["DL","LB","DB"].contains(norm) {
                        posSums[norm, default: 0.0] += pts
                    } else {
                        // ignore offensive positions for defense chart
                    }
                } else if let raw = leagueManager.playerCache?[pid] ?? leagueManager.allPlayers[pid] {
                    let norm = PositionNormalizer.normalize(raw.position ?? "UNK")
                    if ["DL","LB","DB"].contains(norm) {
                        posSums[norm, default: 0.0] += pts
                    } else {
                        // player's resolved position is offensive -> ignore for defense segments
                    }
                } else {
                    // Fallback attribution to a defensive bucket to avoid dropping totals
                    posSums["DL", default: 0.0] += pts
                    unresolvedIds.append(pid)
                }
            }
            // Ensure positions exist in dict (0 default)
            let segments = defPositions.map { pos -> StackedBarWeeklyChart.WeekBarData.Segment in
                let norm = PositionNormalizer.normalize(pos)
                return StackedBarWeeklyChart.WeekBarData.Segment(
                    id: pos,
                    position: norm,
                    value: posSums[norm] ?? 0
                )
            }
#if DEBUG
            // Helpful debug print for developers when running locally
            if !unresolvedIds.isEmpty {
                let sample = unresolvedIds.prefix(6).joined(separator: ", ")
                print("[DEBUG][DefStatExpandedView] week \(week) unresolved ids (sample): \(sample)")
            }
#endif
            return StackedBarWeeklyChart.WeekBarData(id: week, segments: segments)
        }
    }

    // Helper: check if a PlayerWeeklyScore's player matches the target normalized position
    private func matchesNormalizedPosition(_ score: PlayerWeeklyScore, pos: String) -> Bool {
        guard let team = team else { return false }
        if let player = team.roster.first(where: { $0.id == score.player_id }) {
            return PositionNormalizer.normalize(player.position) == PositionNormalizer.normalize(pos)
        }
        // Try global caches (covers started players later dropped from roster)
        if let raw = leagueManager.playerCache?[score.player_id] ?? leagueManager.allPlayers[score.player_id] {
            return PositionNormalizer.normalize(raw.position ?? "") == PositionNormalizer.normalize(pos)
        }
        return false
    }

    // Derived weekly totals (actual roster total per week)
    private var sideWeeklyPoints: [Double] {
        stackedBarWeekData.map { $0.total }
    }

    // Use non-zero completed weeks for averages to avoid dividing by future zero weeks.
    private var sideWeeklyPointsNonZero: [Double] {
        let nonZero = sideWeeklyPoints.filter { $0 > 0.0 }
        // Fallback: if nothing found in stacked data, use team's recorded weeklyActualLineupPoints if available
        if nonZero.isEmpty, let team = team, let weekly = team.weeklyActualLineupPoints {
            let vals = weekly.keys.sorted().map { weekly[$0] ?? 0.0 }.filter { $0 > 0.0 }
            if !vals.isEmpty { return vals }
        }
        return nonZero
    }

    private var weeksPlayed: Int { sideWeeklyPointsNonZero.count }

    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        let recent = sideWeeklyPointsNonZero.suffix(3)
        return recent.reduce(0,+) / Double(min(3, recent.count))
    }

    // seasonAvg (DPPW) computed from non-zero completed weeks, fallback to aggregates/team stored values
    private var seasonAvg: Double {
        if weeksPlayed > 0 {
            return sideWeeklyPointsNonZero.reduce(0, +) / Double(weeksPlayed)
        }
        if let agg = aggregate { return agg.defensivePPW }
        return team?.averageDefensivePPW ?? 0
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var formDeltaColor: Color {
        if formDelta > 2 { return .green }
        if formDelta < -2 { return .red }
        return .yellow
    }

    // MARK: - Defensive Points and Management %

    // Recompute DPF from the exact same weekly totals used to compute DPPW.
    private var sidePointsComputed: Double {
        let sum = stackedBarWeekData.map { $0.total }.reduce(0, +)
        if sum > 0 { return sum }
        if let agg = aggregate { return agg.totalDefensivePointsFor }
        return team?.defensivePointsFor ?? 0
    }

    // Expose sidePoints (prefer aggregate in All Time)
    private var sidePoints: Double {
        if let agg = aggregate { return agg.totalDefensivePointsFor }
        return sidePointsComputed
    }
    private var sideMaxPoints: Double {
        if let agg = aggregate { return agg.totalMaxDefensivePointsFor }
        return team?.maxDefensivePointsFor ?? 0
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
            if agg.defensiveManagementPercent >= 75 { arr.append("Efficient Usage") }
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
            if agg.defensiveManagementPercent < 55 { arr.append("Usage Inefficiency") }
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
            sectionHeader("Defensive Weekly Trend")
            // Chart: Excludes current week if incomplete, uses normalized positions
            StackedBarWeeklyChart(
                weekBars: stackedBarWeekData,
                positionColors: positionColors,
                showPositions: Set(defPositions),
                gridIncrement: 25,
                barSpacing: 4,
                tooltipFont: .caption2.bold(),
                showWeekLabels: true,
                aggregateToOffDef: false,
                showAggregateLegend: false,
                showOffensePositionsLegend: false,
                showDefensePositionsLegend: true   // show DL/LB/DB
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
                    context: .defense,
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
                                pointsFor: sidePoints,
                                maxPointsFor: sideMaxPoints)
            .presentationDetents([.fraction(0.35)])
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Show defensive totals computed from authoritative weekly sums
            Text("DPF \(String(format: "%.2f", sidePoints))")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("DPPW \(String(format: "%.2f", seasonAvg))")
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
                statBlock(title: "DPF", value: sidePoints)
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

    // Small components (consistent with OffStat/TeamStat)

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
