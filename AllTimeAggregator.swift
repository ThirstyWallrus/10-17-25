//
//  AllTimeAggregator.swift
//  DynastyStatDrop
//
//  Aggregates multi-season stats per current franchise (ownerId).
//

import Foundation

@MainActor
struct AllTimeAggregator {
    static func buildAllTime(for league: LeagueData, playerCache: [String: RawSleeperPlayer]) -> LeagueData {
        var copy = league
        let currentIds = league.currentSeasonOwnerIds
        guard !currentIds.isEmpty else {
            copy.allTimeOwnerStats = [:]
            return copy
        }
        var result: [String: AggregatedOwnerStats] = [:]
        for ownerId in currentIds {
            // Gather all playoff matchups for this owner
            let allPlayoffMatchups = allPlayoffMatchupsForOwner(ownerId: ownerId, league: league)
            if let agg = aggregate(ownerId: ownerId, league: league, currentIds: currentIds, allPlayoffMatchups: allPlayoffMatchups, playerCache: playerCache) {
                result[ownerId] = agg
            }
        }
        copy.allTimeOwnerStats = result
        return copy
    }

    private static let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]

    private static let allStatPositions: [String] = ["QB", "RB", "WR", "TE", "K", "DL", "LB", "DB"]
    private static let offensivePositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
    private static let defensivePositions: Set<String> = ["DL", "LB", "DB"]

    /// Aggregate all-time **regular season** stats for this owner.
    /// Only regular season weeks (before playoffStartWeek) are included.
    private static func aggregate(ownerId: String, league: LeagueData, currentIds: [String], allPlayoffMatchups: [SleeperMatchup], playerCache: [String: RawSleeperPlayer]) -> AggregatedOwnerStats? {
        let seasons = league.seasons.sorted { $0.id < $1.id }
        var teamsPerSeason: [(String, TeamStanding, Int)] = [] // (seasonId, team, playoffStartWeek)
        for s in seasons {
            if let t = s.teams.first(where: { $0.ownerId == ownerId }) {
                teamsPerSeason.append((s.id, t, s.playoffStartWeek ?? 14))
            }
        }
        guard !teamsPerSeason.isEmpty else { return nil }

        let latestDisplayName = teamsPerSeason.last?.1.name ?? "Team"

        var totalPF = 0.0, totalMaxPF = 0.0
        var totalOffPF = 0.0, totalMaxOffPF = 0.0
        var totalDefPF = 0.0, totalMaxDefPF = 0.0
        var totalPSA = 0.0
        var championships = 0
        var wins = 0, losses = 0, ties = 0

        var posTotals: [String: Double] = [:]
        var posStarts: [String: Int] = [:]
        var distinctWeeks: Set<String> = []

        var totalWaiverMoves = 0
        var totalFAAB = 0.0
        var totalTrades = 0

        var actualPosCounts: [String: Int] = [:]
        var actualWeeks = 0

        // NEW: Head-to-head vs other current owners
        var headToHead: [String: H2HStats] = [:]
        let currentIdsSet = Set(currentIds)

        for (seasonId, team, playoffStart) in teamsPerSeason {
            let season = seasons.first { $0.id == seasonId }!

            // Head-to-head aggregation for this season vs other current owners
            for oppTeam in season.teams where oppTeam.ownerId != ownerId && currentIdsSet.contains(oppTeam.ownerId) {
                guard let uRid = Int(team.id), let oRid = Int(oppTeam.id) else { continue }
                // FIX: SleeperMatchup does not have roster_ids or week
                // So we cannot filter by $0.roster_ids.contains(uRid) etc or $0.week < playoffStart
                // Instead, we must filter by rosterId and matchupId
                let h2hMatchups = (season.matchups ?? []).filter { m in
                    m.rosterId == uRid || m.rosterId == oRid
                }
                for m in h2hMatchups {
                    // There is only one rosterId per SleeperMatchup (not an array)
                    // To get both sides, we need to get the other entry for the same matchupId
                    let allEntries = season.matchups?.filter { $0.matchupId == m.matchupId } ?? []
                    guard allEntries.count == 2 else { continue }
                    guard let uEntry = allEntries.first(where: { $0.rosterId == uRid }),
                          let oEntry = allEntries.first(where: { $0.rosterId == oRid }) else { continue }
                    let uPts = uEntry.points
                    let oPts = oEntry.points
                    if uPts == 0 && oPts == 0 { continue } // Skip unplayed matchups

                    // UPDATED: Use historical entries for max (instead of team.roster)
                    let weekMatchups = season.matchupsByWeek?[m.matchupId] ?? []
                    guard let uEntry2 = weekMatchups.first(where: { $0.roster_id == uRid }),
                          let oEntry2 = weekMatchups.first(where: { $0.roster_id == oRid }) else { continue }

                    let uMax = computeMaxForEntry(entry: uEntry2, lineupConfig: team.lineupConfig ?? [:], playerCache: playerCache).total
                    let oMax = computeMaxForEntry(entry: oEntry2, lineupConfig: team.lineupConfig ?? [:], playerCache: playerCache).total  // Assume same lineup config

                    let uMgmt = uMax > 0 ? (uPts / uMax) * 100 : 0.0
                    let oMgmt = oMax > 0 ? (oPts / oMax) * 100 : 0.0

                    var curr = headToHead[oppTeam.ownerId] ?? H2HStats(wins: 0, losses: 0, ties: 0, pointsFor: 0, pointsAgainst: 0, games: 0, sumMgmtFor: 0.0, sumMgmtAgainst: 0.0)
                    curr = H2HStats(
                        wins: curr.wins,
                        losses: curr.losses,
                        ties: curr.ties,
                        pointsFor: curr.pointsFor + uPts,
                        pointsAgainst: curr.pointsAgainst + oPts,
                        games: curr.games + 1,
                        sumMgmtFor: curr.sumMgmtFor + uMgmt,
                        sumMgmtAgainst: curr.sumMgmtAgainst + oMgmt
                    )
                    if uPts > oPts {
                        curr = H2HStats(wins: curr.wins + 1, losses: curr.losses, ties: curr.ties, pointsFor: curr.pointsFor, pointsAgainst: curr.pointsAgainst, games: curr.games, sumMgmtFor: curr.sumMgmtFor, sumMgmtAgainst: curr.sumMgmtAgainst)
                    } else if uPts < oPts {
                        curr = H2HStats(wins: curr.wins, losses: curr.losses + 1, ties: curr.ties, pointsFor: curr.pointsFor, pointsAgainst: curr.pointsAgainst, games: curr.games, sumMgmtFor: curr.sumMgmtFor, sumMgmtAgainst: curr.sumMgmtAgainst)
                    } else {
                        curr = H2HStats(wins: curr.wins, losses: curr.losses, ties: curr.ties + 1, pointsFor: curr.pointsFor, pointsAgainst: curr.pointsAgainst, games: curr.games, sumMgmtFor: curr.sumMgmtFor, sumMgmtAgainst: curr.sumMgmtAgainst)
                    }
                    headToHead[oppTeam.ownerId] = curr
                }
            }

            // UPDATED: Recompute from raw matchupsByWeek (historical data)
            championships += team.championships ?? 0

            totalWaiverMoves += team.waiverMoves ?? 0
            totalFAAB += team.faabSpent ?? 0
            totalTrades += team.tradesCompleted ?? 0

            if let counts = team.actualStarterPositionCounts, let weeks = team.actualStarterWeeks {
                for (pos, count) in counts {
                    actualPosCounts[pos, default: 0] += count
                }
                actualWeeks += weeks
            }

            // ---------- UPDATED SECTION: Recompute from historical matchupsByWeek ----------
            let matchupsByWeek = season.matchupsByWeek ?? [:]
            let rosterId = Int(team.id) ?? -1
            for (week, entries) in matchupsByWeek.sorted(by: { $0.key < $1.key }) {
                guard week < playoffStart else { continue }  // Regular season only
                guard let entry = entries.first(where: { $0.roster_id == rosterId }) else { continue }

                distinctWeeks.insert("\(seasonId)-\(week)")

                // PF, Off PF, Def PF from starters' points (using players_points and positions from cache)
                let starters = entry.starters ?? []
                var weekPF = 0.0
                var weekOffPF = 0.0
                var weekDefPF = 0.0
                for starterId in starters {
                    guard let point = entry.players_points?[starterId],
                          let rawPlayer = playerCache[starterId],
                          let pos = rawPlayer.position else { continue }
                    weekPF += point
                    if offensivePositions.contains(pos) {
                        weekOffPF += point
                    } else if defensivePositions.contains(pos) {
                        weekDefPF += point
                    }
                    posTotals[pos, default: 0.0] += point
                    posStarts[pos, default: 0] += 1
                }
                totalPF += weekPF
                totalOffPF += weekOffPF
                totalDefPF += weekDefPF

                // Max PF, Max Off, Max Def from optimal lineup (using historical roster that week)
                let maxes = computeMaxForEntry(entry: entry, lineupConfig: team.lineupConfig ?? [:], playerCache: playerCache)
                let players = entry.players ?? []
                let playersPoints = entry.players_points ?? [:]

                // Build candidates from players in entry.players (i.e., historical roster for that week)
                let candidates: [(id: String, basePos: String, fantasy: [String], points: Double)] = players.compactMap { id in
                    guard let points = playersPoints[id],
                          let raw = playerCache[id],
                          let basePos = raw.position else { return nil }
                    let fantasy = raw.fantasy_positions ?? [basePos]
                    return (id: id, basePos: basePos, fantasy: fantasy, points: points)
                }
                
                totalMaxPF += maxes.total
                totalMaxOffPF += maxes.off
                totalMaxDefPF += maxes.def

                // PSA, Win/Loss/Tie from opponent
                if let matchupId = entry.matchup_id,
                   let oppEntry = entries.first(where: { $0.matchup_id == matchupId && $0.roster_id != rosterId }),
                   let oppPoints = oppEntry.points {
                    totalPSA += oppPoints
                    let myPoints = entry.points ?? 0.0
                    if myPoints > oppPoints { wins += 1 }
                    else if myPoints < oppPoints { losses += 1 }
                    else { ties += 1 }
                }
            }
            // ---------- END UPDATED SECTION ----------

        }

        let weeksPlayed = distinctWeeks.count

        // Derived
        let mgmtPct = totalMaxPF > 0 ? totalPF / totalMaxPF * 100 : 0
        let offMgmt = totalMaxOffPF > 0 ? totalOffPF / totalMaxOffPF * 100 : 0
        let defMgmt = totalMaxDefPF > 0 ? totalDefPF / totalMaxDefPF * 100 : 0

        let ppw = weeksPlayed > 0 ? totalPF / Double(weeksPlayed) : 0
        let offPPW = weeksPlayed > 0 ? totalOffPF / Double(weeksPlayed) : 0
        let defPPW = weeksPlayed > 0 ? totalDefPF / Double(weeksPlayed) : 0

        var posAvgPPW: [String: Double] = [:]
        var indPosPPW: [String: Double] = [:]
        for pos in allStatPositions {
            let total = posTotals[pos] ?? 0
            let starts = posStarts[pos] ?? 0
            posAvgPPW[pos] = weeksPlayed > 0 ? total / Double(weeksPlayed) : 0
            indPosPPW[pos] = starts > 0 ? total / Double(starts) : 0
        }

        let playoffStats = aggregatePlayoffStats(ownerId: ownerId, allPlayoffMatchups: allPlayoffMatchups, league: league, playerCache: playerCache)

        return AggregatedOwnerStats(
            ownerId: ownerId,
            latestDisplayName: latestDisplayName,
            seasonsIncluded: teamsPerSeason.map { $0.0 },
            weeksPlayed: weeksPlayed,
            totalPointsFor: totalPF,
            totalMaxPointsFor: totalMaxPF,
            totalOffensivePointsFor: totalOffPF,
            totalMaxOffensivePointsFor: totalMaxOffPF,
            totalDefensivePointsFor: totalDefPF,
            totalMaxDefensivePointsFor: totalMaxDefPF,
            totalPointsScoredAgainst: totalPSA,
            managementPercent: mgmtPct,
            offensiveManagementPercent: offMgmt,
            defensiveManagementPercent: defMgmt,
            teamPPW: ppw,
            offensivePPW: offPPW,
            defensivePPW: defPPW,
            positionTotals: posTotals,
            positionStartCounts: posStarts,
            positionAvgPPW: posAvgPPW,
            individualPositionPPW: indPosPPW,
            championships: championships,
            totalWins: wins,
            totalLosses: losses,
            totalTies: ties,
            totalWaiverMoves: totalWaiverMoves,
            totalFAABSpent: totalFAAB,
            totalTradesCompleted: totalTrades,
            actualStarterPositionCountsTotals: actualPosCounts,
            actualStarterWeeks: actualWeeks,
            headToHeadVs: headToHead,
            playoffStats: playoffStats
        )
    }

    // ... rest of your file unchanged ...
    private static func maxPointsForWeek(team: TeamStanding, week: Int) -> (total: Double, off: Double, def: Double) {
        let playerScores = team.roster.reduce(into: [String: Double]()) { dict, player in
            if let score = player.weeklyScores.first(where: { $0.week == week })?.points {
                dict[player.id] = score
            }
        }

        // Compute max: optimal lineup
        let startingSlots = team.league?.startingLineup ?? []
        let fixedCounts = fixedSlotCounts(startingSlots: startingSlots)

        // Offensive
        var offPlayerList = team.roster.filter { offensivePositions.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxOff = 0.0
        for pos in Array(offensivePositions) {
            if let count = fixedCounts[pos] {
                let candidates = offPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                let top = Array(candidates.prefix(count))
                maxOff += top.reduce(0.0) { $0 + $1.score }
                // Remove used players
                offPlayerList.removeAll { used in top.contains { $0.id == used.id } }
            }
        }

        // Allocate flex slots
        let flexAllowed: Set<String> = ["RB", "WR", "TE"]
        let flexCount = startingSlots.filter { offensiveFlexSlots.contains($0) }.count
        let flexCandidates = offPlayerList.filter { flexAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        let topFlex = Array(flexCandidates.prefix(flexCount))
        maxOff += topFlex.reduce(0.0) { $0 + $1.score }

        // Defensive
        var defPlayerList = team.roster.filter { defensivePositions.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxDef = 0.0
        for pos in Array(defensivePositions) {
            if let count = fixedCounts[pos] {
                let candidates = defPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                let top = Array(candidates.prefix(count))
                maxDef += top.reduce(0.0) { $0 + $1.score }
                // Remove used players
                defPlayerList.removeAll { used in top.contains { $0.id == used.id } }
            }
        }

        let maxTotal = maxOff + maxDef
        return (maxTotal, maxOff, maxDef)
    }

    // NEW: Compute max PF for a single historical matchup entry (using players on roster that week)
    private static func computeMaxForEntry(entry: MatchupEntry, lineupConfig: [String: Int], playerCache: [String: RawSleeperPlayer]) -> (total: Double, off: Double, def: Double) {
        let players = entry.players ?? []
        let playersPoints = entry.players_points ?? [:]

        // Build candidates
        let candidates: [(id: String, basePos: String, fantasy: [String], points: Double)] = players.compactMap { id in
            guard let points = playersPoints[id],
                  let raw = playerCache[id],
                  let basePos = raw.position else { return nil }
            let fantasy = raw.fantasy_positions ?? [basePos]
            return (id: id, basePos: basePos, fantasy: fantasy, points: points)
        }

        // Expand slots from lineupConfig
        var expandedSlots: [String] = []
        for (slot, count) in lineupConfig {
            expandedSlots.append(contentsOf: Array(repeating: slot, count: count))
        }

        var usedIDs = Set<String>()
        var maxTotal = 0.0
        var maxOff = 0.0
        var maxDef = 0.0

        for slot in expandedSlots {
            let allowed = allowedPositions(for: slot)
            let pick = candidates
                .filter { !usedIDs.contains($0.id) && isEligible(c: $0, allowed: allowed) }
                .max { $0.points < $1.points }
            guard let cand = pick else { continue }
            usedIDs.insert(cand.id)
            maxTotal += cand.points
            if offensivePositions.contains(cand.basePos) { maxOff += cand.points }
            else if defensivePositions.contains(cand.basePos) { maxDef += cand.points }
        }

        return (maxTotal, maxOff, maxDef)
    }

    private static func allowedPositions(for slot: String) -> Set<String> {
        switch slot.uppercased() {
        case "QB","RB","WR","TE","K","DL","LB","DB": return [slot.uppercased()]
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return ["RB","WR","TE"]
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return ["QB","RB","WR","TE"]
        case "IDP": return ["DL","LB","DB"]
        default:
            if slot.uppercased().contains("IDP") { return ["DL","LB","DB"] }
            return [slot.uppercased()]
        }
    }

    private static func isEligible(c: (id: String, basePos: String, fantasy: [String], points: Double), allowed: Set<String>) -> Bool {
        if allowed.contains(c.basePos) { return true }
        return !allowed.intersection(Set(c.fantasy)).isEmpty
    }

    private static func fixedSlotCounts(startingSlots: [String]) -> [String: Int] {
        startingSlots.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func actualPointsForWeek(team: TeamStanding, week: Int, positions: Set<String>) -> Double {
        guard let starters = team.actualStartersByWeek?[week] else { return 0.0 }
        var total = 0.0
        for id in starters {
            if let player = team.roster.first(where: { $0.id == id }),
               positions.contains(player.position),
               let score = player.weeklyScores.first(where: { $0.week == week })?.points {
                total += score
            }
        }
        return total
    }

    // MARK: Sum Functions

    private static func sumMaxPointsForWeeks(team: TeamStanding, weeks: Set<Int>) -> Double {
        weeks.reduce(0.0) { $0 + maxPointsForWeek(team: team, week: $1).total }
    }

    private static func sumMaxOffensivePointsForWeeks(team: TeamStanding, weeks: Set<Int>) -> Double {
        weeks.reduce(0.0) { $0 + maxPointsForWeek(team: team, week: $1).off }
    }

    private static func sumMaxDefensivePointsForWeeks(team: TeamStanding, weeks: Set<Int>) -> Double {
        weeks.reduce(0.0) { $0 + maxPointsForWeek(team: team, week: $1).def }
    }

    private static func sumActualOffensivePointsForWeeks(team: TeamStanding, weeks: Set<Int>) -> Double {
        weeks.reduce(0.0) { $0 + actualPointsForWeek(team: team, week: $1, positions: offensivePositions) }
    }

    private static func sumActualDefensivePointsForWeeks(team: TeamStanding, weeks: Set<Int>) -> Double {
        weeks.reduce(0.0) { $0 + actualPointsForWeek(team: team, week: $1, positions: defensivePositions) }
    }

    private static func sumPointsAgainstForWeeks(team: TeamStanding, weeks: Set<Int>) -> Double {
        // If per-week points against is available, sum it; otherwise fallback to total (but adjust for weeks)
        // For playoffs, accumulate per matchup as done in aggregatePlayoffStats.
        return 0.0 // Implement if needed for regular season PSA per weeks
    }

    // MARK: Playoff Stats Aggregation

    private static func aggregatePlayoffStats(ownerId: String, allPlayoffMatchups: [SleeperMatchup], league: LeagueData, playerCache: [String: RawSleeperPlayer]) -> PlayoffStats {
        var totalPF = 0.0, totalMaxPF = 0.0
        var totalOffPF = 0.0, totalMaxOffPF = 0.0
        var totalDefPF = 0.0, totalMaxDefPF = 0.0
        var wins = 0, losses = 0, ties = 0
        var weeksPlayed = 0

        for matchup in allPlayoffMatchups {
            guard let season = league.seasons.first(where: { $0.matchups?.contains(where: { $0.matchupId == matchup.matchupId }) ?? false }),
                  let ownerTeam = season.teams.first(where: { $0.ownerId == ownerId }),
                  let myRosterId = Int(ownerTeam.id),
                  let weekEntries = season.matchupsByWeek?[matchup.matchupId],
                  let myEntry = weekEntries.first(where: { $0.roster_id == myRosterId }),
                  let myPoints = myEntry.points else { continue }

            // PF, Off PF, Def PF from historical starters
            let starters = myEntry.starters ?? []
            var weekPF = 0.0
            var weekOffPF = 0.0
            var weekDefPF = 0.0
            for starterId in starters {
                guard let point = myEntry.players_points?[starterId],
                      let rawPlayer = playerCache[starterId],
                      let pos = rawPlayer.position else { continue }
                weekPF += point
                if offensivePositions.contains(pos) {
                    weekOffPF += point
                } else if defensivePositions.contains(pos) {
                    weekDefPF += point
                }
            }
            totalPF += weekPF
            totalOffPF += weekOffPF
            totalDefPF += weekDefPF

            // Max PF from historical roster that week
            let maxes = computeMaxForEntry(entry: myEntry, lineupConfig: ownerTeam.lineupConfig ?? [:], playerCache: playerCache)
            totalMaxPF += maxes.total
            totalMaxOffPF += maxes.off
            totalMaxDefPF += maxes.def

            // Opponent points for win/loss
            if let matchupId = myEntry.matchup_id,
               let oppEntry = weekEntries.first(where: { $0.matchup_id == matchupId && $0.roster_id != myRosterId }),
               let oppPoints = oppEntry.points {
                if myPoints > oppPoints { wins += 1 }
                else if myPoints < oppPoints { losses += 1 }
                else { ties += 1 }
            }

            weeksPlayed += 1
        }

        let mgmtPct = totalMaxPF > 0 ? (totalPF / totalMaxPF) * 100 : 0
        let offMgmt = totalMaxOffPF > 0 ? (totalOffPF / totalMaxOffPF) * 100 : 0
        let defMgmt = totalMaxDefPF > 0 ? (totalDefPF / totalMaxDefPF) * 100 : 0

        let ppw = weeksPlayed > 0 ? totalPF / Double(weeksPlayed) : 0
        let offPPW = weeksPlayed > 0 ? totalOffPF / Double(weeksPlayed) : 0
        let defPPW = weeksPlayed > 0 ? totalDefPF / Double(weeksPlayed) : 0

        let isChampion = (weeksPlayed > 0 && losses == 0)  // Simple logic: Undefeated in playoffs = champion (adjust if needed for byes/multi-round)

        return PlayoffStats(
            pointsFor: totalPF,
            maxPointsFor: totalMaxPF,
            ppw: ppw,
            managementPercent: mgmtPct,
            offensivePointsFor: totalOffPF,
            maxOffensivePointsFor: totalMaxOffPF,
            offensivePPW: offPPW,
            offensiveManagementPercent: offMgmt,
            defensivePointsFor: totalDefPF,
            maxDefensivePointsFor: totalMaxDefPF,
            defensivePPW: defPPW,
            defensiveManagementPercent: defMgmt,
            weeks: weeksPlayed,
            wins: wins,
            losses: losses,
            recordString: "\(wins)-\(losses)\(ties > 0 ? "-\(ties)" : "")",
            isChampion: isChampion
        )
    }
}

/// Helper: Gathers all playoff bracket matchups for this owner over all seasons in the league.
/// Must only return playoff bracket games (not consolation), and only for seasons where owner made playoffs.
func allPlayoffMatchupsForOwner(ownerId: String, league: LeagueData) -> [SleeperMatchup] {
    var all: [SleeperMatchup] = []
    for season in league.seasons {
        // Get playoff team count from league/season settings (e.g. from Sleeper API)
        let playoffTeamsCount = season.playoffTeamsCount ?? 4 // Or fetch from settings
        let playoffSeededTeams = season.teams.sorted { $0.leagueStanding < $1.leagueStanding }
            .prefix(playoffTeamsCount)
        guard playoffSeededTeams.contains(where: { $0.ownerId == ownerId }) else { continue }

        // Find bracket weeks: typically first N weeks after playoffStartWeek
        let playoffStart = season.playoffStartWeek ?? 14
        let bracketWeeks: Set<Int> = Set(playoffStart..<(playoffStart + Int(ceil(log2(Double(playoffTeamsCount))))))
        
        // Get season matchups
        let seasonMatchups: [SleeperMatchup] = season.matchups ?? []
        let ownerTeam = season.teams.first(where: { $0.ownerId == ownerId })
        let ownerRosterId = ownerTeam.flatMap { Int($0.id) } ?? -1
        // Use rosterId and matchupId to filter
        let ownerMatchups = seasonMatchups.filter { m in
            bracketWeeks.contains(m.matchupId) && m.rosterId == ownerRosterId
        }
        // Only include up to first playoff loss—for this owner
        var eliminated = false
        for matchup in ownerMatchups.sorted(by: { $0.matchupId < $1.matchupId }) {
            if eliminated { break }
            all.append(matchup)
            // Determine if owner lost this matchup
            if didOwnerLoseMatchup(ownerId: ownerId, matchup: matchup, season: season) {
                eliminated = true
            }
        }
    }
    return all
}

// --- Implement these helpers for your data model ---

func isOwnerRoster(ownerId: String, rosterId: Int, season: SeasonData) -> Bool {
    // Map a Sleeper rosterId to your ownerId for this season.
    return season.teams.first(where: { $0.ownerId == ownerId })?.id == String(rosterId)
}
func didOwnerLoseMatchup(ownerId: String, matchup: SleeperMatchup, season: SeasonData) -> Bool {
    guard let ownerTeam = season.teams.first(where: { $0.ownerId == ownerId }) else { return false }
    let myRosterId = Int(ownerTeam.id) ?? -1
    // Find both entries for this matchup
    let allEntries = season.matchups?.filter { $0.matchupId == matchup.matchupId } ?? []
    guard allEntries.count == 2 else { return false }
    guard let myEntry = allEntries.first(where: { $0.rosterId == myRosterId }),
          let oppEntry = allEntries.first(where: { $0.rosterId != myRosterId }) else { return false }
    let myPoints = myEntry.points
    let oppPoints = oppEntry.points
    return myPoints < oppPoints
}

extension Collection {
    subscript(safe at: Index) -> Element? {
        indices.contains(at) ? self[at] : nil
    }
}
