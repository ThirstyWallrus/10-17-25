//
//  MatchupView.swift
//  DynastyStatDrop
//

import SwiftUI

extension String {
    var reverseRecord: String {
        let parts = self.split(separator: "-")
        if parts.count == 2 {
            return "\(parts[1])-\(parts[0])"
        } else if parts.count == 3 {
            return "\(parts[1])-\(parts[0])-\(parts[2])"
        }
        return self
    }
}

private let offensiveFlexSlots: Set<String> = [
    "FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE",
    "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX"
]

struct MatchupView: View {
    @EnvironmentObject var leagueManager: SleeperLeagueManager
    @EnvironmentObject var appSelection: AppSelection
    @Binding var selectedTab: Tab

    // MARK: - Utility Models

    struct LineupPlayer: Identifiable {
        let id: String
        let position: String
        let points: Double
        let isBench: Bool
    }

    struct TeamDisplay {
        let id: String
        let name: String // Sleeper team name
        let lineup: [LineupPlayer] // starters
        let bench: [LineupPlayer]
        let totalPoints: Double
        let maxPoints: Double
        let managementPercent: Double
        let teamStanding: TeamStanding
    }

    // Layout constants
    fileprivate let horizontalEdgePadding: CGFloat = 16
    fileprivate let menuSpacing: CGFloat = 12
    fileprivate let maxContentWidth: CGFloat = 860

    @AppStorage("statDropPersonality") var userStatDropPersonality: StatDropPersonality = .classicESPN
    @State private var selectedWeek: String = ""
    @State private var isStatDropActive: Bool = false
    @State private var isLoading: Bool = false

    // MARK: - Centralized Selection

    // All selection logic now uses appSelection's published properties

    // Derived references
    private var league: LeagueData? {
        appSelection.selectedLeague
    }

    private var allSeasonIds: [String] {
        guard let league else { return ["All Time"] }
        let sorted = league.seasons.map { $0.id }.sorted(by: >)
        return ["All Time"] + sorted
    }

    private var currentSeasonTeams: [TeamStanding] {
        league?.seasons.sorted { $0.id < $1.id }.last?.teams ?? league?.teams ?? []
    }

    private var seasonTeams: [TeamStanding] {
        guard let league else { return [] }
        if appSelection.selectedSeason == "All Time" {
            return currentSeasonTeams
        }
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams ?? currentSeasonTeams
    }

    // --- UPDATED: Week selection logic ---
    /// Returns the available week choices as ["Week 1", "Week 2", ...] only.
    private var availableWeeks: [String] {
        guard let team = userTeamStanding else { return [] }
        // Gather all week numbers for which the user's team has scores
        let allWeeks = team.roster.flatMap { $0.weeklyScores }.map { $0.week }
        let uniqueWeeks = Set(allWeeks).sorted()
        // If no weeks, return empty
        if uniqueWeeks.isEmpty { return [] }
        // Format as ["Week 1", "Week 2", ...]
        return uniqueWeeks.map { "Week \($0)" }
    }

    private var currentSeasonId: String {
        league?.seasons.sorted { $0.id < $1.id }.last?.id ?? ""
    }

    private var cleanedLeagueName: String {
        league?.name.unicodeScalars.filter { !$0.properties.isEmojiPresentation }.reduce(into: "") { $0 += String($1) } ?? "League"
    }

    private var userTeamStanding: TeamStanding? {
        appSelection.selectedTeam
    }

    private var opponentTeamStanding: TeamStanding? {
        guard let userTeam = userTeamStanding,
              let userRosterId = Int(userTeam.id),
              let season = league?.seasons.first(where: { $0.id == appSelection.selectedSeason }) ?? league?.seasons.last else {
            return nil
        }
        let thisWeekMatchupId = self.currentWeekNumber
        let matchupsForWeek = season.matchups?.filter { $0.matchupId == thisWeekMatchupId } ?? []
        for matchup in matchupsForWeek {
            if matchup.rosterId == userRosterId {
                if let opponentEntry = matchupsForWeek.first(where: { $0.rosterId != userRosterId }) {
                    return season.teams.first { $0.id == String(opponentEntry.rosterId) }
                }
            }
        }
        return nil
    }

