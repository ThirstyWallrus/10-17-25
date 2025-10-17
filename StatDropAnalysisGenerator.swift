//
//  StatDropAnalysisGenerator.swift
//  DynastyStatDrop
//
//  AI-powered, personality-driven stat drop generator.
//  Supports multiple personalities and context-specific analysis (team, offense, defense, full).
//
//  ENHANCEMENTS (v2):
//  - Deeper analysis: Incorporate more stats (position PPW, individual PPW, league comparisons, management breakdowns, records, highs/lows, rivalries).
//  - Personable & comical: Tailor language per personality with puns, exaggerations, motivational quips, sarcasm.
//  - Robustness: Dynamic templates with conditional logic for highs/lows, comparisons; use all available TeamStanding & AggregatedOwnerStats fields.
//  - Creative originality: Vary sentence structures, add unique flair (e.g., analogies, pop culture refs for hype/snarky).
//  - Structure: Break into helpers for stat extraction, phrase building, and assembly.
//  - Fallbacks: Graceful handling for missing data.
//  - Length: FullTeam ~300-500 words; Cards ~100-200 words for brevity.

import Foundation
import SwiftUI

private let offensivePositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
private let defensivePositions: Set<String> = ["DL", "LB", "DB"]
private let offensiveFlexSlots: Set<String> = ["FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE", "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX"]

// MARK: - Stat Drop Personality (Unchanged)

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

// MARK: - Stat Drop Context (Unchanged)

enum StatDropContext: String, Codable {
    case fullTeam    // Full, long-form analysis (MyTeamView, "newspaper")
    case team        // Team-focused, brief (Team Card)
    case offense     // Offense-focused, brief (Offense Card)
    case defense     // Defense-focused, brief (Defense Card)
    // Add more as needed (e.g. matchup, playoff, league, etc.)
}

// MARK: - Focus Enum

enum Focus {
    case offense
    case defense
}

// MARK: - Candidate Struct

struct Candidate {
    let basePos: String
    let fantasy: [String]
    let points: Double
}

// MARK: - TeamStats Struct

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

// MARK: - PreviousWeekStats Struct

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

// MARK: - String Extensions

extension String {
    var capitalizeFirst: String {
        prefix(1).capitalized + dropFirst()
    }

    func rangesOfNumbers() -> [NSRange] {
        var ranges: [NSRange] = []
        let regex = try? NSRegularExpression(pattern: "\\d+\\.?\\d*")
        let matches = regex?.matches(in: self, range: NSRange(location: 0, length: utf16.count))
        for match in matches ?? [] {
            ranges.append(match.range)
        }
        return ranges
    }
}

// MARK: - Enhanced StatDropAnalysisGenerator

@MainActor final class StatDropAnalysisGenerator {
    static let shared = StatDropAnalysisGenerator()

    private init() {}

    /// Main API (Unchanged)
    func generate(for team: TeamStanding,
                  league: LeagueData,
                  week: Int,
                  context: StatDropContext,
                  personality: StatDropPersonality) -> AttributedString {
        switch context {
        case .fullTeam:
            return generateFullTeam(team: team, league: league, week: week, personality: personality)
        case .team:
            return generateTeamCard(team: team, league: league, week: week, personality: personality)
        case .offense:
            return generateOffenseCard(team: team, league: league, week: week, personality: personality)
        case .defense:
            return generateDefenseCard(team: team, league: league, week: week, personality: personality)
        }
    }

    // MARK: - Context-specific Generators (Enhanced)

    private func generateFullTeam(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""

        let stats = extractTeamStats(team: team, league: league)
        let allTime = extractAllTimeStats(ownerId: team.ownerId, league: league)
        let previousWeek = week - 1
        let weekStats = computeWeekStats(team: team, league: league, week: previousWeek)

        analysis += personalityIntro(team: team, week: week, personality: personality, stats: stats)

        analysis += previousWeekBreakdown(weekStats: weekStats, personality: personality)

        analysis += seasonBreakdown(team: team, stats: stats, allTime: allTime, personality: personality)

        analysis += suggestionsAndEncouragement(team: team, personality: personality)

        return formatAttributedString(analysis)
    }

    private func generateTeamCard(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""

        let stats = extractTeamStats(team: team, league: league)
        let previousWeek = week - 1
        let weekStats = computeWeekStats(team: team, league: league, week: previousWeek)

        analysis += personalityIntro(team: team, week: week, personality: personality, stats: stats, isBrief: true)

        analysis += previousWeekBreakdown(weekStats: weekStats, personality: personality, isBrief: true)

        analysis += seasonBreakdown(team: team, stats: stats, allTime: nil, personality: personality, isBrief: true)

        analysis += suggestionsAndEncouragement(team: team, personality: personality, isBrief: true)

        return formatAttributedString(analysis)
    }

