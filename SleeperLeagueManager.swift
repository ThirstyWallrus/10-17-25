//
//  SleeperLeagueManager.swift
//  DynastyStatDrop
//
//  FULL FILE — PATCHED: Robust week/team matchup data population for per-week views.
//  Change: fetchMatchupsByWeek now ensures all teams have a MatchupEntry for every week.
//  No code truncated or removed; patch is additive and continuity-safe.
//

import Foundation
import SwiftUI

// MARK: - Import PositionNormalizer for canonical defensive position mapping
import Foundation

// Ensure PositionNormalizer is available to all code in this file.
import Foundation

// MARK: - Raw Sleeper API Models

struct SleeperUser: Codable {
    let user_id: String
    let username: String?
    let display_name: String?
}

// MARK: - Matchup Entry (from Sleeper matchups endpoint)
struct MatchupEntry: Codable, Equatable {
    let roster_id: Int
    let matchup_id: Int?
    let points: Double?
    let players_points: [String: Double]?
    let players_projected_points: [String: Double]?
    let starters: [String]?
    let players: [String]?
}

struct SleeperRoster: Codable {
    let roster_id: Int
    let owner_id: String?
    let players: [String]?
    let starters: [String]?
    let settings: [String: AnyCodable]?
}

struct AnyCodable: Codable, Equatable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode([AnyCodable].self) { value = v.map { $0.value } }
        else if let v = try? c.decode([String: AnyCodable].self) { value = v.mapValues { $0.value } }
        else { value = "" }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as Bool: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as [Any]:
            try c.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]:
            try c.encode(v.mapValues { AnyCodable($0) })
        default:
            try c.encode(String(describing: value))
        }
    }
    static func ==(lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

struct RawSleeperPlayer: Codable, Equatable {
    let player_id: String
    let full_name: String?
    let position: String?
    let fantasy_positions: [String]?
}

struct SleeperLeague: Codable {
    let league_id: String
    let name: String?
    let season: String?
    let roster_positions: [String]?
    let settings: [String: AnyCodable]?

    var scoringType: String {
        guard let scoring = settings?["scoring_settings"]?.value as? [String: AnyCodable],
              let rec = scoring["rec"]?.value as? Double else { return "custom" }
        if rec == 1.0 { return "ppr" }
        if rec == 0.5 { return "half_ppr" }
        if rec == 0.0 { return "standard" }
        return "custom"
    }

    var currentWeek: Int {
        if let w = settings?["week"]?.value as? Int {
            return w
        }
        return 1
    }
}

struct SleeperTransaction: Codable {
    let transaction_id: String
    let type: String?
    let status: String?
    let roster_ids: [Int]?
    let waiver_bid: Int?
}

// MARK: - Disk Persistence Support

private struct LeagueIndexEntry: Codable, Equatable {
    let id: String
    let name: String
    let season: String
    let lastUpdated: Date
}

// MARK: - Position Normalizer (Global Patch)
import Foundation

@MainActor
class SleeperLeagueManager: ObservableObject {

    @Published var leagues: [LeagueData] = []
    @Published var playoffStartWeek: Int = 14
    @Published var leaguePlayoffStartWeeks: [String: Int] = [:]
    @Published var isRefreshing: Bool = false

    private var activeUsername: String = "global"
    private let legacySingleFilePrefix = "leagues_"
    private let legacyFilename = "leagues.json"
    private let oldUDKey: String? = nil
    private let rootFolderName = "SleeperLeagues"
    private let indexFileName = "index.json"
    private var indexEntries: [LeagueIndexEntry] = []
    var playerCache: [String: RawSleeperPlayer]? = nil
    var allPlayers: [String: RawSleeperPlayer] = [:]
    private var transactionsCache: [String: [SleeperTransaction]] = [:]
    private var usersCache: [String: [SleeperUser]] = [:]
    private var rostersCache: [String: [SleeperRoster]] = [:]

    private let offensivePositions: Set<String> = ["QB","RB","WR","TE","K"]
    private let defensivePositions: Set<String> = ["DL","LB","DB"]
    private let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]

    private static var _lastRefresh: [String: Date] = [:]
    private var refreshThrottleInterval: TimeInterval { 10 * 60 } // 10 minutes

    var weekRosterMatchupMap: [Int: [Int: Int]] = [:]

    init(autoLoad: Bool = false) {
        if autoLoad {
            loadLeaguesWithMigrationIfNeeded(for: activeUsername)
        }
    }

    private func userRootDir(_ user: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(rootFolderName, isDirectory: true).appendingPathComponent(user, isDirectory: true)
    }

    private func ensureUserDir() {
        var dir = userRootDir(activeUsername)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try? dir.setResourceValues(rv)
        }
    }

    private func clearCaches() {
        playerCache = nil
        allPlayers = [:]
        transactionsCache = [:]
        usersCache = [:]
        rostersCache = [:]
    }

    private func leagueFileURL(_ leagueId: String) -> URL {
        userRootDir(activeUsername).appendingPathComponent("\(leagueId).json")
    }

    private func indexFileURL() -> URL {
        userRootDir(activeUsername).appendingPathComponent(indexFileName)
    }

    func setActiveUser(username: String) {
        saveLeagues()
        activeUsername = username.isEmpty ? "global" : username
        loadLeaguesWithMigrationIfNeeded(for: activeUsername)
    }

    func clearInMemory() {
        leagues.removeAll()
        indexEntries.removeAll()
    }

    private func loadLeaguesWithMigrationIfNeeded(for user: String) {
        ensureUserDir()
        migrateLegacySingleFileIfNeeded(for: user)
        migrateLegacyUserDefaultsIfNeeded(for: user)
        loadIndex()
        loadAllLeagueFiles()
    }

    private func migrateLegacySingleFileIfNeeded(for user: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let legacyPath = docs.appendingPathComponent("\(legacySingleFilePrefix)\(user).json")
        guard FileManager.default.fileExists(atPath: legacyPath.path) else {
            let fallback = docs.appendingPathComponent(legacyFilename)
            guard FileManager.default.fileExists(atPath: fallback.path) else { return }
            migrateSingleFile(fallback)
            return
        }
        migrateSingleFile(legacyPath)
    }

    private func migrateSingleFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let old = try? JSONDecoder().decode([LeagueData].self, from: data),
              !old.isEmpty else { return }
        print("[LeagueMigration] Migrating \(old.count) leagues from single file \(url.lastPathComponent)")
        ensureUserDir()
        for lg in old {
            persistLeagueFile(lg)
        }
        rebuildIndexFromDisk()
        try? FileManager.default.removeItem(at: url)
        saveIndex()
    }

    private func migrateLegacyUserDefaultsIfNeeded(for user: String) {
        guard let key = oldUDKey else { return }
        let ud = UserDefaults.standard
        guard let data = ud.data(forKey: key),
              let old = try? JSONDecoder().decode([LeagueData].self, from: data),
              !old.isEmpty else { return }
        print("[LeagueMigration] Migrating \(old.count) leagues from UserDefaults key '\(key)'")
        ensureUserDir()
        for lg in old { persistLeagueFile(lg) }
        rebuildIndexFromDisk()
        ud.removeObject(forKey: key)
        saveIndex()
    }

    private func loadIndex() {
        let url = indexFileURL()
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([LeagueIndexEntry].self, from: data) else {
            indexEntries = []
            return
        }
        indexEntries = arr
    }

    private func saveIndex() {
        ensureUserDir()
        guard let data = try? JSONEncoder().encode(indexEntries) else { return }
        try? data.write(to: indexFileURL(), options: .atomic)
    }

    private func upsertIndex(for league: LeagueData) {
        let entry = LeagueIndexEntry(id: league.id,
                                     name: league.name,
                                     season: league.season,
                                     lastUpdated: Date())
        if let i = indexEntries.firstIndex(where: { $0.id == entry.id }) {
            indexEntries[i] = entry
        } else {
            indexEntries.append(entry)
        }
    }

    private func rebuildIndexFromDisk() {
        var newEntries: [LeagueIndexEntry] = []
        let dir = userRootDir(activeUsername)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" && f.lastPathComponent != indexFileName {
            if let data = try? Data(contentsOf: f),
               let lg = try? JSONDecoder().decode(LeagueData.self, from: data) {
                let e = LeagueIndexEntry(id: lg.id, name: lg.name, season: lg.season, lastUpdated: Date())
                newEntries.append(e)
            }
        }
        indexEntries = newEntries
    }

    private func persistLeagueFile(_ league: LeagueData) {
        ensureUserDir()
        if let data = try? JSONEncoder().encode(league) {
            try? data.write(to: leagueFileURL(league.id), options: .atomic)
            upsertIndex(for: league)
        }
    }

    private func loadLeagueFile(id: String) -> LeagueData? {
        let url = leagueFileURL(id)
        guard let data = try? Data(contentsOf: url),
              let lg = try? JSONDecoder().decode(LeagueData.self, from: data) else { return nil }
        if lg.allTimeOwnerStats == nil {
            return AllTimeAggregator.buildAllTime(for: lg, playerCache: allPlayers)
        }
        return lg
    }

    private func loadAllLeagueFiles() {
        leagues = indexEntries.compactMap { loadLeagueFile(id: $0.id) }
        leagues.forEach { DatabaseManager.shared.saveLeague($0) }
    }

    // PATCH: Helper to get valid weeks for season stat aggregation

    private func validWeeksForSeason(_ season: SeasonData, currentWeek: Int) -> [Int] {
        let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
        return allWeeks.filter { $0 < currentWeek }
    }

    // Public Import

    func fetchAndImportSingleLeague(leagueId: String, username: String) async throws {
        clearCaches()
        let user = try await fetchUser(username: username)
        let baseLeague = try await fetchLeague(leagueId: leagueId)
        let playoffStart = extractPlayoffStartWeek(from: baseLeague)
        leaguePlayoffStartWeeks[leagueId] = playoffStart
        playoffStartWeek = playoffStart
        var leagueData = try await fetchAllSeasonsForLeague(league: baseLeague, userId: user.user_id, playoffStartWeek: playoffStart)
        leagueData = AllTimeAggregator.buildAllTime(for: leagueData, playerCache: allPlayers)

        await MainActor.run {
            if let idx = leagues.firstIndex(where: { $0.id == leagueData.id }) {
                leagues[idx] = leagueData
            } else {
                leagues.append(leagueData)
            }
            persistLeagueFile(leagueData)
            saveIndex()
            DatabaseManager.shared.saveLeague(leagueData)
        }
    }

    private func fetchLeague(leagueId: String) async throws -> SleeperLeague {
        let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SleeperLeague.self, from: data)
    }

    func fetchUser(username: String) async throws -> SleeperUser {
        let url = URL(string: "https://api.sleeper.app/v1/user/\(username)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SleeperUser.self, from: data)
    }

    func fetchLeagues(userId: String, season: String) async throws -> [SleeperLeague] {
        let url = URL(string: "https://api.sleeper.app/v1/user/\(userId)/leagues/nfl/\(season)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([SleeperLeague].self, from: data)
    }

    private func fetchRosters(leagueId: String) async throws -> [SleeperRoster] {
        if let cached = rostersCache[leagueId] { return cached }
        let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)/rosters")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let rosters = try JSONDecoder().decode([SleeperRoster].self, from: data)
        rostersCache[leagueId] = rosters
        return rosters
    }

    private func fetchLeagueUsers(leagueId: String) async throws -> [SleeperUser] {
        if let cached = usersCache[leagueId] { return cached }
        let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)/users")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let users = try JSONDecoder().decode([SleeperUser].self, from: data)
        usersCache[leagueId] = users
        return users
    }

    private func fetchPlayersDict() async throws -> [String: RawSleeperPlayer] {
        if playerCache == nil {
            let url = URL(string: "https://api.sleeper.app/v1/players/nfl")!
            let (data, _) = try await URLSession.shared.data(from: url)
            playerCache = try? JSONDecoder().decode([String: RawSleeperPlayer].self, from: data)
        }
        return playerCache ?? [:]
    }

    private func fetchPlayers(ids: [String]) async throws -> [RawSleeperPlayer] {
        if allPlayers.isEmpty {
            allPlayers = try await fetchPlayersDict()
        }
        return ids.compactMap { allPlayers[$0] }
    }

    // --- PATCHED: Ensure every team has a matchup entry for every week played ---
    private func fetchMatchupsByWeek(leagueId: String) async throws -> [Int: [MatchupEntry]] {
        var out: [Int: [MatchupEntry]] = [:]
        var allRosterIds: Set<Int> = []

        // First, try to fetch all matchups for each week
        for week in 1...18 {
            let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)/matchups/\(week)")!
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let entries = try? JSONDecoder().decode([MatchupEntry].self, from: data),
               !entries.isEmpty {
                out[week] = entries
                allRosterIds.formUnion(entries.map { $0.roster_id })
            }
        }

        // PATCH: Find all roster IDs across all weeks
        if allRosterIds.isEmpty {
            // Fallback: get roster IDs from rosters endpoint if not set
            let rosters = try? await fetchRosters(leagueId: leagueId)
            if let rosters = rosters {
                allRosterIds = Set(rosters.map { $0.roster_id })
            }
        }

        // PATCH: For every week, ensure every roster_id has a MatchupEntry
        for week in 1...18 {
            let entries = out[week] ?? []
            let existingIds = Set(entries.map { $0.roster_id })
            let missingIds = allRosterIds.subtracting(existingIds)
            var completedEntries = entries

            // For each missing team/roster, add a blank entry so UI always has week data
            for rid in missingIds {
                completedEntries.append(
                    MatchupEntry(
                        roster_id: rid,
                        matchup_id: week,
                        points: 0.0,
                        players_points: [:],
                        players_projected_points: [:],
                        starters: [],
                        players: []
                    )
                )
            }
            out[week] = completedEntries
        }

        return out
    }

    private func fetchTransactions(for leagueId: String) async throws -> [SleeperTransaction] {
        if let cached = transactionsCache[leagueId] { return cached }
        var txs: [SleeperTransaction] = []
        for week in 1...18 {
            let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)/transactions/\(week)")!
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let parsed = try? JSONDecoder().decode([SleeperTransaction].self, from: data),
               !parsed.isEmpty {
                txs.append(contentsOf: parsed)
            }
        }
        transactionsCache[leagueId] = txs
        return txs
    }

    private func extractPlayoffStartWeek(from league: SleeperLeague) -> Int {
        if let settings = league.settings,
           let val = settings["playoff_start_week"]?.value as? Int {
            return min(max(13, val), 18)
        }
        return 14
    }

    func setPlayoffStartWeek(_ week: Int) { playoffStartWeek = max(13, min(18, week)) }


    // --- PATCHED SECTION: Robust position assignment for per-season PPW/individualPPW ---
    private func buildTeams(
        leagueId: String,
        rosters: [SleeperRoster],
        users: [SleeperUser],
        parentLeague: LeagueData?,
        lineupPositions: [String],
        transactions: [SleeperTransaction],
        playoffStartWeek: Int,
        matchupsByWeek: [Int: [MatchupEntry]],
        sleeperLeague: SleeperLeague
    ) async throws -> [TeamStanding] {

        let userDisplay: [String: String] = users.reduce(into: [:]) { dict, u in
            let disp = (u.display_name ?? u.username ?? "").trimmingCharacters(in: .whitespaces)
            dict[u.user_id] = disp.isEmpty ? "Owner \(u.user_id)" : disp
        }

        let nonStartingTokens: Set<String> = ["BN","BENCH","TAXI","IR","RESERVE","RESERVED","PUP","OUT"]
        let startingPositions = lineupPositions.filter { !nonStartingTokens.contains($0.uppercased()) }
        let orderedSlots = startingPositions
        let lineupConfig = Dictionary(grouping: startingPositions, by: { $0 }).mapValues { $0.count }

        var results: [TeamStanding] = []

        for roster in rosters {
            let ownerId = roster.owner_id ?? ""
            let teamName = userDisplay[ownerId] ?? "Owner \(ownerId)"

            let rawPlayers = try await fetchPlayers(ids: roster.players ?? [])
            let players: [Player] = rawPlayers.map {
                Player(
                    id: $0.player_id,
                    position: $0.position ?? "UNK",
                    altPositions: $0.fantasy_positions,
                    weeklyScores: weeklyScores(
                        playerId: $0.player_id,
                        rosterId: roster.roster_id,
                        matchups: matchupsByWeek
                    )
                )
            }

            let settings = roster.settings ?? [:]
            let wins = (settings["wins"]?.value as? Int) ?? 0
            let losses = (settings["losses"]?.value as? Int) ?? 0
            let ties = (settings["ties"]?.value as? Int) ?? 0
            let standing = (settings["rank"]?.value as? Int) ?? 0

            var actualTotal = 0.0, actualOff = 0.0, actualDef = 0.0
            var maxTotal = 0.0, maxOff = 0.0, maxDef = 0.0

            var posTotals: [String: Double] = [:]
            var posStartCounts: [String: Int] = [:]

            var weeklyActualLineupPoints: [Int: Double] = [:]
            var actualStarterPosTotals: [String: Int] = [:]
            var actualStarterWeeks = 0

            var actualStartersByWeek: [Int: [String]] = [:]

            let allWeeks = matchupsByWeek.keys.sorted()
            let currentWeek = sleeperLeague.currentWeek
            let completedWeeks = currentWeek > 1
                ? allWeeks.filter { $0 < currentWeek }
                : allWeeks
            let weeksToUse = completedWeeks
            var weeksCounted = 0
            var actualPosTotals: [String: Double] = [:]
            var actualPosStartCounts: [String: Int] = [:]
            var actualPosWeeks: [String: Set<Int>] = [:]

            // --- MAIN PATCHED SECTION: Use robust credited position for per-week actual lineup ---
            for week in weeksToUse {
                guard let allEntries = matchupsByWeek[week],
                      let myEntry = allEntries.first(where: { $0.roster_id == roster.roster_id })
                else { continue }

                var weekHadValidScore = false
                var thisWeekActual = 0.0

                if let starters = myEntry.starters, let playersPoints = myEntry.players_points {
                    let slots = orderedSlots
                    let paddedStarters: [String] = {
                        if starters.count < slots.count {
                            return starters + Array(repeating: "0", count: slots.count - starters.count)
                        } else if starters.count > slots.count {
                            return Array(starters.prefix(slots.count))
                        }
                        return starters
                    }()

                    var startersForThisWeek: [String] = []
                    // --- PATCH: Assign only ONE start per slot (not per eligible position!) ---
                    for idx in 0..<slots.count {
                        let pid = paddedStarters[idx]
                        guard pid != "0" else { continue }
                        let slotType = slots[idx]
                        let rawPlayer = allPlayers[pid]
                        let pos = rawPlayer?.position ?? players.first(where: { $0.id == pid })?.position ?? "UNK"
                        let fantasyPositions = rawPlayer?.fantasy_positions ?? players.first(where: { $0.id == pid })?.altPositions ?? []
                        let candidatePositions = [pos] + fantasyPositions

                        // --- PATCH: Use global SlotPositionAssigner for credited position ---
                        let creditedPosition = SlotPositionAssigner.countedPosition(for: slotType, candidatePositions: candidatePositions, base: pos)
                        let points = playersPoints[pid] ?? 0.0
                        actualPosStartCounts[creditedPosition, default: 0] += 1
                        actualPosTotals[creditedPosition, default: 0] += points
                        if points != 0.0 { weekHadValidScore = true }
                        thisWeekActual += points
                        startersForThisWeek.append(pid)
                        actualStarterPosTotals[creditedPosition, default: 0] += 1
                        actualPosWeeks[creditedPosition, default: Set<Int>()].insert(week)
                    }
                    actualStartersByWeek[week] = startersForThisWeek
                }

                if weekHadValidScore {
                    weeksCounted += 1
                    actualStarterWeeks += 1
                    if thisWeekActual > 0 {
                        weeklyActualLineupPoints[week] = thisWeekActual
                    }
                    actualTotal += thisWeekActual
                    // Split offense/defense for this week, using position sets (normalized)
                    var weekOff = 0.0, weekDef = 0.0
                    if let starters = myEntry.starters, let playersPoints = myEntry.players_points {
                        for pid in starters {
                            let posRaw = allPlayers[pid]?.position
                                ?? players.first(where: { $0.id == pid })?.position
                                ?? ""
                            let pos = PositionNormalizer.normalize(posRaw)
                            let points = playersPoints[pid] ?? 0.0
                            if offensivePositions.contains(pos) { weekOff += points }
                            else if defensivePositions.contains(pos) { weekDef += points }
                        }
                    }
                    actualOff += weekOff
                    actualDef += weekDef
                }

                // --- OPTIMAL LINEUP: Use the weekly player pool from the matchup entry ---
                let candidates: [Candidate] = {
                    guard let weeklyPlayerIds = myEntry.players else { return [] }
                    return weeklyPlayerIds.compactMap { pid in
                        let raw = allPlayers[pid]
                        let basePosRaw = raw?.position ?? players.first(where: { $0.id == pid })?.position ?? "UNK"
                        let basePos = PositionNormalizer.normalize(basePosRaw)
                        let fantasyRaw = raw?.fantasy_positions ?? [basePosRaw]
                        // normalize all eligible fantasy positions
                        let fantasy = fantasyRaw.map { PositionNormalizer.normalize($0) }
                        let points = myEntry.players_points?[pid] ?? 0.0
                        return Candidate(id: pid, basePos: basePos, fantasy: fantasy, points: points)
                    }
                }()

                var strictSlots: [String] = []
                var flexSlots: [String] = []
                for slot in orderedSlots {
                    let allowed = allowedPositions(for: slot)
                    if allowed.count == 1 &&
                        !isIDPFlex(slot) &&
                        !offensiveFlexSlots.contains(slot.uppercased()) {
                        strictSlots.append(slot)
                    } else {
                        flexSlots.append(slot)
                    }
                }
                let optimalOrder = strictSlots + flexSlots

                var used = Set<String>()
                var weekMax = 0.0, weekOff = 0.0, weekDef = 0.0

                for slot in optimalOrder {
                    let allowed = allowedPositions(for: slot).map { PositionNormalizer.normalize($0) }
                    let allowedSet = Set(allowed)
                    let pick = candidates
                        .filter { !used.contains($0.id) && isEligible($0, allowed: allowedSet) }
                        .max(by: { $0.points < $1.points })

                    guard let best = pick else { continue }
                    used.insert(best.id)
                    weekMax += best.points
                    // --- PATCH: Use global SlotPositionAssigner for credited position ---
                    let counted = SlotPositionAssigner.countedPosition(for: slot, candidatePositions: best.fantasy, base: best.basePos)
                    let credited = PositionNormalizer.normalize(counted)
                    if offensivePositions.contains(credited) { weekOff += best.points }
                    else if defensivePositions.contains(credited) { weekDef += best.points }
                    posTotals[credited, default: 0] += best.points
                    posStartCounts[credited, default: 0] += 1
                }

                maxTotal += weekMax
                maxOff += weekOff
                maxDef += weekDef
            }

            let managementPercent = maxTotal > 0 ? (actualTotal / maxTotal) * 100 : 0
            let offensiveMgmt = maxOff > 0 ? (actualOff / maxOff * 100) : 0
            let defensiveMgmt = maxDef > 0 ? (actualDef / maxDef * 100) : 0
            let teamPPW = weeksCounted > 0 ? actualTotal / Double(weeksCounted) : 0

            // --- PATCHED SECTION: Use robust credited position counts for individualPPW/positionPPW ---
            var positionPPW: [String: Double] = [:]
            var individualPPW: [String: Double] = [:]
            for (pos, total) in actualPosTotals {
                let starts = Double(actualPosStartCounts[pos] ?? 0)
                individualPPW[pos] = starts > 0 ? total / starts : 0
                positionPPW[pos] = weeksCounted > 0 ? total / Double(weeksCounted) : 0
            }

            var strengths: [String] = []
            if managementPercent >= 85 { strengths.append("Efficient lineup mgmt") }
            if actualOff > actualDef + 75 { strengths.append("Strong offense") }
            if actualDef > actualOff + 75 { strengths.append("Strong defense") }

            var weaknesses: [String] = []
            if managementPercent < 65 { weaknesses.append("Lineup efficiency low") }

            let playoffRec = playoffRecord(settings)
            let champCount = championships(settings)
            let pointsAgainst = ((settings["fpts_against"]?.value as? Double) ?? 0)
                              + (((settings["fpts_against_decimal"]?.value as? Double) ?? 0)/100)

            let txs = try await fetchTransactions(for: leagueId)
            let waiverMoves = waiverMoveCount(rosterId: roster.roster_id, in: txs)
            let faabSpentVal = faabSpent(rosterId: roster.roster_id, in: txs)
            let trades = tradeCount(rosterId: roster.roster_id, in: txs)


            let standingModel = TeamStanding(
                id: String(roster.roster_id),
                name: teamName,
                positionStats: [],
                ownerId: ownerId,
                roster: players,
                leagueStanding: standing,
                pointsFor: actualTotal,
                maxPointsFor: maxTotal,
                managementPercent: managementPercent,
                teamPointsPerWeek: teamPPW,
                winLossRecord: "\(wins)-\(losses)-\(ties)",
                bestGameDescription: nil,
                biggestRival: nil,
                strengths: strengths,
                weaknesses: weaknesses,
                playoffRecord: playoffRec,
                championships: champCount,
                winStreak: nil,
                lossStreak: nil,
                offensivePointsFor: actualOff,
                maxOffensivePointsFor: maxOff,
                offensiveManagementPercent: offensiveMgmt,
                averageOffensivePPW: weeksCounted > 0 ? actualOff / Double(weeksCounted) : 0,
                offensiveStrengths: strengths.filter { $0.lowercased().contains("offense") },
                offensiveWeaknesses: weaknesses.filter { $0.lowercased().contains("offense") },
                positionAverages: positionPPW,
                individualPositionAverages: individualPPW,
                defensivePointsFor: actualDef,
                maxDefensivePointsFor: maxDef,
                defensiveManagementPercent: defensiveMgmt,
                averageDefensivePPW: weeksCounted > 0 ? actualDef / Double(weeksCounted) : 0,
                defensiveStrengths: strengths.filter { $0.lowercased().contains("defense") },
                defensiveWeaknesses: weaknesses.filter { $0.lowercased().contains("defense") },
                pointsScoredAgainst: pointsAgainst,
                league: parentLeague,
                lineupConfig: lineupConfig,
                weeklyActualLineupPoints: weeklyActualLineupPoints.isEmpty ? nil : weeklyActualLineupPoints,
                actualStartersByWeek: actualStartersByWeek.isEmpty ? nil : actualStartersByWeek,
                actualStarterPositionCounts: actualStarterPosTotals.isEmpty ? nil : actualStarterPosTotals,
                actualStarterWeeks: actualStarterWeeks == 0 ? nil : actualStarterWeeks,
                waiverMoves: waiverMoves,
                faabSpent: faabSpentVal,
                tradesCompleted: trades
            )

            results.append(standingModel)
        }
        return results
    }

    private func weeklyScores(
        playerId: String,
        rosterId: Int,
        matchups: [Int: [MatchupEntry]]
    ) -> [PlayerWeeklyScore] {
        var scores: [PlayerWeeklyScore] = []
        for (week, entries) in matchups {
            guard let me = entries.first(where: { $0.roster_id == rosterId }),
                  let pts = me.players_points?[playerId] else { continue }
            scores.append(PlayerWeeklyScore(
                week: week,
                points: pts,
                player_id: playerId,
                points_half_ppr: pts,
                matchup_id: me.matchup_id ?? 0,
                points_ppr: pts,
                points_standard: pts
            ))
        }
        return scores.sorted { $0.week < $1.week }
    }
    
    // MARK: - Transactions Helpers

        private func waiverMoveCount(rosterId: Int, in tx: [SleeperTransaction]) -> Int {
            tx.filter {
                let t = ($0.type ?? "").lowercased()
                return (t == "waiver" || t == "free_agent")
                    && ($0.status ?? "").lowercased() == "complete"
                    && ($0.roster_ids?.contains(rosterId) ?? false)
            }.count
        }

        private func faabSpent(rosterId: Int, in tx: [SleeperTransaction]) -> Double {
            tx.reduce(0.0) { acc, tr in
                let t = (tr.type ?? "").lowercased()
                guard t == "waiver",
                      (tr.status ?? "").lowercased() == "complete",
                      (tr.roster_ids?.contains(rosterId) ?? false) else { return acc }
                return acc + Double(tr.waiver_bid ?? 0)
            }
        }

        private func tradeCount(rosterId: Int, in tx: [SleeperTransaction]) -> Int {
            tx.filter {
                ($0.type ?? "").lowercased() == "trade"
                && ($0.status ?? "").lowercased() == "complete"
                && ($0.roster_ids?.contains(rosterId) ?? false)
            }.count
        }

    private struct Candidate {
        let id: String
        let basePos: String
        let fantasy: [String]
        let points: Double
    }

    // --- PATCH: Normalize allowed position set before checking eligibility
    private func isEligible(_ c: Candidate, allowed: Set<String>) -> Bool {
        // Both c.basePos and c.fantasy are already normalized in buildTeams
        if allowed.contains(c.basePos) { return true }
        return !allowed.intersection(Set(c.fantasy)).isEmpty
    }

    private func playoffRecord(_ settings: [String: AnyCodable]) -> String? {
        let w = (settings["playoff_wins"]?.value as? Int) ?? 0
        let l = (settings["playoff_losses"]?.value as? Int) ?? 0
        return (w + l) > 0 ? "\(w)-\(l)" : nil
    }

    private func championships(_ settings: [String: AnyCodable]) -> Int? {
        if let champ = settings["champion"]?.value as? Bool, champ { return 1 }
        if let c = settings["championships"]?.value as? Int { return c }
        if let arr = settings["championship_seasons"]?.value as? [String], !arr.isEmpty { return arr.count }
        return nil
    }

    // --- PATCH: Normalize all allowed positions for slot assignment
    private func allowedPositions(for slot: String) -> Set<String> {
        let u = slot.uppercased()
        switch u {
        case "QB","RB","WR","TE","K","DL","LB","DB": return [u]
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return ["RB","WR","TE"]
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return ["QB","RB","WR","TE"]
        case "IDP","DP","D","DEF","DL_LB_DB": return ["DL","LB","DB"]
        case "DL_LB": return ["DL","LB"]
        case "LB_DB": return ["LB","DB"]
        case "DL_DB": return ["DL","DB"]
        default:
            if u.contains("IDP") { return ["DL","LB","DB"] }
            if u.allSatisfy({ "DLB".contains($0) }) { return ["DL","LB","DB"] }
            return [u]
        }
    }

    private func isIDPFlex(_ slot: String) -> Bool {
        let u = slot.uppercased()
        if u.contains("IDP") { return u != "DL" && u != "LB" && u != "DB" }
        return ["DP","D","DEF","DL_LB_DB","DL_LB","LB_DB","DL_DB"].contains(u) ||
               (u.allSatisfy({ "DLB".contains($0) }) && u.count > 1)
    }

    // --- PATCH: Remove local countedPosition function, use global SlotPositionAssigner instead

    // --- PATCH: Remove local mappedPositionForStarter, use SlotPositionAssigner if needed elsewhere ---

    private func baseLeagueName(_ name: String) -> String {
        let pattern = "[\\p{Emoji}\\p{Emoji_Presentation}\\p{Emoji_Modifier_Base}\\p{Emoji_Component}\\p{Symbol}\\p{Punctuation}]"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: name.utf16.count)
        let stripped = regex?.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "") ?? name
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchAllSeasonsForLeague(league: SleeperLeague, userId: String, playoffStartWeek: Int) async throws -> LeagueData {
        let currentYear = Calendar.current.component(.year, from: Date())
        let startYear = currentYear - 9
        let base = baseLeagueName(league.name ?? "")
        var seasonData: [SeasonData] = []

        for yr in startYear...currentYear {
            let seasonId = "\(yr)"
            let userLeagues = try await fetchLeagues(userId: userId, season: seasonId)
            if let seasonLeague = userLeagues.first(where: { baseLeagueName($0.name ?? "") == base }) {
                let rosters = try await fetchRosters(leagueId: seasonLeague.league_id)
                let users = try await fetchLeagueUsers(leagueId: seasonLeague.league_id)
                let tx = try await fetchTransactions(for: seasonLeague.league_id)
                let matchupsByWeek = try await fetchMatchupsByWeek(leagueId: seasonLeague.league_id)
                let seasonPlayoffStart = extractPlayoffStartWeek(from: seasonLeague)
                let teams = try await buildTeams(
                    leagueId: seasonLeague.league_id,
                    rosters: rosters,
                    users: users,
                    parentLeague: nil,
                    lineupPositions: seasonLeague.roster_positions ?? [],
                    transactions: tx,
                    playoffStartWeek: seasonPlayoffStart,
                    matchupsByWeek: matchupsByWeek,
                    sleeperLeague: seasonLeague
                )
                let matchups = convertToSleeperMatchups(matchupsByWeek)
                seasonData.append(SeasonData(id: seasonId, season: seasonId, teams: teams, playoffStartWeek: playoffStartWeek, playoffTeamsCount: nil, matchups: matchups, matchupsByWeek: matchupsByWeek))
            }
        }

        let latestSeason = seasonData.last?.season ?? league.season ?? "\(currentYear)"
        let latestTeams = seasonData.last?.teams ?? []

        return LeagueData(
            id: league.league_id,
            name: league.name ?? "Unnamed League",
            season: latestSeason,
            teams: latestTeams,
            seasons: seasonData,
            startingLineup: league.roster_positions ?? []
        )
    }

    func saveLeagues() {
        for lg in leagues {
            persistLeagueFile(lg)
        }
        saveIndex()
    }

    func loadLeagues() {
        loadIndex()
        loadAllLeagueFiles()
    }

    func rebuildAllTime(leagueId: String) {
        guard let idx = leagues.firstIndex(where: { $0.id == leagueId }) else { return }
        leagues[idx] = AllTimeAggregator.buildAllTime(for: leagues[idx], playerCache: allPlayers)
        persistLeagueFile(leagues[idx])
        saveIndex()
    }
}

