//```swift
//
//  MyTeamView.swift (Refactored to AppSelection Single Source of Truth)
//  - Removed local leaguePickerId/seasonPicker/teamPickerId
//  - Uses LeagueSeasonTeamPicker for consistent selection
//  - All derived data now references appSelection.*
//

import SwiftUI

private func positionColor(_ pos: String) -> Color {
    switch pos {
    case "QB": return .red
    case "RB": return .green
    case "WR": return .blue
    case "TE": return .yellow
    case "K":  return .purple.opacity(0.6)
    case "DL": return .orange
    case "LB": return .purple
    case "DB": return .pink
    default:   return .white
    }
}

struct AssignedSlot: Identifiable {
    let id = UUID()
    let slot: String
    let playerPos: String
    let score: Double
}

struct BenchPlayer: Identifiable {
    let id: String
    let pos: String
    let score: Double
}

struct MyTeamView: View {
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var leagueManager: SleeperLeagueManager
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var selectedTab: Tab
    @AppStorage("statDropPersonality") var userStatDropPersonality: StatDropPersonality = .classicESPN
    @State private var selectedWeek: String = "SZN"
    @State private var isStatDropActive: Bool = false

    // Layout constants
    fileprivate let horizontalEdgePadding: CGFloat = 16
    fileprivate let menuSpacing: CGFloat = 12
    fileprivate let maxContentWidth: CGFloat = 860

