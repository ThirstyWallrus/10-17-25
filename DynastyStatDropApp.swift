//
//  DynastyStatDropApp.swift
//  DynastyStatDrop
//
//  Adds foreground (scenePhase) & post-login throttled refresh
//  while preserving existing per-user league loading.
//  Includes DEBUG big-write probe for UserDefaults (detects large Data blobs).
//
//  Concurrency-safe version: removed mutable static vars that triggered
//  Swift Concurrency diagnostics. Idempotence is handled via an
//  associated object flag on the UserDefaults meta-class instead of
//  shared mutable state.
//

import SwiftUI
import Foundation
import ObjectiveC.runtime

// MARK: - DEBUG Big Write Probe (UserDefaults)
//
// Detects large Data values (>= threshold) written to UserDefaults.
// Swizzles only the (Any?, String) overload of set(_:forKey:).
// Idempotent: uses associated object marker instead of mutable static vars.
//
#if DEBUG
private let DSD_DEFAULTS_BIG_WRITE_THRESHOLD = 3_500_000 // ~3.3 MB (warn before 4 MB hard limit)

private enum _DSDProbeAssoc {
    // Unique key address
    nonisolated(unsafe) static var installedFlagKey: UInt8 = 0
}

extension UserDefaults {

    static func installBigWriteProbe(threshold: Int = DSD_DEFAULTS_BIG_WRITE_THRESHOLD) {
        // Obtain the dynamic class of the singleton instance
        guard let cls: AnyClass = object_getClass(UserDefaults.standard) else {
            print("[BigWriteProbe] Could not get UserDefaults meta-class.")
            return
        }

        // If already installed (associated flag present), exit.
        if objc_getAssociatedObject(cls, &_DSDProbeAssoc.installedFlagKey) != nil {
            return
        }

        // Disambiguate overloaded selector (Any?, String)
        let originalSelector = #selector(
            UserDefaults.set(_:forKey:) as (UserDefaults) -> (Any?, String) -> Void
        )
        let swizzledSelector = #selector(UserDefaults.dsd_probe_setAny(_:forKey:))

        guard
            let originalMethod = class_getInstanceMethod(cls, originalSelector),
            let swizzledMethod = class_getInstanceMethod(cls, swizzledSelector)
        else {
            print("[BigWriteProbe] Swizzle failed (methods not found).")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
        objc_setAssociatedObject(
            cls,
            &_DSDProbeAssoc.installedFlagKey,
            NSNumber(value: true),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        print("[BigWriteProbe] Installed (threshold: \(threshold) bytes).")
    }

    /// Swizzled implementation replacing set(_:forKey:) (Any?, String).
    @objc private func dsd_probe_setAny(_ value: Any?, forKey defaultName: String) {
        if let data = value as? Data, data.count >= DSD_DEFAULTS_BIG_WRITE_THRESHOLD {
            print("[BigWriteProbe] Data write \(data.count) bytes for key '\(defaultName)'")
        }
        // Call original (now at dsd_probe_setAny because of the exchange).
        dsd_probe_setAny(value, forKey: defaultName)
    }
}
#endif

@main
struct DynastyStatDropApp: App {
    @StateObject var authViewModel = AuthViewModel()
    @StateObject var appSelection = AppSelection()
    @StateObject var leagueManager = SleeperLeagueManager()
    @StateObject var migrationManager = DataMigrationManager()
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
#if DEBUG
        UserDefaults.installBigWriteProbe()
#endif
    }
    
    var body: some Scene {
        WindowGroup {
            if !authViewModel.isLoggedIn {
                SignIn()
                    .environmentObject(authViewModel)
                    .environmentObject(appSelection)
                    .environmentObject(leagueManager)
            } else {
                MainTabView()
                    .environmentObject(authViewModel)
                    .environmentObject(appSelection)
                    .environmentObject(leagueManager)
                    .task {
                        migrationManager.runMigrationIfNeeded(leagueManager: leagueManager)
                        appSelection.updateLeagues(
                            leagueManager.leagues,
                            username: authViewModel.currentUsername
                        )
                    }
                    .onChange(of: authViewModel.isLoggedIn) { _, loggedIn in
                        if loggedIn, let user = authViewModel.currentUsername {
                            leagueManager.setActiveUser(username: user)
                            appSelection.updateLeagues(leagueManager.leagues, username: user)
                            Task {
                                await leagueManager.refreshAllLeaguesIfNeeded(username: user, force: false)
                                await MainActor.run {
                                    appSelection.updateLeagues(leagueManager.leagues, username: user)
                                }
                            }
                        }
                    }
                    .onChange(of: authViewModel.currentUsername) { _, user in
                        guard let user else { return }
                        leagueManager.setActiveUser(username: user)
                        appSelection.updateLeagues(leagueManager.leagues, username: user)
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active,
                           authViewModel.isLoggedIn,
                           let user = authViewModel.currentUsername {
                            Task {
                                await leagueManager.refreshAllLeaguesIfNeeded(username: user, force: false)
                                await MainActor.run {
                                    appSelection.updateLeagues(leagueManager.leagues, username: user)
                                }
                            }
                        }
                    }
                    .onChange(of: leagueManager.leagues) { _ in
                        appSelection.updateLeagues(
                            leagueManager.leagues,
                            username: authViewModel.currentUsername
                        )
                    }
            }
        }
    }
}

func checkForNewStatDropAndNotify() {
    // For each team/league/context/personality the user cares about...
    // let statDrop = StatDropPersistence.shared.getOrGenerateStatDrop(for: team, league: league, context: .fullTeam, personality: preferredPersonality)
    // If this was a new generation (i.e., previously not present in UserDefaults), trigger your push/local notification.
    // You can add an additional flag in UserDefaults to track if notification was sent for this week.
}
