//
//  Position.swift
//  DSD
//
//  Created by Dynasty Stat Drop on 7/8/25.
//

import SwiftUI

// MARK: - Data Models

enum Position: String, CaseIterable {
    case QB, RB, WR, TE, K, DL, LB, DB
}

struct WeeklyPositionStats: Identifiable {
    let id = UUID()
    let week: Int
    let score: Double
    let playersPlayed: Int
}

struct PositionSeasonStats {
    let position: Position
    let weeklyStats: [WeeklyPositionStats]

    var totalPoints: Double {
        weeklyStats.reduce(0) { $0 + $1.score }
    }

    var totalPlayersPlayed: Int {
        weeklyStats.reduce(0) { $0 + $1.playersPlayed }
    }

    var numberOfWeeks: Int {
        weeklyStats.count
    }

    var averagePointsPerWeek: Double {
        numberOfWeeks > 0 ? totalPoints / Double(numberOfWeeks) : 0
    }

    var averagePlayersPerWeek: Double {
        numberOfWeeks > 0 ? Double(totalPlayersPlayed) / Double(numberOfWeeks) : 0
    }

    var averagePointsPerPlayer: Double {
        totalPlayersPlayed > 0 ? totalPoints / Double(totalPlayersPlayed) : 0
    }

    func statsForWeek(_ week: Int) -> (playersPlayed: Int, totalPoints: Double, avgPointsPerPlayer: Double)? {
        guard let stat = weeklyStats.first(where: { $0.week == week }) else { return nil }
        let avgPerPlayer = stat.playersPlayed > 0 ? stat.score / Double(stat.playersPlayed) : 0
        return (stat.playersPlayed, stat.score, avgPerPlayer)
    }
}

struct TeamStatsData: Identifiable {
    var id: String { teamName }
    let teamName: String
    let statsByPosition: [Position: [WeeklyPositionStats]]
}

class StatsViewModel: ObservableObject {
    @Published var teams: [TeamStatsData] = []

    func importData(from leagues: [LeagueData]) {
        // Use DSDStatsService and SleeperLeagueManager data
        self.teams = leagues.flatMap { league in
            league.seasons.flatMap { season in
                season.teams.map { team in
                    // Compute statsByPosition using team's roster and DSDStatsService
                    let statsByPosition = computePositionWeeklyStats(for: team, in: season)
                    return TeamStatsData(teamName: team.name, statsByPosition: statsByPosition)
                }
            }
        }
    }
    
    private func computePositionWeeklyStats(for team: TeamStanding, in season: SeasonData) -> [Position: [WeeklyPositionStats]] {
        let lineupConfig = team.lineupConfig ?? inferredLineupConfig(from: team.roster)
        var statsByPosition: [Position: [WeeklyPositionStats]] = [:]
        
        for pos in Position.allCases {
            var weekly: [WeeklyPositionStats] = []
            for week in 1...18 {
                guard let weekEntries = season.matchupsByWeek?[week],
                      let rosterId = Int(team.id),
                      let myEntry = weekEntries.first(where: { $0.roster_id == rosterId }),
                      let startedIds = myEntry.starters,
                      !startedIds.isEmpty else {
                    // Fallback to legacy logic if no matchup data
                    let players = team.roster.filter { $0.position == pos.rawValue }
                    let scores = players.compactMap { player in player.weeklyScores.first(where: { $0.week == week })?.points }
                    let totalPoints = scores.reduce(0, +)
                    let playersPlayed = scores.count
                    if playersPlayed > 0 {
                        weekly.append(WeeklyPositionStats(week: week, score: totalPoints, playersPlayed: playersPlayed))
                    }
                    continue
                }
                
                let startedPlayers = team.roster.filter { startedIds.contains($0.id) }
                let playersPoints = myEntry.players_points ?? [:]
                
                let candidates: [MigCandidate] = startedPlayers.map { player in
                    MigCandidate(basePos: player.position, fantasy: [player.position] + (player.altPositions ?? []), points: playersPoints[player.id] ?? 0)
                }
                
                let slots = expandSlots(lineupConfig: lineupConfig)
                
                var assignment: [MigCandidate: String] = [:]
                var availableSlots = slots
                
                let sortedCandidates = candidates.sorted {
                    eligibleSlots(for: $0, availableSlots).count < eligibleSlots(for: $1, availableSlots).count
                }
                
                for c in sortedCandidates {
                    let elig = eligibleSlots(for: c, availableSlots)
                    if elig.isEmpty { continue }
                    
                    let specific = elig.filter { ["QB","RB","WR","TE","K","DL","LB","DB"].contains($0.uppercased()) }
                    let chosen = specific.first ?? elig.first!
                    
                    assignment[c] = chosen
                    
                    if let idx = availableSlots.firstIndex(of: chosen) {
                        availableSlots.remove(at: idx)
                    }
                }
                
                var posMap: [String: (score: Double, played: Int)] = [:]
                
                for (c, slot) in assignment {
                    let counted = countedPosition(for: slot, candidatePositions: c.fantasy, base: c.basePos)
                    var current = posMap[counted, default: (0, 0)]
                    current.score += c.points
                    current.played += 1
                    posMap[counted] = current
                }
                
                if let (score, played) = posMap[pos.rawValue], played > 0 {
                    weekly.append(WeeklyPositionStats(week: week, score: score, playersPlayed: played))
                }
            }
            statsByPosition[pos] = weekly
        }
        
        return statsByPosition
    }
    