    /// Determines the current week number (default for the menu).
    /// If selectedWeek is empty, defaults to the latest week available.
    private var currentWeekNumber: Int {
        // Parse selectedWeek like "Week 1" → 1
        if let weekNum = Int(selectedWeek.replacingOccurrences(of: "Week ", with: "")), !selectedWeek.isEmpty {
            return weekNum
        }
        // If not set, use latest available week
        if let lastWeek = availableWeeks.last,
           let lastNum = Int(lastWeek.replacingOccurrences(of: "Week ", with: "")) {
            return lastNum
        }
        return 1 // Fallback
    }

    private var userTeam: TeamDisplay? {
        userTeamStanding.map { teamDisplay(for: $0, week: currentWeekNumber) }
    }

    private var opponentTeam: TeamDisplay? {
        opponentTeamStanding.map { teamDisplay(for: $0, week: currentWeekNumber) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading matchup data...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        headerBlock
                        if isStatDropActive {
                            statDropContent
                        } else {
                            matchupContent
                        }
                        Spacer(minLength: 120)
                    }
                    .frame(maxWidth: maxContentWidth)
                    .padding(.horizontal, horizontalEdgePadding)
                    .padding(.top, 32)
                    .padding(.bottom, 120)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            setDefaultWeekSelection()
            refreshData()
        }
    }

    /// Sets the initial week selection to the current/latest week.
    private func setDefaultWeekSelection() {
        // If weeks available, pick the latest (current) week
        if let lastWeek = availableWeeks.last {
            selectedWeek = lastWeek
        } else {
            selectedWeek = "" // None available
        }
    }

    private func refreshData() {
        guard let leagueId = appSelection.selectedLeagueId else { return }
        isLoading = true
        leagueManager.refreshLeagueData(leagueId: leagueId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedLeague):
                    if let index = appSelection.leagues.firstIndex(where: { $0.id == leagueId }) {
                        appSelection.leagues[index] = updatedLeague
                    }
                case .failure(let error):
                    print("Failed to refresh league data: \(error.localizedDescription)")
                }
                isLoading = false
            }
        }
    }

    // MARK: - Header
    private var headerBlock: some View {
        VStack(spacing: 18) {
            Text("Matchup")
                .font(.system(size: 36, weight: .heavy))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            selectionMenus
        }
    }

    // --- Menu Geometry ---
    private var selectionMenus: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                HStack {
                    leagueMenu
                        .frame(width: geo.size.width)
                }
            }
            .frame(height: 50)

            GeometryReader { geo in
                let virtualSpacing: CGFloat = menuSpacing * 3
                let virtualTotal = geo.size.width - virtualSpacing
                let tabWidth = virtualTotal / 4
                let actualSpacing = (geo.size.width - 3 * tabWidth) / 2
                HStack(spacing: actualSpacing) {
                    seasonMenu
                        .frame(width: tabWidth)
                    weekMenu
                        .frame(width: tabWidth)
                    statDropMenu
                        .frame(width: tabWidth)
                }
            }
            .frame(height: 50)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, horizontalEdgePadding)
    }

    // --- Individual Menus ---
    private var leagueMenu: some View {
        Menu {
            ForEach(appSelection.leagues, id: \.id) { lg in
                Button(lg.name) {
                    appSelection.selectedLeagueId = lg.id
                    appSelection.selectedSeason = lg.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
                    appSelection.userHasManuallySelectedTeam = false
                    appSelection.syncSelectionAfterLeagueChange(username: nil, sleeperUserId: nil)
                }
            }
        } label: {
            menuLabel(appSelection.selectedLeague?.name ?? "League")
        }
    }

    private var seasonMenu: some View {
        Menu {
            ForEach(allSeasonIds, id: \.self) { sid in
                Button(sid) {
                    appSelection.selectedSeason = sid
                    appSelection.syncSelectionAfterSeasonChange(username: nil, sleeperUserId: nil)
                    setDefaultWeekSelection() // Update week selection if season changes
                }
            }
        } label: {
            menuLabel(appSelection.selectedSeason.isEmpty ? "Year" : appSelection.selectedSeason)
        }
    }

    /// Week menu now only lists ["Week 1", "Week 2", ...] (no SZN/full season).
    private var weekMenu: some View {
        Menu {
            ForEach(availableWeeks, id: \.self) { wk in
                Button(wk) { selectedWeek = wk }
            }
        } label: {
            menuLabel(selectedWeek.isEmpty ? (availableWeeks.last ?? "Week 1") : selectedWeek)
        }
    }

    private var statDropMenu: some View {
        Menu {
            if isStatDropActive {
                Button("Back to Matchup") { isStatDropActive = false }
            } else {
                Button("View DSD") { isStatDropActive = true }
            }
        } label: {
            menuLabel("DSD")
        }
    }

    private func menuLabel(_ text: String) -> some View {
        Text(text)
            .bold()
            .foregroundColor(.orange)
            .font(.custom("Phatt", size: 16))
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.black)
                    .shadow(color: .blue.opacity(0.7), radius: 8, y: 2)
            )
    }

    private var statDropContent: some View {
        Group {
            if let team = userTeamStanding, let lg = league {
                StatDropAnalysisBox(
                    team: team,
                    league: lg,
                    context: .fullTeam,
                    personality: userStatDropPersonality
                )
            } else {
                Text("No data available for Stat Drop.")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.body)
            }
        }
    }

    // MARK: - Matchup Content
    private var matchupContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            scoresSection
            lineupsSection
            benchesSection
            if let user = userTeamStanding, let opp = opponentTeamStanding, let lg = league {
                headToHeadStatsSection(user: user, opp: opp, league: lg)
            }
        }
    }

    private var scoresSection: some View {
        HStack(spacing: 16) {
            teamScoreBox(team: userTeam, accent: Color.cyan, isUser: true)
            teamScoreBox(team: opponentTeam, accent: Color.yellow, isUser: false)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func teamScoreBox(team: TeamDisplay?, accent: Color, isUser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isUser ? "Your Team" : "Opponent")
                .font(.headline.bold())
                .foregroundColor(.orange)

            if let team = team {
                HStack {
                    Text("Points")
                    Spacer()
                    Text(String(format: "%.1f", team.totalPoints))
                        .foregroundColor(.green)
                }
                HStack {
                    Text("Max Points")
                    Spacer()
                    Text(String(format: "%.1f", team.maxPoints))
                        .foregroundColor(.white.opacity(0.8))
                }
                HStack {
                    Text("Mgmt %")
                    Spacer()
                    Text(String(format: "%.2f%%", team.managementPercent))
                        .foregroundColor(.cyan)
                }
            } else {
                Text("No data available")
                    .foregroundColor(.red)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
    }

    private var lineupsSection: some View {
        HStack(spacing: 16) {
            teamLineupBox(team: userTeam, accent: Color.cyan, title: "Your Lineup")
            teamLineupBox(team: opponentTeam, accent: Color.yellow, title: "Opponent Lineup")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func teamLineupBox(team: TeamDisplay?, accent: Color, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.bold())
                .foregroundColor(.orange)

            if let lineup = team?.lineup {
                ForEach(lineup) { player in
                    HStack {
                        Text(player.position)
                            .foregroundColor(positionColor(player.position))
                        Spacer()
                        Text(String(format: "%.1f", player.points))
                            .foregroundColor(.green)
                    }
                }
            } else {
                Text("No lineup data")
                    .foregroundColor(.gray)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
    }

    private var benchesSection: some View {
        HStack(spacing: 16) {
            teamBenchBox(team: userTeam, accent: Color.cyan, title: "Your Bench")
            teamBenchBox(team: opponentTeam, accent: Color.yellow, title: "Opponent Bench")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func teamBenchBox(team: TeamDisplay?, accent: Color, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.bold())
                .foregroundColor(.orange)

            if let bench = team?.bench {
                ForEach(bench) { player in
                    HStack {
                        Text(player.position)
                            .foregroundColor(positionColor(player.position))
                        Spacer()
                        Text(String(format: "%.1f", player.points))
                            .foregroundColor(.green.opacity(0.7))
                    }
                }
            } else {
                Text("No bench data")
                    .foregroundColor(.gray)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
    }

    private func headToHeadStatsSection(user: TeamStanding, opp: TeamStanding, league: LeagueData) -> some View {
        let (h2hRecord, avgMgmtFor, avgPF, avgMgmtAgainst, avgPA) = getHeadToHead(userOwnerId: user.ownerId, oppOwnerId: opp.ownerId, league: league, seasonId: appSelection.selectedSeason)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Head-to-Head Stats")
                .font(.headline.bold())
                .foregroundColor(.orange)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .foregroundColor(.cyan)
                        .bold()
                    statRow("Record vs Opponent", h2hRecord)
                    statRow("Mgmt % vs Opponent", String(format: "%.2f%%", avgMgmtFor))
                    statRow("Avg Points/Game vs Opponent", String(format: "%.1f", avgPF))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(opp.name)
                        .foregroundColor(.yellow)
                        .bold()
                    statRow("Record vs You", h2hRecord.reverseRecord)
                    statRow("Mgmt % vs You", String(format: "%.2f%%", avgMgmtAgainst))
                    statRow("Avg Points/Game vs You", String(format: "%.1f", avgPA))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .foregroundColor(.orange)
                .bold()
        }
        .font(.caption)
    }

    // MARK: - Data Extraction Helpers

    private func getHeadToHead(userOwnerId: String, oppOwnerId: String, league: LeagueData, seasonId: String) -> (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        let seasons: [SeasonData]
        if seasonId == "All Time" {
            seasons = league.seasons
        } else if let s = league.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
            seasons = [s]
        } else {
            return ("0-0", 0.0, 0.0, 0.0, 0.0)
        }

        var wins = 0
        var losses = 0
        var ties = 0
        var pointsFor = 0.0
        var pointsAgainst = 0.0
        var sumMgmtFor = 0.0
        var sumMgmtAgainst = 0.0
        var games = 0

        for season in seasons {
            guard let userTeam = season.teams.first(where: { $0.ownerId == userOwnerId }),
                  let oppTeam = season.teams.first(where: { $0.ownerId == oppOwnerId }),
                  let uRid = Int(userTeam.id),
                  let oRid = Int(oppTeam.id) else { continue }

            let playoffStart = season.playoffStartWeek ?? 14
            let h2hMatchups = season.matchups?.filter { $0.matchupId < playoffStart && ($0.rosterId == uRid || $0.rosterId == oRid) } ?? []
            let grouped = Dictionary(grouping: h2hMatchups, by: { $0.matchupId })
            for (_, group) in grouped {
                guard group.count == 2 else { continue }
                let entries = group.sorted { ($0.rosterId == uRid ? 0 : 1) < ($1.rosterId == uRid ? 0 : 1) }
                let uEntry = entries.first(where: { $0.rosterId == uRid })
                let oEntry = entries.first(where: { $0.rosterId == oRid })
                guard let uPts = uEntry?.points, let oPts = oEntry?.points else { continue }
                if uPts == 0 || oPts == 0 { continue }

                let uMax = maxPointsForWeek(team: userTeam, matchupId: uEntry?.matchupId ?? 0)
                let oMax = maxPointsForWeek(team: oppTeam, matchupId: oEntry?.matchupId ?? 0)
                let uMgmt = uMax > 0 ? (uPts / uMax) * 100 : 0.0
                let oMgmt = oMax > 0 ? (oPts / oMax) * 100 : 0.0

                pointsFor += uPts
                pointsAgainst += oPts
                sumMgmtFor += uMgmt
                sumMgmtAgainst += oMgmt
                games += 1
                if uPts > oPts { wins += 1 }
                else if uPts < oPts { losses += 1 }
                else { ties += 1 }
            }
        }

        let record = "\(wins)-\(losses)\(ties > 0 ? "-\(ties)" : "")"
        let avgMgmtFor = games > 0 ? sumMgmtFor / Double(games) : 0.0
        let avgPF = games > 0 ? pointsFor / Double(games) : 0.0
        let avgMgmtAgainst = games > 0 ? sumMgmtAgainst / Double(games) : 0.0
        let avgPA = games > 0 ? pointsAgainst / Double(games) : 0.0
        return (record, avgMgmtFor, avgPF, avgMgmtAgainst, avgPA)
    }

    private func lineupPlayers(for team: TeamStanding, week: Int) -> ([LineupPlayer], [LineupPlayer]) {
        guard let starters = team.actualStartersByWeek?[week] else { return ([], []) }
        let starterSet = Set(starters)
        let players = team.roster.compactMap { player -> LineupPlayer? in
            guard let weekScore = player.weeklyScores.first(where: { $0.week == week }) else { return nil }
            let points = weekScore.points_half_ppr ?? weekScore.points
            let isBench = !starterSet.contains(player.id)
            return LineupPlayer(
                id: player.id,
                position: player.position,
                points: points,
                isBench: isBench
            )
        }
        let lineup = players.filter { !$0.isBench }.sorted { $0.points > $1.points }
        let bench = players.filter { $0.isBench }.sorted { $0.points > $1.points }
        return (lineup, bench)
    }

    private func teamDisplay(for team: TeamStanding, week: Int) -> TeamDisplay {
        let (lineup, bench) = lineupPlayers(for: team, week: week)
        let (actualTotal, maxTotal, _, _, _, _) = computeManagementForWeek(team: team, week: week)
        let managementPercent = maxTotal > 0 ? (actualTotal / maxTotal * 100) : 0.0
        return TeamDisplay(
            id: team.id,
            name: team.name,
            lineup: lineup,
            bench: bench,
            totalPoints: actualTotal,
            maxPoints: maxTotal,
            managementPercent: managementPercent,
            teamStanding: team
        )
    }

    private func computeManagementForWeek(team: TeamStanding, week: Int) -> (Double, Double, Double, Double, Double, Double) {
        let playerScores = team.roster.reduce(into: [String: Double]()) { dict, player in
            if let score = player.weeklyScores.first(where: { $0.week == week }) {
                dict[player.id] = score.points_half_ppr ?? score.points
            }
        }
        let actualStarters = team.actualStartersByWeek?[week] ?? []
        let actualTotal = actualStarters.reduce(0.0) { $0 + (playerScores[$1] ?? 0.0) }
        let offPositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
        let actualOff = actualStarters.reduce(0.0) { sum, id in
            if let player = team.roster.first(where: { $0.id == id }), offPositions.contains(player.position) {
                return sum + (playerScores[id] ?? 0.0)
            } else {
                return sum
            }
        }
        let actualDef = actualTotal - actualOff

        var startingSlots = team.league?.startingLineup ?? []
        if startingSlots.isEmpty, let config = team.lineupConfig, !config.isEmpty {
            startingSlots = expandSlots(config)
        }
        let fixedCounts = fixedSlotCounts(startingSlots: startingSlots)

        let offPosSet: Set<String> = ["QB", "RB", "WR", "TE", "K"]
        var offPlayerList = team.roster.filter { offPosSet.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxOff = 0.0
        for pos in Array(offPosSet) {
            if let count = fixedCounts[pos] {
                let candidates = offPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                maxOff += candidates.prefix(count).reduce(0.0) { $0 + $1.score }
                let usedIds = candidates.prefix(count).map { $0.id }
                offPlayerList.removeAll { usedIds.contains($0.id) }
            }
        }
        let regFlexCount = startingSlots.reduce(0) { $0 + (regularFlexSlots.contains($1.uppercased()) ? 1 : 0) }
        let supFlexCount = startingSlots.reduce(0) { $0 + (superFlexSlots.contains($1.uppercased()) ? 1 : 0) }
        let regAllowed: Set<String> = ["RB", "WR", "TE"]
        let regCandidates = offPlayerList.filter { regAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        maxOff += regCandidates.prefix(regFlexCount).reduce(0.0) { $0 + $1.score }
        let usedReg = regCandidates.prefix(regFlexCount).map { $0.id }
        offPlayerList.removeAll { usedReg.contains($0.id) }
        let supAllowed: Set<String> = ["QB", "RB", "WR", "TE"]
        let supCandidates = offPlayerList.filter { supAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        maxOff += supCandidates.prefix(supFlexCount).reduce(0.0) { $0 + $1.score }

        let defPosSet: Set<String> = ["DL", "LB", "DB"]
        var defPlayerList = team.roster.filter { defPosSet.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxDef = 0.0
        for pos in Array(defPosSet) {
            if let count = fixedCounts[pos] {
                let candidates = defPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                maxDef += candidates.prefix(count).reduce(0.0) { $0 + $1.score }
                let usedIds = candidates.prefix(count).map { $0.id }
                defPlayerList.removeAll { usedIds.contains($0.id) }
            }
        }
        let idpFlexCount = startingSlots.reduce(0) { $0 + (idpFlexSlots.contains($1.uppercased()) ? 1 : 0) }
        let idpCandidates = defPlayerList.sorted { $0.score > $1.score }
        maxDef += idpCandidates.prefix(idpFlexCount).reduce(0.0) { $0 + $1.score }

        let maxTotal = maxOff + maxDef
        return (actualTotal, maxTotal, actualOff, maxOff, actualDef, maxDef)
    }

    private func fixedSlotCounts(startingSlots: [String]) -> [String: Int] {
        startingSlots.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private func positionColor(_ pos: String) -> Color {
        switch pos {
        case "QB": return .red
        case "RB": return .green
        case "WR": return .blue
        case "TE": return .yellow
        case "K": return .purple.opacity(0.6)
        case "DL": return .orange
        case "LB": return .purple
        case "DB": return .pink
        default: return .white
        }
    }

    private func maxPointsForWeek(team: TeamStanding, matchupId: Int) -> Double {
        let playerScores = team.roster.reduce(into: [String: Double]()) { dict, player in
            if let score = player.weeklyScores.first(where: { $0.matchup_id == matchupId }) {
                dict[player.id] = score.points_half_ppr ?? score.points
            }
        }

        var startingSlots = team.league?.startingLineup ?? []
        if startingSlots.isEmpty, let config = team.lineupConfig, !config.isEmpty {
            startingSlots = expandSlots(config)
        }
        let fixedCounts = fixedSlotCounts(startingSlots: startingSlots)

        let offPosSet: Set<String> = ["QB", "RB", "WR", "TE", "K"]
        var offPlayerList = team.roster.filter { offPosSet.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxOff = 0.0
        for pos in Array(offPosSet) {
            if let count = fixedCounts[pos] {
                let candidates = offPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                maxOff += candidates.prefix(count).reduce(0.0) { $0 + $1.score }
                let usedIds = candidates.prefix(count).map { $0.id }
                offPlayerList.removeAll { usedIds.contains($0.id) }
            }
        }
        let regFlexCount = startingSlots.reduce(0) { $0 + (regularFlexSlots.contains($1.uppercased()) ? 1 : 0) }
        let supFlexCount = startingSlots.reduce(0) { $0 + (superFlexSlots.contains($1.uppercased()) ? 1 : 0) }
        let regAllowed: Set<String> = ["RB", "WR", "TE"]
        let regCandidates = offPlayerList.filter { regAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        maxOff += regCandidates.prefix(regFlexCount).reduce(0.0) { $0 + $1.score }
        let usedReg = regCandidates.prefix(regFlexCount).map { $0.id }
        offPlayerList.removeAll { usedReg.contains($0.id) }
        let supAllowed: Set<String> = ["QB", "RB", "WR", "TE"]
        let supCandidates = offPlayerList.filter { supAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        maxOff += supCandidates.prefix(supFlexCount).reduce(0.0) { $0 + $1.score }

        let defPosSet: Set<String> = ["DL", "LB", "DB"]
        var defPlayerList = team.roster.filter { defPosSet.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxDef = 0.0
        for pos in Array(defPosSet) {
            if let count = fixedCounts[pos] {
                let candidates = defPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                maxDef += candidates.prefix(count).reduce(0.0) { $0 + $1.score }
                let usedIds = candidates.prefix(count).map { $0.id }
                defPlayerList.removeAll { usedIds.contains($0.id) }
            }
        }
        let idpFlexCount = startingSlots.reduce(0) { $0 + (idpFlexSlots.contains($1.uppercased()) ? 1 : 0) }
        let idpCandidates = defPlayerList.sorted { $0.score > $1.score }
        maxDef += idpCandidates.prefix(idpFlexCount).reduce(0.0) { $0 + $1.score }

        return maxOff + maxDef
    }

    private let regularFlexSlots: Set<String> = ["FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE"]
    private let superFlexSlots: Set<String> = ["SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX"]
    private let idpFlexSlots: Set<String> = ["IDP"]

    private func expandSlots(_ config: [String: Int]) -> [String] {
        config.flatMap { Array(repeating: $0.key, count: $0.value) }
    }
}
