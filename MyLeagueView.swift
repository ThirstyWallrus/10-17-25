//
//  MyLeagueView.swift
//  DynastyStatDrop
//
//  VISUAL UPGRADE: Adds sorting by record/PF, replaces PA with Grade column using TeamGradeComponents.swift
//

import SwiftUI

struct MyLeagueView: View {
    @EnvironmentObject var appSelection: AppSelection
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

    private var cleanedLeagueName: String {
        league?.name.unicodeScalars.filter { !$0.properties.isEmojiPresentation }.reduce(into: "") { $0 += String($1) } ?? "League"
    }

    // Get the latest season's teams, fallback to league.teams
    private var teams: [TeamStanding] {
        if let lg = league {
            return lg.seasons.sorted { $0.id < $1.id }.last?.teams ?? lg.teams
        }
        return []
    }

    // MARK: - Grade Calculation Logic

    // Parse W-L-T string ("10-4-1") to (wins, losses, ties)
    private func parseRecord(_ record: String?) -> (Int, Int, Int) {
        guard let rec = record else { return (0,0,0) }
        let parts = rec.split(separator: "-").map { Int($0) ?? 0 }
        if parts.count == 3 { return (parts[0], parts[1], parts[2]) }
        if parts.count == 2 { return (parts[0], parts[1], 0) }
        return (0,0,0)
    }

    // Construct TeamGradeComponents for the current season only
    private var gradeComponents: [TeamGradeComponents] {
        teams.map { team in
            let wl = DSDStatsService.shared.stat(for: team, type: .winLossRecord) as? String
            let (w, l, t) = parseRecord(wl)
            let games = Double(w + l + t)
            let recordPct = games > 0 ? (Double(w) + 0.5 * Double(t)) / games : 0
            return TeamGradeComponents(
                pointsFor: DSDStatsService.shared.stat(for: team, type: .pointsFor) as? Double ?? 0,
                    ppw: team.teamPointsPerWeek,
                    mgmt: team.managementPercent,
                    offMgmt: team.offensiveManagementPercent ?? 0,
                    defMgmt: team.defensiveManagementPercent ?? 0,
                    recordPct: recordPct,
                    qbPPW: DSDStatsService.shared.stat(for: team, type: .qbPositionPPW) as? Double ?? 0,
                    rbPPW: DSDStatsService.shared.stat(for: team, type: .rbPositionPPW) as? Double ?? 0,
                    wrPPW: DSDStatsService.shared.stat(for: team, type: .wrPositionPPW) as? Double ?? 0,
                    tePPW: DSDStatsService.shared.stat(for: team, type: .tePositionPPW) as? Double ?? 0,
                    kPPW: DSDStatsService.shared.stat(for: team, type: .kickerPPW) as? Double ?? 0,
                    dlPPW: DSDStatsService.shared.stat(for: team, type: .dlPositionPPW) as? Double ?? 0,
                    lbPPW: DSDStatsService.shared.stat(for: team, type: .lbPositionPPW) as? Double ?? 0,
                    dbPPW: DSDStatsService.shared.stat(for: team, type: .dbPositionPPW) as? Double ?? 0,
                    teamName: team.name
                )
        }
    }

    // Map from team name to grade tuple
    private var teamGrades: [String: (grade: String, composite: Double)] {
        let gc = gradeComponents
        let all = gradeTeams(gc) // [(teamName, grade, score, breakdown)]
        var dict: [String: (String, Double)] = [:]
        for (name, grade, score, _) in all {
            dict[name] = (grade, score)
        }
        return dict
    }

    // Sorted teams: by recordPct desc, then PF desc, then name
    private var sortedTeams: [TeamStanding] {
        let grades = gradeComponents
        return teams.sorted { a, b in
            let recA = grades.first(where: { $0.teamName == a.name })?.recordPct ?? 0
            let recB = grades.first(where: { $0.teamName == b.name })?.recordPct ?? 0
            if recA != recB { return recA > recB }
            let pfA = DSDStatsService.shared.stat(for: a, type: .pointsFor) as? Double ?? 0
            let pfB = DSDStatsService.shared.stat(for: b, type: .pointsFor) as? Double ?? 0
            if pfA != pfB { return pfA > pfB }
            return a.name < b.name
        }
    }

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

            // Bottom Row: Match tab widths to MyTeamView (as if 4 tabs), but space 3 equally
            GeometryReader { geo in
                let virtualSpacing: CGFloat = menuSpacing * 3 // As if 4 tabs
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
                    Text("Record")
                        .foregroundColor(.orange)
                        .font(.headline)
                        .frame(width: 60, alignment: .trailing)
                    Text("PF")
                        .foregroundColor(.orange)
                        .font(.headline)
                        .frame(width: 60, alignment: .trailing)
                    Text("Grade")
                        .foregroundColor(.orange)
                        .font(.headline)
                        .frame(width: 50, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)

                ForEach(sortedTeams) { team in
                    let wl = DSDStatsService.shared.stat(for: team, type: .winLossRecord) as? String ?? "--"
                    let pf = DSDStatsService.shared.stat(for: team, type: .pointsFor) as? Double ?? 0
                    let gradeTuple = teamGrades[team.name]
                    let grade = gradeTuple?.grade ?? "--"
                    let composite = gradeTuple?.composite ?? 0

                    HStack {
                        Text(team.name)
                            .foregroundColor(.white)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(wl)
                            .foregroundColor(.green)
                            .bold()
                            .frame(width: 60, alignment: .trailing)

                        Text(String(format: "%.2f", pf))
                            .foregroundColor(.cyan)
                            .bold()
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
}