    private func generateOffenseCard(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""

        let stats = extractTeamStats(team: team, league: league)
        let previousWeek = week - 1
        let weekStats = computeWeekStats(team: team, league: league, week: previousWeek)

        analysis += offenseIntro(team: team, personality: personality, stats: stats)

        analysis += offenseWeekBreakdown(weekStats: weekStats, personality: personality)

        analysis += offenseSeasonBreakdown(stats: stats, personality: personality)

        analysis += offenseSuggestions(team: team, personality: personality)

        return formatAttributedString(analysis)
    }

    private func generateDefenseCard(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""

        let stats = extractTeamStats(team: team, league: league)
        let previousWeek = week - 1
        let weekStats = computeWeekStats(team: team, league: league, week: previousWeek)

        analysis += defenseIntro(team: team, personality: personality, stats: stats)

        analysis += defenseWeekBreakdown(weekStats: weekStats, personality: personality)

        analysis += defenseSeasonBreakdown(stats: stats, personality: personality)

        analysis += defenseSuggestions(team: team, personality: personality)

        return formatAttributedString(analysis)
    }

    // MARK: - Computation Helpers

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
            return PreviousWeekStats(week: week, actual: actual.total, max: max.total, mgmt: mgmt, offActual: actual.off, offMax: max.off, offMgmt: offMgmt, defActual: actual.def, defMax: max.def, defMgmt: defMgmt, posSums: posSums, leagueRank: rank, numTeams: league.teams.count)
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
                    if offensivePositions.contains(player.position) {
                        off += pts
                    } else if defensivePositions.contains(player.position) {
                        def += pts
                    }
                }
            }
        } else if let pts = team.weeklyActualLineupPoints?[week] {
            total = pts
            // off and def not computable without starters, remain 0
        }

        return (total, off, def)
    }

    private func computeMaxPointsForWeek(team: TeamStanding, league: LeagueData, week: Int) -> (total: Double, off: Double, def: Double) {
        let slots = league.startingLineup
        var candidates: [Candidate] = team.roster.compactMap({ player in
            if let score = player.weeklyScores.first(where: { $0.week == week }) {
                return Candidate(basePos: player.position, fantasy: player.altPositions ?? [], points: score.points)
            }
            return nil
        })

        var used = Set<Int>()
        var totalMax = 0.0
        var offMax = 0.0
        var defMax = 0.0

        for slot in slots {
            var pickIdx: Int? = nil
            var maxP = -1.0
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
                let counted = countedPosition(for: slot, candidatePositions: c.fantasy, base: c.basePos)
                if offensivePositions.contains(counted) {
                    offMax += c.points
                } else if defensivePositions.contains(counted) {
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
                    dict[player.position, default: 0] += score.points
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

    private func isIDPFlex(_ slot: String) -> Bool {
        let u = slot.uppercased()
        return u.contains("IDP") && u != "DL" && u != "LB" && u != "DB"
    }

    private func countedPosition(for slot: String, candidatePositions: [String], base: String) -> String {
        let u = slot.uppercased()
        if ["DL", "LB", "DB"].contains(u) { return u }
        if isIDPFlex(u) || offensiveFlexSlots.contains(u) { return candidatePositions.first ?? base }
        return base
    }

    // MARK: - Extraction Helpers

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

    // MARK: - Phrase Builders

    private func personalityIntro(team: TeamStanding, week: Int, personality: StatDropPersonality, stats: TeamStats, isBrief: Bool = false) -> String {
        let intro = "Week \(week) Stat Drop for \(team.name):"
        switch personality {
        case .classicESPN:
            return "\(intro) Let's dive into the numbers."
        case .hypeMan:
            return "\(intro.uppercased()) LET'S GET HYPED!"
        case .snarkyAnalyst:
            return "\(intro) Buckle up for disappointment."
        case .oldSchoolRadio:
            return "\(intro) Gather 'round the radio, folks."
        case .statGeek:
            return "\(intro) Time for some deep stats."
        case .motivationalCoach:
            return "\(intro) You've got the power!"
        case .britishCommentator:
            return "\(intro) Quite the show."
        case .localNews:
            return "\(intro) Community update."
        case .dramatic:
            return "\(intro) THE DRAMA UNFOLDS!"
        case .robotAI:
            return "\(intro) Initializing analysis."
        }
    }

    private func previousWeekBreakdown(weekStats: PreviousWeekStats?, personality: StatDropPersonality, isBrief: Bool = false) -> String {
        guard let stats = weekStats else { return "\n\nNo data for previous week." }

        let week = stats.week
        let actualStr = String(format: "%.1f", stats.actual)
        let maxStr = String(format: "%.1f", stats.max)
        let mgmtStr = String(format: "%.0f%%", stats.mgmt)
        let rankStr = "\(stats.leagueRank) out of \(stats.numTeams)"
        let topStr = stats.topPos.map { "\($0) shining with \(String(format: "%.1f", $1)) pts" } ?? "no standout position"
        let weakStr = stats.weakPos.map { "\($0) struggling with \(String(format: "%.1f", $1)) pts" } ?? "no weak position"
        let offMgmtStr = String(format: "%.0f%%", stats.offMgmt)
        let defMgmtStr = String(format: "%.0f%%", stats.defMgmt)

        let fullText = "Scored \(actualStr) points out of a possible \(maxStr), for a management efficiency of \(mgmtStr). Offense management \(offMgmtStr), defense \(defMgmtStr). That performance ranked you \(rankStr) in the league. Top position was \(topStr), while weakest was \(weakStr)."

        let briefText = "Week \(week): \(actualStr) pts (\(mgmtStr) mgmt, off \(offMgmtStr), def \(defMgmtStr)), rank \(rankStr). Top: \(topStr); Weak: \(weakStr)."

        let text = isBrief ? briefText : fullText

        switch personality {
        case .classicESPN:
            return "\n\nPrevious Week (Week \(week)): \(text)"
        case .hypeMan:
            return "\n\nWEEK \(week) RECAP: SMASHED \(actualStr) PTS OUTTA \(maxStr)! MGMT \(mgmtStr), OFF \(offMgmtStr), DEF \(defMgmtStr) - BEAST MODE! RANK \(rankStr) - TOP DOG! \(topStr.uppercased()), \(weakStr.uppercased()) - UPGRADE!"
        case .snarkyAnalyst:
            return "\n\nLast week (Week \(week)): Only \(actualStr) when \(maxStr) was possible. \(mgmtStr) management, off \(offMgmtStr), def \(defMgmtStr) - could do better. Ranked \(rankStr). \(topStr) was decent, \(weakStr) was laughable."
        case .oldSchoolRadio:
            return "\n\nIn Week \(week), you tallied \(actualStr) points, potential \(maxStr). Management \(mgmtStr), off \(offMgmtStr), def \(defMgmtStr), rank \(rankStr). \(topStr.capitalizeFirst), \(weakStr)."
        case .statGeek:
            return "\n\nWeek \(week) stats: \(actualStr)/\(maxStr) pts, \(mgmtStr) efficiency (off \(offMgmtStr), def \(defMgmtStr)), rank \(rankStr). Top: \(topStr), bottom: \(weakStr)."
        case .motivationalCoach:
            return "\n\nWeek \(week): Great effort with \(actualStr) pts (\(mgmtStr) mgmt, off \(offMgmtStr), def \(defMgmtStr)), rank \(rankStr). Build on \(topStr), improve \(weakStr)!"
        case .britishCommentator:
            return "\n\nWeek \(week): \(actualStr) points from \(maxStr), \(mgmtStr) management (off \(offMgmtStr), def \(defMgmtStr)). Position \(rankStr). Jolly good \(topStr), a bit off \(weakStr)."
        case .localNews:
            return "\n\nLocal recap for Week \(week): \(actualStr) pts, \(mgmtStr) mgmt (off \(offMgmtStr), def \(defMgmtStr)), rank \(rankStr). Highlights \(topStr), needs work \(weakStr)."
        case .dramatic:
            return "\n\nTHE TRAGEDY OF WEEK \(week): \(actualStr) POINTS AGAINST FATE'S \(maxStr)! \(mgmtStr) DESTINY (OFF \(offMgmtStr), DEF \(defMgmtStr))! RANK \(rankStr)! \(topStr.uppercased()) GLORY, \(weakStr.uppercased()) DESPAIR!"
        case .robotAI:
            return "\n\nWeek \(week) data: Points \(actualStr)/\(maxStr), management \(mgmtStr) (off \(offMgmtStr), def \(defMgmtStr)), rank \(rankStr). Top \(topStr), weak \(weakStr)."
        }
    }

    private func seasonBreakdown(team: TeamStanding, stats: TeamStats, allTime: AggregatedOwnerStats?, personality: StatDropPersonality, isBrief: Bool = false) -> String {
        let standing = stats.leagueStanding
        let record = stats.record
        let mgmt = String(format: "%.0f%%", stats.managementPercent)
        let ppw = String(format: "%.1f", stats.ppw)
        let vsLg = stats.ppw > stats.leagueAvgPpw ? "above league average" : "below league average"
        let streakStr = if let ws = team.winStreak, ws > 1 {
            "on a hot \(ws)-win streak"
        } else if let ls = team.lossStreak, ls > 1 {
            "stuck in a \(ls)-loss rut - time to break free"
        } else { "steady as she goes" }
        let offMgmt = String(format: "%.0f%%", stats.offensiveManagementPercent)
        let offPPW = String(format: "%.1f", stats.offensivePPW)
        let defMgmt = String(format: "%.0f%%", stats.defensiveManagementPercent)
        let defPPW = String(format: "%.1f", stats.defensivePPW)
        let strengths = stats.strengths?.joined(separator: ", ") ?? "none apparent"
        let weaknesses = stats.weaknesses?.joined(separator: ", ") ?? "none glaring"
        let rival = team.biggestRival ?? "yourself"
        let allTimeStr = if let at = allTime {
            "Historically, \(at.championships) championships and a \(at.recordString) record."
        } else { "" }

        let fullText = "Currently \(standing)th in the league with a \(record) record. Overall management at \(mgmt), averaging \(ppw) PPW (\(vsLg)). \(streakStr.capitalizeFirst). Offense running at \(offMgmt) management, \(offPPW) PPW; defense at \(defMgmt), \(defPPW) PPW. Strengths in \(strengths), weaknesses in \(weaknesses). Biggest rival: \(rival). \(allTimeStr)"

        let briefText = "\(standing)th place, \(record), mgmt \(mgmt), PPW \(ppw) (\(vsLg)). \(streakStr). Off \(offPPW)/\(offMgmt), Def \(defPPW)/\(defMgmt). Strengths \(strengths), weaknesses \(weaknesses)."

        let text = isBrief ? briefText : fullText

        switch personality {
        case .classicESPN:
            return "\n\nFull Season Breakdown: \(text)"
        case .hypeMan:
            return "\n\nSEASON SO FAR: \(standing)TH WITH \(record)! MGMT \(mgmt) - CRUSHING! PPW \(ppw) \(vsLg.uppercased())! \(streakStr.uppercased())! OFF \(offPPW) \(offMgmt), DEF \(defPPW) \(defMgmt)! STRENGTHS \(strengths.uppercased()), FIX \(weaknesses.uppercased())! RIVAL \(rival.uppercased())! \(allTimeStr.uppercased())"
        case .snarkyAnalyst:
            return "\n\nSeason summary: Languishing in \(standing)th with \(record). Management \(mgmt) - adequate at best. PPW \(ppw), \(vsLg) - big deal. \(streakStr). Off \(offMgmt), def \(defMgmt) - predictable. Strengths? \(strengths). Weaknesses: \(weaknesses). Rival \(rival)? Please. \(allTimeStr)"
        case .oldSchoolRadio:
            return "\n\nThe season thus far: Holding \(standing)th spot, record \(record). Management \(mgmt), PPW \(ppw) \(vsLg). \(streakStr.capitalizeFirst). Offense \(offPPW) PPW at \(offMgmt), defense \(defPPW) at \(defMgmt). Strong in \(strengths), weak in \(weaknesses). Rival is \(rival). \(allTimeStr)"
        case .statGeek:
            return "\n\nSeason stats: Rank \(standing), record \(record), mgmt \(mgmt)%, PPW \(ppw) (\(vsLg)). Streak: \(streakStr). Off: \(offPPW) PPW \(offMgmt)%, Def: \(defPPW) \(defMgmt)%. Strengths \(strengths), weaknesses \(weaknesses). Rival \(rival). \(allTimeStr)"
        case .motivationalCoach:
            return "\n\nSeason progress: You're in \(standing)th with \(record) - solid foundation! Management \(mgmt), PPW \(ppw) \(vsLg). \(streakStr.capitalizeFirst) - keep the fire! Offense \(offPPW) at \(offMgmt), defense \(defPPW) at \(defMgmt). Lean on strengths \(strengths), address \(weaknesses). Rival \(rival) - beat 'em! \(allTimeStr)"
        case .britishCommentator:
            return "\n\nSeason to date: Position \(standing), record \(record). Management \(mgmt), PPW \(ppw) \(vsLg). \(streakStr). Offence \(offPPW) at \(offMgmt), defence \(defPPW) at \(defMgmt). Strong points \(strengths), weak spots \(weaknesses). Rival \(rival). \(allTimeStr)"
        case .localNews:
            return "\n\nCommunity season update: \(standing)th place, \(record) record. Mgmt \(mgmt), \(ppw) PPW \(vsLg). \(streakStr). Off \(offPPW) \(offMgmt), Def \(defPPW) \(defMgmt). Strengths \(strengths), work on \(weaknesses). Local rival \(rival). \(allTimeStr)"
        case .dramatic:
            return "\n\nTHE GRAND SEASON EPIC: THRONE AT \(standing)TH, RECORD \(record)! MGMT \(mgmt) - FATE'S HAND! PPW \(ppw) \(vsLg.uppercased())! \(streakStr.uppercased())! OFFENSE SAGA \(offPPW) \(offMgmt), DEFENSE LEGEND \(defPPW) \(defMgmt)! STRENGTHS \(strengths.uppercased()), WEAKNESSES \(weaknesses.uppercased())! RIVAL NEMESIS \(rival.uppercased())! \(allTimeStr.uppercased())"
        case .robotAI:
            return "\n\nSeason data: Rank \(standing), record \(record), management \(mgmt)%, PPW \(ppw) (\(vsLg)). Streak \(streakStr). Off \(offPPW) \(offMgmt)%, Def \(defPPW) \(defMgmt)%. Strengths \(strengths), weaknesses \(weaknesses). Rival \(rival). \(allTimeStr)"
        }
    }

    private func suggestionsAndEncouragement(team: TeamStanding, personality: StatDropPersonality, isBrief: Bool = false) -> String {
        let standing = team.leagueStanding
        let weaknesses = team.weaknesses?.joined(separator: ", ") ?? ""
        let suggestion = !weaknesses.isEmpty ? "Hit the waivers or make trades for \(weaknesses) to bolster your roster." : "Your team looks balanced - maintain the course."
        let encouragement = standing <= (team.league?.teams.count ?? 12) / 2 ? "You're in contention - push for the playoffs!" : "Plenty of games left - stage a comeback!"
        let fullText = "\(suggestion) \(encouragement)"
        let briefText = "\(suggestion) \(encouragement)"

        let text = isBrief ? briefText : fullText

        switch personality {
        case .classicESPN:
            return "\n\nLooking ahead: \(text)"
        case .hypeMan:
            return "\n\nNEXT MOVES: GRAB WAIVERS/TRADES FOR \(weaknesses.uppercased()) - LEVEL UP! \(encouragement.uppercased()) GO GET 'EM!"
        case .snarkyAnalyst:
            return "\n\nSuggestions: \(suggestion) As if that'll help. \(encouragement) Or don't, whatever."
        case .oldSchoolRadio:
            return "\n\nForward thinking: \(suggestion) \(encouragement) Like the good old days."
        case .statGeek:
            return "\n\nOptimal moves: \(suggestion) \(encouragement) Statistically speaking."
        case .motivationalCoach:
            return "\n\nGame plan: \(suggestion) \(encouragement) You can do it!"
        case .britishCommentator:
            return "\n\nRecommendations: \(suggestion) \(encouragement) Cheerio."
        case .localNews:
            return "\n\nCommunity tips: \(suggestion) \(encouragement) Stay strong."
        case .dramatic:
            return "\n\nTHE CLIMAX APPROACHES: \(suggestion.uppercased())! \(encouragement.uppercased()) DESTINY AWAITS!"
        case .robotAI:
            return "\n\nComputed advice: \(suggestion) \(encouragement)"
        }
    }

    private func offenseWeekBreakdown(weekStats: PreviousWeekStats?, personality: StatDropPersonality) -> String {
        guard let stats = weekStats else { return "" }

        let week = stats.week
        let actualStr = String(format: "%.1f", stats.offActual)
        let mgmtStr = String(format: "%.0f%%", stats.offMgmt)
        let topStr = stats.topOffPos.map { "\($0) with \(String(format: "%.1f", $1)) pts" } ?? "no standout"
        let weakStr = stats.weakOffPos.map { "\($0) with \(String(format: "%.1f", $1)) pts" } ?? "no weak"

        let text = "Offense scored \(actualStr) points, management \(mgmtStr). Top \(topStr), weak \(weakStr)."

        switch personality {
        case .classicESPN:
            return "\nPrevious Week Offense (Week \(week)): \(text)"
        case .hypeMan:
            return "\nOFF WEEK \(week): \(actualStr) PTS, \(mgmtStr) MGMT! TOP \(topStr.uppercased()), FIX \(weakStr.uppercased())!"
        case .snarkyAnalyst:
            return "\nOffense last week: \(actualStr) pts, \(mgmtStr). \(topStr) okay, \(weakStr) pathetic."
        case .oldSchoolRadio:
            return "\nOffense in Week \(week): \(text)"
        case .statGeek:
            return "\nOffense Week \(week): \(actualStr) pts, \(mgmtStr). Top \(topStr), bottom \(weakStr)."
        case .motivationalCoach:
            return "\nOffense Week \(week): \(actualStr) pts, \(mgmtStr). Build on \(topStr), improve \(weakStr)!"
        case .britishCommentator:
            return "\nOffence Week \(week): \(text)"
        case .localNews:
            return "\nLocal offense Week \(week): \(text)"
        case .dramatic:
            return "\nOFFENSE DRAMA WEEK \(week): \(actualStr) PTS, \(mgmtStr)! \(topStr.uppercased()), \(weakStr.uppercased())!"
        case .robotAI:
            return "\nOffense Week \(week): \(actualStr) pts, \(mgmtStr). Top \(topStr), weak \(weakStr)."
        }
    }

    private func defenseWeekBreakdown(weekStats: PreviousWeekStats?, personality: StatDropPersonality) -> String {
        guard let stats = weekStats else { return "" }

        let week = stats.week
        let actualStr = String(format: "%.1f", stats.defActual)
        let mgmtStr = String(format: "%.0f%%", stats.defMgmt)
        let topStr = stats.topDefPos.map { "\($0) with \(String(format: "%.1f", $1)) pts" } ?? "no standout"
        let weakStr = stats.weakDefPos.map { "\($0) with \(String(format: "%.1f", $1)) pts" } ?? "no weak"

        let text = "Defense scored \(actualStr) points, management \(mgmtStr). Top \(topStr), weak \(weakStr)."

        switch personality {
        case .classicESPN:
            return "\nPrevious Week Defense (Week \(week)): \(text)"
        case .hypeMan:
            return "\nDEF WEEK \(week): \(actualStr) PTS, \(mgmtStr) MGMT! TOP \(topStr.uppercased()), FIX \(weakStr.uppercased())!"
        case .snarkyAnalyst:
            return "\nDefense last week: \(actualStr) pts, \(mgmtStr). \(topStr) passable, \(weakStr) disastrous."
        case .oldSchoolRadio:
            return "\nDefense in Week \(week): \(text)"
        case .statGeek:
            return "\nDefense Week \(week): \(actualStr) pts, \(mgmtStr). Top \(topStr), bottom \(weakStr)."
        case .motivationalCoach:
            return "\nDefense Week \(week): \(actualStr) pts, \(mgmtStr). Strengthen \(weakStr), celebrate \(topStr)!"
        case .britishCommentator:
            return "\nDefence Week \(week): \(text)"
        case .localNews:
            return "\nLocal defense Week \(week): \(text)"
        case .dramatic:
            return "\nDEFENSE EPIC WEEK \(week): \(actualStr) PTS, \(mgmtStr)! \(topStr.uppercased()), \(weakStr.uppercased())!"
        case .robotAI:
            return "\nDefense Week \(week): \(actualStr) pts, \(mgmtStr). Top \(topStr), weak \(weakStr)."
        }
    }

    private func offenseSeasonBreakdown(stats: TeamStats, personality: StatDropPersonality) -> String {
        let mgmt = String(format: "%.0f%%", stats.offensiveManagementPercent)
        let ppw = String(format: "%.1f", stats.offensivePPW)
        let strengths = stats.offensiveStrengths?.joined(separator: ", ") ?? "--"
        let weaknesses = stats.offensiveWeaknesses?.joined(separator: ", ") ?? "--"

        let text = "Offense management \(mgmt), PPW \(ppw). Strengths \(strengths), weaknesses \(weaknesses)."

        switch personality {
        case .classicESPN:
            return "\nSeason Offense: \(text)"
        case .hypeMan:
            return "\nOFF SEASON: MGMT \(mgmt), PPW \(ppw)! STRENGTHS \(strengths.uppercased()), FIX \(weaknesses.uppercased())!"
        case .snarkyAnalyst:
            return "\nOffense season: \(mgmt) mgmt, \(ppw) PPW. Strengths \(strengths)? Sure. Weaknesses \(weaknesses) - obvious."
        case .oldSchoolRadio:
            return "\nOffense season: \(text)"
        case .statGeek:
            return "\nOffense season: \(mgmt)%, \(ppw) PPW. Strengths \(strengths), weaknesses \(weaknesses)."
        case .motivationalCoach:
            return "\nOffense season: \(mgmt) mgmt, \(ppw) PPW. Capitalize on \(strengths), improve \(weaknesses)!"
        case .britishCommentator:
            return "\nOffence season: \(text)"
        case .localNews:
            return "\nLocal offense season: \(text)"
        case .dramatic:
            return "\nOFFENSE SEASON SAGA: \(mgmt) MGMT, \(ppw) PPW! STRENGTHS \(strengths.uppercased()), WEAKNESSES \(weaknesses.uppercased())!"
        case .robotAI:
            return "\nOffense season: \(mgmt)%, \(ppw) PPW. Strengths \(strengths), weaknesses \(weaknesses)."
        }
    }

    private func defenseSeasonBreakdown(stats: TeamStats, personality: StatDropPersonality) -> String {
        let mgmt = String(format: "%.0f%%", stats.defensiveManagementPercent)
        let ppw = String(format: "%.1f", stats.defensivePPW)
        let strengths = stats.defensiveStrengths?.joined(separator: ", ") ?? "--"
        let weaknesses = stats.defensiveWeaknesses?.joined(separator: ", ") ?? "--"

        let text = "Defense management \(mgmt), PPW \(ppw). Strengths \(strengths), weaknesses \(weaknesses)."

        switch personality {
        case .classicESPN:
            return "\nSeason Defense: \(text)"
        case .hypeMan:
            return "\nDEF SEASON: MGMT \(mgmt), PPW \(ppw)! STRENGTHS \(strengths.uppercased()), FIX \(weaknesses.uppercased())!"
        case .snarkyAnalyst:
            return "\nDefense season: \(mgmt) mgmt, \(ppw) PPW. Strengths \(strengths), weaknesses \(weaknesses) - shocking."
        case .oldSchoolRadio:
            return "\nDefense season: \(text)"
        case .statGeek:
            return "\nDefense season: \(mgmt)%, \(ppw) PPW. Strengths \(strengths), weaknesses \(weaknesses)."
        case .motivationalCoach:
            return "\nDefense season: \(mgmt) mgmt, \(ppw) PPW. Fortify \(weaknesses), celebrate \(strengths)!"
        case .britishCommentator:
            return "\nDefence season: \(text)"
        case .localNews:
            return "\nLocal defense season: \(text)"
        case .dramatic:
            return "\nDEFENSE SEASON LEGEND: \(mgmt) MGMT, \(ppw) PPW! STRENGTHS \(strengths.uppercased()), WEAKNESSES \(weaknesses.uppercased())!"
        case .robotAI:
            return "\nDefense season: \(mgmt)%, \(ppw) PPW. Strengths \(strengths), weaknesses \(weaknesses)."
        }
    }

    private func offenseSuggestions(team: TeamStanding, personality: StatDropPersonality) -> String {
        let weaknesses = team.offensiveWeaknesses?.joined(separator: ", ") ?? ""
        let suggestion = !weaknesses.isEmpty ? "Scout waivers or trades for \(weaknesses) to amp up offense." : "Offense solid - keep rolling."

        switch personality {
        case .classicESPN:
            return "\nOffense Tips: \(suggestion)"
        case .hypeMan:
            return "\nOFF BOOST: GRAB \(weaknesses.uppercased()) FROM WAIVERS/TRADES - EXPLODE!"
        case .snarkyAnalyst:
            return "\nOffense advice: \(suggestion) Or don't, stay mediocre."
        case .oldSchoolRadio:
            return "\nOffense suggestions: \(suggestion)"
        case .statGeek:
            return "\nOffense optimization: \(suggestion)"
        case .motivationalCoach:
            return "\nOffense plan: \(suggestion) Go for it!"
        case .britishCommentator:
            return "\nOffence recommendations: \(suggestion)"
        case .localNews:
            return "\nLocal offense tips: \(suggestion)"
        case .dramatic:
            return "\nOFFENSE QUEST: \(suggestion.uppercased()) - CONQUER!"
        case .robotAI:
            return "\nOffense compute: \(suggestion)"
        }
    }

    private func defenseSuggestions(team: TeamStanding, personality: StatDropPersonality) -> String {
        let weaknesses = team.defensiveWeaknesses?.joined(separator: ", ") ?? ""
        let suggestion = !weaknesses.isEmpty ? "Target waivers or trades for \(weaknesses) to lock down defense." : "Defense strong - maintain."

        switch personality {
        case .classicESPN:
            return "\nDefense Tips: \(suggestion)"
        case .hypeMan:
            return "\nDEF LOCK: SNAG \(weaknesses.uppercased()) WAIVERS/TRADES - IMPENETRABLE!"
        case .snarkyAnalyst:
            return "\nDefense advice: \(suggestion) If you must."
        case .oldSchoolRadio:
            return "\nDefense suggestions: \(suggestion)"
        case .statGeek:
            return "\nDefense optimization: \(suggestion)"
        case .motivationalCoach:
            return "\nDefense plan: \(suggestion) Stay tough!"
        case .britishCommentator:
            return "\nDefence recommendations: \(suggestion)"
        case .localNews:
            return "\nLocal defense tips: \(suggestion)"
        case .dramatic:
            return "\nDEFENSE ODYSSEY: \(suggestion.uppercased()) - UNBREAKABLE!"
        case .robotAI:
            return "\nDefense compute: \(suggestion)"
        }
    }

    private func offenseIntro(team: TeamStanding, personality: StatDropPersonality, stats: TeamStats) -> String {
        switch personality {
        case .classicESPN:
            return "Offense Stat Drop for \(team.name): Let's break it down."
        case .hypeMan:
            return "OFFENSE HYPE FOR \(team.name.uppercased())!"
        case .snarkyAnalyst:
            return "Offense for \(team.name): Don't get too excited."
        case .oldSchoolRadio:
            return "Offense report for \(team.name), folks."
        case .statGeek:
            return "Offense stats deep dive for \(team.name)."
        case .motivationalCoach:
            return "Offense analysis for \(team.name) - let's improve!"
        case .britishCommentator:
            return "Offence overview for \(team.name)."
        case .localNews:
            return "Local offense update for \(team.name)."
        case .dramatic:
            return "THE EPIC OFFENSE OF \(team.name.uppercased())!"
        case .robotAI:
            return "Processing offense for \(team.name)."
        }
    }

    private func defenseIntro(team: TeamStanding, personality: StatDropPersonality, stats: TeamStats) -> String {
        switch personality {
        case .classicESPN:
            return "Defense Stat Drop for \(team.name): Let's analyze."
        case .hypeMan:
            return "DEFENSE HYPE FOR \(team.name.uppercased())!"
        case .snarkyAnalyst:
            return "Defense for \(team.name): Holes everywhere."
        case .oldSchoolRadio:
            return "Defense report for \(team.name), listeners."
        case .statGeek:
            return "Defense stats breakdown for \(team.name)."
        case .motivationalCoach:
            return "Defense analysis for \(team.name) - strengthen up!"
        case .britishCommentator:
            return "Defence overview for \(team.name)."
        case .localNews:
            return "Local defense update for \(team.name)."
        case .dramatic:
            return "THE MIGHTY DEFENSE OF \(team.name.uppercased())!"
        case .robotAI:
            return "Processing defense for \(team.name)."
        }
    }

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

import SwiftUI

struct StatDropAnalysisBox: View {
    let team: TeamStanding
    let league: LeagueData
    let context: StatDropContext
    let personality: StatDropPersonality

    var body: some View {
        let attributed = StatDropPersistence.shared.getOrGenerateStatDrop(
            for: team,
            league: league,
            context: context,
            personality: personality
        )
        VStack(alignment: .leading, spacing: 8) {
            Text(context == .fullTeam ? "Weekly Stat Drop" : "Stat Drop Analysis")
                .font(.headline)
                .foregroundColor(.yellow)
            Text(attributed)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.13))
        )
        .padding(.vertical, 4)
    }
}


import Foundation

/// Helper for persisting and scheduling weekly Stat Drop analysis.
@MainActor final class StatDropPersistence {
    static let shared = StatDropPersistence()
    private let userDefaults = UserDefaults.standard

    /// The scheduled drop day for a new week (e.g. Tuesday).
    /// You can customize this or make it dynamic per-league if you wish.
    static var weeklyDropWeekday: Int { 3 } // 1 = Sunday, 2 = Monday, 3 = Tuesday...
    static var dropHour: Int { 9 } // 9am UTC

    private init() {}

    /// Returns the current NFL/fantasy week number (1-18) based on the date and league season.
    /// Assumes season starts on first Thursday in September of the league year.
    /// Adjusts for the weekly drop (e.g., Tuesday reflects the just-completed week).
    func currentWeek(for date: Date = Date(), leagueSeason: String) -> Int {
        guard let year = Int(leagueSeason) else { return 1 } // Fallback if season not numeric

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)! // UTC

        // Find first Thursday in September of the year
        var septFirst = DateComponents(year: year, month: 9, day: 1)
        let septFirstDate = calendar.date(from: septFirst)!

        var seasonStart = septFirstDate
        var weekday = calendar.component(.weekday, from: seasonStart)
        while weekday != 5 { // 5 = Thursday (Sunday=1)
            seasonStart = calendar.date(byAdding: .day, value: 1, to: seasonStart)!
            weekday = calendar.component(.weekday, from: seasonStart)
        }

        // Days since season start
        let daysSinceStart = calendar.dateComponents([.day], from: seasonStart, to: date).day ?? 0

        // Raw week = (days // 7) + 1, but cap at 18
        var rawWeek = (daysSinceStart / 7) + 1
        if rawWeek > 18 { rawWeek = 18 }
        if rawWeek < 1 { rawWeek = 1 }

        // Adjust for drop schedule: If before Tuesday 9am of the current NFL week, use previous week
        let adjustedDate = adjustedDateForDrop(date)
        let adjustedDays = calendar.dateComponents([.day], from: seasonStart, to: adjustedDate).day ?? 0
        let adjustedWeek = (adjustedDays / 7) + 1

        return min(max(adjustedWeek, 1), 18)
    }

    /// Adjusts a date to the latest scheduled drop (e.g. most recent Tuesday 9am).
    private func adjustedDateForDrop(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let weekStart = calendar.date(from: components)!
        // Find this week's Tuesday 9am
        let dropDate = calendar.date(byAdding: .day, value: StatDropPersistence.weeklyDropWeekday - 1, to: weekStart)!
        let dropDateWithHour = calendar.date(bySettingHour: StatDropPersistence.dropHour, minute: 0, second: 0, of: dropDate)!
        // If current date is before this drop, go back one week
        if date < dropDateWithHour {
            return calendar.date(byAdding: .weekOfYear, value: -1, to: dropDateWithHour)!
        }
        return dropDateWithHour
    }

    /// Key for storing/retrieving stat drops. Uniqueness: (league, team, context, week, personality)
    private func storageKey(leagueId: String, teamId: String, context: StatDropContext, week: Int, personality: StatDropPersonality) -> String {
        "statdrop.\(leagueId).\(teamId).\(context.rawValue).\(week).\(personality.rawValue)"
    }

    /// Retrieves the persisted stat drop for this week, or generates and saves a new one if not present.
    func getOrGenerateStatDrop(for team: TeamStanding,
                               league: LeagueData,
                               context: StatDropContext,
                               personality: StatDropPersonality) -> AttributedString {
        let leagueId = league.id
        let teamId = team.id
        let week = currentWeek(leagueSeason: league.season)
        let key = storageKey(leagueId: leagueId, teamId: teamId, context: context, week: week, personality: personality)

        if let savedData = userDefaults.data(forKey: key),
           let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: savedData) {
            return AttributedString(saved)
        }

        let generated = StatDropAnalysisGenerator.shared.generate(
            for: team,
            league: league,
            week: week,
            context: context,
            personality: personality
        )
        // Persist it (as NSAttributedString)
        let nsAttr = NSAttributedString(generated)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsAttr, requiringSecureCoding: false) {
            userDefaults.set(data, forKey: key)
        }
        return generated
    }

    /// Clears all persisted stat drops (for debugging or force refresh).
    func clearAll() {
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix("statdrop.") {
            userDefaults.removeObject(forKey: key)
        }
    }
}
