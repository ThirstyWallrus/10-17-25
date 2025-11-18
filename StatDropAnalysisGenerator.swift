//
//  StatDropAnalysisGenerator.swift
//  DynastyStatDrop
//
//  AI-powered, personality-driven stat drop generator.
//  Supports multiple personalities and context-specific analysis (team, offense, defense, full).
//
//  ENHANCEMENTS (v2):
//  - Deeper analysis: position PPW, individual PPW, league comparisons, management breakdowns, rivalries.
//  - Personable & comical: tailored language per personality.
//  - Robustness: dynamic templates with conditional logic and fallbacks.
//  - View-specific generators: myTeam, myLeague, matchup.
//  - Persistence updated to include opponent id for matchup context.
//

import Foundation
import SwiftUI

private let offensivePositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
private let defensivePositions: Set<String> = ["DL", "LB", "DB"]
private let offensiveFlexSlots: Set<String> = ["FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE", "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX"]

// MARK: - Stat Drop Personality

enum StatDropPersonality: String, CaseIterable, Identifiable, Codable {
    case classicESPN
    case hypeMan
    case snarkyAnalyst
    case oldSchoolRadio
    case statGeek
    case motivationalCoach
    case britishCommentator
    case localNews
    case dramatic
    case robotAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classicESPN: return "Classic ESPN Anchor"
        case .hypeMan: return "Hype Man"
        case .snarkyAnalyst: return "Snarky Analyst"
        case .oldSchoolRadio: return "Old School Radio"
        case .statGeek: return "Stat Geek"
        case .motivationalCoach: return "Motivational Coach"
        case .britishCommentator: return "British Commentator"
        case .localNews: return "Local News"
        case .dramatic: return "Overly Dramatic"
        case .robotAI: return "Robot AI"
        }
    }

    var description: String {
        switch self {
        case .classicESPN: return "Professional, witty, classic sports banter."
        case .hypeMan: return "High energy, hype, and a touch of swagger."
        case .snarkyAnalyst: return "Sarcastic, dry humor, loves a good roast."
        case .oldSchoolRadio: return "Earnest, vintage, 1950s radio vibes."
        case .statGeek: return "Obscure stats and fun trivia galore."
        case .motivationalCoach: return "Pep talks, tough love, and inspiration."
        case .britishCommentator: return "Polite, understated, dry wordplay."
        case .localNews: return "Folksy, small-town charm and puns."
        case .dramatic: return "Everything is epic, even your kicker."
        case .robotAI: return "Deadpan, literal, and occasionally glitchy."
        }
    }
}

// MARK: - Stat Drop Context

enum StatDropContext: String, Codable {
    case fullTeam    // Full, long-form analysis
    case team        // Team card (brief)
    case offense     // Offense card (brief)
    case defense     // Defense card (brief)
    // View-specific:
    case myTeam
    case myLeague
    case matchup
}

// MARK: - Helper structs

struct Candidate {
    let basePos: String
    let fantasy: [String]
    let points: Double
}

struct TeamStats {
    let pointsFor: Double
    let maxPointsFor: Double
    let managementPercent: Double
    let ppw: Double
    let leagueAvgPpw: Double
    let record: String
    let offensivePointsFor: Double
    let maxOffensivePointsFor: Double
    let offensiveManagementPercent: Double
    let offensivePPW: Double
    let defensivePointsFor: Double
    let maxDefensivePointsFor: Double
    let defensiveManagementPercent: Double
    let defensivePPW: Double
    let positionAverages: [String: Double]
    let offensiveStrengths: [String]?
    let offensiveWeaknesses: [String]?
    let defensiveStrengths: [String]?
    let defensiveWeaknesses: [String]?
    let strengths: [String]?
    let weaknesses: [String]?
    let leagueStanding: Int
}

struct PreviousWeekStats {
    let week: Int
    let actual: Double
    let max: Double
    let mgmt: Double
    let offActual: Double
    let offMax: Double
    let offMgmt: Double
    let defActual: Double
    let defMax: Double
    let defMgmt: Double
    let posSums: [String: Double]
    let leagueRank: Int
    let numTeams: Int

    var topPos: (String, Double)? { posSums.max { $0.value < $1.value } }
    var weakPos: (String, Double)? { posSums.min { $0.value < $1.value } }
    var topOffPos: (String, Double)? { posSums.filter { offensivePositions.contains($0.key) }.max { $0.value < $1.value } }
    var weakOffPos: (String, Double)? { posSums.filter { offensivePositions.contains($0.key) }.min { $0.value < $1.value } }
    var topDefPos: (String, Double)? { posSums.filter { defensivePositions.contains($0.key) }.max { $0.value < $1.value } }
    var weakDefPos: (String, Double)? { posSums.filter { defensivePositions.contains($0.key) }.min { $0.value < $1.value } }
}

