/**
 * HIAHAppSigner.swift
 * HIAH LoginWindow - App Signing Service
 *
 * Signs .ipa files and app bundles using ALTSigner.
 * Handles provisioning profile creation and app ID management.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation
import UIKit

/// Signs apps using AltSign's ALTSigner
class HIAHAppSigner {
    static let shared = HIAHAppSigner()
    
    private init() {}
    
    // MARK: - App Signing
    
    /// Sign an app at the given URL
    /// - Parameters:
    ///   - appURL: URL to the .app bundle or .ipa file
    ///   - progress: Optional progress handler
    /// - Returns: URL to the signed app
    func signApp(at appURL: URL, progress: ((Double, String) -> Void)? = nil) async throws -> URL {
        progress?(0.0, "Preparing to sign...")
        
        // Ensure we have authentication
        guard HIAHAccountManager.shared.account != nil,
              let team = HIAHAccountManager.shared.team,
              let session = HIAHAccountManager.shared.session else {
            throw AltSignError.authenticationFailed("Not logged in")
        }
        
        // Ensure we have a certificate
        progress?(0.1, "Fetching certificate...")
        let certificate = try await HIAHCertificateManager.shared.fetchCertificate()
        
        // Load the app
        progress?(0.2, "Loading app...")
        let app = try loadApp(at: appURL)
        
        // Register device if needed
        progress?(0.3, "Registering device...")
        try await registerDeviceIfNeeded(team: team, session: session)
        
        // Create or fetch App ID
        progress?(0.4, "Creating App ID...")
        let appID = try await createAppID(for: app, team: team, session: session)
        
        // Fetch provisioning profile
        progress?(0.6, "Fetching provisioning profile...")
        let profile = try await ALTAppleAPI.shared.fetchProvisioningProfile(
            for: appID,
            deviceType: .iphone,
            team: team,
            session: session
        )
        
        // Create signer
        progress?(0.7, "Signing app...")
        let signer = ALTSigner(team: team, certificate: certificate)
        
        // Sign the app
        try await signer.signApp(at: app.fileURL, provisioningProfiles: [profile])
        
        progress?(1.0, "Done!")
        print("[Signer] ✅ App signed successfully: \(app.name)")
        
        return app.fileURL
    }
    
    /// Sign HIAH Desktop itself for refresh
    func signSelf() async throws {
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            throw AltSignError.signingFailed("Could not find app bundle")
        }
        
        print("[Signer] Signing HIAH Desktop for refresh...")
        _ = try await signApp(at: URL(fileURLWithPath: bundlePath))
        print("[Signer] ✅ HIAH Desktop signed")
    }
    
    // MARK: - Helper Methods
    
    private func loadApp(at url: URL) throws -> ALTApplication {
        // Handle .ipa files
        if url.pathExtension.lowercased() == "ipa" {
            // Extract .ipa to temporary location
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("HIAH_Signing")
                .appendingPathComponent(UUID().uuidString)
            
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Unzip .ipa using AltSign's NSFileManager+Zip extension
            // This extracts and returns the .app URL directly
            var appURL: URL?
            do {
                appURL = try FileManager.default.unzipAppBundle(at: url, toDirectory: tempDir)
            } catch {
                throw AltSignError.signingFailed("Failed to extract .ipa: \(error.localizedDescription)")
            }
            
            guard let appURL = appURL else {
                throw AltSignError.signingFailed("Failed to extract .ipa")
            }
            
            guard let app = ALTApplication(fileURL: appURL) else {
                throw AltSignError.signingFailed("Failed to load app bundle")
            }
            
            return app
        }
        
        // Handle .app bundles directly
        guard let app = ALTApplication(fileURL: url) else {
            throw AltSignError.signingFailed("Failed to load app bundle")
        }
        
        return app
    }
    
    private func registerDeviceIfNeeded(team: ALTTeam, session: ALTAppleAPISession) async throws {
        let deviceUDID = await UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let deviceName = await UIDevice.current.name
        
        // Fetch existing devices
        let existingDevices = try await ALTAppleAPI.shared.fetchDevices(
            for: team,
            types: .iphone,
            session: session
        )
        
        // Check if device is already registered
        if existingDevices.contains(where: { $0.identifier == deviceUDID }) {
            print("[Signer] Device already registered")
            return
        }
        
        // Register device
        print("[Signer] Registering device: \(deviceName)")
        _ = try await ALTAppleAPI.shared.registerDevice(
            name: deviceName,
            identifier: deviceUDID,
            type: .iphone,
            team: team,
            session: session
        )
        
        print("[Signer] Device registered")
    }
    
    private func createAppID(for app: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        // Generate a unique bundle ID for this app + team
        let bundleID = "com.\(team.identifier.prefix(10)).\(app.bundleIdentifier.replacingOccurrences(of: ".", with: "-"))"
        
        // Fetch existing App IDs
        let existingAppIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
        
        // Check if we already have an App ID for this bundle
        if let existingAppID = existingAppIDs.first(where: { $0.bundleIdentifier == bundleID }) {
            print("[Signer] Using existing App ID: \(existingAppID.bundleIdentifier)")
            return existingAppID
        }
        
        // Create new App ID
        print("[Signer] Creating App ID: \(bundleID)")
        let appID = try await ALTAppleAPI.shared.addAppID(
            name: app.name,
            bundleIdentifier: bundleID,
            team: team,
            session: session
        )
        
        return appID
    }
}

