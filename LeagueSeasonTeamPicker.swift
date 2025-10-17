//
//  LeagueSeasonTeamPicker.swift
//  DynastyStatDrop
//
//  Fixed:
//   - Removed calls to non‑existent AppSelection methods (setLeague / setSeason / setTeam).
//   - Directly updates @EnvironmentObject AppSelection's published properties.
//   - Adds small helper logic to keep season & team selections valid after changes.
//   - Persists league selection when a new league is chosen (if a username was used during updateLeagues()).
//     (Persistence still handled externally via AppSelection.updateLeagues; here we only mutate state.)
//

import SwiftUI

struct LeagueSeasonTeamPicker: View {
    @EnvironmentObject var appSelection: AppSelection

    // Configuration
    var showLeague: Bool = true
    var showSeason: Bool = true
    var showTeam: Bool = true
    var seasonLabel: String = "Season"
    var teamLabel: String = "Team"
    var leagueLabel: String = "League"
    var maxMenuWidth: CGFloat = 180

    private var league: LeagueData? { appSelection.selectedLeague }

    private var seasonIds: [String] {
        guard let league else { return ["All Time"] }
        let ids = league.seasons.map { $0.id }.sorted(by: >)
        return ["All Time"] + ids
    }

    private var seasonTeams: [TeamStanding] {
        guard let league else { return [] }
        if appSelection.selectedSeason == "All Time" {
            return league.seasons.sorted { $0.id < $1.id }.last?.teams ?? league.teams
        }
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams
            ?? league.seasons.sorted { $0.id < $1.id }.last?.teams
            ?? league.teams
    }

    var body: some View {
        HStack(spacing: 12) {
            if showLeague {
                Menu {
                    ForEach(appSelection.leagues, id: \.id) { lg in
                        Button(lg.name) { selectLeague(lg.id) }
                    }
                } label: {
                    pill(appSelection.selectedLeague?.name ?? leagueLabel)
                }
                .frame(maxWidth: maxMenuWidth)
            }
            if showSeason {
                Menu {
                    ForEach(seasonIds, id: \.self) { sid in
                        Button(sid) { selectSeason(sid) }
                    }
                } label: {
                    pill(appSelection.selectedSeason.isEmpty ? seasonLabel : appSelection.selectedSeason)
                }
                .frame(maxWidth: maxMenuWidth)
            }
            if showTeam {
                Menu {
                    ForEach(seasonTeams, id: \.id) { tm in
                        Button(tm.name) { selectTeam(tm.id) }
                    }
                } label: {
                    pill(seasonTeams.first(where: { $0.id == appSelection.selectedTeamId })?.name
                         ?? teamLabel)
                }
                .frame(maxWidth: maxMenuWidth)
            }
        }
        .onChange(of: appSelection.selectedLeagueId) { _ in
            normalizeAfterLeagueChange()
        }
        .onChange(of: appSelection.selectedSeason) { _ in
            normalizeAfterSeasonChange()
        }
        .onAppear {
            normalizeAfterLeagueChange()
            normalizeAfterSeasonChange()
        }
    }

    // MARK: - Selection Mutators

    private func selectLeague(_ id: String) {
        guard appSelection.selectedLeagueId != id else { return }
        appSelection.selectedLeagueId = id
        // Reset season to latest or All Time
        if let lg = appSelection.selectedLeague {
            let latest = lg.seasons.sorted { $0.id < $1.id }.last?.id
            appSelection.selectedSeason = latest ?? "All Time"
            // Pick first team in latest season (or overall fallback)
            if let latestTeams = lg.seasons.sorted(by: { $0.id < $1.id }).last?.teams,
               let first = latestTeams.first {
                appSelection.selectedTeamId = first.id
            } else {
                appSelection.selectedTeamId = lg.teams.first?.id
            }
        } else {
            appSelection.selectedSeason = "All Time"
            appSelection.selectedTeamId = nil
        }
    }

    private func selectSeason(_ seasonId: String) {
        guard appSelection.selectedSeason != seasonId else { return }
        appSelection.selectedSeason = seasonId
        normalizeAfterSeasonChange()
    }

    private func selectTeam(_ teamId: String) {
        appSelection.selectedTeamId = teamId
    }

    // MARK: - Normalization

    private func normalizeAfterLeagueChange() {
        guard let lg = appSelection.selectedLeague else {
            appSelection.selectedSeason = "All Time"
            appSelection.selectedTeamId = nil
            return
        }
        // Ensure season valid
        if appSelection.selectedSeason != "All Time" &&
            !lg.seasons.contains(where: { $0.id == appSelection.selectedSeason }) {
            appSelection.selectedSeason = lg.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
        }
        normalizeAfterSeasonChange()
    }

    private func normalizeAfterSeasonChange() {
        guard let lg = appSelection.selectedLeague else { return }
        let teams = seasonTeams
        if teams.isEmpty {
            appSelection.selectedTeamId = nil
            return
        }
        if let current = appSelection.selectedTeamId,
           teams.contains(where: { $0.id == current }) {
            return
        }
        appSelection.selectedTeamId = teams.first?.id
    }

    // MARK: - UI Helpers

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.orange)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black)
                    .shadow(color: .blue.opacity(0.6), radius: 8, y: 2)
            )
            .accessibilityLabel(text)
    }
}