    // MARK: Shared Utility Functions
    
    private let offensivePositions: Set<String> = ["QB","RB","WR","TE","K"]
    private let defensivePositions: Set<String> = ["DL","LB","DB"]
    private let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]
    
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
    
    private func countedPosition(for slot: String, candidatePositions: [String], base: String) -> String {
        let s = slot.uppercased()
        if ["QB","RB","WR","TE","K","DL","LB","DB"].contains(s) { return s }
        let allowed = allowedPositions(for: s)
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
    
    private func expandSlots(lineupConfig: [String: Int]) -> [String] {
        lineupConfig.flatMap { Array(repeating: $0.key, count: $0.value) }
    }
    
    private func inferredLineupConfig(from roster: [Player]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for p in roster { counts[p.position, default: 0] += 1 }
        return counts.mapValues { min($0, 3) }
    }
}

// MARK: - Views

struct PositionStatsView: View {
    let position: Position
    let teams: [TeamStatsData]

    var body: some View {
        List {
            ForEach(teams) { team in
                if let weeklyStats = team.statsByPosition[position], !weeklyStats.isEmpty {
                    let seasonStats = PositionSeasonStats(position: position, weeklyStats: weeklyStats)
                    Section(header: Text(team.teamName).font(.headline)) {
                        HStack {
                            Text("Week")
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Text("Score")
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text("Players")
                                .frame(width: 60, alignment: .center)
                        }
                        .font(.subheadline)
                        .foregroundColor(.gray)

                        ForEach(weeklyStats.sorted(by: { $0.week < $1.week })) { stat in
                            HStack {
                                Text("\(stat.week)")
                                    .frame(width: 60, alignment: .leading)
                                Spacer()
                                Text(String(format: "%.1f", stat.score))
                                    .frame(width: 60, alignment: .center)
                                Spacer()
                                Text("\(stat.playersPlayed)")
                                    .frame(width: 60, alignment: .center)
                            }
                            .font(.body)
                        }

                        HStack {
                            Text("Total")
                                .font(.subheadline.bold())
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Text(String(format: "%.1f", seasonStats.totalPoints))
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text("\(seasonStats.totalPlayersPlayed)")
                                .frame(width: 60, alignment: .center)
                        }

                        HStack {
                            Text("Avg/Week")
                                .font(.subheadline.bold())
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Text(String(format: "%.1f", seasonStats.averagePointsPerWeek))
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text(String(format: "%.1f", seasonStats.averagePlayersPerWeek))
                                .frame(width: 60, alignment: .center)
                        }

                        HStack {
                            Text("Avg/Player")
                                .font(.subheadline.bold())
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Text(String(format: "%.1f", seasonStats.averagePointsPerPlayer))
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text("")
                                .frame(width: 60)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(position.rawValue) Stats")
    }
}

struct FantasyStatsView: View {
    @StateObject private var viewModel = StatsViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appSelection: AppSelection
    @State private var selectedPosition: Position = .QB

    var body: some View {
        NavigationView {
            VStack {
                Picker("Position", selection: $selectedPosition) {
                    ForEach(Position.allCases, id: \.self) { position in
                        Text(position.rawValue).tag(position)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                PositionStatsView(position: selectedPosition, teams: viewModel.teams)
            }
            .navigationTitle("Fantasy Stats")
        }
        .onAppear {
            // Use leagues from appSelection, which are in sync with SleeperLeagueManager
            if authViewModel.hasImportedLeague {
                viewModel.importData(from: appSelection.leagues)
            }
        }
    }
}

#Preview {
    FantasyStatsView()
        .environmentObject(AuthViewModel())
        .environmentObject(AppSelection())
}
