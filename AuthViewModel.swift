//
//  AuthViewModel.swift
//  DynastyStatDrop
//
//  Added "Remember Me" support (username persistence).
//

import SwiftUI

class AuthViewModel: ObservableObject {
    let instanceID = UUID().uuidString
    // Auth state
    @Published var isLoggedIn: Bool = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var registrationCompleted = false
    @Published var currentUsername: String? = nil
    @Published var hasImportedLeague = false
    @Published var userTeam: String?
    @Published var oauthTokens: [Platform: String] = [:]

    // Remember‑me (persisted in UserDefaults)
    @Published var rememberedUsername: String?

    enum Platform: String, CaseIterable, Codable {
        case sleeper = "Sleeper"
        case yahoo = "Yahoo"
    }

    private let rememberedKey = "lastRememberedUsername"

    init() {
        // Restore login state
            self.isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
            self.currentUsername = UserDefaults.standard.string(forKey: "currentUsername")
            // Load any remembered username (does NOT log in automatically, just pre-fills)
            if let stored = UserDefaults.standard.string(forKey: rememberedKey),
               UserDefaults.standard.bool(forKey: "rememberMe_\(stored)") {
                rememberedUsername = stored
        }
    }

    // MARK: Public API

    /// Sign in normal user path (validates empty fields, sets errors) with remember flag.
    func signIn(username: String, password: String, remember: Bool) {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Username and password are required."
            showError = true
            isLoggedIn = false
            return
        }
        login(identifier: username, password: password, remember: remember)
    }

    /// Legacy signature kept for backward compatibility (assumes remember=false).
    func signIn(username: String, password: String) {
        signIn(username: username, password: password, remember: false)
    }

    /// Legacy signature for existing calls (assumes remember=false).
    func login(identifier: String, password: String, remember: Bool) {
        isLoggedIn = true
        UserDefaults.standard.set(true, forKey: "isLoggedIn")
        currentUsername = identifier
        UserDefaults.standard.set(identifier, forKey: "currentUsername")
        storeRememberPreference(username: identifier, remember: remember)
        loadUserData(username: identifier)
    }

    func register(email: String, username: String, password: String) {
        registrationCompleted = true
    }

    func loadUserData(username: String) {
        currentUsername = username
        hasImportedLeague = UserDefaults.standard.bool(forKey: "hasImportedLeague_\(username)")
        userTeam = UserDefaults.standard.string(forKey: "userTeam_\(username)")
    }

    func storeOAuthToken(platform: Platform, token: String) {
        oauthTokens[platform] = token
    }
    
    func logout() {
        isLoggedIn = false
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        currentUsername = nil
        UserDefaults.standard.removeObject(forKey: "currentUsername")
    }
    // MARK: Remember Me

    private func storeRememberPreference(username: String, remember: Bool) {
        if remember {
            UserDefaults.standard.set(true, forKey: "rememberMe_\(username)")
            UserDefaults.standard.set(username, forKey: rememberedKey)
            rememberedUsername = username
        } else {
            UserDefaults.standard.set(false, forKey: "rememberMe_\(username)")
            if let stored = UserDefaults.standard.string(forKey: rememberedKey),
               stored == username {
                // Only clear the global pointer if it points to this user
                UserDefaults.standard.removeObject(forKey: rememberedKey)
            }
            rememberedUsername = nil
        }
    }

    /// External setter if UI wants to toggle after login.
    func setRememberPreference(_ remember: Bool) {
        guard let user = currentUsername else { return }
        storeRememberPreference(username: user, remember: remember)
    }

    // MARK: Entitlement Helpers (unchanged from previous extended version)

    func grantPro(for username: String) {
        UserDefaults.standard.set(true, forKey: "dsd.entitlement.pro.\(username)")
    }

    func revokePro(for username: String) {
        UserDefaults.standard.set(false, forKey: "dsd.entitlement.pro.\(username)")
    }

    func isProUser(_ username: String?) -> Bool {
        guard let u = username else { return false }
        return UserDefaults.standard.bool(forKey: "dsd.entitlement.pro.\(u)")
    }
}