    // Derived references
    private var league: LeagueData? { appSelection.selectedLeague }

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
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams
            ?? currentSeasonTeams
    }

    private var selectedTeamSeason: TeamStanding? {
        seasonTeams.first { $0.id == appSelection.selectedTeamId }
    }

    private var aggregated: AggregatedOwnerStats? {
        guard appSelection.selectedSeason == "All Time",
              let league,
              let team = selectedTeamSeason else { return nil }
        return league.allTimeOwnerStats?[team.ownerId]
    }

    private var currentSeasonId: String {
        league?.seasons.sorted { $0.id < $1.id }.last?.id ?? ""
    }

    private var availableWeeks: [String] {
        guard let team = selectedTeamSeason else { return ["SZN"] }
        let allWeeks = team.roster.flatMap { $0.weeklyScores }.map { $0.week }
        let uniqueWeeks = Set(allWeeks).sorted()
        if uniqueWeeks.isEmpty { return ["SZN"] }
        return uniqueWeeks.map { "Wk \($0)" } + ["SZN"]
    }

    private let mainPositions = ["QB","RB","WR","TE","K","DL","LB","DB"]

    private var showEmptyState: Bool {
        leagueManager.leagues.isEmpty || !authViewModel.isLoggedIn
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showEmptyState {
                emptyState
            } else {
                mainContent
            }
        }
        .onAppear {
            validateSelection()
        }
        .onChange(of: appSelection.leagues) {
            validateSelection()
        }
        .onChange(of: appSelection.selectedSeason) {
            selectedWeek = "SZN"
        }
        .onChange(of: appSelection.selectedTeamId) {
            selectedWeek = "SZN"
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func validateSelection() {
        guard !showEmptyState else { return }
        // Ensure selectedLeagueId is valid
        if appSelection.selectedLeagueId == nil || !appSelection.leagues.contains(where: { $0.id == appSelection.selectedLeagueId }) {
            appSelection.selectedLeagueId = appSelection.leagues.first?.id
        }
        // Ensure selectedSeason is valid
        if let league = appSelection.selectedLeague,
            !league.seasons.contains(where: { $0.id == appSelection.selectedSeason }) && appSelection.selectedSeason != "All Time" {
            appSelection.selectedSeason = league.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
        }
        // Ensure selectedTeamId is valid
        let validTeams = seasonTeams
        if let currentTeamId = appSelection.selectedTeamId,
           !validTeams.contains(where: { $0.id == currentTeamId }) {
            appSelection.selectedTeamId = validTeams.first?.id
        }
        // Ensure selectedWeek is valid
        if !availableWeeks.contains(selectedWeek) {
            selectedWeek = "SZN"
        }
    }

    // MARK: Empty
    private var emptyState: some View {
        VStack(spacing: 18) {
            Text(authViewModel.isLoggedIn ? "No League Imported" : "Please Sign In")
                .font(.title2.bold())
                .foregroundColor(.orange)
            Text(authViewModel.isLoggedIn
                 ? "Go to the Dashboard and import your Sleeper league."
                 : "Sign in and import a Sleeper league to begin.")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 40)
            Button {
                selectedTab = .dashboard
            } label: {
                Text("Go to Dashboard")
                    .bold()
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Color.orange))
                    .foregroundColor(.black)
            }
        }
        .padding()
    }

    // MARK: Main
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 36) {
                headerBlock
                contentStack
            }
            .adaptiveWidth(max: maxContentWidth, padding: horizontalEdgePadding)
            .padding(.top, 32)
            .padding(.bottom, 120)
        }
    }

    // --- NEW MENU LAYOUT HERE ---
    private var headerBlock: some View {
        VStack(spacing: 18) {
            Text(displayTeamName())
                .font(.system(size: 36, weight: .heavy))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            selectionMenus
        }
    }

    // --- DSDDashboard-style Menu Geometry ---
    private var selectionMenus: some View {
        VStack(spacing: 10) {
            // Top Row: League selector stretches full width
            GeometryReader { geo in
                HStack {
                    leagueMenu
                        .frame(width: geo.size.width)
                }
            }
            .frame(height: 50)

            // Bottom Row: Year (25%), Team (25%), Week (25%), StatDrop (25%)
            GeometryReader { geo in
                let spacing: CGFloat = menuSpacing * 3
                let totalAvailable = geo.size.width - spacing
                let tabWidth = totalAvailable / 4
                HStack(spacing: menuSpacing) {
                    seasonMenu
                        .frame(width: tabWidth)
                    teamMenu
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
                    appSelection.selectedTeamId = lg.teams.first?.id
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
                }
            }
        } label: {
            menuLabel(appSelection.selectedSeason.isEmpty ? "Year" : appSelection.selectedSeason)
        }
    }

    private var teamMenu: some View {
        Menu {
            ForEach(seasonTeams, id: \.id) { tm in
                Button(tm.name) { appSelection.selectedTeamId = tm.id }
            }
        } label: {
            menuLabel("Team")
        }
    }

    private var weekMenu: some View {
        Menu {
            ForEach(availableWeeks, id: \.self) { wk in
                Button(wk) { selectedWeek = wk }
            }
        } label: {
            menuLabel(selectedWeek)
        }
    }

    private var statDropMenu: some View {
        Menu {
            if isStatDropActive {
                Button("Back to Stats") { isStatDropActive = false }
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


    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isStatDropActive {
                if appSelection.selectedSeason == "All Time" || (appSelection.selectedSeason != currentSeasonId && selectedWeek != "SZN") {
                    Text("Weekly Stat Drops are only available for the current season.")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.body)
                } else if let team = selectedTeamSeason, let league = league {
                    StatDropAnalysisBox(
                        team: team,
                        league: league,
                        context: .fullTeam,
                        personality: userStatDropPersonality
                    )
                } else {
                    Text("No data available.")
                }
            } else {
                managementSection
                positionPPWSection
                perStartPPWSection
                if selectedWeek == "SZN" {
                    averageStartersSection
                } else {
                    lineupSection
                }
                transactionSection
                totalsSection
                strengthsWeaknessesSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topHeader: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(displayTeamName())
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 12)
            Text(appSelection.selectedSeason)
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Sections (same logic as prior version but referencing appSelection)
    private var managementSection: some View {
        sectionBox {
            Text("Management %")
                .sectionTitleStyle()
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Team")
                    Text("Offense")
                    Text("Defense")
                }
                .foregroundColor(.white.opacity(0.8)) // Just label color

                VStack(alignment: .leading, spacing: 4) {
                    let (f, o, d) = managementTriplet()
                    Text(String(format: "%.1f%%", f))
                        .foregroundColor(Color.mgmtPercentColor(f))
                    Text(String(format: "%.1f%%", o))
                        .foregroundColor(Color.mgmtPercentColor(o))
                    Text(String(format: "%.1f%%", d))
                        .foregroundColor(Color.mgmtPercentColor(d))
                }
            }
        }
    }

    private func valueLine(_ text: String, _ color: Color) -> some View {
        Text(text)
            .foregroundColor(color)
            .accessibilityLabel(text)
    }

    private var positionPPWSection: some View {
        sectionBox {
            Text(selectedWeek == "SZN" ? "Position Avg Points / Week" : "Position Points (Week \(selectedWeek.replacingOccurrences(of: "Wk ", with: "")))")
                .sectionTitleStyle()
            gridForPositions(valueProvider: positionPPW, leagueAvgProvider: leaguePosPPW)
        }
    }
    private var perStartPPWSection: some View {
        sectionBox {
            Text(selectedWeek == "SZN" ? "Per Starter Slot Avg (Individual PPW)" : "Per Starter Slot Points (Individual Points in Week \(selectedWeek.replacingOccurrences(of: "Wk ", with: "")))")
                .sectionSubtitleStyle()
            gridForPositions(valueProvider: individualPPW, leagueAvgProvider: leagueIndividualPPW)
        }
    }
    private var averageStartersSection: some View {
        sectionBox {
            Text("Average Starters / Week")
                .sectionTitleStyle()
            HStack {
                Text("Pos").frame(width: 34, alignment: .leading)
                Text("Avg").frame(width: 60, alignment: .trailing)
                Text("Fixed").frame(width: 38, alignment: .trailing)
                Text("Flex").frame(width: 50, alignment: .trailing)
                Spacer()
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(mainPositions, id: \.self) { pos in
                    let avg = averageActualStarters(pos)
                    let base = fixedSlotCounts()[pos] ?? 0
                    let flexAvg = max(0, avg - Double(base))
                    HStack {
                        Text(pos).frame(width: 34, alignment: .leading)
                        Text(String(format: "%.2f", avg)).foregroundColor(avgColor(avg: avg, base: base)).frame(width: 60, alignment: .trailing)
                        Text("\(base)").frame(width: 38, alignment: .trailing)
                        Text(String(format: "%.2f", flexAvg)).frame(width: 50, alignment: .trailing)
                        Spacer()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                }
            }
        }
    }
    private var lineupSection: some View {
        sectionBox {
            Text("Lineup (Week \(selectedWeek.replacingOccurrences(of: "Wk ", with: "")))")
                .sectionTitleStyle()
            HStack {
                Text("Slot")
                    .bold()
                    .frame(maxWidth: .infinity / 3, alignment: .leading)
                Text("Pos")
                    .bold()
                    .frame(maxWidth: .infinity / 3, alignment: .center)
                Text("Score")
                    .bold()
                    .frame(maxWidth: .infinity / 3, alignment: .trailing)
            }
            if let week = getSelectedWeekNumber(), let t = selectedTeamSeason, let slots = league?.startingLineup {
                let startingSlots = slots.filter { !["BN", "IR", "TAXI"].contains($0) }
                let assigned = assignPlayersToSlots(team: t, week: week, slots: startingSlots)
                ForEach(assigned) { item in
                    HStack {
                        Text(item.slot)
                            .frame(maxWidth: .infinity / 3, alignment: .leading)
                        Text(item.playerPos)
                            .frame(maxWidth: .infinity / 3, alignment: .center)
                        Text(String(format: "%.2f", item.score))
                            .frame(maxWidth: .infinity / 3, alignment: .trailing)
                    }
                    .font(.caption)
                }
                let starters = t.actualStartersByWeek?[week] ?? []
                let bench = getBenchPlayers(team: t, week: week, starters: starters)
                ForEach(bench) { player in
                    HStack {
                        Text("BN")
                            .frame(maxWidth: .infinity / 3, alignment: .leading)
                        Text(player.pos)
                            .frame(maxWidth: .infinity / 3, alignment: .center)
                        Text(String(format: "%.2f", player.score))
                            .frame(maxWidth: .infinity / 3, alignment: .trailing)
                    }
                    .font(.caption)
                }
            } else {
                Text("No data available.")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.caption)
            }
        }
    }
    private var transactionSection: some View {
        sectionBox {
            Text("Transactions")
                .sectionTitleStyle()
            VStack(alignment: .leading, spacing: 4) {
                if appSelection.selectedSeason == "All Time", let agg = aggregated {
                    let waiverAll = agg.totalWaiverMoves
                    let faabAll = agg.totalFAABSpent
                    let tradesAll = agg.totalTradesCompleted
                    let seasons = max(1, agg.seasonsIncluded.count)
                    let faabPer = waiverAll > 0 ? faabAll / Double(waiverAll) : 0
                    let tradesPerSeason = Double(tradesAll) / Double(seasons)
                    transactionLine("Waiver Moves (All)", "\(waiverAll)")
                    transactionLine("FAAB Spent (All)", String(format: "%.0f", faabAll))
                    transactionLine("FAAB / Move", String(format: "%.2f", faabPer))
                    transactionLine("Trades (All)", "\(tradesAll)")
                    transactionLine("Trades / Season", String(format: "%.2f", tradesPerSeason))
                } else if let t = selectedTeamSeason {
                    transactionLine("Waiver Moves", "\(t.waiverMoves ?? 0)")
                    transactionLine("FAAB Spent", String(format: "%.0f", t.faabSpent ?? 0))
                    transactionLine("Trades", "\(t.tradesCompleted ?? 0)")
                } else {
                    Text("No transaction data")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.caption)
                }
            }
        }
    }
    private func transactionLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.68))
            Spacer()
            Text(value)
                .foregroundColor(.yellow)
        }
        .font(.caption.bold())
    }
    private var totalsSection: some View {
        sectionBox {
            Text("Totals")
                .sectionTitleStyle()
            Text(pointsSummary())
                .foregroundColor(.white)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var strengthsWeaknessesSection: some View {
        sectionBox {
            Text("Profile")
                .sectionTitleStyle()
            if let a = aggregated {
                profileLines(record: a.recordString,
                             seasons: a.seasonsIncluded.count,
                             championships: a.championships)
            } else if let t = selectedTeamSeason {
                profileLines(record: t.winLossRecord ?? "--",
                             seasons: nil,
                             championships: t.championships ?? 0)
            } else {
                Text("Select a team for details.")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.caption)
            }
        }
    }
    private func profileLines(record: String, seasons: Int?, championships: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Record: \(record)")
                .foregroundColor(.green)
            if let seasons {
                Text("Seasons: \(seasons)")
                    .foregroundColor(.white.opacity(0.7))
            }
            Text("Championships: \(championships)")
                .foregroundColor(championships > 0 ? .yellow : .white.opacity(0.5))
        }
        .font(.caption)
    }

    // MARK: Data Helpers
    private func displayTeamName() -> String {
        if let agg = aggregated { return agg.latestDisplayName }
        return selectedTeamSeason?.name ?? "Your Team"
    }
    private func managementTriplet() -> (Double, Double, Double) {
        if selectedWeek == "SZN" {
            if let a = aggregated {
                return (a.managementPercent,
                        a.offensiveManagementPercent,
                        a.defensiveManagementPercent)
            }
            if let t = selectedTeamSeason {
                return (t.managementPercent,
                        t.offensiveManagementPercent ?? 0,
                        t.defensiveManagementPercent ?? 0)
            }
            return (0,0,0)
        } else if let week = getSelectedWeekNumber(), let t = selectedTeamSeason {
            let (_, _, offActual, offMax, defActual, defMax) = computeWeeklyLineupPoints(team: t, week: week)
            let actual = offActual + defActual
            let maxPF = offMax + defMax
            let mgmt = maxPF > 0 ? (actual / maxPF * 100) : 0
            let off = offMax > 0 ? (offActual / offMax * 100) : 0
            let defMgmt = defMax > 0 ? (defActual / defMax * 100) : 0
            return (mgmt, off, defMgmt)
        } else {
            return (0,0,0)
        }
    }
    private func fixedSlotCounts() -> [String:Int] {
        let posSet: Set<String> = ["QB","RB","WR","TE","K","DL","LB","DB"]
        if let config = selectedTeamSeason?.lineupConfig {
            return config.reduce(into: [String:Int]()) { acc, pair in
                let key = pair.key.uppercased()
                if posSet.contains(key) {
                    acc[key, default: 0] += pair.value
                }
            }
        }
        if let raw = league?.startingLineup {
            return raw.reduce(into: [String:Int]()) { acc, slot in
                let u = slot.uppercased()
                if posSet.contains(u) {
                    acc[u, default: 0] += 1
                }
            }
        }
        return [:]
    }
    private func avgColor(avg: Double, base: Int) -> Color {
        if base == 0 {
            return avg > 0 ? .cyan : .white.opacity(0.55)
        }
        if avg + 0.01 < Double(base) { return .red }
        if abs(avg - Double(base)) < 0.05 { return .green }
        return .yellow
    }
    private func positionPoints(in team: TeamStanding, week: Int, pos: String) -> Double {
        guard let starters = team.actualStartersByWeek?[week] else { return 0 }
        let starterIds = Set(starters)
        let posPoints = team.roster.filter { starterIds.contains($0.id) && $0.position == pos }.reduce(0.0) { sum, player in
            let score = player.weeklyScores.first { $0.week == week }?.points ?? 0
            return sum + score
        }
        return posPoints
    }
    private func numberOfStarters(in team: TeamStanding, week: Int, pos: String) -> Int {
        guard let starters = team.actualStartersByWeek?[week] else { return 0 }
        return starters.filter { playerId in
            team.roster.first { $0.id == playerId }?.position == pos
        }.count
    }
    private func positionPPW(_ pos: String) -> Double {
        if let a = aggregated { return a.positionAvgPPW[pos] ?? 0 }
        if selectedWeek == "SZN" {
            return selectedTeamSeason?.positionAverages?[pos] ?? 0
        } else if let week = getSelectedWeekNumber(), let t = selectedTeamSeason {
            return positionPoints(in: t, week: week, pos: pos)
        } else {
            return 0
        }
    }
    private func individualPPW(_ pos: String) -> Double {
        if let a = aggregated { return a.individualPositionPPW[pos] ?? 0 }
        if selectedWeek == "SZN" {
            return selectedTeamSeason?.individualPositionAverages?[pos] ?? 0
        } else if let week = getSelectedWeekNumber(), let t = selectedTeamSeason {
            let posPoints = positionPPW(pos)
            let numStarters = numberOfStarters(in: t, week: week, pos: pos)
            return numStarters > 0 ? posPoints / Double(numStarters) : 0
        } else {
            return 0
        }
    }
    private func averageActualStarters(_ pos: String) -> Double {
        if let agg = aggregated {
            guard agg.actualStarterWeeks > 0 else { return 0 }
            return Double(agg.actualStarterPositionCountsTotals[pos] ?? 0) / Double(agg.actualStarterWeeks)
        }
        if selectedWeek == "SZN" {
            if let t = selectedTeamSeason,
               let weeks = t.actualStarterWeeks,
               weeks > 0 {
                return Double(t.actualStarterPositionCounts?[pos] ?? 0) / Double(weeks)
            }
            return 0
        } else if let week = getSelectedWeekNumber(), let t = selectedTeamSeason {
            return Double(numberOfStarters(in: t, week: week, pos: pos))
        } else {
            return 0
        }
    }
    private func pointsSummary() -> String {
        if selectedWeek == "SZN" {
            if let a = aggregated {
                return String(
                    format: "PF %.0f • PPW %.2f • MaxPF %.0f • Mgmt %.1f%% (Off %.1f%% / Def %.1f%%)",
                    a.totalPointsFor, a.teamPPW, a.totalMaxPointsFor, a.managementPercent,
                    a.offensiveManagementPercent, a.defensiveManagementPercent
                )
            }
            if let t = selectedTeamSeason {
                return String(
                    format: "PF %.0f • PPW %.2f • MaxPF %.0f • Mgmt %.1f%%",
                    t.pointsFor, t.teamPointsPerWeek, t.maxPointsFor, t.managementPercent
                )
            }
            return "--"
        } else if let week = getSelectedWeekNumber(), let t = selectedTeamSeason {
            let (pf, maxPF, offAct, offMax, defAct, defMax) = computeWeeklyLineupPoints(team: t, week: week)
            let mgmt = maxPF > 0 ? (pf / maxPF * 100) : 0
            let offMgmt = offMax > 0 ? (offAct / offMax * 100) : 0
            let defMgmt = defMax > 0 ? (defAct / defMax * 100) : 0
            return String(
                format: "PF %.0f • MaxPF %.0f • Mgmt %.1f%% (Off %.1f%% / Def %.1f%%)",
                pf, maxPF, mgmt, offMgmt, defMgmt
            )
        } else {
            return "--"
        }
    }
    private func leagueAvgMgmt() -> Double {
        if selectedWeek == "SZN" {
            return baseLeagueAvg { $0.managementPercent }
        } else {
            // No weekly management
            return 0
        }
    }
    private func leagueAvgOffMgmt() -> Double {
        if selectedWeek == "SZN" {
            return baseLeagueAvg { $0.offensiveManagementPercent ?? 0 }
        } else {
            // No weekly management
            return 0
        }
    }
    private func leagueAvgDefMgmt() -> Double {
        if selectedWeek == "SZN" {
            return baseLeagueAvg { $0.defensiveManagementPercent ?? 0 }
        } else {
            // No weekly management
            return 0
        }
    }
    private func leaguePosPPW(_ pos: String) -> Double {
        if selectedWeek == "SZN" {
            return average(seasonTeams.compactMap { $0.positionAverages?[pos] })
        } else if let week = getSelectedWeekNumber() {
            let teamPosPoints = seasonTeams.map { team in
                positionPoints(in: team, week: week, pos: pos)
            }
            return average(teamPosPoints)
        } else {
            return 0
        }
    }
    private func leagueIndividualPPW(_ pos: String) -> Double {
        if selectedWeek == "SZN" {
            return average(seasonTeams.compactMap { $0.individualPositionAverages?[pos] })
        } else if let week = getSelectedWeekNumber() {
            let teamIndPPW = seasonTeams.map { team in
                let posPoints = positionPoints(in: team, week: week, pos: pos)
                let numStarters = numberOfStarters(in: team, week: week, pos: pos)
                return numStarters > 0 ? posPoints / Double(numStarters) : 0
            }
            return average(teamIndPPW)
        } else {
            return 0
        }
    }
    private func baseLeagueAvg(_ selector: (TeamStanding) -> Double) -> Double { average(seasonTeams.map(selector)) }
    private func colorVsLeague(_ value: Double, leagueAvg: Double) -> Color {
        if value > leagueAvg + 3 { return .green }
        if value < leagueAvg - 3 { return .red }
        return .yellow
    }
    private func gridForPositions(valueProvider: @escaping (String) -> Double,
                                  leagueAvgProvider: @escaping (String) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(mainPositions, id: \.self) { pos in
                let val = valueProvider(pos)
                let avg = leagueAvgProvider(pos)
                HStack {
                    Text(pos)
                        .foregroundColor(positionColor(pos))
                        .frame(width: 40, alignment: .leading)
                    Text(String(format: "%.2f", val))
                        .foregroundColor(colorVsLeague(val, leagueAvg: avg))
                        .frame(width: 70, alignment: .leading)
                    Text("Lg \(String(format: "%.2f", avg))")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.caption2)
                    Spacer()
                }
                .font(.caption.bold())
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
    private func average(_ arr: [Double]) -> Double {
        guard !arr.isEmpty else { return 0 }
        return arr.reduce(0,+) / Double(arr.count)
    }
    private func sectionBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Weekly Computation Helpers
    private func getSelectedWeekNumber() -> Int? {
        if selectedWeek == "SZN" {
            return nil
        }
        let numStr = selectedWeek.replacingOccurrences(of: "Wk ", with: "")
        return Int(numStr)
    }

    private func computeWeeklyLineupPoints(team: TeamStanding, week: Int) -> (Double, Double, Double, Double, Double, Double) {
        // actualTotal, maxTotal, actualOff, maxOff, actualDef, maxDef

        var playerScores: [String: Double] = [:]
        var playerPos: [String: String] = [:]
        for player in team.roster {
            if let score = player.weeklyScores.first { $0.week == week }?.points {
                playerScores[player.id] = score
                playerPos[player.id] = player.position
            }
        }

        // Compute actual points (total, off, def) from starters
        let starters = team.actualStartersByWeek?[week] ?? []
        var actualTotal = 0.0
        var actualOff = 0.0
        var actualDef = 0.0
        for id in starters {
            if let score = playerScores[id], let pos = playerPos[id] {
                actualTotal += score
                if offensivePositions.contains(pos) {
                    actualOff += score
                } else if defensivePositions.contains(pos) {
                    actualDef += score
                }
            }
        }

        // Compute max points
        let startingSlots = league?.startingLineup ?? []
        let fixedCounts = fixedSlotCounts()

        // Offensive computation
        let offPositions: Set<String> = offensivePositions
        var offPlayerList = team.roster.filter { offPositions.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxOff = 0.0

        // Allocate fixed offensive slots
        for pos in Array(offPositions) {
            if let count = fixedCounts[pos] {
                var candidates = offPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                let top = Array(candidates.prefix(count))
                maxOff += top.reduce(0.0) { $0 + $1.score }
                // Remove used players
                offPlayerList.removeAll { used in top.contains { $0.id == used.id } }
            }
        }

        // Allocate flex slots (assuming standard FLEX for RB/WR/TE, count all non-fixed slots as flex)
        let flexAllowed: Set<String> = ["RB", "WR", "TE"]
        let flexCount = startingSlots.filter { offensiveFlexSlots.contains($0) }.count
        var flexCandidates = offPlayerList.filter { flexAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        let topFlex = Array(flexCandidates.prefix(flexCount))
        maxOff += topFlex.reduce(0.0) { $0 + $1.score }

        // Defensive computation
        let defPositions: Set<String> = defensivePositions
        var defPlayerList = team.roster.filter { defPositions.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxDef = 0.0

        // Allocate fixed defensive slots
        for pos in Array(defPositions) {
            if let count = fixedCounts[pos] {
                var candidates = defPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                let top = Array(candidates.prefix(count))
                maxDef += top.reduce(0.0) { $0 + $1.score }
                // Remove used players
                defPlayerList.removeAll { used in top.contains { $0.id == used.id } }
            }
        }

        // Assume no defensive flex for simplicity

        let maxTotal = maxOff + maxDef

        return (actualTotal, maxTotal, actualOff, maxOff, actualDef, maxDef)
    }

    private func assignPlayersToSlots(team: TeamStanding, week: Int, slots: [String]) -> [AssignedSlot] {
        guard let starters = team.actualStartersByWeek?[week], starters.count == slots.count else { return [] }
        var results: [AssignedSlot] = []
        for (index, slot) in slots.enumerated() {
            let player_id = starters[index]
            if let player = team.roster.first(where: { $0.id == player_id }),
               let score = player.weeklyScores.first(where: { $0.week == week })?.points {
                results.append(AssignedSlot(slot: slot, playerPos: player.position, score: score))
            }
        }
        return results
    }

    private func getBenchPlayers(team: TeamStanding, week: Int, starters: [String]) -> [BenchPlayer] {
        var res: [BenchPlayer] = []
        for player in team.roster where !starters.contains(player.id) {
            if let score = player.weeklyScores.first(where: { $0.week == week })?.points {
                res.append(BenchPlayer(id: player.id, pos: player.position, score: score))
            }
        }
        return res.sorted { $0.score > $1.score }
    }

    private let offensivePositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
    private let defensivePositions: Set<String> = ["DL", "LB", "DB"]
    private let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]
}

// MARK: Text Style Helpers
private extension Text {
    func sectionTitleStyle() -> Text {
        self.font(.title2.bold()).foregroundColor(.orange)
    }
    func sectionSubtitleStyle() -> Text {
        self.font(.headline.bold()).foregroundColor(.orange)
    }
}

