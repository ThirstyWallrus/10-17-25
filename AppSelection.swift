//
//  AppSelection.swift
//  DynastyStatDrop
//
//  Centralized season selection logic for all views.
//  OwnerId aware All Time selection
//  Added:
//   - Persistence of last selected league per username
//   - Helper to load persisted selection
//   - OwnerId aware team selection (uses Sleeper userId if available)
//   - Centralized season/team selection logic.
//   - Always prefers current year season if present.
//   - Exposes helpers for views to use and sync selection state.
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

    /// Centralized season picking logic.
    /// - If current year present, pick that.
    /// - Otherwise, pick latest season in DB.
    /// - If none, fallback to "All Time".
    func pickDefaultSeason(league: LeagueData?) -> String {
        guard let league else { return "All Time" }
        let currentYear = String(Calendar.current.component(.year, from: Date()))
        if league.seasons.contains(where: { $0.id == currentYear }) {
            return currentYear
        }
        return league.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
    }

    /// Centralized team picking logic.
    /// - Tries to pick by Sleeper userId, username, or first team.
    func pickDefaultTeam(league: LeagueData?, seasonId: String, username: String?, sleeperUserId: String?) -> (teamId: String?, teamName: String?) {
        guard let league else { return (nil, nil) }
        let teams: [TeamStanding]
        if seasonId == "All Time" {
            teams = league.seasons.sorted { $0.id < $1.id }.last?.teams ?? []
        } else {
            teams = league.seasons.first(where: { $0.id == seasonId })?.teams ?? []
        }
        if let sleeperId = sleeperUserId,
           let foundTeam = teams.first(where: { $0.ownerId == sleeperId }) {
            return (foundTeam.id, foundTeam.name)
        } else if let username = username,
                  let foundTeam = teams.first(where: { $0.name == username }) {
            return (foundTeam.id, foundTeam.name)
        } else {
            let firstTeam = teams.first
            return (firstTeam?.id, firstTeam?.name)
        }
    }

    /// Updates leagues and (re)selects a league/team/season centrally.
    /// - Persists selectedLeagueId for the given username.
    /// - Owner-aware: Uses Sleeper userId if available to match team to current user.
    /// - Centralized: Always prefers current year season if present, else latest, else "All Time".
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

        // Centralized: Pick default season (prefers current year)
        selectedSeason = pickDefaultSeason(league: league)

        // Centralized: Pick default team
        let teamPick = pickDefaultTeam(league: league, seasonId: selectedSeason, username: username, sleeperUserId: sleeperUserId)
        selectedTeamId = teamPick.teamId
        self.userTeam = teamPick.teamName ?? ""

        if let user = username {
            persistLeagueSelection(for: user, leagueId: selectedLeagueId)
        }
    }

    /// When league or season changes, update season/team selection centrally.
    func syncSelectionAfterLeagueChange(username: String?, sleeperUserId: String?) {
        guard let league = selectedLeague else {
            selectedSeason = "All Time"
            selectedTeamId = nil
            return
        }
        selectedSeason = pickDefaultSeason(league: league)
        let teamPick = pickDefaultTeam(league: league, seasonId: selectedSeason, username: username, sleeperUserId: sleeperUserId)
        selectedTeamId = teamPick.teamId
        self.userTeam = teamPick.teamName ?? ""
    }

    /// When season changes, update team selection centrally.
    func syncSelectionAfterSeasonChange(username: String?, sleeperUserId: String?) {
        guard let league = selectedLeague else { return }
        let teamPick = pickDefaultTeam(league: league, seasonId: selectedSeason, username: username, sleeperUserId: sleeperUserId)
        selectedTeamId = teamPick.teamId
        self.userTeam = teamPick.teamName ?? ""
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