// MARK: - String helpers

extension String {
    var capitalizeFirst: String { prefix(1).capitalized + dropFirst() }

    func rangesOfNumbers() -> [NSRange] {
        var ranges: [NSRange] = []
        let regex = try? NSRegularExpression(pattern: "\\d+\\.?\\d*")
        let matches = regex?.matches(in: self, range: NSRange(location: 0, length: utf16.count))
        for match in matches ?? [] { ranges.append(match.range) }
        return ranges
    }
}

// MARK: - StatDropAnalysisGenerator

@MainActor final class StatDropAnalysisGenerator {
    static let shared = StatDropAnalysisGenerator()
    private init() {}

    /// Main API
    func generate(for team: TeamStanding,
                  league: LeagueData,
                  week: Int,
                  context: StatDropContext,
                  personality: StatDropPersonality,
                  opponent: TeamStanding? = nil,
                  explicitWeek: Int? = nil) -> AttributedString {
        switch context {
        case .fullTeam, .team:
            return generateMyTeam(team: team, league: league, week: week, personality: personality)
        case .offense:
            return generateOffenseCard(team: team, league: league, week: week, personality: personality)
        case .defense:
            return generateDefenseCard(team: team, league: league, week: week, personality: personality)
        case .myTeam:
            return generateMyTeam(team: team, league: league, week: week, personality: personality)
        case .myLeague:
            return generateMyLeague(team: team, league: league, week: week, personality: personality)
        case .matchup:
            return generateMatchup(team: team, opponent: opponent, league: league, week: explicitWeek ?? week, personality: personality)
        }
    }

    // MARK: - Context generators

    private func generateMyTeam(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""

        let stats = extractTeamStats(team: team, league: league)
        let allTime = extractAllTimeStats(ownerId: team.ownerId, league: league)
        let previousWeek = max(1, week - 1)
        let weekStats = computeWeekStats(team: team, league: league, week: previousWeek)

        analysis += personalityIntroTeam(team: team, week: week, personality: personality, stats: stats)
        analysis += previousWeekBreakdown(weekStats: weekStats, personality: personality)
        analysis += seasonBreakdown(team: team, stats: stats, allTime: allTime, personality: personality)

        if let wk = weekStats {
            if let top = wk.topPos {
                analysis += "\n\nMVP Area Last Week: \(top.0) produced \(String(format: \"%.1f\", top.1)) points — keep feeding it."
            }
            if let weak = wk.weakOffPos {
                analysis += "\nBench Watch: \(weak.0) underperformed with \(String(format: \"%.1f\", weak.1)) — consider upgrades."
            }
        }

        analysis += lookAheadForTeam(team: team, league: league, week: week, personality: personality, stats: stats)
        analysis += suggestionsAndEncouragement(team: team, personality: personality)

        return formatAttributedString(analysis)
    }

    private func generateMyLeague(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""
        let stats = extractTeamStats(team: team, league: league)
        let teams = league.teams
        let sortedByPPW = teams.sorted { $0.teamPointsPerWeek > $1.teamPointsPerWeek }
        let top = sortedByPPW.first
        let bottom = sortedByPPW.last
        let avgPPW = teams.map { $0.teamPointsPerWeek }.reduce(0, +) / Double(max(1, teams.count))

        analysis += personalityIntroLeague(team: team, league: league, personality: personality, stats: stats)

        if let top = top {
            analysis += "\n\nLeague Leader: \(top.name) is pacing the league at \(String(format: \"%.1f\", top.teamPointsPerWeek)) PPW."
        }
        if let bottom = bottom {
            analysis += " Lagging Team: \(bottom.name) at \(String(format: \"%.1f\", bottom.teamPointsPerWeek)) PPW."
        }
        analysis += "\nLeague average PPW: \(String(format: \"%.2f\", avgPPW)). Your team: \(team.name) at \(String(format: \"%.2f\", stats.ppw)) PPW."

        let rankByPPW = sortedByPPW.firstIndex(where: { $0.id == team.id })?.advanced(by: 1) ?? team.leagueStanding
        analysis += "\nYou're roughly ranked \(rankByPPW) by PPW. Strengths vs league: \(Array(stats.positionAverages.keys).sorted().prefix(3).joined(separator: \", \"))."

        if let champs = league.allTimeOwnerStats?.values.sorted(by: { $0.championships > $1.championships }).first {
            analysis += "\n\nAll-time leaderboard tease: \(champs.latestDisplayName) leads historically with \(champs.championships) championships."
        }

        analysis += "\n\nLeague Look-Ahead: Watch teams that are trending upward. Keep an eye on trades and waiver activity."
        analysis += "\n\nSuggestions: If your team is below league avg PPW, target players with positive recent usage/ppw trends."

        return formatAttributedString(analysis)
    }

