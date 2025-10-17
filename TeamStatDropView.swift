//
//  TeamStatDropView.swift
//  DSD
//
//  Created by Dynasty Stat Drop on 7/8/25.
//

import SwiftUI

struct TeamStatDropView: View {
    @EnvironmentObject var appSelection: AppSelection

    @State private var leagueId: String = ""
    @State private var seasonId: String = "All Time"
    @State private var teamId: String = ""

    private var league: LeagueData? {
        appSelection.leagues.first { $0.id == leagueId }
    }

    private var latestSeason: SeasonData? {
        league?.seasons.sorted { $0.id < $1.id }.last
    }

    private var currentTeams: [TeamStanding] {
        latestSeason?.teams ?? []
    }

    private var seasonTeams: [TeamStanding] {
        guard let league else { return [] }
        if seasonId == "All Time" { return currentTeams }
        return league.seasons.first { $0.id == seasonId }?.teams ?? []
    }

    private var team: TeamStanding? {
        seasonTeams.first { $0.id == teamId }
    }

    private var aggregate: AggregatedOwnerStats? {
        guard seasonId == "All Time",
              let league,
              let t = team else { return nil }
        return league.allTimeOwnerStats?[t.ownerId]
    }

    private var seasonIds: [String] {
        guard let league else { return ["All Time"] }
        return ["All Time"] + league.seasons.map { $0.id }
    }

    // Choose a personality or allow user to pick; here we'll just use classicESPN as default
    @AppStorage("statDropPersonality") private var userStatDropPersonality: StatDropPersonality = .classicESPN

    var body: some View {
        VStack(alignment: .leading) {
            pickerRow
            Divider().background(Color.white.opacity(0.2))
            if let tm = team {
                content(for: tm)
            } else {
                Text("Select a team to view stats.")
                    .foregroundColor(.gray)
                    .padding()
            }
            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { initPickers() }
        .onChange(of: appSelection.leagues) { _ in syncLeague() }
        .onChange(of: leagueId) { _ in resetSeason() }
        .onChange(of: seasonId) { _ in resetTeam() }
    }

    private var pickerRow: some View {
        HStack {
            Menu {
                ForEach(appSelection.leagues, id: \.id) { lg in
                    Button(lg.name) { leagueId = lg.id }
                }
            } label: { pickerLabel(league?.name ?? "League", width: 150) }

            Menu {
                ForEach(seasonIds, id: \.self) { sid in
                    Button(sid) { seasonId = sid }
                }
            } label: { pickerLabel(seasonId, width: 110) }

            Menu {
                ForEach(seasonTeams, id: \.id) { tm in
                    Button(tm.name) { teamId = tm.id }
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
            VStack(alignment: .leading, spacing: 20) {
                Text("Team Stats – \(displayName(team))")
                    .font(.title2.bold())
                    .foregroundColor(.orange)

                // Top metrics
                HStack {
                    statBox("Points For", pfString(team))
                    statBox("PPW", ppwString(aggregate?.teamPPW ?? team.teamPointsPerWeek))
                    statBox("Max PF", maxPFString(team))
                    statBox("Mgmt %", mgmtString(team))
                }

                // Record / Rival / Best Game
                HStack {
                    statBox("Record", recordString(team))
                    statBox("Best Game", bestGameString(team))
                    statBox("Biggest Rival", rivalString(team))
                }

                // --- INSERT ANALYSIS SECTION HERE ---
                if let league = league {
                    StatDropAnalysisBox(
                        team: team,
                        league: league,
                        context: seasonId == "All Time" ? .fullTeam : .team,
                        personality: userStatDropPersonality
                    )
                }

                // REMOVE strengthsWeaknesses(team) SECTION

                championshipsSection(team)
            }
            .padding()
        }
    }

    // MARK: Derived strings

    private func displayName(_ team: TeamStanding) -> String {
        aggregate?.latestDisplayName ?? team.name
    }
    private func pfString(_ team: TeamStanding) -> String {
        if let a = aggregate { return String(format: "%.0f", a.totalPointsFor) }
        return String(format: "%.0f", team.pointsFor)
    }
    private func ppwString(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        return String(format: "%.2f", v)
    }
    private func maxPFString(_ team: TeamStanding) -> String {
        if let a = aggregate { return String(format: "%.0f", a.totalMaxPointsFor) }
        return String(format: "%.0f", team.maxPointsFor)
    }
    private func mgmtString(_ team: TeamStanding) -> String {
        let v: Double
        if let a = aggregate {
            v = a.managementPercent
        } else {
            // Calculate management percent from regular season data
            v = team.maxPointsFor > 0 ? (team.pointsFor / team.maxPointsFor) * 100 : 0
        }
        return String(format: "%.2f%%", v)
    }
    private func recordString(_ team: TeamStanding) -> String {
        if let a = aggregate { return a.recordString }
        return team.winLossRecord ?? "--"
    }
    private func bestGameString(_ team: TeamStanding) -> String {
        team.bestGameDescription ?? "--"
    }
    private func rivalString(_ team: TeamStanding) -> String {
        team.biggestRival ?? "--"
    }

    private func championshipsSection(_ team: TeamStanding) -> some View {
        let champs = aggregate?.championships ?? (team.championships ?? 0)
        return HStack {
            Text("Championships:")
                .foregroundColor(.yellow)
                .bold()
            if champs > 0 {
                Text(String(repeating: "🏆", count: champs))
            } else {
                Text("None").foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
        .font(.headline)
    }

    // MARK: - UI Helpers

    private func statBox(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.05)))
    }

    // MARK: - Init / Sync
    private func initPickers() {
        if leagueId.isEmpty { leagueId = appSelection.leagues.first?.id ?? "" }
        if seasonId.isEmpty {
            seasonId = league?.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
        }
        resetTeam()
    }

    private func syncLeague() {
        if !appSelection.leagues.contains(where: { $0.id == leagueId }) {
            leagueId = appSelection.leagues.first?.id ?? ""
        }
        resetSeason()
    }

    private func resetSeason() {
        if let lg = league,
           seasonId != "All Time",
           !lg.seasons.contains(where: { $0.id == seasonId }) {
            seasonId = lg.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
        }
        resetTeam()
    }

    private func resetTeam() {
        if !seasonTeams.contains(where: { $0.id == teamId }) {
            teamId = seasonTeams.first?.id ?? ""
        }
    }
}
