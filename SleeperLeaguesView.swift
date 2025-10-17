//
//  SleeperLeaguesView.swift
//  DynastyStatDrop
//
//  FIXES:
//   • Uses @EnvironmentObject instead of creating a second @StateObject instance
//   • Relies on limit helpers via SleeperLeagueManager+Limits.swift
//   • Adds import slot / limit UI
//   • Full copy/paste replacement
//

import SwiftUI

struct SleeperLeaguesView: View {
    // Optional external context for showing a selected team/roster (if embedded somewhere)
    let selectedTeam: String
    let roster: [(name: String, position: String)]

    // Use the shared manager injected at app root (DO NOT create a new instance here).
    @EnvironmentObject private var manager: SleeperLeagueManager

    @State private var username: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fetchedLeagues: [SleeperLeague] = []
    @State private var selectedLeagueId: String = ""

    private var activeSeasonLeagues: [SleeperLeague] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return fetchedLeagues.filter { $0.season == "\(currentYear)" }
    }

    private var remainingSlots: Int {
        manager.remainingSlots()
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                headerRow
                limitsRow
                fetchResultsBlock
                importedLeaguesList
                selectedTeamBlock
                Spacer()
            }
            .navigationTitle("Sleeper Leagues")
            .onAppear {
                // Ensure persisted leagues are loaded (safe idempotent)
                manager.loadLeagues()
            }
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 10) {
            TextField("Enter Sleeper username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)

            Button("Fetch") {
                Task { await fetchLeagues() }
            }
            .disabled(username.isEmpty || isLoading)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var limitsRow: some View {
        HStack {
            Text("Imported: \(manager.leagues.count)/\(manager.currentLimit()) • Remaining: \(remainingSlots)")
                .font(.footnote.monospaced())
                .foregroundColor(remainingSlots == 0 ? .yellow : .white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal)
    }

    private var fetchResultsBlock: some View {
        VStack(spacing: 14) {
            if isLoading { ProgressView("Loading leagues...") }

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            if !activeSeasonLeagues.isEmpty {
                Picker("Select League", selection: $selectedLeagueId) {
                    ForEach(activeSeasonLeagues, id: \.league_id) { league in
                        Text(league.name ?? "Unnamed League")
                            .tag(league.league_id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal)

                Button("Import Selected") {
                    Task { await downloadSelectedLeague() }
                }
                .disabled(!manager.canImportAnother() || selectedLeagueId.isEmpty || isLoading)
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                if !manager.canImportAnother() {
                    Text("League limit reached. Remove one to import another.")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            } else if !fetchedLeagues.isEmpty {
                Text("No active (current season) leagues found.")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
    }

    private var importedLeaguesList: some View {
        List {
            Section(header: Text("Imported Leagues")) {
                if manager.leagues.isEmpty {
                    Text("None imported yet.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(manager.leagues) { league in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(league.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Seasons: \(league.seasons.count)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .onDelete(perform: deleteLeague)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private var selectedTeamBlock: some View {
        Group {
            if !selectedTeam.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected Team: \(selectedTeam)")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("Roster")
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.85))
                    ForEach(roster, id: \.name) { player in
                        Text("• \(player.name) – \(player.position)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Actions

    private func fetchLeagues() async {
        isLoading = true
        errorMessage = nil
        fetchedLeagues = []
        selectedLeagueId = ""
        do {
            let currentSeason = Calendar.current.component(.year, from: Date())
            let seasons = (currentSeason - 9 ... currentSeason).map { "\($0)" }
            let leagues = try await manager.fetchAllLeaguesForUser(username: username, seasons: seasons)
            fetchedLeagues = leagues
            selectedLeagueId = activeSeasonLeagues.first?.league_id ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func downloadSelectedLeague() async {
        guard manager.canImportAnother(),
              !selectedLeagueId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await manager.fetchAndImportSingleLeague(leagueId: selectedLeagueId, username: username)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteLeague(at offsets: IndexSet) {
        for index in offsets {
            let league = manager.leagues[index]
            manager.removeLeague(leagueId: league.id)
        }
    }
}