    private func generateMatchup(team: TeamStanding, opponent: TeamStanding?, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""
        let stats = extractTeamStats(team: team, league: league)
        let teamWeekStats = computeWeekStats(team: team, league: league, week: week)
        let oppWeekStats = opponent.flatMap { computeWeekStats(team: $0, league: league, week: week) }
        let oppStats = opponent.flatMap { extractTeamStats(team: $0, league: league) }
        let headToHead = opponent.flatMap { computeHeadToHeadStats(teamOwnerId: team.ownerId, oppOwnerId: $0.ownerId, league: league) }

        analysis += personalityIntroMatchup(team: team, opponent: opponent, week: week, personality: personality, stats: stats)

        if let h2h = headToHead {
            analysis += "\n\nAll-time vs \(opponent?.name ?? \"Opponent\"): \(h2h.record) — PF: \(String(format: \"%.1f\", h2h.avgPointsFor)) / \(String(format: \"%.1f\", h2h.avgPointsAgainst))."
        }

        if let opp = opponent, let oppS = oppStats {
            analysis += "\n\nMatchup Snapshot (Week \(week)):"
            analysis += "\n- Your Offense: \(String(format: \"%.1f\", stats.offensivePPW)) PPW vs Their Defense: \(String(format: \"%.1f\", oppS.defensivePPW)) PPW"
            analysis += "\n- Your Defense: \(String(format: \"%.1f\", stats.defensivePPW)) PPW vs Their Offense: \(String(format: \"%.1f\", oppS.offensivePPW)) PPW"
            let proj = projectedWinChance(teamStats: stats, oppStats: oppS)
            analysis += "\n\nProjection: \(String(format: \"%.0f\", proj*100))% chance to win (heuristic)."
        } else {
            analysis += "\n\nUpcoming Matchup: opponent data unavailable — focus on maximizing management and starting hot players."
        }

        if let tw = teamWeekStats {
            analysis += previousWeekBreakdown(weekStats: tw, personality: personality, isBrief: true)
        }
        if let ow = oppWeekStats {
            analysis += "\n\nOpponent Recap: " + previousWeekBreakdown(weekStats: ow, personality: personality, isBrief: true)
        }

        switch personality {
        case .hypeMan:
            analysis += "\n\nIT'S GAME TIME — BRING THE NOISE AND DOMINATE!"
        case .snarkyAnalyst:
            analysis += "\n\nDon't choke. Then again, maybe they will."
        case .motivationalCoach:
            analysis += "\n\nTrust the plan. Set your lineup, believe, go win."
        default:
            analysis += "\n\nGood luck — lineup smart, win proud."
        }

        return formatAttributedString(analysis)
    }

    // MARK: - Computation helpers

    private func computeWeekStats(team: TeamStanding, league: LeagueData, week: Int) -> PreviousWeekStats? {
        if week < 1 { return nil }

        let actual = computeActualPointsForWeek(team: team, week: week)
        let max = computeMaxPointsForWeek(team: team, league: league, week: week)

        let mgmt = max.total > 0 ? (actual.total / max.total * 100) : 0
        let offMgmt = max.off > 0 ? (actual.off / max.off * 100) : 0
        let defMgmt = max.def > 0 ? (actual.def / max.def * 100) : 0

        let posSums = computePositionSumsForWeek(team: team, week: week)
        let leaguePoints = computeLeagueWeekPoints(league: league, week: week)
        let sorted = leaguePoints.sorted { $0.value > $1.value }

        if let idx = sorted.firstIndex(where: { $0.key == team.id }) {
            let rank = idx + 1
            return PreviousWeekStats(week: week,
                                     actual: actual.total,
                                     max: max.total,
                                     mgmt: mgmt,
                                     offActual: actual.off,
                                     offMax: max.off,
                                     offMgmt: offMgmt,
                                     defActual: actual.def,
                                     defMax: max.def,
                                     defMgmt: defMgmt,
                                     posSums: posSums,
                                     leagueRank: rank,
                                     numTeams: league.teams.count)
        }

        return nil
    }

    private func computeActualPointsForWeek(team: TeamStanding, week: Int) -> (total: Double, off: Double, def: Double) {
        var total = 0.0
        var off = 0.0
        var def = 0.0

        if let starters = team.actualStartersByWeek?[week] {
            for id in starters {
                if let player = team.roster.first(where: { $0.id == id }), let score = player.weeklyScores.first(where: { $0.week == week }) {
                    let pts = score.points
                    total += pts
                    let pos = PositionNormalizer.normalize(player.position)
                    if offensivePositions.contains(pos) {
                        off += pts
                    } else if defensivePositions.contains(pos) {
                        def += pts
                    }
                }
            }
        } else if let pts = team.weeklyActualLineupPoints?[week] {
            total = pts
        }

        return (total, off, def)
    }

