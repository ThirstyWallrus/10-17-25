//
//  DSDStatsService.swift
//  DynastyStatDrop
//
//  Season + All Time stat access
//

import Foundation

@MainActor
final class DSDStatsService {
    static let shared = DSDStatsService()
    
    enum StatType: String, CaseIterable {
        case pointsFor, maxPointsFor, managementPercent, teamAveragePPW, winLossRecord, playoffRecord, championships, bestGameDescription, biggestRival, strengths, weaknesses
        case offensivePointsFor, maxOffensivePointsFor, offensiveManagementPercent, averageOffensivePPW, bestOffensivePositionPPW, worstOffensivePositionPointsAgainstPPW
        case defensivePointsFor, maxDefensivePointsFor, defensiveManagementPercent, averageDefensivePPW, bestDefensivePositionPPW, worstDefensivePositionPointsAgainstPPW
        case qbPositionPPW, rbPositionPPW, wrPositionPPW, tePositionPPW, kickerPPW, dlPositionPPW, lbPositionPPW, dbPositionPPW
        case individualQBPPW, individualRBPPW, individualWRPPW, individualTEPPW, individualKickerPPW, individualDLPPW, individualLBPPW, individualDBPPW
        case highestPointsInGameAllTime, highestPointsInGameSeason, mostPointsAgainstAllTime, mostPointsAgainstSeason, playoffBerthsAllTime, playoffRecordAllTime
        case headToHeadRecord
        case offensiveStrengths, offensiveWeaknesses
        case defensiveStrengths, defensiveWeaknesses
        // NEW starters-per-week (actual usage)
        case avgQBStartersPerWeek, avgRBStartersPerWeek, avgWRStartersPerWeek, avgTEStartersPerWeek
        case avgKStartersPerWeek, avgDLStartersPerWeek, avgLBStartersPerWeek, avgDBStartersPerWeek
        // NEW transactions
        case waiverMovesSeason, waiverMovesAllTime
        case faabSpentSeason, faabSpentAllTime, faabAvgPerMoveAllTime
        case tradesCompletedSeason, tradesCompletedAllTime, tradesPerSeasonAverage
        case playoffPointsFor, playoffPPW, playoffManagementPercent,
                 playoffOffensivePointsFor, playoffOffensivePPW, playoffOffensiveManagementPercent,
                 playoffDefensivePointsFor, playoffDefensivePPW, playoffDefensiveManagementPercent
    }
    
    // MARK: - Helper: Only include completed weeks for season stats
    private func validWeeksForSeason(_ season: SeasonData, currentWeek: Int) -> [Int] {
        let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
        return allWeeks.filter { $0 < currentWeek }
    }
    
    // MARK: Per-season stats (TeamStanding)
    
