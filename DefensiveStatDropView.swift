import SwiftUI

struct DefensiveStatDropView: View {
    @EnvironmentObject var appSelection: AppSelection

    private var league: LeagueData? {
        appSelection.selectedLeague
    }

    private var latestSeason: SeasonData? {
        league?.seasons.sorted { $0.id < $1.id }.last
    }

    private var currentTeams: [TeamStanding] {
        latestSeason?.teams ?? []
    }

    private var seasonTeams: [TeamStanding] {
        guard let league = league else { return [] }
        if appSelection.selectedSeason == "All Time" { return currentTeams }
        return league.seasons.first { $0.id == appSelection.selectedSeason }?.teams ?? []
    }

    private var team: TeamStanding? {
        appSelection.selectedTeam
    }

    private var aggregate: AggregatedOwnerStats? {
        guard appSelection.selectedSeason == "All Time",
              let league = league,
              let t = team else { return nil }
        return league.allTimeOwnerStats?[t.ownerId]
    }

    private var seasonIds: [String] {
        guard let league = league else { return ["All Time"] }
        return ["All Time"] + league.seasons.map { $0.id }
    }

    private let defPositions = ["DL","LB","DB"]

    var body: some View {
        VStack(alignment: .leading) {
            pickerRow
            Divider().background(Color.white.opacity(0.2))
            if let tm = team {
                content(for: tm)
            } else {
                Text("Select a team to view defensive stats.")
                    .foregroundColor(.gray)
                    .padding()
            }
            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        // Selection is now always centralized via AppSelection; no local state or init logic required.
    }

    private var pickerRow: some View {
        HStack {
            Menu {
                ForEach(appSelection.leagues, id: \.id) { lg in
                    Button(lg.name) { appSelection.selectedLeagueId = lg.id }
                }
            } label: { pickerLabel(league?.name ?? "League", width: 150) }

            Menu {
                ForEach(seasonIds, id: \.self) { id in
                    Button(id) { appSelection.selectedSeason = id }
                }
            } label: { pickerLabel(appSelection.selectedSeason, width: 110) }

            Menu {
                ForEach(seasonTeams, id: \.id) { tm in
                    Button(tm.name) { appSelection.selectedTeamId = tm.id }
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

    private func content(for team: TeamStanding) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Defensive Stats – \(displayName(team))")
                    .font(.title2.bold())
                    .foregroundColor(.orange)

                HStack {
                    statBox("Points For", dpfString(team))
                    statBox("Avg PPW", dppwString(team))
                    statBox("Max PF", maxDefString(team))
                    statBox("Mgmt %", defMgmtString(team))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Positions")
                        .font(.headline).foregroundColor(.yellow)
                    ForEach(defPositions, id: \.self) { pos in
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
                    StatDropAnalysisBox(team: team, league: league, context: .defense, personality: .classicESPN)
                }
            }
            .padding()
        }
    }

    // Derived strings
    private func displayName(_ team: TeamStanding) -> String {
        aggregate?.latestDisplayName ?? team.name
    }
    private func dpfString(_ team: TeamStanding) -> String {
        if let a = aggregate { return String(format: "%.0f", a.totalDefensivePointsFor) }
        return String(format: "%.0f", team.defensivePointsFor ?? 0)
    }
    private func dppwString(_ team: TeamStanding) -> String {
        if let a = aggregate { return String(format: "%.2f", a.defensivePPW) }
        return String(format: "%.2f", team.averageDefensivePPW ?? 0)
    }
    private func maxDefString(_ team: TeamStanding) -> String {
        if let a = aggregate { return String(format: "%.0f", a.totalMaxDefensivePointsFor) }
        return String(format: "%.0f", team.maxDefensivePointsFor ?? 0)
    }
    private func defMgmtString(_ team: TeamStanding) -> String {
        let v: Double
        if let a = aggregate { v = a.defensiveManagementPercent }
        else { v = team.defensiveManagementPercent ?? 0 }
        return String(format: "%.1f%%", v)
    }

    private func posPPW(_ pos: String) -> Double {
        if let a = aggregate { return a.positionAvgPPW[pos] ?? 0 }
        return team?.positionAverages?[pos] ?? 0
    }

    private func posIndPPW(_ pos: String) -> Double {
        if let a = aggregate { return a.individualPositionPPW[pos] ?? 0 }
        return team?.individualPositionAverages?[pos] ?? 0
    }

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
        case "DL": return .orange
        case "LB": return .mint
        case "DB": return .pink
        default: return .white
        }
    }
}