    private func computeMaxPointsForWeek(team: TeamStanding, league: LeagueData, week: Int) -> (total: Double, off: Double, def: Double) {
        let slots = league.startingLineup
        var candidates: [Candidate] = team.roster.compactMap({ player in
            if let score = player.weeklyScores.first(where: { $0.week == week }) {
                let base = PositionNormalizer.normalize(player.position)
                let fantasy = (player.altPositions ?? []).map { PositionNormalizer.normalize($0) }
                return Candidate(basePos: base, fantasy: fantasy, points: score.points)
            }
            return nil
        })

        var used = Set<Int>()
        var totalMax = 0.0
        var offMax = 0.0
        var defMax = 0.0

        for slot in slots {
            var pickIdx: Int? = nil
            var maxP = -Double.infinity
            for (i, c) in candidates.enumerated() {
                if !used.contains(i) && isEligible(c: c, allowed: allowedPositions(for: slot)) && c.points > maxP {
                    maxP = c.points
                    pickIdx = i
                }
            }
            if let idx = pickIdx {
                used.insert(idx)
                let c = candidates[idx]
                totalMax += c.points
                let counted = SlotPositionAssigner.countedPosition(for: slot, candidatePositions: c.fantasy, base: c.basePos)
                let norm = PositionNormalizer.normalize(counted)
                if offensivePositions.contains(norm) {
                    offMax += c.points
                } else if defensivePositions.contains(norm) {
                    defMax += c.points
                }
            }
        }

        return (totalMax, offMax, defMax)
    }

    private func computePositionSumsForWeek(team: TeamStanding, week: Int) -> [String: Double] {
        var dict: [String: Double] = [:]
        if let starters = team.actualStartersByWeek?[week] {
            for id in starters {
                if let player = team.roster.first(where: { $0.id == id }), let score = player.weeklyScores.first(where: { $0.week == week }) {
                    let norm = PositionNormalizer.normalize(player.position)
                    dict[norm, default: 0] += score.points
                }
            }
        }
        return dict
    }

    private func computeLeagueWeekPoints(league: LeagueData, week: Int) -> [String: Double] {
        var dict: [String: Double] = [:]
        for t in league.teams {
            let actual = computeActualPointsForWeek(team: t, week: week)
            dict[t.id] = actual.total
        }
        return dict
    }

    private func isEligible(c: Candidate, allowed: Set<String>) -> Bool {
        if allowed.contains(c.basePos) { return true }
        return !allowed.intersection(Set(c.fantasy)).isEmpty
    }

    private func allowedPositions(for slot: String) -> Set<String> {
        let u = slot.uppercased()
        switch u {
        case "QB", "RB", "WR", "TE", "K", "DL", "LB", "DB": return [u]
        case "FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE": return ["RB", "WR", "TE"]
        case "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX": return ["QB", "RB", "WR", "TE"]
        case "IDP": return ["DL", "LB", "DB"]
        default:
            if u.contains("IDP") { return ["DL", "LB", "DB"] }
            return [u]
        }
    }

    // MARK: - Extraction helpers

    private func extractTeamStats(team: TeamStanding, league: LeagueData) -> TeamStats {
        let totalPpw = league.teams.reduce(0.0) { $0 + $1.teamPointsPerWeek }
        let avgPpw = league.teams.isEmpty ? 0 : totalPpw / Double(league.teams.count)

        return TeamStats(
            pointsFor: team.pointsFor,
            maxPointsFor: team.maxPointsFor,
            managementPercent: team.managementPercent,
            ppw: team.teamPointsPerWeek,
            leagueAvgPpw: avgPpw,
            record: team.winLossRecord ?? "0-0",
            offensivePointsFor: team.offensivePointsFor ?? 0,
            maxOffensivePointsFor: team.maxOffensivePointsFor ?? 0,
            offensiveManagementPercent: team.offensiveManagementPercent ?? 0,
            offensivePPW: team.averageOffensivePPW ?? 0,
            defensivePointsFor: team.defensivePointsFor ?? 0,
            maxDefensivePointsFor: team.maxDefensivePointsFor ?? 0,
            defensiveManagementPercent: team.defensiveManagementPercent ?? 0,
            defensivePPW: team.averageDefensivePPW ?? 0,
            positionAverages: team.positionAverages ?? [:],
            offensiveStrengths: team.offensiveStrengths,
            offensiveWeaknesses: team.offensiveWeaknesses,
            defensiveStrengths: team.defensiveStrengths,
            defensiveWeaknesses: team.defensiveWeaknesses,
            strengths: team.strengths,
            weaknesses: team.weaknesses,
            leagueStanding: team.leagueStanding
        )
    }

    private func extractAllTimeStats(ownerId: String, league: LeagueData) -> AggregatedOwnerStats? {
        league.allTimeOwnerStats?[ownerId]
    }

