/**
 * SigningService.swift
 * HIAH LoginWindow - App Signing Service
 *
 * High-level signing service that integrates with HIAHAppSigner.
 * Provides SwiftUI-friendly interface with progress updates.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation
import Combine

@MainActor
class SigningService: ObservableObject {
    static let shared = SigningService()
    
    @Published var isSigningInProgress = false
    @Published var signingProgress: Double = 0.0
    @Published var signingStatus: String = ""
    @Published var lastError: Error?
    
    private init() {}
    
    // MARK: - App Signing
    
    /// Sign an app at the given path
    func signApp(at path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try await signApp(at: url)
    }
    
    /// Sign an app at the given URL
    func signApp(at url: URL) async throws {
        guard !isSigningInProgress else {
            throw AltSignError.signingFailed("Signing already in progress")
        }
        
        isSigningInProgress = true
        signingProgress = 0.0
        signingStatus = "Starting..."
        lastError = nil
        
        defer {
            isSigningInProgress = false
        }
        
        do {
            _ = try await HIAHAppSigner.shared.signApp(at: url) { [weak self] progress, status in
                Task { @MainActor in
                    self?.signingProgress = progress
                    self?.signingStatus = status
                }
            }
            
            signingStatus = "✅ Signed successfully"
            print("[SigningService] App signed: \(url.lastPathComponent)")
            
        } catch {
            signingStatus = "❌ Signing failed"
            lastError = error
            print("[SigningService] Signing failed: \(error)")
            throw error
        }
    }
    
    /// Sign HIAH Desktop for 7-day refresh
    func signHIAHDesktop() async throws {
        print("[SigningService] Signing HIAH Desktop for refresh...")
        
        isSigningInProgress = true
        signingProgress = 0.0
        signingStatus = "Refreshing HIAH Desktop..."
        
        defer {
            isSigningInProgress = false
        }
        
        do {
            try await HIAHAppSigner.shared.signSelf()
            signingStatus = "✅ HIAH Desktop refreshed"
        } catch {
            signingStatus = "❌ Refresh failed"
            lastError = error
            throw error
        }
    }
    
    /// Verify a signature at the given path
    func verifySignature(at path: String) -> Bool {
        // Use codesign to verify
        // For now, return false as placeholder
        print("[SigningService] Signature verification not yet implemented")
        return false
    }
}
