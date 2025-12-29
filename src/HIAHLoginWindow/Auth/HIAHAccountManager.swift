/**
 * HIAHAccountManager.swift
 * HIAH LoginWindow - Account Management
 *
 * Manages Apple ID authentication and session state using AltSign.
 * This is the primary interface for authentication in HIAH Desktop.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation
import UIKit

/// Manages Apple ID account authentication and session persistence
@objc(HIAHAccountManager)
@objcMembers
class HIAHAccountManager: NSObject {
    @objc static let shared = HIAHAccountManager()
    
    // MARK: - Properties
    
    /// Current authenticated account (nil if not logged in)
    @objc private(set) var account: ALTAccount?
    
    /// Current team (selected from account's teams)
    @objc private(set) var team: ALTTeam?
    
    /// Current API session
    @objc private(set) var session: ALTAppleAPISession?
    
    /// Whether the user is authenticated
    var isAuthenticated: Bool {
        return account != nil && session != nil
    }
    
    // Keychain storage keys
    private let keychainService = "com.aspauldingcode.HIAHDesktop.account"
    
    private override init() {
        super.init()
        // Try to restore session on startup
        Task {
            await restoreSession()
        }
    }
    
    // MARK: - 2FA Handling
    
    /// Closure called when 2FA verification is needed
    /// The closure receives a callback that must be called with the verification code
    var twoFactorHandler: ((@escaping (String?) -> Void) -> Void)?
    
    // MARK: - Authentication
    
    /// Login with Apple ID and password
    /// - Note: This requires proper Anisette data and may prompt for 2FA
    func login(appleID: String, password: String) async throws -> ALTAccount {
        print("[Account] Starting authentication for: \(appleID)")
        
        // Step 1: Fetch Anisette data
        print("[Account] Fetching Anisette data...")
        let anisetteData = try await AnisetteData.fetch()
        print("[Account] ✅ Anisette data fetched")
        
        // Step 2: Authenticate with Apple using AltSign's GSA implementation
        print("[Account] Authenticating with Apple...")
        
        let (account, session) = try await ALTAppleAPI.shared.authenticate(
            appleID: appleID,
            password: password,
            anisetteData: anisetteData,
            twoFactorHandler: { [weak self] callback in
                // Handle 2FA: notify UI to show verification prompt
                print("[Account] ⚠️ 2FA verification required")
                
                if let handler = self?.twoFactorHandler {
                    handler(callback)
                } else {
                    // No handler set - post notification for UI to handle
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("HIAHRequires2FA"),
                            object: nil,
                            userInfo: ["callback": callback]
                        )
                    }
                }
            }
        )
        
        print("[Account] ✅ Authenticated as: \(account.appleID)")
        
        // Step 3: Fetch teams
        print("[Account] Fetching teams...")
        let teams = try await ALTAppleAPI.shared.fetchTeams(for: account, session: session)
        
        guard let team = teams.first else {
            throw AltSignError.noTeamsFound
        }
        
        print("[Account] ✅ Found team: \(team.name)")
        
        // Store state
        self.account = account
        self.session = session
        self.team = team
        
        // Persist for future launches
        saveSession(appleID: appleID, dsid: session.dsid, authToken: session.authToken)
        
        return account
    }
    
    /// Logout and clear session
    @objc func logout() {
        print("[Account] Logging out...")
        
        // Clear session data from keychain
        clearSession()
        
        // Clear in-memory state
        self.account = nil
        self.session = nil
        self.team = nil
        
        // Post notification
        NotificationCenter.default.post(name: NSNotification.Name("HIAHAuthenticationSignOut"), object: nil)
        
        print("[Account] Logged out successfully")
    }
    
    // MARK: - Session Management
    
    /// Restore session from keychain on app launch
    private func restoreSession() async {
        guard let sessionData = loadSession() else {
            print("[Account] No saved session found")
            return
        }
        
        print("[Account] Restoring session for: \(sessionData.appleID)")
        
        // Fetch fresh Anisette data
        guard let anisetteData = try? await AnisetteData.fetch() else {
            print("[Account] Failed to fetch Anisette data for session restore")
            return
        }
        
        // Create session with stored tokens and fresh Anisette
        let session = ALTAppleAPISession(
            dsid: sessionData.dsid,
            authToken: sessionData.authToken,
            anisetteData: anisetteData
        )
        
        // Create account from stored data
        let account = ALTAccount()
        account.appleID = sessionData.appleID
        account.identifier = sessionData.dsid
        
        // Validate session by fetching teams
        do {
            let teams = try await ALTAppleAPI.shared.fetchTeams(for: account, session: session)
            
            guard let team = teams.first else {
                print("[Account] No teams found - session may be invalid")
                clearSession()
                return
            }
            
            self.account = account
            self.session = session
            self.team = team
            
            print("[Account] ✅ Session restored successfully")
        } catch {
            print("[Account] Session validation failed: \(error)")
            clearSession()
        }
    }
    
    /// Refresh the session (fetch new Anisette data)
    func refreshSession() async throws {
        guard account != nil, let session = session else {
            throw AltSignError.authenticationFailed("Not logged in")
        }
        
        print("[Account] Refreshing session...")
        
        // Get fresh Anisette data
        let anisetteData = try await AnisetteData.fetch()
        
        // Update session with new Anisette
        session.anisetteData = anisetteData
        
        print("[Account] Session refreshed")
    }
    
    // MARK: - Keychain Persistence
    
    private struct SessionData {
        let appleID: String
        let dsid: String
        let authToken: String
    }
    
    private func saveSession(appleID: String, dsid: String, authToken: String) {
        let defaults = UserDefaults.standard
        defaults.set(appleID, forKey: "HIAH_Account_AppleID")
        defaults.set(dsid, forKey: "HIAH_Account_DSID")
        
        // Store auth token in keychain (more secure)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "authToken",
            kSecValueData as String: authToken.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
        
        print("[Account] Session saved")
    }
    
    private func loadSession() -> SessionData? {
        let defaults = UserDefaults.standard
        
        guard let appleID = defaults.string(forKey: "HIAH_Account_AppleID"),
              let dsid = defaults.string(forKey: "HIAH_Account_DSID") else {
            return nil
        }
        
        // Load auth token from keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "authToken",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let authToken = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return SessionData(appleID: appleID, dsid: dsid, authToken: authToken)
    }
    
    private func clearSession() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "HIAH_Account_AppleID")
        defaults.removeObject(forKey: "HIAH_Account_DSID")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "authToken"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
