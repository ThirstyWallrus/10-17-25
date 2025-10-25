//
//  TeamStatDropView.swift
//  DSD
//
//  Created by Dynasty Stat Drop on 7/8/25.
//
//  Refactored: Selection state/logic fully centralized in AppSelection
//  - All local state for leagueId, seasonId, teamId removed
//  - All references to league, season, team, aggregate now use AppSelection published properties
//  - All pickers mutate AppSelection directly
//  - No auto-selection logic locally; rely on AppSelection logic
//

import SwiftUI

struct TeamStatDropView: View {
    @EnvironmentObject var appSelection: AppSelection

    // Choose a personality or allow user to pick; here we'll just use classicESPN as default
    @AppStorage("statDropPersonality") private var userStatDropPersonality: StatDropPersonality = .classicESPN

    private var league: LeagueData? {
        appSelection.selectedLeague
    }

    private var seasonTeams: [TeamStanding] {
        guard let league = appSelection.selectedLeague else { return [] }
        if appSelection.selectedSeason == "All Time" {
            // Show teams from latest season for "All Time"
            return league.seasons.sorted { $0.id < $1.id }.last?.teams ?? []
        }
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams ?? []
    }

    private var team: TeamStanding? {
        appSelection.selectedTeam
    }

    private var aggregate: AggregatedOwnerStats? {
        guard appSelection.selectedSeason == "All Time",
              let league = appSelection.selectedLeague,
              let t = appSelection.selectedTeam else { return nil }
        return league.allTimeOwnerStats?[t.ownerId]
    }

    private var seasonIds: [String] {
        guard let league = appSelection.selectedLeague else { return ["All Time"] }
        let ids = league.seasons.map { $0.id }
        return ["All Time"] + ids
    }

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
        .onAppear {
            // On appear, no local selection logic needed.
        }
        // Sync menus with AppSelection updates
        .onChange(of: appSelection.selectedLeagueId) { _ in /* No local logic needed */ }
        .onChange(of: appSelection.selectedSeason) { _ in /* No local logic needed */ }
        .onChange(of: appSelection.selectedTeamId) { _ in /* No local logic needed */ }
        .onChange(of: appSelection.leagues) { _ in /* No local logic needed */ }
    }

    private var pickerRow: some View {
        HStack {
            // League picker
            Menu {
                ForEach(appSelection.leagues, id: \.id) { lg in
                    Button(lg.name) {
                        appSelection.selectedLeagueId = lg.id
                    }
                }
            } label: {
                pickerLabel(appSelection.selectedLeague?.name ?? "League", width: 150)
            }

            // Season picker
            Menu {
                ForEach(seasonIds, id: \.self) { sid in
                    Button(sid) {
                        appSelection.selectedSeason = sid
                    }
                }
            } label: {
                pickerLabel(appSelection.selectedSeason.isEmpty ? "Season" : appSelection.selectedSeason, width: 110)
            }

            // Team picker
            Menu {
                ForEach(seasonTeams, id: \.id) { tm in
                    Button(tm.name) {
                        appSelection.selectedTeamId = tm.id
                    }
                }
            } label: {
                pickerLabel(appSelection.selectedTeam?.name ?? "Team", width: 140)
            }
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
                        context: appSelection.selectedSeason == "All Time" ? .fullTeam : .team,
                        personality: userStatDropPersonality
                    )
                }

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
}