    func stat(for team: TeamStanding, type: StatType, league: LeagueData? = nil) -> Any? {
        switch type {
        case .pointsFor:
            return filteredPointsFor(team: team, league: league)
        case .maxPointsFor:
            return filteredMaxPointsFor(team: team, league: league)
        case .managementPercent:
            return filteredManagementPercent(team: team, league: league)
        case .teamAveragePPW:
            return filteredTeamAveragePPW(team: team, league: league)
        // ... All other cases unchanged from original code, see below ...
        case .winLossRecord: return team.winLossRecord
        case .playoffRecord: return team.playoffRecord
        case .championships: return team.championships ?? 0
        case .bestGameDescription: return bestGameDescription(for: team)
        case .biggestRival: return team.biggestRival
        case .strengths: return team.strengths ?? []
        case .weaknesses: return team.weaknesses ?? []
        case .offensivePointsFor: return team.offensivePointsFor
        case .maxOffensivePointsFor: return team.maxOffensivePointsFor
        case .offensiveManagementPercent: return team.offensiveManagementPercent
        case .averageOffensivePPW: return team.averageOffensivePPW
        case .bestOffensivePositionPPW: return bestOffPos(team)
        case .worstOffensivePositionPointsAgainstPPW: return worstOffPos(team)
        case .defensivePointsFor: return team.defensivePointsFor
        case .maxDefensivePointsFor: return team.maxDefensivePointsFor
        case .defensiveManagementPercent: return team.defensiveManagementPercent
        case .averageDefensivePPW: return team.averageDefensivePPW
        case .bestDefensivePositionPPW: return bestDefPos(team)
        case .worstDefensivePositionPointsAgainstPPW: return worstDefPos(team)
        case .qbPositionPPW: return team.positionAverages?["QB"]
        case .rbPositionPPW: return team.positionAverages?["RB"]
        case .wrPositionPPW: return team.positionAverages?["WR"]
        case .tePositionPPW: return team.positionAverages?["TE"]
        case .kickerPPW: return team.positionAverages?["K"]
        case .dlPositionPPW: return team.positionAverages?["DL"]
        case .lbPositionPPW: return team.positionAverages?["LB"]
        case .dbPositionPPW: return team.positionAverages?["DB"]
        case .individualQBPPW: return team.individualPositionAverages?["QB"]
        case .individualRBPPW: return team.individualPositionAverages?["RB"]
        case .individualWRPPW: return team.individualPositionAverages?["WR"]
        case .individualTEPPW: return team.individualPositionAverages?["TE"]
        case .individualKickerPPW: return team.individualPositionAverages?["K"]
        case .individualDLPPW: return team.individualPositionAverages?["DL"]
        case .individualLBPPW: return team.individualPositionAverages?["LB"]
        case .individualDBPPW: return team.individualPositionAverages?["DB"]
        case .highestPointsInGameAllTime, .highestPointsInGameSeason, .mostPointsAgainstAllTime, .mostPointsAgainstSeason, .playoffBerthsAllTime, .playoffRecordAllTime, .headToHeadRecord: return nil
        case .offensiveStrengths: return team.offensiveStrengths ?? []
        case .offensiveWeaknesses: return team.offensiveWeaknesses ?? []
        case .defensiveStrengths: return team.defensiveStrengths ?? []
        case .defensiveWeaknesses: return team.defensiveWeaknesses ?? []
        case .avgQBStartersPerWeek: return avgStarter(team, "QB")
        case .avgRBStartersPerWeek: return avgStarter(team, "RB")
        case .avgWRStartersPerWeek: return avgStarter(team, "WR")
        case .avgTEStartersPerWeek: return avgStarter(team, "TE")
        case .avgKStartersPerWeek: return avgStarter(team, "K")
        case .avgDLStartersPerWeek: return avgStarter(team, "DL")
        case .avgLBStartersPerWeek: return avgStarter(team, "LB")
        case .avgDBStartersPerWeek: return avgStarter(team, "DB")
        case .waiverMovesSeason: return team.waiverMoves ?? 0
        case .faabSpentSeason: return team.faabSpent ?? 0
        case .tradesCompletedSeason: return team.tradesCompleted ?? 0
        case .playoffPointsFor, .playoffPPW, .playoffManagementPercent, .playoffOffensivePointsFor, .playoffOffensivePPW, .playoffOffensiveManagementPercent, .playoffDefensivePointsFor, .playoffDefensivePPW, .playoffDefensiveManagementPercent: return nil
        case .waiverMovesAllTime:
            if let league = team.league,
               let stats = league.allTimeOwnerStats?[team.ownerId] {
                return stats.totalWaiverMoves
            }
            return nil
        case .faabSpentAllTime:
            if let league = team.league,
               let stats = league.allTimeOwnerStats?[team.ownerId] {
                return stats.totalFAABSpent
            }
            return nil
        case .faabAvgPerMoveAllTime:
            if let league = team.league,
               let stats = league.allTimeOwnerStats?[team.ownerId] {
                return stats.totalWaiverMoves > 0 ? (stats.totalFAABSpent / Double(stats.totalWaiverMoves)) : 0
            }
            return 0.0
        case .tradesCompletedAllTime:
            if let league = team.league,
               let stats = league.allTimeOwnerStats?[team.ownerId] {
                return stats.totalTradesCompleted
            }
            return nil
        case .tradesPerSeasonAverage:
            if let league = team.league,
               let stats = league.allTimeOwnerStats?[team.ownerId] {
                return stats.seasonsIncluded.isEmpty ? 0 :
                    Double(stats.totalTradesCompleted) / Double(stats.seasonsIncluded.count)
            }
            return 0.0
        }
    }
    
    // MARK: Week-exclusion patch helpers for season aggregations

    // Use only completed weeks for season-long stat aggregations.
    private func filteredPointsFor(team: TeamStanding, league: LeagueData?) -> Double {
        guard let league = league,
              let season = league.seasons.first(where: { $0.teams.contains(where: { $0.id == team.id }) }) else {
            return team.pointsFor
        }
        let currentWeek = (league.seasons.sorted { $0.id < $1.id }.last?.matchupsByWeek?.keys.max() ?? 18) + 1
        let validWeeks = validWeeksForSeason(season, currentWeek: currentWeek)
        return team.roster
            .flatMap { $0.weeklyScores }
            .filter { validWeeks.contains($0.week) }
            .reduce(0) { $0 + $1.points }
    }