    private func computeHeadToHeadStats(teamOwnerId: String, oppOwnerId: String, league: LeagueData) -> H2HStats? {
        guard let agg = league.allTimeOwnerStats?[teamOwnerId], let h2h = agg.headToHeadVs[oppOwnerId] else { return nil }
        return h2h
    }

    private func projectedWinChance(teamStats: TeamStats, oppStats: TeamStats) -> Double {
        let ppwDiff = teamStats.ppw - oppStats.ppw
        let mgmtDiff = teamStats.managementPercent - oppStats.managementPercent
        let wPPW = 0.7
        let wMgmt = 0.3
        let raw = (ppwDiff * wPPW) + (mgmtDiff/100.0 * (wMgmt * 10.0))
        let base: Double = 0.5
        let scaled = base + (raw / max(1.0, abs(teamStats.ppw) + abs(oppStats.ppw)))
        return min(max(scaled, 0.02), 0.98)
    }

    // MARK: - Phrase builders / look-ahead

    private func personalityIntroTeam(team: TeamStanding, week: Int, personality: StatDropPersonality, stats: TeamStats, isBrief: Bool = false) -> String {
        let intro = "Week \(week) Stat Drop — \(team.name):"
        switch personality {
        case .classicESPN: return "\(intro) Here's your team-focused breakdown."
        case .hypeMan: return "\(intro.uppercased()) READY TO RUMBLE!"
        case .snarkyAnalyst: return "\(intro) Let's see what you forgot to bench this week."
        case .oldSchoolRadio: return "\(intro) Tune in for the team's report."
        case .statGeek: return "\(intro) Numbers incoming."
        case .motivationalCoach: return "\(intro) Time to level up!"
        case .britishCommentator: return "\(intro) A refined appraisal."
        case .localNews: return "\(intro) Neighborhood scoreboard."
        case .dramatic: return "\(intro) THE WEEK AWAITS!"
        case .robotAI: return "\(intro) Processing team telemetry."
        }
    }

    private func personalityIntroLeague(team: TeamStanding, league: LeagueData, personality: StatDropPersonality, stats: TeamStats) -> String {
        let intro = "League Stat Drop — \(league.name):"
        switch personality {
        case .classicESPN: return "\(intro) League-wide highlights and where you fit in."
        case .hypeMan: return "\(intro.uppercased()) WHO'S ON TOP?!"
        case .snarkyAnalyst: return "\(intro) Leagues are just drama with spreadsheets."
        case .oldSchoolRadio: return "\(intro) League dispatches."
        case .statGeek: return "\(intro) Aggregated metrics incoming."
        case .motivationalCoach: return "\(intro) See how you stack up, champ."
        case .britishCommentator: return "\(intro) A genteel overview."
        case .localNews: return "\(intro) Community highlights."
        case .dramatic: return "\(intro) EPIC LEAGUE TALES!"
        case .robotAI: return "\(intro) Aggregating league telemetry."
        }
    }

    private func personalityIntroMatchup(team: TeamStanding, opponent: TeamStanding?, week: Int, personality: StatDropPersonality, stats: TeamStats) -> String {
        let oppName = opponent?.name ?? "Opponent"
        let intro = "Matchup Preview — Week \(week): \(team.name) vs \(oppName):"
        switch personality {
        case .classicESPN: return "\(intro) Quick preview and key numbers."
        case .hypeMan: return "\(intro.uppercased()) TIME TO DOMINATE!"
        case .snarkyAnalyst: return "\(intro) Don't embarrass yourself. Or do, it's entertaining."
        case .oldSchoolRadio: return "\(intro) A proper matchup preview."
        case .statGeek: return "\(intro) Head-to-head metrics forthcoming."
        case .motivationalCoach: return "\(intro) Execute the plan and win!"
        case .britishCommentator: return "\(intro) A most engaging duel."
        case .localNews: return "\(intro) Your town vs theirs."
        case .dramatic: return "\(intro) BATTLE OF LEGENDS!"
        case .robotAI: return "\(intro) Calculating outcome probabilities."
        }
    }

    private func lookAheadForTeam(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality, stats: TeamStats) -> String {
        let trendNote: String
        if stats.managementPercent > 85 {
            trendNote = "Your lineup management is elite — expect consistent scoring."
        } else if stats.managementPercent < 65 {
            trendNote = "Lineup efficiency low — tidy the roster and expect risk."
        } else {
            trendNote = "Management is solid; marginal gains on rosters and trades may pay off."
        }

        let expected = String(format: "%.0f", stats.ppw * 1.05 + 0.5)
        var look = "\n\nLook-Ahead: With current usage, expect roughly \(expected) points next week (heuristic). \(trendNote)"

        switch personality {
        case .hypeMan: look += " GET READY — BIG WEEK AHEAD!"
        case .snarkyAnalyst: look += " Or don't do anything and be surprised."
        case .motivationalCoach: look += " You can make it happen — tweak the bench!"
        default: break
        }
        return look
    }

