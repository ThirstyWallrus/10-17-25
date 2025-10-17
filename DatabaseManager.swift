//
//  DatabaseManager.swift
//  DynastyStatDrop
//
//  (No structural changes; relies on canonical models from LeagueData.swift)
//

import Foundation

class DatabaseManager {
    @MainActor static let shared = DatabaseManager()
    private var leagues: [String: LeagueData] = [:]

    func saveLeague(_ league: LeagueData) {
        leagues[league.id] = league
    }

    func getLeague(leagueId: String) -> LeagueData? {
        leagues[leagueId]
    }

    func getTeamsForLeague(leagueId: String, season: String) -> [TeamStanding] {
        guard let league = leagues[leagueId] else { return [] }
        return league.seasons.first(where: { $0.id == season })?.teams ?? []
    }

    func getRosterForTeam(leagueId: String, season: String, teamName: String) -> [String] {
        guard
            let league = leagues[leagueId],
            let seasonData = league.seasons.first(where: { $0.id == season }),
            let team = seasonData.teams.first(where: { $0.name == teamName })
        else { return [] }
        return team.roster.map { $0.position }
    }

    func getWeeklyStatsByPosition(leagueId: String, week: Int) -> [String: [PlayerWeeklyScore]] {
        guard let league = leagues[leagueId] else { return [:] }
        var positionScores: [String: [PlayerWeeklyScore]] = [:]
        for season in league.seasons {
            for team in season.teams {
                for player in team.roster {
                    if let score = player.weeklyScores.first(where: { $0.week == week }) {
                        positionScores[player.position, default: []].append(score)
                    }
                }
            }
        }
        return positionScores
    }

    func getWeeklyStatsForPosition(leagueId: String, week: Int, position: String) -> [PlayerWeeklyScore] {
        getWeeklyStatsByPosition(leagueId: leagueId, week: week)[position] ?? []
    }
}

// FIXED: matchups array element is SleeperMatchup, with fields: rosterId, matchupId, starters, players, points, customPoints
// There is NO 'roster_ids' (should be rosterId), NO 'week' (should use matchupId as week proxy if needed), NO 'matchup_id' (should be matchupId).
// Use the correct property names as defined in the SleeperMatchup struct.

func buildWeekRosterMatchupMap(matchups: [SleeperMatchup]) -> [Int: [Int: Int]] {
    var map: [Int: [Int: Int]] = [:]
    for matchup in matchups {
        // Since SleeperMatchup has only 'rosterId', not 'roster_ids', treat each matchup as representing one team in one matchup/week.
        // We use 'matchupId' as the week proxy (if that's how your app is using it).
        // If you expect a list of matchups for each week, you should group by matchupId.

        // If you ever add a 'week' property to SleeperMatchup, update this accordingly.
        map[matchup.matchupId, default: [:]][matchup.rosterId] = matchup.matchupId
    }
    return map
}