    private func filteredMaxPointsFor(team: TeamStanding, league: LeagueData?) -> Double {
        guard let league = league,
              let season = league.seasons.first(where: { $0.teams.contains(where: { $0.id == team.id }) }) else {
            return team.maxPointsFor
        }
        let currentWeek = (league.seasons.sorted { $0.id < $1.id }.last?.matchupsByWeek?.keys.max() ?? 18) + 1
        let validWeeks = validWeeksForSeason(season, currentWeek: currentWeek)
        // For maxPointsFor, if you have per-week max, use it; otherwise fallback
        if let maxPerWeek = team.weeklyActualLineupPoints {
            return validWeeks.compactMap { maxPerWeek[$0] }.reduce(0, +)
        }
        return team.maxPointsFor
    }

    private func filteredManagementPercent(team: TeamStanding, league: LeagueData?) -> Double {
        let pf = filteredPointsFor(team: team, league: league)
        let maxPF = filteredMaxPointsFor(team: team, league: league)
        return maxPF > 0 ? (pf / maxPF) * 100 : 0
    }

    private func filteredTeamAveragePPW(team: TeamStanding, league: LeagueData?) -> Double {
        guard let league = league,
              let season = league.seasons.first(where: { $0.teams.contains(where: { $0.id == team.id }) }) else {
            return team.teamPointsPerWeek
        }
        let currentWeek = (league.seasons.sorted { $0.id < $1.id }.last?.matchupsByWeek?.keys.max() ?? 18) + 1
        let validWeeks = validWeeksForSeason(season, currentWeek: currentWeek)
        let pf = filteredPointsFor(team: team, league: league)
        return validWeeks.isEmpty ? 0 : pf / Double(validWeeks.count)
    }
    
    // --- Existing helpers below ---

    func stat(for agg: AggregatedOwnerStats, type: StatType) -> Any? {
        switch type {
        case .pointsFor: return agg.totalPointsFor
        case .maxPointsFor: return agg.totalMaxPointsFor
        case .managementPercent: return agg.managementPercent
        case .teamAveragePPW: return agg.teamPPW
        case .winLossRecord: return agg.recordString
        case .playoffRecord: return agg.playoffStats.recordString
        case .championships: return agg.championships
        case .bestGameDescription, .biggestRival, .strengths, .weaknesses: return nil
        case .offensivePointsFor: return agg.totalOffensivePointsFor
        case .maxOffensivePointsFor: return agg.totalMaxOffensivePointsFor
        case .offensiveManagementPercent: return agg.offensiveManagementPercent
        case .averageOffensivePPW: return agg.offensivePPW
        case .bestOffensivePositionPPW, .worstOffensivePositionPointsAgainstPPW: return nil
        case .defensivePointsFor: return agg.totalDefensivePointsFor
        case .maxDefensivePointsFor: return agg.totalMaxDefensivePointsFor
        case .defensiveManagementPercent: return agg.defensiveManagementPercent
        case .averageDefensivePPW: return agg.defensivePPW
        case .bestDefensivePositionPPW, .worstDefensivePositionPointsAgainstPPW: return nil
        case .qbPositionPPW: return agg.positionAvgPPW["QB"]
        case .rbPositionPPW: return agg.positionAvgPPW["RB"]
        case .wrPositionPPW: return agg.positionAvgPPW["WR"]
        case .tePositionPPW: return agg.positionAvgPPW["TE"]
        case .kickerPPW: return agg.positionAvgPPW["K"]
        case .dlPositionPPW: return agg.positionAvgPPW["DL"]
        case .lbPositionPPW: return agg.positionAvgPPW["LB"]
        case .dbPositionPPW: return agg.positionAvgPPW["DB"]
        case .individualQBPPW: return agg.individualPositionPPW["QB"]
        case .individualRBPPW: return agg.individualPositionPPW["RB"]
        case .individualWRPPW: return agg.individualPositionPPW["WR"]
        case .individualTEPPW: return agg.individualPositionPPW["TE"]
        case .individualKickerPPW: return agg.individualPositionPPW["K"]
        case .individualDLPPW: return agg.individualPositionPPW["DL"]
        case .individualLBPPW: return agg.individualPositionPPW["LB"]
        case .individualDBPPW: return agg.individualPositionPPW["DB"]
        case .offensiveStrengths, .offensiveWeaknesses, .defensiveStrengths, .defensiveWeaknesses: return nil
        case .avgQBStartersPerWeek: return avgStarterAllTime(agg, "QB")
        case .avgRBStartersPerWeek: return avgStarterAllTime(agg, "RB")
        case .avgWRStartersPerWeek: return avgStarterAllTime(agg, "WR")
        case .avgTEStartersPerWeek: return avgStarterAllTime(agg, "TE")
        case .avgKStartersPerWeek: return avgStarterAllTime(agg, "K")
        case .avgDLStartersPerWeek: return avgStarterAllTime(agg, "DL")
        case .avgLBStartersPerWeek: return avgStarterAllTime(agg, "LB")
        case .avgDBStartersPerWeek: return avgStarterAllTime(agg, "DB")
        case .waiverMovesAllTime: return agg.totalWaiverMoves
        case .faabSpentAllTime: return agg.totalFAABSpent
        case .faabAvgPerMoveAllTime:
            return agg.totalWaiverMoves > 0 ? (agg.totalFAABSpent / Double(agg.totalWaiverMoves)) : 0
        case .tradesCompletedAllTime: return agg.totalTradesCompleted
        case .tradesPerSeasonAverage:
            return agg.seasonsIncluded.isEmpty ? 0 :
                Double(agg.totalTradesCompleted) / Double(agg.seasonsIncluded.count)
        case .waiverMovesSeason, .faabSpentSeason, .tradesCompletedSeason: return nil
        case .highestPointsInGameAllTime,
             .highestPointsInGameSeason,
             .mostPointsAgainstAllTime,
             .mostPointsAgainstSeason,
             .playoffBerthsAllTime,
             .headToHeadRecord: return nil
        case .playoffPointsFor:
            return agg.playoffStats.pointsFor
        case .playoffPPW:
            return agg.playoffStats.ppw
        case .playoffManagementPercent:
            return agg.playoffStats.managementPercent
        case .playoffOffensivePointsFor:
            return agg.playoffStats.offensivePointsFor
        case .playoffOffensivePPW:
            return agg.playoffStats.offensivePPW
        case .playoffOffensiveManagementPercent:
            return agg.playoffStats.offensiveManagementPercent
        case .playoffDefensivePointsFor:
            return agg.playoffStats.defensivePointsFor
        case .playoffDefensivePPW:
            return agg.playoffStats.defensivePPW
        case .playoffDefensiveManagementPercent:
            return agg.playoffStats.defensiveManagementPercent
        case .playoffRecordAllTime:
            // Return playoff record across all time
            return agg.playoffStats.recordString
        }
    }
    