    // MARK: - Phrase builders reused from original style

    private func previousWeekBreakdown(weekStats: PreviousWeekStats?, personality: StatDropPersonality, isBrief: Bool = false) -> String {
        guard let stats = weekStats else { return "\n\nNo data for previous week." }

        let week = stats.week
        let actualStr = String(format: "%.1f", stats.actual)
        let maxStr = String(format: "%.1f", stats.max)
        let mgmtStr = String(format: "%.0f%%", stats.mgmt)
        let rankStr = "\(stats.leagueRank) out of \(stats.numTeams)"
        let topStr = stats.topPos.map { "\($0) shining with \(String(format: \"%.1f\", $1)) pts" } ?? "no standout position"
        let weakStr = stats.weakPos.map { "\($0) struggling with \(String(format: \"%.1f\", $1)) pts" } ?? "no weak position"
        let offMgmtStr = String(format: "%.0f%%", stats.offMgmt)
        let defMgmtStr = String(format: "%.0f%%", stats.defMgmt)

        let fullText = "Scored \(actualStr) points out of a possible \(maxStr), for a management efficiency of \(mgmtStr). Offense management \(offMgmtStr), defense \(defMgmtStr). That performance put you \(rankStr) in the weekly standings. Top area: \(topStr). Weak area: \(weakStr)."
        let briefText = "Week \(week): \(actualStr) pts (\(mgmtStr) mgmt, off \(offMgmtStr), def \(defMgmtStr)), rank \(rankStr). Top: \(topStr); Weak: \(weakStr)."

        let text = isBrief ? briefText : fullText

        switch personality {
        case .classicESPN: return "\n\nPrevious Week (Week \(week)): \(text)"
        case .hypeMan: return "\n\nWEEK \(week) RECAP: \(actualStr) PTS OF \(maxStr)! MGMT \(mgmtStr) — BEAST MODE! RANK \(rankStr)! \(topStr.uppercased())."
        case .snarkyAnalyst: return "\n\nLast week (Week \(week)): Only \(actualStr) when \(maxStr) was possible. \(mgmtStr) management. Ranked \(rankStr). \(topStr). \(weakStr)."
        case .oldSchoolRadio: return "\n\nIn Week \(week), you tallied \(actualStr) points, potential \(maxStr). Management \(mgmtStr), off \(offMgmtStr), def \(defMgmtStr), rank \(rankStr). \(topStr.capitalizeFirst)."
        case .statGeek: return "\n\nWeek \(week) stats: \(actualStr)/\(maxStr) pts, \(mgmtStr) efficiency (off \(offMgmtStr), def \(defMgmtStr)), rank \(rankStr). Top: \(topStr), bottom: \(weakStr)."
        case .motivationalCoach: return "\n\nWeek \(week): Great effort with \(actualStr) pts (\(mgmtStr) mgmt). Build on \(topStr), improve \(weakStr)!"
        case .britishCommentator: return "\n\nWeek \(week): \(actualStr) points from \(maxStr), \(mgmtStr) management (off \(offMgmtStr), def \(defMgmtStr)). Jolly good \(topStr), a bit off \(weakStr)."
        case .localNews: return "\n\nLocal recap for Week \(week): \(actualStr) pts, \(mgmtStr) mgmt. Highlights: \(topStr), needs work: \(weakStr)."
        case .dramatic: return "\n\nTHE TRAGEDY/GLORY OF WEEK \(week): \(actualStr) POINTS / \(maxStr)! MANAGEMENT \(mgmtStr)! \(topStr.uppercased()). \(weakStr.uppercased())."
        case .robotAI: return "\n\nWeek \(week) data: Points \(actualStr)/\(maxStr), management \(mgmtStr) (off \(offMgmtStr), def \(defMgmtStr)), rank \(rankStr). Top \(topStr), weak \(weakStr)."
        }
    }

