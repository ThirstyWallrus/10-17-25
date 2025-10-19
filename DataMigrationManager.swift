//
//  DataMigrationManager.swift
//  DynastyStatDrop
//
//  Purpose:
//   Migrates previously persisted LeagueData / TeamStanding models to
//   the latest schema & calculation rules (dual‑designation flex logic,
//   offensive/defensive max & management %, extended starter metrics).
//
//  Version History:
//   1 -> 2 : Initial offensive / defensive split introduction (legacy).
//   2 -> 3 : Weekly actual lineup volatility capture (weeklyActualLineupPoints).
//   3 -> 4 : Extended fields (actualStarterPositionCounts, actualStarterWeeks,
//            waiverMoves, faabSpent, tradesCompleted) + unified dual-flex logic.
//            (This migration is idempotent; safe to run once per data set.)
//

import Foundation

@MainActor
final class DataMigrationManager: ObservableObject {

    private let dataVersionKey = "dsd.data.version"
    private let currentDataVersion = 5   // UPDATED to 4 for extended starter / transaction metrics

    private let offensivePositions: Set<String> = ["QB","RB","WR","TE","K"]
    private let defensivePositions: Set<String> = ["DL","LB","DB"]
    private let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]

    private func isOffensiveSlot(_ slot: String) -> Bool {
        let u = slot.uppercased()
        let defSlots: Set<String> = ["DL", "LB", "DB", "IDP", "DEF"]
        return !defSlots.contains(u)
    }

    func runMigrationIfNeeded(leagueManager: SleeperLeagueManager) {
        let stored = UserDefaults.standard.integer(forKey: dataVersionKey)
        
        // WIPE old cache/data if version increased
        if stored < currentDataVersion {
            wipeOldCacheAndData()
        }
        guard stored < currentDataVersion else { return }

        var migratedLeagues: [LeagueData] = []
        for league in leagueManager.leagues {
            // PATCH: build a playerCache for canonical lookup
            var playerCache: [String: RawSleeperPlayer] = leagueManager.allPlayers
            // Defensive: If empty, try to rebuild from all seasons
            if playerCache.isEmpty {
                for s in league.seasons {
                    for t in s.teams {
                        for p in t.roster {
                            playerCache[p.id] = RawSleeperPlayer(player_id: p.id, full_name: nil, position: p.position, fantasy_positions: p.altPositions)
                        }
                    }
                }
            }

            var newSeasons: [SeasonData] = []
            for season in league.seasons {
                let migratedTeams = season.teams.map { migrateTeam($0, season: season, playerCache: playerCache) }
                newSeasons.append(SeasonData(id: season.id, season: season.season, teams: migratedTeams, playoffStartWeek: season.playoffStartWeek, playoffTeamsCount: season.playoffTeamsCount, matchups: season.matchups, matchupsByWeek: season.matchupsByWeek))
            }
            let latestTeams = newSeasons.last?.teams ?? league.teams
            migratedLeagues.append(
                LeagueData(id: league.id,
                           name: league.name,
                           season: league.season,
                           teams: latestTeams,
                           seasons: newSeasons,
                           startingLineup: league.startingLineup)
            )
        }

        leagueManager.leagues = migratedLeagues
        leagueManager.saveLeagues()
        UserDefaults.standard.set(currentDataVersion, forKey: dataVersionKey)
        print("[Migration] Completed data migration to version \(currentDataVersion)")
    }
    
    private func wipeOldCacheAndData() {
        let defaults = UserDefaults.standard
        let legacyKeys = [
            "dsd.league.cache",
            "dsd.old.standings",
            "dsd.allTimeCache",
        ]
        for key in legacyKeys { defaults.removeObject(forKey: key) }

        // Remove possible files in Documents (customize as needed)
        let fm = FileManager.default
        if let docDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let files = try fm.contentsOfDirectory(at: docDir, includingPropertiesForKeys: nil)
                for url in files {
                    if url.lastPathComponent.hasPrefix("league_") || url.lastPathComponent.hasSuffix(".cache") {
                        try fm.removeItem(at: url)
                    }
                }
            } catch {
                print("Error wiping old caches: \(error)")
            }
        }
        print("[Migration] Old caches and data wiped")
    }
    
    // MARK: Team Migration

    // PATCH: Accept playerCache for weekly starter lookup
    private func migrateTeam(_ old: TeamStanding, season: SeasonData?, playerCache: [String: RawSleeperPlayer]) -> TeamStanding {
        // If already has fully populated offensive / defensive max + mgmt% and extended fields, skip
        if let offMax = old.maxOffensivePointsFor,
           let defMax = old.maxDefensivePointsFor,
           offMax > 0, defMax > 0,
           (old.offensiveManagementPercent ?? 0) > 0,
           (old.defensiveManagementPercent ?? 0) > 0 {

            // Extended fields may be absent in pre-v4; ensure presence (defaults).
            return TeamStanding(
                id: old.id,
                name: old.name,
                positionStats: old.positionStats,
                ownerId: old.ownerId,
                roster: old.roster,
                leagueStanding: old.leagueStanding,
                pointsFor: old.pointsFor,
                maxPointsFor: old.maxPointsFor,
                managementPercent: old.managementPercent,
                teamPointsPerWeek: old.teamPointsPerWeek,
                winLossRecord: old.winLossRecord,
                bestGameDescription: old.bestGameDescription,
                biggestRival: old.biggestRival,
                strengths: old.strengths,
                weaknesses: old.weaknesses,
                playoffRecord: old.playoffRecord,
                championships: old.championships,
                winStreak: old.winStreak,
                lossStreak: old.lossStreak,
                offensivePointsFor: old.offensivePointsFor,
                maxOffensivePointsFor: old.maxOffensivePointsFor,
                offensiveManagementPercent: old.offensiveManagementPercent,
                averageOffensivePPW: old.averageOffensivePPW,
                offensiveStrengths: old.offensiveStrengths,
                offensiveWeaknesses: old.offensiveWeaknesses,
                positionAverages: old.positionAverages,
                individualPositionAverages: old.individualPositionAverages,
                defensivePointsFor: old.defensivePointsFor,
                maxDefensivePointsFor: old.maxDefensivePointsFor,
                defensiveManagementPercent: old.defensiveManagementPercent,
                averageDefensivePPW: old.averageDefensivePPW,
                defensiveStrengths: old.defensiveStrengths,
                defensiveWeaknesses: old.defensiveWeaknesses,
                pointsScoredAgainst: old.pointsScoredAgainst,
                league: old.league,
                lineupConfig: old.lineupConfig ?? inferredLineupConfig(from: old.roster),
                weeklyActualLineupPoints: old.weeklyActualLineupPoints ?? [:],
                actualStartersByWeek: old.actualStartersByWeek ?? [:],
                actualStarterPositionCounts: old.actualStarterPositionCounts ?? [:],
                actualStarterWeeks: old.actualStarterWeeks ?? 0,
                waiverMoves: old.waiverMoves ?? 0,
                faabSpent: old.faabSpent ?? 0,
                tradesCompleted: old.tradesCompleted ?? 0
            )
        }

        guard let season = season else {
            return old
        }

        let myRosterId = Int(old.id) ?? -1
        let playoffStart = season.playoffStartWeek ?? 14
        let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
        let regWeeks = allWeeks.filter { $0 < playoffStart }

        var actualTotal = 0.0
        var maxTotal = 0.0
        var maxOff = 0.0
        var maxDef = 0.0
        var totalOffPF = 0.0
        var totalDefPF = 0.0
        var posPPW: [String: Double] = [:]
        var indivPPW: [String: Double] = [:]
        var posCounts: [String: Int] = [:]
        var indivCounts: [String: Int] = [:]

        var tempStarters: [Int: [String]] = [:]
        var tempCounts: [String: Int] = [:]
        var tempWeeks = 0

        let lineupConfig = old.lineupConfig ?? inferredLineupConfig(from: old.roster)
        let slots = expandSlots(lineupConfig: lineupConfig)
        
        // PATCH: Use the weekly player pool and playerCache for all lookups
        //         Instead of only old.roster

        var actualStartersByWeek: [Int: [String]] = [:]
        var actualStarterPositionCounts: [String: Int] = [:]
        var actualStarterWeeks: Int = 0
        var weeklyActualLineupPoints: [Int: Double] = [:]

        for week in regWeeks {
            let weekEntries = season.matchupsByWeek?[week] ?? []
            guard let myEntry = weekEntries.first(where: { $0.roster_id == myRosterId }) else { continue }

            let myPoints = myEntry.points ?? 0.0
            actualTotal += myPoints
            weeklyActualLineupPoints[week] = myPoints

            // PATCH: Use only the weekly player pool, not just old.roster
            var startersForThisWeek: [String] = []
            var weekOff = 0.0
            var weekDef = 0.0

            // Use starter IDs and build Player from playerCache if not in roster
            if let starters = myEntry.starters, let playersPoints = myEntry.players_points {
                startersForThisWeek = starters
                for (idx, pid) in starters.enumerated() {
                    // Find position for this starter
                    let player: RawSleeperPlayer? = {
                        // Prefer current roster if available
                        if let p = old.roster.first(where: { $0.id == pid }) {
                            return RawSleeperPlayer(
                                player_id: p.id,
                                full_name: nil,
                                position: p.position,
                                fantasy_positions: p.altPositions
                            )
                        }
                        // Fallback to player cache
                        return playerCache[pid]
                    }()
                    let pos = player?.position?.uppercased() ?? "UNK"
                    let pts = playersPoints[pid] ?? 0.0
                    if offensivePositions.contains(pos) {
                        weekOff += pts
                    } else if defensivePositions.contains(pos) {
                        weekDef += pts
                    }
                    // Position stats
                    posPPW[pos, default: 0.0] += pts
                    indivPPW[pos, default: 0.0] += pts
                    posCounts[pos, default: 0] += 1
                    indivCounts[pos, default: 0] += 1
                }
            }
            totalOffPF += weekOff
            totalDefPF += weekDef

            // --- OPTIMAL LINEUP: Use player pool for this week ---
            let candidates: [MigCandidate] = {
                // Build candidates from all players in this week's player pool
                let pool = myEntry.players ?? []
                let playersPoints = myEntry.players_points ?? [:]
                return pool.compactMap { pid in
                    let raw = playerCache[pid]
                    let basePos = raw?.position ?? old.roster.first(where: { $0.id == pid })?.position ?? "UNK"
                    let fantasy = raw?.fantasy_positions ?? [basePos]
                    let points = playersPoints[pid] ?? 0.0
                    return MigCandidate(basePos: basePos, fantasy: fantasy, points: points)
                }
            }()

            var used = Set<MigCandidate>()
            var weekMax = 0.0
            var weekMaxOff = 0.0
            var weekMaxDef = 0.0

            for slot in slots {
                let allowed = allowedPositions(for: slot)
                let pick = candidates
                    .filter { !used.contains($0) && isEligible(c: $0, allowed: allowed) }
                    .max { $0.points < $1.points }
                guard let cand = pick else { continue }
                used.insert(cand)
                weekMax += cand.points
                if isOffensiveSlot(slot) {
                    weekMaxOff += cand.points
                } else {
                    weekMaxDef += cand.points
                }
            }
            maxTotal += weekMax
            maxOff += weekMaxOff
            maxDef += weekMaxDef

            // --- ACTUAL STARTERS PER POSITION (usage) ---
            if let startersList = myEntry.starters, !startersList.isEmpty {
                tempStarters[week] = startersList
                var assignment: [MigCandidate: String] = [:]
                var availableSlots = slots

                // Build candidate objects for all starters, using their position from playerCache
                let sortedStarters = startersList.compactMap { pid in
                    let raw = playerCache[pid]
                    let pos = raw?.position ?? old.roster.first(where: { $0.id == pid })?.position ?? "UNK"
                    let alt = raw?.fantasy_positions ?? []
                    return MigCandidate(basePos: pos, fantasy: [pos] + alt, points: myEntry.players_points?[pid] ?? 0)
                }

                for c in sortedStarters {
                    let elig = eligibleSlots(for: c, availableSlots)
                    if elig.isEmpty { continue }
                    let specific = elig.filter { ["QB","RB","WR","TE","K","DL","LB","DB"].contains($0.uppercased()) }
                    let chosen = specific.first ?? elig.first!
                    assignment[c] = chosen
                    if let idx = availableSlots.firstIndex(of: chosen) {
                        availableSlots.remove(at: idx)
                    }
                }
                
                for (c, slot) in assignment {
                    let counted = countedPosition(for: slot, candidatePositions: c.fantasy, base: c.basePos)
                    tempCounts[counted, default: 0] += 1
                }
                
                tempWeeks += 1
            }
            
            if !tempCounts.isEmpty {
                actualStarterPositionCounts = tempCounts
                actualStarterWeeks = tempWeeks
                actualStartersByWeek = tempStarters
            }
        }

        let managementPercent = maxTotal > 0 ? (actualTotal / maxTotal) * 100 : 0
        let offensiveManagementPercent = maxOff > 0 ? (totalOffPF / maxOff) * 100 : 0
        let defensiveManagementPercent = maxDef > 0 ? (totalDefPF / maxDef) * 100 : 0

        return TeamStanding(
            id: old.id,
            name: old.name,
            positionStats: old.positionStats,
            ownerId: old.ownerId,
            roster: old.roster,
            leagueStanding: old.leagueStanding,
            pointsFor: actualTotal,
            maxPointsFor: maxTotal > 0 ? maxTotal : old.maxPointsFor,
            managementPercent: managementPercent,
            teamPointsPerWeek: old.teamPointsPerWeek,
            winLossRecord: old.winLossRecord,
            bestGameDescription: old.bestGameDescription,
            biggestRival: old.biggestRival,
            strengths: old.strengths,
            weaknesses: old.weaknesses,
            playoffRecord: old.playoffRecord,
            championships: old.championships,
            winStreak: old.winStreak,
            lossStreak: old.lossStreak,
            offensivePointsFor: totalOffPF > 0 ? totalOffPF : old.offensivePointsFor,
            maxOffensivePointsFor: maxOff > 0 ? maxOff : old.maxOffensivePointsFor,
            offensiveManagementPercent: offensiveManagementPercent,
            averageOffensivePPW: old.averageOffensivePPW,
            offensiveStrengths: old.offensiveStrengths,
            offensiveWeaknesses: old.offensiveWeaknesses,
            positionAverages: posPPW.isEmpty ? old.positionAverages : posPPW,
            individualPositionAverages: indivPPW.isEmpty ? old.individualPositionAverages : indivPPW,
            defensivePointsFor: totalDefPF > 0 ? totalDefPF : old.defensivePointsFor,
            maxDefensivePointsFor: maxDef > 0 ? maxDef : old.maxDefensivePointsFor,
            defensiveManagementPercent: defensiveManagementPercent,
            averageDefensivePPW: old.averageDefensivePPW,
            defensiveStrengths: old.defensiveStrengths,
            defensiveWeaknesses: old.defensiveWeaknesses,
            pointsScoredAgainst: old.pointsScoredAgainst,
            league: old.league,
            lineupConfig: lineupConfig,
            weeklyActualLineupPoints: weeklyActualLineupPoints.isEmpty ? old.weeklyActualLineupPoints : weeklyActualLineupPoints,
            actualStartersByWeek: actualStartersByWeek.isEmpty ? old.actualStartersByWeek : actualStartersByWeek,
            actualStarterPositionCounts: actualStarterPositionCounts.isEmpty ? old.actualStarterPositionCounts : actualStarterPositionCounts,
            actualStarterWeeks: actualStarterWeeks == 0 ? old.actualStarterWeeks : actualStarterWeeks,
            waiverMoves: old.waiverMoves ?? 0,
            faabSpent: old.faabSpent ?? 0,
            tradesCompleted: old.tradesCompleted ?? 0
        )
    }

    // MARK: Shared Logic (mirrors updated runtime logic)

    private func allowedPositions(for slot: String) -> Set<String> {
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

    private func isIDPFlex(_ slot: String) -> Bool {
        let s = slot.uppercased()
        return s.contains("IDP") && s != "DL" && s != "LB" && s != "DB"
    }

    private func countedPosition(for slot: String,
                                 candidatePositions: [String],
                                 base: String) -> String {
        let s = slot.uppercased()
        if ["QB","RB","WR","TE","K","DL","LB","DB"].contains(s) { return s }
        let allowed = allowedPositions(for: slot)
        return candidatePositions.filter { allowed.contains($0) }.first ?? base
    }

    private struct MigCandidate: Hashable {
        let basePos: String
        let fantasy: [String]
        let points: Double
    }

    private func isEligible(c: MigCandidate, allowed: Set<String>) -> Bool {
        !allowed.intersection(Set(c.fantasy)).isEmpty
    }

    private func eligibleSlots(for c: MigCandidate, _ slots: [String]) -> [String] {
        slots.filter { isEligible(c: c, allowed: allowedPositions(for: $0)) }
    }

    private func inferredLineupConfig(from roster: [Player]) -> [String:Int] {
        var counts: [String:Int] = [:]
        for p in roster { counts[p.position, default: 0] += 1 }
        return counts.mapValues { min($0, 3) }
    }

    private func expandSlots(lineupConfig: [String:Int]) -> [String] {
        lineupConfig.flatMap { Array(repeating: $0.key, count: $0.value) }
    }
    
    private func slotPriority(_ slot: String) -> Int {
        if ["QB","RB","WR","TE","K","DL","LB","DB"].contains(slot.uppercased()) { return 1 } // higher for specific
        return 0
    }

}