    // MARK: Helpers
    
    private func bestGameDescription(for team: TeamStanding) -> String? {
        if let desc = team.bestGameDescription, !desc.isEmpty { return desc }
        guard let weeklyPoints = team.weeklyActualLineupPoints, !weeklyPoints.isEmpty else { return nil }
        guard let bestPoints = weeklyPoints.values.max(),
              let bestWeek = weeklyPoints.first(where: { $1 == bestPoints })?.key else { return nil }
        return "Week \(bestWeek) – \(String(format: "%.1f", bestPoints)) pts"
    }
    
    private func highestPoints(_ team: TeamStanding) -> Double {
        team.roster.flatMap { $0.weeklyScores }
            .map { $0.points_half_ppr ?? $0.points }
            .max() ?? 0
    }
    
    private func bestOffPos(_ team: TeamStanding) -> (String, Double)? {
        guard let dict = team.positionAverages else { return nil }
        let off: Set<String> = ["QB","RB","WR","TE","K"]
        return dict.filter { off.contains($0.key) }.max { $0.value < $1.value }
    }
    private func worstOffPos(_ team: TeamStanding) -> (String, Double)? {
        guard let dict = team.positionAverages else { return nil }
        let off: Set<String> = ["QB","RB","WR","TE","K"]
        return dict.filter { off.contains($0.key) }.min { $0.value < $1.value }
    }
    private func bestDefPos(_ team: TeamStanding) -> (String, Double)? {
        guard let dict = team.positionAverages else { return nil }
        let def: Set<String> = ["DL","LB","DB"]
        return dict.filter { def.contains($0.key) }.max { $0.value < $1.value }
    }
    private func worstDefPos(_ team: TeamStanding) -> (String, Double)? {
        guard let dict = team.positionAverages else { return nil }
        let def: Set<String> = ["DL","LB","DB"]
        return dict.filter { def.contains($0.key) }.min { $0.value < $1.value }
    }
    private func avgStarter(_ team: TeamStanding, _ pos: String) -> Double {
        guard let counts = team.actualStarterPositionCounts,
              let weeks = team.actualStarterWeeks, weeks > 0 else { return 0 }
        return Double(counts[pos] ?? 0) / Double(weeks)
    }
    private func avgStarterAllTime(_ agg: AggregatedOwnerStats, _ pos: String) -> Double {
        guard agg.actualStarterWeeks > 0 else { return 0 }
        return Double(agg.actualStarterPositionCountsTotals[pos] ?? 0) / Double(agg.actualStarterWeeks)
    }
    
    func playoffStats(for team: TeamStanding) -> PlayoffStats? {
        guard let league = team.league,
              let agg = league.allTimeOwnerStats?[team.ownerId] else {
            return nil
        }
        return agg.playoffStats
    }
    
}