// MARK: - Bulk Fetch Helper

extension SleeperLeagueManager {
    func fetchAllLeaguesForUser(username: String, seasons: [String]) async throws -> [SleeperLeague] {
        var out: [SleeperLeague] = []
        let user = try await fetchUser(username: username)
        for s in seasons {
            let list = try await fetchLeagues(userId: user.user_id, season: s)
            out.append(contentsOf: list)
        }
        return out
    }
}

extension SleeperLeagueManager {
    func refreshAllLeaguesIfNeeded(username: String?, force: Bool = false) async {
        guard !leagues.isEmpty else { return }
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let targets = leagues.filter {
            let last = Self._lastRefresh[$0.id] ?? .distantPast
            return force || now.timeIntervalSince(last) >= refreshThrottleInterval
        }
        guard !targets.isEmpty else { return }

        let maxConcurrent = 3
        var updated: [LeagueData] = []
        var active = 0

        for league in targets {
            while active >= maxConcurrent {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            active += 1
            Task {
                defer { active -= 1 }
                do {
                    if let refreshed = try await refreshLatestSeason(for: league) {
                        await MainActor.run {
                            updated.append(refreshed)
                            Self._lastRefresh[league.id] = now
                        }
                    }
                } catch {
                }
            }
        }

        while active > 0 {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        guard !updated.isEmpty else { return }
        for newLeague in updated {
            if let idx = leagues.firstIndex(where: { $0.id == newLeague.id }) {
                leagues[idx] = newLeague
                persistLeagueFile(newLeague)
            }
        }
        saveIndex()
    }

    func forceRefreshAllLeagues(username: String?) async {
        await refreshAllLeaguesIfNeeded(username: username, force: true)
    }

    private func refreshLatestSeason(for league: LeagueData) async throws -> LeagueData? {
        guard let latestSeason = league.seasons.sorted(by: { $0.id < $1.id }).last else { return nil }

        let baseLeague = try await fetchLeague(leagueId: league.id)

        let rosters = try await fetchRosters(leagueId: league.id)
        let users = try await fetchLeagueUsers(leagueId: league.id)
        let tx = try await fetchTransactions(for: league.id)
        let matchupsByWeek = try await fetchMatchupsByWeek(leagueId: league.id)

        let playoffStart = leaguePlayoffStartWeeks[league.id] ?? playoffStartWeek
        let teams = try await buildTeams(
            leagueId: league.id,
            rosters: rosters,
            users: users,
            parentLeague: nil,
            lineupPositions: league.startingLineup,
            transactions: tx,
            playoffStartWeek: playoffStart,
            matchupsByWeek: matchupsByWeek,
            sleeperLeague: baseLeague
        )
        var newSeasons = league.seasons
        if let i = newSeasons.firstIndex(where: { $0.id == latestSeason.id }) {
            let matchups = convertToSleeperMatchups(matchupsByWeek)
            newSeasons[i] = SeasonData(id: latestSeason.id, season: latestSeason.season, teams: teams, playoffStartWeek: playoffStartWeek, playoffTeamsCount: nil, matchups: matchups, matchupsByWeek: matchupsByWeek)
        }

        let updated = LeagueData(
            id: league.id,
            name: league.name,
            season: league.season,
            teams: teams,
            seasons: newSeasons,
            startingLineup: league.startingLineup
        )

        return AllTimeAggregator.buildAllTime(for: updated, playerCache: allPlayers)
    }

    func refreshLeagueData(leagueId: String, completion: @escaping (Result<LeagueData, Error>) -> Void) {
        if let existingLeague = leagues.first(where: { $0.id == leagueId }) {
            completion(.success(existingLeague))
        } else {
            completion(.failure(NSError(domain: "LeagueManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "League not found"])))
        }
    }

    /// FIXED VERSION OF convertToSleeperMatchups (see below for details)
    private func convertToSleeperMatchups(_ matchupsByWeek: [Int: [MatchupEntry]]) -> [SleeperMatchup] {
        var result: [SleeperMatchup] = []
        for (week, entries) in matchupsByWeek {
            // Group by matchup_id
            let grouped = Dictionary(grouping: entries) { $0.matchup_id ?? 0 }
            for (mid, group) in grouped {
                // Each group should have one entry per team in that matchup
                let sortedGroup = group.sorted { $0.roster_id < $1.roster_id }
                for entry in sortedGroup {
                    // Each entry is for a specific team's roster
                    result.append(SleeperMatchup(
                        starters: entry.starters ?? [],
                        rosterId: entry.roster_id,
                        players: entry.players ?? [],
                        matchupId: mid,
                        points: entry.points ?? 0.0,
                        customPoints: nil
                    ))
                }
            }
        }
        return result.sorted { $0.matchupId < $1.matchupId }
    }
}