    private func seasonBreakdown(team: TeamStanding, stats: TeamStats, allTime: AggregatedOwnerStats?, personality: StatDropPersonality, isBrief: Bool = false) -> String {
        let standing = stats.leagueStanding
        let record = stats.record
        let mgmt = String(format: "%.0f%%", stats.managementPercent)
        let ppw = String(format: "%.1f", stats.ppw)
        let vsLg = stats.ppw > stats.leagueAvgPpw ? "above league average" : "below league average"
        let streakStr: String = {
            if let ws = team.winStreak, ws > 1 { return "on a hot \(ws)-win streak" }
            if let ls = team.lossStreak, ls > 1 { return "stuck in a \(ls)-loss rut - time to break free" }
            return "steady as she goes"
        }()
        let offMgmt = String(format: "%.0f%%", stats.offensiveManagementPercent)
        let offPPW = String(format: "%.1f", stats.offensivePPW)
        let defMgmt = String(format: "%.0f%%", stats.defensiveManagementPercent)
        let defPPW = String(format: "%.1f", stats.defensivePPW)
        let strengths = stats.strengths?.joined(separator: ", ") ?? "none apparent"
        let weaknesses = stats.weaknesses?.joined(separator: ", ") ?? "none glaring"
        let rival = team.biggestRival ?? "yourself"
        let allTimeStr = allTime.map { "Historically, \($0.championships) championships and a \($0.recordString) record." } ?? ""

        let fullText = "Currently \(standing)th in the league with a \(record) record. Overall management at \(mgmt), averaging \(ppw) PPW (\(vsLg)). \(streakStr.capitalizeFirst). Offense running at \(offPPW) PPW with \(offMgmt) mgmt; Defense \(defPPW) PPW with \(defMgmt) mgmt. Strengths: \(strengths). Weaknesses: \(weaknesses). Rival: \(rival). \(allTimeStr)"
        let briefText = "\(standing)th place, \(record), mgmt \(mgmt), PPW \(ppw) (\(vsLg)). \(streakStr). Off \(offPPW)/\(offMgmt), Def \(defPPW)/\(defMgmt). Strengths: \(strengths)."

        let text = isBrief ? briefText : fullText

        switch personality {
        case .classicESPN: return "\n\nFull Season Breakdown: \(text)"
        case .hypeMan: return "\n\nSEASON SO FAR: \(standing)TH WITH \(record)! MGMT \(mgmt)! PPW \(ppw) \(vsLg.uppercased())! \(streakStr.uppercased())!"
        case .snarkyAnalyst: return "\n\nSeason summary: Hanging at \(standing)th with \(record). Management \(mgmt). PPW \(ppw) (\(vsLg)). \(streakStr)."
        case .oldSchoolRadio: return "\n\nThe season thus far: Holding \(standing)th spot, record \(record). Management \(mgmt), PPW \(ppw) \(vsLg). \(streakStr.capitalizeFirst)."
        case .statGeek: return "\n\nSeason stats: Rank \(standing), record \(record), mgmt \(mgmt)%, PPW \(ppw) (\(vsLg)). \(streakStr)."
        case .motivationalCoach: return "\n\nSeason progress: You're in \(standing)th with \(record) — keep the momentum! \(streakStr.capitalizeFirst)."
        case .britishCommentator: return "\n\nSeason to date: Position \(standing), record \(record). Management \(mgmt), PPW \(ppw) \(vsLg)."
        case .localNews: return "\n\nCommunity season update: \(standing)th place, \(record) record. Mgmt \(mgmt), \(ppw) PPW \(vsLg)."
        case .dramatic: return "\n\nTHE GRAND SEASON EPIC: THRONE AT \(standing)TH, RECORD \(record)! MGMT \(mgmt)! PPW \(ppw)!"
        case .robotAI: return "\n\nSeason data: Rank \(standing), record \(record), management \(mgmt)%, PPW \(ppw) (\(vsLg))."
        }
    }

    private func suggestionsAndEncouragement(team: TeamStanding, personality: StatDropPersonality, isBrief: Bool = false) -> String {
        let standing = team.leagueStanding
        let weaknesses = team.weaknesses?.joined(separator: ", ") ?? ""
        let suggestion = !weaknesses.isEmpty ? "Consider waivers/trades to improve: \(weaknesses)." : "Roster looks balanced — maintain."
        let encouragement = standing <= (team.league?.teams.count ?? 12) / 2 ? "You're in contention — push for the playoffs!" : "Plenty of games left — stage a comeback!"

        let text = "\(suggestion) \(encouragement)"

        switch personality {
        case .classicESPN: return "\n\nLooking ahead: \(text)"
        case .hypeMan: return "\n\nNEXT MOVES: \(suggestion.uppercased()) \(encouragement.uppercased())"
        case .snarkyAnalyst: return "\n\nSuggestions: \(suggestion) Or ignore — drama is entertaining."
        case .oldSchoolRadio: return "\n\nForward thinking: \(suggestion) \(encouragement)"
        case .statGeek: return "\n\nOptimal moves: \(suggestion) \(encouragement)"
        case .motivationalCoach: return "\n\nGame plan: \(suggestion) \(encouragement) You can do it!"
        case .britishCommentator: return "\n\nRecommendations: \(suggestion) \(encouragement)"
        case .localNews: return "\n\nCommunity tips: \(suggestion) \(encouragement)"
        case .dramatic: return "\n\nTHE CLIMAX APPROACHES: \(suggestion.uppercased()) \(encouragement.uppercased())"
        case .robotAI: return "\n\nComputed advice: \(suggestion) \(encouragement)"
        }
    }

    // MARK: - Formatting

