// TeamStatExpandedView.swift
// DynastyStatDrop
//
// Updated to accept a lightweight dictionary for aggregated all-time stats to avoid
// cross-file nested type reference issues (DSDashboard.AggregatedTeamStats).
// The view uses keys from the dictionary when available and falls back to season/team values.

import SwiftUI

struct TeamStatExpandedView: View {
    @EnvironmentObject var appSelection: AppSelection
    // Closure returns optional aggregated all-time stats for this team as a dictionary.
    // Keys used (when present): "totalPointsFor", "totalMaxPointsFor", "aggregatedManagementPercent",
    // "avgTeamPPW", "offensivePointsFor", "defensivePointsFor",
    // "totalMaxOffensivePointsFor", "totalMaxDefensivePointsFor"
    let aggregatedAllTime: (TeamStanding) -> [String: Any]?

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

    // Attempt to get aggregated dict when in all-time mode
    private var aggregateDict: [String: Any]? {
        guard isAllTime, let t = team else { return nil }
        return aggregatedAllTime(t)
    }

    // MARK: - Weeks to Include (Exclude Current Week if Incomplete)
    private var validWeeks: [Int] {
        guard let lg = league, let team else { return [] }
        // For season mode, use the selected season
        if !isAllTime, let season = lg.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
            let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        // For all time mode, use the latest season's weeks (continuity)
        if isAllTime {
            let latest = lg.seasons.sorted { $0.id < $1.id }.last
            let allWeeks = latest?.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        return []
    }

    // MARK: - Authoritative week points helper
    // Returns playerId -> points for the given team & week using:
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
                    // If starters present, sum only starters (match MatchupView / MyLeagueView)
                    if let starters = myEntry.starters, !starters.isEmpty {
                        var map: [String: Double] = [:]
                        for pid in starters {
                            if let p = playersPoints[pid] {
                                map[pid] = p
                            } else {
                                // if starter id not present in players_points, skip or treat as 0
                                map[pid] = 0.0
                            }
                        }
                        return map
                    } else {
                        // No starters info — fall back to full players_points map
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

    // MARK: - Stacked Bar Chart Data (whole team)
    private var stackedBarWeekData: [StackedBarWeeklyChart.WeekBarData] {
        guard let team else { return [] }
        let sortedWeeks = validWeeks
        return sortedWeeks.map { week in
            let playerPoints = authoritativePointsForWeek(team: team, week: week)
            // Map playerId -> position and sum by normalized position tokens
            var posSums: [String: Double] = [:]
            for (pid, pts) in playerPoints {
                if let player = team.roster.first(where: { $0.id == pid }) {
                    let norm = PositionNormalizer.normalize(player.position)
                    posSums[norm, default: 0.0] += pts
                } else {
                    // If player not found on roster (rare), skip to preserve roster-focused charts
                    continue
                }
            }
            // Ensure positions exist in dict (0 default)
            let segments = teamPositions.map { pos -> StackedBarWeeklyChart.WeekBarData.Segment in
                let norm = PositionNormalizer.normalize(pos)
                return StackedBarWeeklyChart.WeekBarData.Segment(
                    id: pos,
                    position: norm,
                    value: posSums[norm] ?? 0
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
            if let agg = aggregateDict, let v = agg["avgTeamPPW"] as? Double { return v }
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
        if let agg = aggregateDict, let v = agg["totalPointsFor"] as? Double { return v }
        return team?.pointsFor ?? 0
    }
    private var teamMaxPointsFor: Double {
        if let agg = aggregateDict, let v = agg["totalMaxPointsFor"] as? Double { return v }
        return team?.maxPointsFor ?? 0
    }
    private var managementPercent: Double {
        if let agg = aggregateDict, let v = agg["aggregatedManagementPercent"] as? Double {
            return v
        }
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
        if let agg = aggregateDict {
            var arr: [String] = []
            if let v = agg["aggregatedManagementPercent"] as? Double, v >= 75 { arr.append("Efficient Usage") }
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
        if let agg = aggregateDict {
            var arr: [String] = []
            if let v = agg["aggregatedManagementPercent"] as? Double, v < 55 { arr.append("Usage Inefficiency") }
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
            // New centered title and large stat bubble row
            VStack(spacing: 10) {
                // Centered Title
                Text("Team Drop")
                    .font(.custom("Phatt", size: 22))
                    .bold()
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                // Stat bubble row
                GeometryReader { geo in
                    let horizontalPadding: CGFloat = 8
                    let spacing: CGFloat = 10
                    // We now show 4 bubbles: Grade, PF, M%, PPW (MPF removed)
                    let itemCount: CGFloat = 4
                    // compute available width inside the geometry reader
                    let available = max(0, geo.size.width - horizontalPadding * 2 - (spacing * (itemCount - 1)))
                    // keep bubble size reasonable and cap it
                    let bubbleSize = min(72, floor(available / itemCount))
                    HStack(spacing: spacing) {
                        // 1) Grade
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            if let g = computedGrade()?.grade {
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

                        // 2) PF
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(formattedPF())
                                .font(.system(size: bubbleSize * 0.30, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.45) // allows the number to shrink instead of wrapping
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("PF")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 3) Mgmt%
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.0f%%", managementPercent))
                                .font(.system(size: bubbleSize * 0.28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.45)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("M%")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 4) PPW
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", seasonAvg))
                                .font(.system(size: bubbleSize * 0.26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.45)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("PPW")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    // Fix the geometry height so parent layout is stable
                    .frame(width: geo.size.width, height: bubbleSize + 26, alignment: .center)
                }
                .frame(height: 96) // conservative fixed height to keep inside card and avoid overflow
            }

            sectionHeader("Team Weekly Trend")
            // Chart: Excludes current week if incomplete, uses normalized positions
            StackedBarWeeklyChart(
                weekBars: stackedBarWeekData,  // Update to team-specific data as needed
                positionColors: positionColors,
                showPositions: Set(teamPositions),
                gridIncrement: 50,
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

    // Compute formatted PF string with no grouping that might wrap; keep it short.
    private func formattedPF() -> String {
        let val = teamPointsFor
        // Use short formatting for very large values (K, M) to keep inside bubble if necessary
        if val >= 1_000_000 {
            return String(format: "%.1fM", val / 1_000_000)
        } else if val >= 1000 {
            return String(format: "%.0f", val) // show plain integer for thousands
        } else {
            return String(format: "%.0f", val)
        }
    }

    // MARK: - Grade helper (wraps TeamGradeComponents grade computation)
    private func computedGrade() -> (grade: String, composite: Double)? {
        guard let league = league else { return nil }
        // Build components for season mode using season-level values (or aggregatedAllTime when appropriate)
        let teamsToProcess: [TeamStanding] = {
            // If we have a seasons array and we're in season mode, try to target selectedSeason
            if !isAllTime, let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
                return season.teams
            }
            // Fallback to league latest teams
            return league.seasons.sorted { $0.id < $1.id }.last?.teams ?? league.teams
        }()
        var comps: [TeamGradeComponents] = []
        for t in teamsToProcess {
            // For the given team, get pointsFor, ppw, mgmt, offMgmt, defMgmt, recordPct, positional ppw
            let aggForTeam: [String: Any]? = {
                if isAllTime { return aggregatedAllTime(t) }
                return nil
            }()
            let pf = isAllTime ? (aggForTeam?["totalPointsFor"] as? Double ?? t.pointsFor) : (t.pointsFor)
            let mpf = isAllTime ? (aggForTeam?["totalMaxPointsFor"] as? Double ?? t.maxPointsFor) : (t.maxPointsFor)
            let mgmt = (mpf > 0) ? (pf / mpf * 100) : (t.managementPercent)
            let offMgmt = isAllTime ? (aggForTeam?["offensiveManagementPercent"] as? Double ?? (t.offensiveManagementPercent ?? 0)) : (t.offensiveManagementPercent ?? 0)
            let defMgmt = isAllTime ? (aggForTeam?["defensiveManagementPercent"] as? Double ?? (t.defensiveManagementPercent ?? 0)) : (t.defensiveManagementPercent ?? 0)
            let ppwVal: Double = {
                if isAllTime { return aggForTeam?["avgTeamPPW"] as? Double ?? t.teamPointsPerWeek }
                // compute season average via DSDStatsService filtered helper (use shared)
                if let lg = league {
                    return (DSDStatsService.shared.stat(for: t, type: .teamAveragePPW, league: lg, selectedSeason: appSelection.selectedSeason) as? Double) ?? t.teamPointsPerWeek
                }
                return t.teamPointsPerWeek
            }()
            // Position averages (fallback to 0)
            let qb = (t.positionAverages?[PositionNormalizer.normalize("QB")] ?? 0)
            let rb = (t.positionAverages?[PositionNormalizer.normalize("RB")] ?? 0)
            let wr = (t.positionAverages?[PositionNormalizer.normalize("WR")] ?? 0)
            let te = (t.positionAverages?[PositionNormalizer.normalize("TE")] ?? 0)
            let k = (t.positionAverages?[PositionNormalizer.normalize("K")] ?? 0)
            let dl = (t.positionAverages?[PositionNormalizer.normalize("DL")] ?? 0)
            let lb = (t.positionAverages?[PositionNormalizer.normalize("LB")] ?? 0)
            let db = (t.positionAverages?[PositionNormalizer.normalize("DB")] ?? 0)
            // Record percent
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
        // Compute grades
        let graded = gradeTeams(comps)
        // Find this team's grade
        if let team = team, let found = graded.first(where: { $0.0 == team.name }) {
            return (found.1, found.2)
        }
        return nil
    }

    // MARK: - UI helpers for the stat bubble row

    /// A generic stat bubble builder: content is the visual bubble content, caption is the small label beneath.
    @ViewBuilder
    private func statBubble<Content: View, Caption: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: @escaping () -> Content, @ViewBuilder caption: @escaping () -> Caption) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // Slight glass/bubble effect background
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
                        // subtle specular shine
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
