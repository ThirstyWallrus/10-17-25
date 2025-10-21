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

// --- PATCH: Import PositionNormalizer globally
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
            var newSeasons: [SeasonData] = []
            for season in league.seasons {
                let migratedTeams = season.teams.map { migrateTeam($0, season: season) }
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

    private func migrateTeam(_ old: TeamStanding, season: SeasonData?) -> TeamStanding {
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
        let allWeeks = old.weeklyActualLineupPoints?.keys.sorted() ?? []
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
        
        let playerCache: [String: RawSleeperPlayer] = [:]

        var actualStartersByWeek: [Int: [String]] = [:]
        var actualStarterPositionCounts: [String: Int] = [:]
        var actualStarterWeeks: Int = 0

        for week in regWeeks {
            let weekEntries = season.matchupsByWeek?[week] ?? []
            guard let myEntry = weekEntries.first(where: { $0.roster_id == myRosterId }) else { continue }

            let myPoints = myEntry.points ?? 0.0
            actualTotal += myPoints

            // Offensive/Defensive Split using slots primarily
            var off = 0.0
            var defPF = 0.0  // Renamed to avoid conflict
            guard let starters = myEntry.starters,
                  let starterPoints = myEntry.players_points, // <-- FIX: use players_points
                  starters.count == starterPoints.count else { continue }
            if slots.count == starters.count {
                for i in 0..<starters.count {
                    let pid = starters[i]
                    let pts = starterPoints[pid] ?? 0.0
                    // --- PATCH: Normalize position for defensive stat split ---
                    let normalized = PositionNormalizer.normalize(slots[i])
                    if isOffensiveSlot(slots[i]) {
                        off += pts
                    } else if normalized == "DL" || normalized == "LB" || normalized == "DB" {
                        defPF += pts
                    }
                }
            } else {
                // Fallback to position-based
                for i in 0..<starters.count {
                    let pid = starters[i]
                    let pts = starterPoints[pid] ?? 0.0
                    // FIX: We want a RawSleeperPlayer? here. Use playerCache[pid] if available, else map from old.roster
                    let player: RawSleeperPlayer? = playerCache[pid] ?? {
                        if let p = old.roster.first(where: { $0.id == pid }) {
                            // Map Player to RawSleeperPlayer (approximate: position is present)
                            return RawSleeperPlayer(
                                player_id: p.id,
                                full_name: nil,
                                position: p.position,
                                fantasy_positions: p.altPositions
                            )
                        }
                        return nil
                    }()
                    if let pos = player?.position?.uppercased() {
                        let normalized = PositionNormalizer.normalize(pos)
                        if offensivePositions.contains(normalized) {
                            off += pts
                        } else if defensivePositions.contains(normalized) {
                            defPF += pts
                        }
                        // --- PATCH: Use normalized position for stat groupings ---
                        posPPW[normalized, default: 0] += pts
                        indivPPW[normalized, default: 0] += pts
                        posCounts[normalized, default: 0] += 1
                        indivCounts[normalized, default: 0] += 1
                    }
                }
            }
            totalOffPF += off
            totalDefPF += defPF

            // Optimal Lineup
            let candidates: [MigCandidate] = old.roster.compactMap { player in
                guard let ws = player.weeklyScores.first(where: { $0.week == week }) else { return nil }
                return MigCandidate(basePos: player.position, fantasy: player.altPositions ?? [], points: ws.points_half_ppr ?? ws.points)
            }
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
                let normalized = PositionNormalizer.normalize(slot)
                weekMax += cand.points
                if isOffensiveSlot(slot) {
                    weekMaxOff += cand.points
                } else if normalized == "DL" || normalized == "LB" || normalized == "DB" {
                    weekMaxDef += cand.points
                }
            }
            maxTotal += weekMax
            maxOff += weekMaxOff
            maxDef += weekMaxDef

            // Actual starters per position (usage)
            if let startersList = myEntry.starters, !startersList.isEmpty {
                tempStarters[week] = startersList
                var assignment: [MigCandidate: String] = [:]
                var availableSlots = slots

                let sortedStarters = startersList.compactMap { pid in
                    old.roster.first { $0.id == pid }.map { MigCandidate(basePos: $0.position, fantasy: $0.altPositions ?? [], points: 0) }
                }

                for c in sortedStarters {
                    let elig = eligibleSlots(for: c, availableSlots)
                    if elig.isEmpty { continue }
                    let specific = elig.filter { ["QB","RB","WR","TE","K","DL","LB","DB"].contains(PositionNormalizer.normalize($0)) }
                    let chosen = specific.first ?? elig.first!
                    assignment[c] = chosen
                    if let idx = availableSlots.firstIndex(of: chosen) {
                        availableSlots.remove(at: idx)
                    }
                }
                
                // PATCHED: Use slot assignment rules for duel-designated/flex positions
                for (c, slot) in assignment {
                    let counted = countedPosition(for: slot, candidatePositions: [c.basePos] + c.fantasy, base: c.basePos)
                    let normalized = PositionNormalizer.normalize(counted)
                    tempCounts[normalized, default: 0] += 1
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

        // --- PATCH: Normalize keys in posPPW and indivPPW before storing ---
        let normalizedPosPPW = Dictionary(uniqueKeysWithValues: posPPW.map { (PositionNormalizer.normalize($0.key), $0.value) })
        let normalizedIndivPPW = Dictionary(uniqueKeysWithValues: indivPPW.map { (PositionNormalizer.normalize($0.key), $0.value) })
        let normalizedPosCounts = Dictionary(uniqueKeysWithValues: posCounts.map { (PositionNormalizer.normalize($0.key), $0.value) })
        let normalizedIndivCounts = Dictionary(uniqueKeysWithValues: indivCounts.map { (PositionNormalizer.normalize($0.key), $0.value) })

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
            positionAverages: normalizedPosPPW.isEmpty ? old.positionAverages : normalizedPosPPW,
            individualPositionAverages: normalizedIndivPPW.isEmpty ? old.individualPositionAverages : normalizedIndivPPW,
            defensivePointsFor: totalDefPF > 0 ? totalDefPF : old.defensivePointsFor,
            maxDefensivePointsFor: maxDef > 0 ? maxDef : old.maxDefensivePointsFor,
            defensiveManagementPercent: defensiveManagementPercent,
            averageDefensivePPW: old.averageDefensivePPW,
            defensiveStrengths: old.defensiveStrengths,
            defensiveWeaknesses: old.defensiveWeaknesses,
            pointsScoredAgainst: old.pointsScoredAgainst,
            league: old.league,
            lineupConfig: lineupConfig,
            weeklyActualLineupPoints: old.weeklyActualLineupPoints,
            actualStartersByWeek: actualStartersByWeek,
            actualStarterPositionCounts: actualStarterPositionCounts,
            actualStarterWeeks: actualStarterWeeks,
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

    // PATCHED: Use slot assignment rules for duel-designated/flex positions
    private func countedPosition(for slot: String,
                                 candidatePositions: [String],
                                 base: String) -> String {
        let s = slot.uppercased()
        let strict = ["QB", "RB", "WR", "TE", "K", "DL", "LB", "DB"]
        let offensiveFlexes: Set<String> = [
            "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE","WRRBTEFLEX"
        ]
        let idpFlexes: Set<String> = [
            "IDPFLEX","IDP_FLEX","DFLEX","DL_LB_DB","DL_LB","LB_DB","DL_DB","DP","D","DEF"
        ]
        if strict.contains(s) {
            // Player is credited as the slot they were started in
            return s
        }
        if offensiveFlexes.contains(s) {
            // Credit as first eligible position (e.g., LB/DL in FLEX -> "LB")
            return candidatePositions.first ?? base
        }
        if idpFlexes.contains(s) || s.contains("IDP") {
            // Credit as first eligible position for IDP flexes
            return candidatePositions.first ?? base
        }
        // Fallback
        return candidatePositions.first ?? base
    }

    private struct MigCandidate: Hashable {
        let basePos: String
        let fantasy: [String]
        let points: Double
    }

    private func isEligible(c: MigCandidate, allowed: Set<String>) -> Bool {
        // PATCH: Use normalized position for eligibility checks
        let normalizedAllowed = Set(allowed.map { PositionNormalizer.normalize($0) })
        let allCandidate = [c.basePos] + c.fantasy
        return allCandidate.map { PositionNormalizer.normalize($0) }.contains(where: { normalizedAllowed.contains($0) })
    }

    private func eligibleSlots(for c: MigCandidate, _ slots: [String]) -> [String] {
        slots.filter { isEligible(c: c, allowed: allowedPositions(for: $0)) }
    }

    private func inferredLineupConfig(from roster: [Player]) -> [String:Int] {
        var counts: [String:Int] = [:]
        for p in roster {
            // PATCH: Normalize position for starter slot assignment
            let normalized = PositionNormalizer.normalize(p.position)
            counts[normalized, default: 0] += 1
        }
        return counts.mapValues { min($0, 3) }
    }

    private func expandSlots(lineupConfig: [String:Int]) -> [String] {
        lineupConfig.flatMap { Array(repeating: $0.key, count: $0.value) }
    }
    
    private func slotPriority(_ slot: String) -> Int {
        if ["QB","RB","WR","TE","K","DL","LB","DB"].contains(PositionNormalizer.normalize(slot)) { return 1 } // higher for specific
        return 0
    }

}
