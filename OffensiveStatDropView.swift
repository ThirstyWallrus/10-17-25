import SwiftUI

struct OffensiveStatDropView: View {
    @EnvironmentObject var appSelection: AppSelection

    // Remove all local @State and selection vars; use AppSelection exclusively

    private var league: LeagueData? {
        appSelection.selectedLeague
    }

    private var latestSeason: SeasonData? {
        league?.seasons.sorted { $0.id < $1.id }.last
    }

    // Current franchises only in All Time mode
    private var currentTeams: [TeamStanding] {
        latestSeason?.teams ?? []
    }

    private var seasonTeams: [TeamStanding] {
        guard let league else { return [] }
        if appSelection.selectedSeason == "All Time" { return currentTeams }
        return league.seasons.first { $0.id == appSelection.selectedSeason }?.teams ?? []
    }

    private var team: TeamStanding? {
        seasonTeams.first { $0.id == appSelection.selectedTeamId }
    }

    private var aggregate: AggregatedOwnerStats? {
        guard appSelection.selectedSeason == "All Time",
              let league,
              let t = team else { return nil }
        return league.allTimeOwnerStats?[t.ownerId]
    }

    private var seasonIds: [String] {
        guard let league else { return ["All Time"] }
        return ["All Time"] + league.seasons.map { $0.id }
    }

    private let offensePositions = ["QB","RB","WR","TE","K"]

    var body: some View {
        VStack(alignment: .leading) {
            pickerRow
            Divider().background(Color.white.opacity(0.2))
            if let tm = team {
                content(for: tm)
            } else {
                Text("Select a team to view offensive stats.")
                    .foregroundColor(.gray)
                    .padding()
            }
            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            // Remove local picker initialization, rely on centralized selection
            // Optionally, the view could trigger a sync if desired, but not needed for continuity
        }
        .onChange(of: appSelection.leagues) { _ in
            // Rely on AppSelection's centralized sync logic, no local mutation
        }
        // All season/team/league changes are handled via AppSelection
    }

    // MARK: - Pickers

    private var pickerRow: some View {
        HStack {
            Menu {
                ForEach(appSelection.leagues, id: \.id) { lg in
                    Button(lg.name) {
                        appSelection.selectedLeagueId = lg.id
                        appSelection.syncSelectionAfterLeagueChange(username: nil, sleeperUserId: nil)
                    }
                }
            } label: { pickerLabel(league?.name ?? "League", width: 150) }

            Menu {
                ForEach(seasonIds, id: \.self) { sid in
                    Button(sid) {
                        appSelection.selectedSeason = sid
                        appSelection.syncSelectionAfterSeasonChange(username: nil, sleeperUserId: nil)
                    }
                }
            } label: { pickerLabel(appSelection.selectedSeason, width: 110) }

            Menu {
                ForEach(seasonTeams, id: \.id) { tm in
                    Button(tm.name) {
                        appSelection.selectedTeamId = tm.id
                    }
                }
            } label: { pickerLabel(team?.name ?? "Team", width: 140) }
        }
        .padding(.top, 12)
        .padding(.horizontal)
    }

    private func pickerLabel(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .bold()
            .foregroundColor(.orange)
            .frame(width: width, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black)
                    .shadow(color: .blue, radius: 8)
            )
    }

    // MARK: - Content

    private func content(for team: TeamStanding) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Offensive Stats – \(displayName(team))")
                    .font(.title2.bold())
                    .foregroundColor(.orange)

                HStack {
                    statBox("Points For", pfString(team))
                    statBox("Avg PPW", oppwString(team))
                    statBox("Max PF", maxOffString(team))
                    statBox("Mgmt %", offMgmtString(team))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Positions")
                        .font(.headline).foregroundColor(.yellow)
                    ForEach(offensePositions, id: \.self) { pos in
                        HStack {
                            Text("\(pos):")
                                .foregroundColor(colorFor(pos)).bold()
                            Text("Avg/Wk: \(String(format: "%.2f", posPPW(pos)))")
                                .foregroundColor(.white)
                            Text("Per Slot: \(String(format: "%.2f", posIndPPW(pos)))")
                                .foregroundColor(.cyan)
                        }
                        .font(.caption.bold())
                    }
                }

                if let league = league {
                    StatDropAnalysisBox(team: team, league: league, context: .offense, personality: .classicESPN)
                }
            }
            .padding()
        }
    }

    // MARK: - Strings / Derived

    private func displayName(_ team: TeamStanding) -> String {
        aggregate?.latestDisplayName ?? team.name
    }

    private func pfString(_ team: TeamStanding) -> String {
        if let a = aggregate { return String(format: "%.0f", a.totalOffensivePointsFor) }
        return String(format: "%.0f", team.offensivePointsFor ?? 0)
    }

    private func oppwString(_ team: TeamStanding) -> String {
        if let a = aggregate { return String(format: "%.2f", a.offensivePPW) }
        return String(format: "%.2f", team.averageOffensivePPW ?? 0)
    }

    private func maxOffString(_ team: TeamStanding) -> String {
        if let a = aggregate { return String(format: "%.0f", a.totalMaxOffensivePointsFor) }
        return String(format: "%.0f", team.maxOffensivePointsFor ?? 0)
    }

    private func offMgmtString(_ team: TeamStanding) -> String {
        let m: Double
        if let a = aggregate {
            m = a.offensiveManagementPercent
        } else {
            m = team.offensiveManagementPercent ?? 0
        }
        return String(format: "%.1f%%", m)
    }

    private func posPPW(_ pos: String) -> Double {
        if let a = aggregate { return a.positionAvgPPW[pos] ?? 0 }
        return team.positionAverages?[pos] ?? 0
    }

    private func posIndPPW(_ pos: String) -> Double {
        if let a = aggregate { return a.individualPositionPPW[pos] ?? 0 }
        return team.individualPositionAverages?[pos] ?? 0
    }

    // MARK: - UI Helpers

    private func statBox(_ label: String, _ value: String) -> some View {
        VStack {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    private func colorFor(_ pos: String) -> Color {
        switch pos {
        case "QB": return .red
        case "RB": return .green
        case "WR": return .blue
        case "TE": return .yellow
        case "K": return .purple
        default: return .white
        }
    }
}