    private func formatAttributedString(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        let ranges = text.rangesOfNumbers()
        for nsRange in ranges {
            if let stringRange = Range(nsRange, in: text) {
                if let start = AttributedString.Index(stringRange.lowerBound, within: attr),
                   let end = AttributedString.Index(stringRange.upperBound, within: attr) {
                    let attrRange = start..<end
                    attr[attrRange].font = .boldSystemFont(ofSize: 16)
                    attr[attrRange].foregroundColor = .yellow
                }
            }
        }
        return attr
    }
}

// MARK: - Persistence + View wrapper (kept minimal, compatibility-aware)

import SwiftUI

struct StatDropAnalysisBox: View {
    let team: TeamStanding
    let league: LeagueData
    let context: StatDropContext
    let personality: StatDropPersonality
    var opponent: TeamStanding? = nil
    var explicitWeek: Int? = nil

    var body: some View {
        let attributed = StatDropPersistence.shared.getOrGenerateStatDrop(
            for: team,
            league: league,
            context: context,
            personality: personality,
            opponent: opponent,
            explicitWeek: explicitWeek
        )
        VStack(alignment: .leading, spacing: 8) {
            Text(context == .fullTeam || context == .myTeam ? "Weekly Stat Drop" : "Stat Drop Analysis")
                .font(.headline)
                .foregroundColor(.yellow)
            Text(attributed)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.13)))
        .padding(.vertical, 4)
    }
}

// MARK: - Persistence helper

@MainActor final class StatDropPersistence {
    static let shared = StatDropPersistence()
    private let userDefaults = UserDefaults.standard

    static var weeklyDropWeekday: Int { 3 } // Tuesday
    static var dropHour: Int { 9 } // 9am UTC

    private init() {}

    func currentWeek(for date: Date = Date(), leagueSeason: String) -> Int {
        guard let year = Int(leagueSeason) else { return 1 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var septFirst = DateComponents(year: year, month: 9, day: 1)
        let septFirstDate = calendar.date(from: septFirst)!
        var seasonStart = septFirstDate
        var weekday = calendar.component(.weekday, from: seasonStart)
        while weekday != 5 {
            seasonStart = calendar.date(byAdding: .day, value: 1, to: seasonStart)!
            weekday = calendar.component(.weekday, from: seasonStart)
        }
        let adjustedDate = adjustedDateForDrop(date)
        let daysSinceStart = calendar.dateComponents([.day], from: seasonStart, to: adjustedDate).day ?? 0
        var rawWeek = (daysSinceStart / 7) + 1
        if rawWeek > 18 { rawWeek = 18 }
        if rawWeek < 1 { rawWeek = 1 }
        return rawWeek
    }

    private func adjustedDateForDrop(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let weekStart = calendar.date(from: components)!
        let dropDate = calendar.date(byAdding: .day, value: StatDropPersistence.weeklyDropWeekday - 1, to: weekStart)!
        let dropDateWithHour = calendar.date(bySettingHour: StatDropPersistence.dropHour, minute: 0, second: 0, of: dropDate)!
        if date < dropDateWithHour {
            return calendar.date(byAdding: .weekOfYear, value: -1, to: dropDateWithHour)!
        }
        return dropDateWithHour
    }

    private func storageKey(leagueId: String, teamId: String, opponentId: String?, context: StatDropContext, week: Int, personality: StatDropPersonality) -> String {
        if context == .matchup {
            let opp = opponentId ?? "none"
            return "statdrop.\(leagueId).\(teamId).\(opp).\(context.rawValue).\(week).\(personality.rawValue)"
        } else {
            return "statdrop.\(leagueId).\(teamId).\(context.rawValue).\(week).\(personality.rawValue)"
        }
    }

    func getOrGenerateStatDrop(for team: TeamStanding,
                               league: LeagueData,
                               context: StatDropContext,
                               personality: StatDropPersonality,
                               opponent: TeamStanding? = nil,
                               explicitWeek: Int? = nil) -> AttributedString {
        let leagueId = league.id
        let teamId = team.id
        let week = explicitWeek ?? currentWeek(leagueSeason: league.season)
        let key = storageKey(leagueId: leagueId, teamId: teamId, opponentId: opponent?.id, context: context, week: week, personality: personality)

        if let savedData = userDefaults.data(forKey: key),
           let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: savedData) {
            return AttributedString(saved)
        }

        let generated = StatDropAnalysisGenerator.shared.generate(
            for: team,
            league: league,
            week: week,
            context: context,
            personality: personality,
            opponent: opponent,
            explicitWeek: explicitWeek
        )

        let nsAttr = NSAttributedString(generated)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsAttr, requiringSecureCoding: false) {
            userDefaults.set(data, forKey: key)
        }
        return generated
    }

    func clearAll() {
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix("statdrop.") {
            userDefaults.removeObject(forKey: key)
        }
    }
}
