//
//  MyLeagueView.swift
//  DynastyStatDrop
//
//  VISUAL UPGRADE: Adds sorting by record/PF, replaces PA with Grade column using TeamGradeComponents.swift
//
//  PATCH: Menu layout now matches MyTeamView — Season | Off/Def | Wks | DSD.
//         Off/Def context drives standings/grades/stat calculation. Week selector is "Wks" button.
//         Standings table sorts by PF, then Grade, then team name; grades/stat columns reflect context/week.
//         All logic is integrated for continuity, no code is truncated or removed.

import SwiftUI

enum LeagueContext: String, CaseIterable {
    case full = "Full Team"
    case offense = "Offense"
    case defense = "Defense"
    var label: String {
        switch self {
        case .full: return "Full Team"
        case .offense: return "Offense"
        case .defense: return "Defense"
        }
    }
}

struct MyLeagueView: View {
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var leagueManager: SleeperLeagueManager
    @Binding var selectedTab: Tab
    @AppStorage("statDropPersonality") var userStatDropPersonality: StatDropPersonality = .classicESPN
    @State private var selectedWeek: String = "SZN"
    @State private var isStatDropActive: Bool = false
    @State private var selectedContext: LeagueContext = .full

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
        guard let team = seasonTeams.first else { return ["SZN"] }
        if let season = league?.seasons.first(where: { $0.teams.contains(where: { $0.id == team.id }) }),
           let mByWeek = season.matchupsByWeek {
            let weeks = mByWeek.keys.sorted()
            if weeks.isEmpty { return ["SZN"] }
            return weeks.map { "Wk \($0)" } + ["SZN"]
        }
        let allWeeks = team.roster.flatMap { $0.weeklyScores }.map { $0.week }
        let uniqueWeeks = Set(allWeeks).sorted()
        if uniqueWeeks.isEmpty { return ["SZN"] }
        return uniqueWeeks.map { "Wk \($0)" } + ["SZN"]
    }

    private var cleanedLeagueName: String {
        league?.name.unicodeScalars.filter { !$0.properties.isEmojiPresentation }.reduce(into: "") { $0 += String($1) } ?? "League"
    }

    private var teams: [TeamStanding] {
        if let lg = league {
            return lg.seasons.sorted { $0.id < $1.id }.last?.teams ?? lg.teams
        }
        return []
    }

    // MARK: - Grade Calculation Logic (Context/Week aware)

    // For single week view, provide stat/grade for only that week & context
    private func getSelectedWeekNumber() -> Int? {
        if selectedWeek == "SZN" {
            return nil
        }
        let numStr = selectedWeek.replacingOccurrences(of: "Wk ", with: "")
        return Int(numStr)
    }

    private func pointsFor(team: TeamStanding) -> Double {
        if let week = getSelectedWeekNumber() {
            return statForWeek(team: team, week: week, context: selectedContext)
        } else {
            switch selectedContext {
            case .full: return DSDStatsService.shared.stat(for: team, type: .pointsFor) as? Double ?? 0
            case .offense: return DSDStatsService.shared.stat(for: team, type: .offensivePointsFor) as? Double ?? 0
            case .defense: return DSDStatsService.shared.stat(for: team, type: .defensivePointsFor) as? Double ?? 0
            }
        }
    }
    private func managementPercent(team: TeamStanding) -> Double {
        if let week = getSelectedWeekNumber() {
            return mgmtForWeek(team: team, week: week, context: selectedContext)
        } else {
            switch selectedContext {
            case .full: return team.managementPercent
            case .offense: return team.offensiveManagementPercent ?? 0
            case .defense: return team.defensiveManagementPercent ?? 0
            }
        }
    }
    // Week stat/grade helpers
    private func statForWeek(team: TeamStanding, week: Int, context: LeagueContext) -> Double {
        guard let league = league,
              let season = league.seasons.first(where: { $0.teams.contains(where: { $0.id == team.id }) }),
              let myEntry = season.matchupsByWeek?[week]?.first(where: { $0.roster_id == Int(team.id) }),
              let starters = myEntry.starters,
              let playersPoints = myEntry.players_points
        else { return 0 }
        let allPlayers = leagueManager.playerCache ?? [:]
        var off = 0.0, def = 0.0, total = 0.0
        for pid in starters {
            let player = team.roster.first(where: { $0.id == pid })
                ?? allPlayers[pid].map { raw in
                    Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                }
            let pos = PositionNormalizer.normalize(player?.position ?? "UNK")
            let pts = playersPoints[pid] ?? 0
            if ["QB","RB","WR","TE","K"].contains(pos) { off += pts }
            else if ["DL","LB","DB"].contains(pos) { def += pts }
            total += pts
        }
        switch context {
        case .full: return total
        case .offense: return off
        case .defense: return def
        }
    }
    private func mgmtForWeek(team: TeamStanding, week: Int, context: LeagueContext) -> Double {
        guard let league = league,
              let season = league.seasons.first(where: { $0.teams.contains(where: { $0.id == team.id }) }),
              let myEntry = season.matchupsByWeek?[week]?.first(where: { $0.roster_id == Int(team.id) }),
              let playersPool = myEntry.players,
              let playersPoints = myEntry.players_points
        else { return 0 }
        let playerCache = leagueManager.playerCache ?? [:]
        let startingSlots = league.startingLineup.filter { !["BN", "IR", "TAXI"].contains($0) }
        // --- ACTUAL ---
        let starters = myEntry.starters ?? []
        var actualOff = 0.0, actualDef = 0.0, actualTotal = 0.0
        for pid in starters {
            let p = team.roster.first(where: { $0.id == pid })
                ?? playerCache[pid].map { raw in
                    Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                }
            let pos = PositionNormalizer.normalize(p?.position ?? "UNK")
            let score = playersPoints[pid] ?? 0
            actualTotal += score
            if ["QB","RB","WR","TE","K"].contains(pos) {
                actualOff += score
            } else if ["DL","LB","DB"].contains(pos) {
                actualDef += score
            }
        }
        // --- MAX/OPTIMAL ---
        let candidates: [(id: String, pos: String, altPos: [String], score: Double)] = playersPool.compactMap { pid in
            let p = team.roster.first(where: { $0.id == pid })
                ?? playerCache[pid].map { raw in
                    Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                }
            guard let p = p else { return nil }
            let basePos = PositionNormalizer.normalize(p.position)
            let altPos = (p.altPositions ?? []).map { PositionNormalizer.normalize($0) }
            return (id: pid, pos: basePos, altPos: altPos, score: playersPoints[pid] ?? 0)
        }
        var strictSlots: [String] = []
        var flexSlots: [String] = []
        for slot in startingSlots {
            let allowed = allowedPositions(for: slot)
            if allowed.count == 1 &&
                !isIDPFlex(slot) &&
                !offensiveFlexSlots.contains(slot.uppercased()) {
                strictSlots.append(slot)
            } else {
                flexSlots.append(slot)
            }
        }
        let optimalOrder = strictSlots + flexSlots
        var used = Set<String>()
        var maxTotal = 0.0
        var maxOff = 0.0
        var maxDef = 0.0
        for slot in optimalOrder {
            let allowed = allowedPositions(for: slot)
            let pick = candidates
                .filter { !used.contains($0.id) && isEligible($0, allowed: allowed) }
                .max { $0.score < $1.score }
            guard let best = pick else { continue }
            used.insert(best.id)
            maxTotal += best.score
            if ["QB","RB","WR","TE","K"].contains(best.pos) { maxOff += best.score }
            else if ["DL","LB","DB"].contains(best.pos) { maxDef += best.score }
        }
        switch context {
        case .full: return maxTotal > 0 ? (actualTotal / maxTotal) * 100 : 0
        case .offense: return maxOff > 0 ? (actualOff / maxOff) * 100 : 0
        case .defense: return maxDef > 0 ? (actualDef / maxDef) * 100 : 0
        }
    }

    // Standings sorted by PF, then Grade, then name (all context/week aware)
    private var gradeComponents: [TeamGradeComponents] {
        seasonTeams.map { team in
            let pf = pointsFor(team: team)
            let mgmt = managementPercent(team: team)
            let ppw = getSelectedWeekNumber() != nil ? pf : team.teamPointsPerWeek
            let recordPct: Double = {
                let wl = DSDStatsService.shared.stat(for: team, type: .winLossRecord) as? String
                let (w, l, t) = TeamGradeComponents.parseRecord(wl)
                let games = Double(w + l + t)
                return games > 0 ? (Double(w) + 0.5 * Double(t)) / games : 0
            }()
            // For offense/defense, zero out irrelevant stats for grading
            let stat = { (type: DSDStatsService.StatType) -> Double in
                if getSelectedWeekNumber() != nil { return 0 } // week grading only by PF/Mgmt/Record
                switch selectedContext {
                case .full: return DSDStatsService.shared.stat(for: team, type: type) as? Double ?? 0
                case .offense:
                    if [.offensivePointsFor, .maxOffensivePointsFor, .offensiveManagementPercent, .averageOffensivePPW, .qbPositionPPW, .rbPositionPPW, .wrPositionPPW, .tePositionPPW, .kickerPPW].contains(type) {
                        return DSDStatsService.shared.stat(for: team, type: type) as? Double ?? 0
                    }
                    return 0
                case .defense:
                    if [.defensivePointsFor, .maxDefensivePointsFor, .defensiveManagementPercent, .averageDefensivePPW, .dlPositionPPW, .lbPositionPPW, .dbPositionPPW].contains(type) {
                        return DSDStatsService.shared.stat(for: team, type: type) as? Double ?? 0
                    }
                    return 0
                }
            }
            return TeamGradeComponents(
                pointsFor: pf,
                ppw: ppw,
                mgmt: mgmt,
                offMgmt: selectedContext == .defense ? 0 : stat(.offensiveManagementPercent),
                defMgmt: selectedContext == .offense ? 0 : stat(.defensiveManagementPercent),
                recordPct: recordPct,
                qbPPW: stat(.qbPositionPPW),
                rbPPW: stat(.rbPositionPPW),
                wrPPW: stat(.wrPositionPPW),
                tePPW: stat(.tePositionPPW),
                kPPW: stat(.kickerPPW),
                dlPPW: stat(.dlPositionPPW),
                lbPPW: stat(.lbPositionPPW),
                dbPPW: stat(.dbPositionPPW),
                teamName: team.name
            )
        }
    }
    private var teamGrades: [String: (grade: String, composite: Double)] {
        let gc = gradeComponents
        let all = gradeTeams(gc)
        var dict: [String: (String, Double)] = [:]
        for (name, grade, score, _) in all {
            dict[name] = (grade, score)
        }
        return dict
    }
    private var sortedTeams: [TeamStanding] {
        let grades = gradeComponents
        // PF desc, then Grade desc, then name asc
        return seasonTeams.sorted { a, b in
            let pfA = pointsFor(team: a)
            let pfB = pointsFor(team: b)
            if pfA != pfB { return pfA > pfB }
            let gradeA = teamGrades[a.name]?.composite ?? 0
            let gradeB = teamGrades[b.name]?.composite ?? 0
            if gradeA != gradeB { return gradeA > gradeB }
            return a.name < b.name
        }
    }

    // MARK: - UI

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    headerBlock
                    if isStatDropActive {
                        statDropContent
                    } else {
                        standingsSection
                        leagueInfoSection
                    }
                    Spacer(minLength: 120)
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, horizontalEdgePadding)
                .padding(.top, 32)
                .padding(.bottom, 120)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Header
    private var headerBlock: some View {
        VStack(spacing: 18) {
            Text(cleanedLeagueName)
                .font(.system(size: 36, weight: .heavy))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            selectionMenus
        }
    }

    // --- Four-tab Menu Layout (matches MyTeamView) ---
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

            // Bottom Row: 4 tabs equally spaced (Season, Off/Def, Wks, DSD)
            GeometryReader { geo in
                let spacing: CGFloat = menuSpacing * 3
                let totalAvailable = geo.size.width - spacing
                let tabWidth = totalAvailable / 4
                HStack(spacing: menuSpacing) {
                    seasonMenu
                        .frame(width: tabWidth)
                    offDefMenu
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

    private var offDefMenu: some View {
        Menu {
            // Only one can be selected at a time; Full Team is default
            Button("Team") { selectedContext = .full }
            Button("Off") { selectedContext = .offense }
            Button("Def") { selectedContext = .defense }
        } label: {
            menuLabel(selectedContext.label)
        }
    }

    private var weekMenu: some View {
        Menu {
            ForEach(availableWeeks, id: \.self) { wk in
                Button(wk) { selectedWeek = wk }
            }
        } label: {
            menuLabel("Wks")
        }
    }

    private var statDropMenu: some View {
        Menu {
            if isStatDropActive {
                Button("Stats") { isStatDropActive = false }
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
        }
    }

    // MARK: Standings
    private var standingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standings")
                .font(.headline.bold())
                .foregroundColor(.orange)
                .padding(.bottom, 6)

            if sortedTeams.isEmpty {
                Text("No teams available. Import or select a league.")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.caption)
            } else {
                // Standings header
                HStack {
                    Text("Team")
                        .foregroundColor(.orange)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("PF")
                        .foregroundColor(.orange)
                        .font(.headline)
                        .frame(width: 70, alignment: .trailing)
                    Text("Mgmt%")
                        .foregroundColor(.orange)
                        .font(.headline)
                        .frame(width: 70, alignment: .trailing)
                    Text("Grade")
                        .foregroundColor(.orange)
                        .font(.headline)
                        .frame(width: 50, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)

                ForEach(sortedTeams) { team in
                    let pf = pointsFor(team: team)
                    let mgmt = managementPercent(team: team)
                    let gradeTuple = teamGrades[team.name]
                    let grade = gradeTuple?.grade ?? "--"
                    let composite = gradeTuple?.composite ?? 0

                    HStack {
                        Text(team.name)
                            .foregroundColor(.white)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: "%.2f", pf))
                            .foregroundColor(.cyan)
                            .bold()
                            .frame(width: 70, alignment: .trailing)

                        Text(String(format: "%.1f%%", mgmt))
                            .foregroundColor(Color.mgmtPercentColor(mgmt))
                            .frame(width: 70, alignment: .trailing)

                        Text(grade)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(gradeColor(grade))
                            .frame(width: 50, alignment: .trailing)
                            .shadow(color: gradeColor(grade).opacity(0.23), radius: 2, y: 1)
                            .overlay(
                                Text(emojiForGrade(grade))
                                    .font(.system(size: 17))
                                    .offset(y: 17)
                                    .opacity(grade != "--" ? 0.26 : 0)
                            )
                    }
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(composite >= 0.85 ? 0.05 : 0.02))
                            .shadow(color: composite >= 0.85 ? .yellow.opacity(0.18) : .clear, radius: 4, y: 2)
                    )
                }
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

    // MARK: League Info
    private var leagueInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("League Info")
                .font(.headline.bold())
                .foregroundColor(.orange)

            Text("Season: \(league?.season ?? "--")")
                .foregroundColor(.white.opacity(0.8))

            Text("Teams: \(teams.count)")
                .foregroundColor(.white.opacity(0.8))
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

    // MARK: - Grade Color/Emoji
    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A+": return .green
        case "A": return .green.opacity(0.87)
        case "A-": return .mint
        case "B+": return .yellow
        case "B": return .orange
        case "B-": return .orange.opacity(0.8)
        case "C+": return .red
        case "C": return .red.opacity(0.75)
        case "C-": return .gray
        default: return .gray.opacity(0.6)
        }
    }
    private func emojiForGrade(_ grade: String) -> String {
        switch grade {
        case "A+": return "⚡️"
        case "A": return "🔥"
        case "A-": return "🏆"
        case "B+": return "👍"
        case "B": return "👌"
        case "B-": return "🙂"
        case "C+": return "🤔"
        case "C": return "😬"
        case "C-": return "🥶"
        default: return ""
        }
    }

    // --- Utility functions for position/slot logic (from MyTeamView) ---
    private func allowedPositions(for slot: String) -> Set<String> {
        switch slot.uppercased() {
        case "QB","RB","WR","TE","K","DL","LB","DB": return Set([PositionNormalizer.normalize(slot)])
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return Set(["RB","WR","TE"].map(PositionNormalizer.normalize))
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return Set(["QB","RB","WR","TE"].map(PositionNormalizer.normalize))
        case "IDP": return Set(["DL","LB","DB"])
        default:
            if slot.uppercased().contains("IDP") { return Set(["DL","LB","DB"]) }
            return Set([PositionNormalizer.normalize(slot)])
        }
    }
    private func isIDPFlex(_ slot: String) -> Bool {
        let s = slot.uppercased()
        return s.contains("IDP") && s != "DL" && s != "LB" && s != "DB"
    }
    private func isEligible(_ c: (id: String, pos: String, altPos: [String], score: Double), allowed: Set<String>) -> Bool {
        let normBase = PositionNormalizer.normalize(c.pos)
        let normAlt = c.altPos.map { PositionNormalizer.normalize($0) }
        if allowed.contains(normBase) { return true }
        return !allowed.intersection(Set(normAlt)).isEmpty
    }
    private let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]
}
