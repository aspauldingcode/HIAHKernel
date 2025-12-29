/**
 * AuthenticationManager.swift
 * HIAH LoginWindow - Authentication Management
 *
 * High-level authentication manager that coordinates between
 * HIAHAccountManager and HIAHCertificateManager.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation
import Security
import UIKit

enum AuthenticationError: Error, LocalizedError {
    case invalidCredentials
    case networkError
    case certificateDownloadFailed
    case keychainError
    case notLoggedIn
    case twoFactorRequired
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Apple ID or password"
        case .networkError:
            return "Network connection failed. Please check your internet connection."
        case .certificateDownloadFailed:
            return "Failed to download development certificate"
        case .keychainError:
            return "Failed to store credentials securely"
        case .notLoggedIn:
            return "Not logged in. Please sign in first."
        case .twoFactorRequired:
            return "Two-factor authentication required. Please check your trusted devices."
        }
    }
}

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    // MARK: - Published State
    
    @Published var isAuthenticated = false
    @Published var appleID: String?
    @Published var certificateExpirationDate: Date?
    @Published var isLoading = false
    @Published var lastError: Error?
    
    // MARK: - Private Properties
    
    private let accountManager = HIAHAccountManager.shared
    private let certificateManager = HIAHCertificateManager.shared
    
    // MARK: - Initialization
    
    private init() {
        // Check existing authentication state
        checkExistingAuthentication()
        
        // Listen for account changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HIAHAccountDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkExistingAuthentication()
            }
        }
    }
    
    // MARK: - Authentication
    
    /// Authenticate with Apple ID and password
    func authenticate(appleID: String, password: String) async throws {
        print("[Auth] Starting authentication for: \(appleID)")
        
        isLoading = true
        lastError = nil
        
        defer {
            isLoading = false
        }
        
        do {
            // Step 1: Login with account manager
            let account = try await accountManager.login(appleID: appleID, password: password)
            
            // Step 2: Fetch certificate
            _ = try await certificateManager.fetchCertificate()
            
            // Step 3: Update state
            self.appleID = account.appleID
            self.isAuthenticated = true
            self.certificateExpirationDate = certificateManager.expirationDate
            
            print("[Auth] ✅ Authentication successful!")
            
            // Notify observers
            NotificationCenter.default.post(
                name: NSNotification.Name("HIAHAuthenticationSuccess"),
                object: nil
            )
            
        } catch {
            print("[Auth] ❌ Authentication failed: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Sign out and clear all credentials
    func signOut() {
        print("[Auth] Signing out...")
        
        // Clear account
        accountManager.logout()
        
        // Clear certificate (optionally revoke)
        Task {
            try? await certificateManager.revokeCertificate()
        }
        
        // Clear state
        self.appleID = nil
        self.isAuthenticated = false
        self.certificateExpirationDate = nil
        
        // Notify observers
        NotificationCenter.default.post(
            name: NSNotification.Name("HIAHAuthenticationSignOut"),
            object: nil
        )
        
        print("[Auth] Signed out")
    }
    
    /// Refresh authentication (get new certificate if needed)
    func refresh() async throws {
        guard accountManager.isAuthenticated else {
            throw AuthenticationError.notLoggedIn
        }
        
        print("[Auth] Refreshing...")
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Refresh session
            try await accountManager.refreshSession()
            
            // Refresh certificate if needed
            if certificateManager.needsRefresh() {
                _ = try await certificateManager.fetchCertificate()
            }
            
            self.certificateExpirationDate = certificateManager.expirationDate
            
            print("[Auth] ✅ Refresh successful")
            
        } catch {
            print("[Auth] ❌ Refresh failed: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Check if certificate needs refresh (expiring within 2 days)
    func needsRefresh() -> Bool {
        return certificateManager.needsRefresh()
    }
    
    /// Get days until certificate expiration
    var daysUntilExpiration: Int? {
        guard let expirationDate = certificateExpirationDate else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }
    
    // MARK: - Private Methods
    
    private func checkExistingAuthentication() {
        // Check if account manager has a valid session
        if accountManager.isAuthenticated {
            self.appleID = accountManager.account?.appleID
            self.isAuthenticated = true
            self.certificateExpirationDate = certificateManager.expirationDate
            
            if let days = daysUntilExpiration {
                print("[Auth] Existing auth found - \(days) days until expiration")
                
                if days < 2 {
                    print("[Auth] ⚠️ Certificate expiring soon!")
                }
            }
        } else {
            self.appleID = nil
            self.isAuthenticated = false
            self.certificateExpirationDate = nil
        }
    }
}
