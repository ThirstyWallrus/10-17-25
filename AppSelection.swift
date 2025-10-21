//
//  AppSelection.swift
//  DynastyStatDrop
//
//  OwnerId aware All Time selection
//  Added:
//   - Persistence of last selected league per username
//   - Helper to load persisted selection
//   - OwnerId aware team selection (uses Sleeper userId if available)
//

import SwiftUI

final class AppSelection: ObservableObject {
    @Published var userTeam: String = ""              // display name
    @Published var leagues: [LeagueData] = []
    @Published var selectedLeagueId: String? = nil
    @Published var selectedTeamId: String? = nil      // current season team id
    @Published var selectedSeason: String = ""        // season id or "All Time"

    // Helper to get last selected league key
    private func lastSelectedLeagueKey(for username: String) -> String {
        "dsd.lastSelectedLeague.\(username)"
    }

    var selectedLeague: LeagueData? {
        leagues.first { $0.id == selectedLeagueId }
    }

    var isAllTimeMode: Bool { selectedSeason == "All Time" }

    // In All Time mode we still reference the current season’s matching team (latest)
    var selectedOwnerId: String? {
        guard let league = selectedLeague else { return nil }
        let latest = league.seasons.sorted { $0.id < $1.id }.last
        return latest?.teams.first(where: { $0.id == selectedTeamId })?.ownerId
    }

    var selectedTeam: TeamStanding? {
        guard let league = selectedLeague else { return nil }
        if isAllTimeMode {
            let latest = league.seasons.sorted { $0.id < $1.id }.last
            return latest?.teams.first(where: { $0.id == selectedTeamId })
        } else {
            return league.seasons.first(where: { $0.id == selectedSeason })?
                .teams.first(where: { $0.id == selectedTeamId })
        }
    }

    /// Updates leagues and (re)selects a league/team.
    /// - Persists selectedLeagueId for the given username.
    /// - Owner-aware: Uses Sleeper userId if available to match team to current user.
    func updateLeagues(_ newLeagues: [LeagueData], username: String? = nil, sleeperUserId: String? = nil) {
        leagues = newLeagues

        guard !newLeagues.isEmpty else {
            selectedLeagueId = nil
            selectedTeamId = nil
            selectedSeason = ""
            return
        }

        // Attempt restore of persisted selection
        if let user = username,
           let restored = loadPersistedLeagueSelection(for: user),
           newLeagues.contains(where: { $0.id == restored }) {
            selectedLeagueId = restored
        } else {
            selectedLeagueId = newLeagues.first?.id
        }

        guard let league = selectedLeague else { return }
        let latestSeasonId = league.seasons.sorted { $0.id < $1.id }.last?.id
        selectedSeason = latestSeasonId ?? "All Time"

        // OwnerId-aware team selection logic
        if let sleeperId = sleeperUserId,
           let latestSeason = league.seasons.sorted(by: { $0.id < $1.id }).last,
           let foundTeam = latestSeason.teams.first(where: { $0.ownerId == sleeperId }) {
            selectedTeamId = foundTeam.id
            self.userTeam = foundTeam.name
        } else if let username = username,
                  let latestSeason = league.seasons.sorted(by: { $0.id < $1.id }).last,
                  let teamByName = latestSeason.teams.first(where: { $0.name == username }) {
            selectedTeamId = teamByName.id
            self.userTeam = teamByName.name
        } else {
            // Fallback: select first team in latest season
            let firstTeam = league.seasons.sorted(by: { $0.id < $1.id }).last?.teams.first
            selectedTeamId = firstTeam?.id
            self.userTeam = firstTeam?.name ?? ""
        }

        if let user = username {
            persistLeagueSelection(for: user, leagueId: selectedLeagueId)
        }
    }

    func persistLeagueSelection(for username: String, leagueId: String?) {
        let key = lastSelectedLeagueKey(for: username)
        if let leagueId {
            UserDefaults.standard.set(leagueId, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func loadPersistedLeagueSelection(for username: String) -> String? {
        let key = lastSelectedLeagueKey(for: username)
        return UserDefaults.standard.string(forKey: key)
    }
}
