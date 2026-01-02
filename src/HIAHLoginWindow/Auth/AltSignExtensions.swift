/**
 * AltSignExtensions.swift
 * HIAH LoginWindow - Swift Extensions for AltSign
 *
 * Provides async/await wrappers and Swift-friendly interfaces
 * for the Objective-C AltSign framework.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation

// MARK: - Error Types

enum AltSignError: Error, LocalizedError {
    case authenticationFailed(String)
    case noTeamsFound
    case certificateFailed(String)
    case provisioningFailed(String)
    case signingFailed(String)
    case invalidAnisetteData
    case anisetteServerTimeout
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .noTeamsFound: return "No development teams found for this Apple Account"
        case .certificateFailed(let msg): return "Certificate error: \(msg)"
        case .provisioningFailed(let msg): return "Provisioning profile error: \(msg)"
        case .signingFailed(let msg): return "Signing failed: \(msg)"
        case .invalidAnisetteData: return "Failed to fetch Anisette data from all servers"
        case .anisetteServerTimeout: return "Anisette servers timed out. If using LocalDevVPN, try disabling it temporarily to sign in."
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Anisette Data Provider

/// Fetches Anisette data required for Apple authentication
/// In a full SideStore implementation, this would use minimuxer or an external server
struct AnisetteData {
    
    /// Fetch Anisette data from an Anisette server or local provider
    static func fetch() async throws -> ALTAnisetteData {
        // Option 1: Use local anisette (requires minimuxer)
        // Option 2: Use external anisette server
        
        // For now, create local anisette data using device info
        // This is a simplified version - real implementation needs proper anisette server
        
        #if targetEnvironment(simulator)
        // Simulator: Create mock anisette data for testing
        return createMockAnisetteData()
        #else
        // Real device: Try to fetch from anisette server
        return try await fetchFromServer()
        #endif
    }
    
    private static func createMockAnisetteData() -> ALTAnisetteData {
        // Mock data for simulator testing
        let machineID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let otp = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let localUserID = UUID().uuidString
        
        return ALTAnisetteData(
            machineID: machineID,
            oneTimePassword: otp,
            localUserID: localUserID,
            routingInfo: 0,
            deviceUniqueIdentifier: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            deviceSerialNumber: "SIMULATOR",
            deviceDescription: "<MacBookPro13,1> <macOS;13.0;22A380> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3600.0.11.11.5)>",
            date: Date(),
            locale: Locale.current,
            timeZone: TimeZone.current
        )
    }
    
    private static func fetchFromServer() async throws -> ALTAnisetteData {
        // List of public anisette servers (like SideStore uses)
        let servers = [
            "https://ani.sidestore.io/",
            "https://armconverter.com/anisette/irGb3Quww8zrhgqnzmrx",
        ]
        
        var lastError: Error? = nil
        
        for serverURL in servers {
            do {
                guard let url = URL(string: serverURL) else { continue }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("Sidestore/1.0", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 15
                
                print("[Anisette] Trying server: \(serverURL)")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("[Anisette] Invalid response type")
                    continue
                }
                
                guard httpResponse.statusCode == 200 else {
                    print("[Anisette] Server returned status: \(httpResponse.statusCode)")
                    continue
                }
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[Anisette] Failed to parse JSON")
                    continue
                }
                
                // Convert to [String: String] for ALTAnisetteData
                var stringDict: [String: String] = [:]
                
                // Map server response keys to ALTAnisetteData keys
                // Different servers use different key names
                let keyMappings: [(serverKeys: [String], altKey: String)] = [
                    (["X-Apple-I-MD-M", "machineID"], "machineID"),
                    (["X-Apple-I-MD", "oneTimePassword"], "oneTimePassword"),
                    (["X-Apple-I-MD-LU", "localUserID"], "localUserID"),
                    (["X-Apple-I-MD-RINFO", "routingInfo"], "routingInfo"),
                    (["X-Mme-Device-Id", "deviceUniqueIdentifier"], "deviceUniqueIdentifier"),
                    (["X-Apple-I-SRL-NO", "deviceSerialNumber"], "deviceSerialNumber"),
                    (["X-MMe-Client-Info", "deviceDescription"], "deviceDescription"),
                    (["X-Apple-I-Client-Time", "date"], "date"),
                    (["X-Apple-Locale", "locale"], "locale"),
                    (["X-Apple-I-TimeZone", "timeZone"], "timeZone"),
                ]
                
                for mapping in keyMappings {
                    for serverKey in mapping.serverKeys {
                        if let value = json[serverKey] {
                            stringDict[mapping.altKey] = String(describing: value)
                            break
                        }
                    }
                }
                
                // Validate we have all required fields
                let requiredKeys = ["machineID", "oneTimePassword", "localUserID", "routingInfo", 
                                    "deviceUniqueIdentifier", "deviceSerialNumber", "deviceDescription", 
                                    "date", "locale", "timeZone"]
                let missingKeys = requiredKeys.filter { stringDict[$0] == nil }
                
                if !missingKeys.isEmpty {
                    print("[Anisette] Missing keys: \(missingKeys)")
                    continue
                }
                
                guard let anisetteData = ALTAnisetteData(json: stringDict) else {
                    print("[Anisette] Failed to create ALTAnisetteData from dict")
                    continue
                }
                
                print("[Anisette] ✅ Fetched from: \(serverURL)")
                return anisetteData
                
            } catch {
                print("[Anisette] Server \(serverURL) failed: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }
        
        // Check if all failures were timeouts (likely VPN interference)
        if let urlError = lastError as? URLError {
            if urlError.code == .timedOut || urlError.code == .networkConnectionLost {
                print("[Anisette] ⚠️ All servers timed out - VPN might be interfering")
                throw AltSignError.anisetteServerTimeout
            }
        }
        
        throw lastError ?? AltSignError.invalidAnisetteData
    }
}

// MARK: - ALTAppleAPI Swift Extensions

extension ALTAppleAPI {
    
    /// Authenticate with Apple using async/await
    /// Uses AltSign's built-in GSA authentication
    func authenticate(
        appleID: String,
        password: String,
        anisetteData: ALTAnisetteData,
        twoFactorHandler: @escaping (@escaping (String?) -> Void) -> Void
    ) async throws -> (account: ALTAccount, session: ALTAppleAPISession) {
        return try await withCheckedThrowingContinuation { continuation in
            // Use ALTAppleAPI's real authenticate method (from ALTAppleAPI+Authentication.swift)
            self.authenticate(
                appleID: appleID,
                password: password,
                anisetteData: anisetteData,
                verificationHandler: twoFactorHandler
            ) { account, session, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.authenticationFailed(error.localizedDescription))
                } else if let account = account, let session = session {
                    continuation.resume(returning: (account, session))
                } else {
                    continuation.resume(throwing: AltSignError.authenticationFailed("Unknown authentication error"))
                }
            }
        }
    }
    
    /// Authenticate without 2FA handler (will throw if 2FA is required)
    func authenticate(appleID: String, password: String, anisetteData: ALTAnisetteData) async throws -> (account: ALTAccount, session: ALTAppleAPISession) {
        return try await authenticate(
            appleID: appleID,
            password: password,
            anisetteData: anisetteData,
            twoFactorHandler: { callback in
                // No 2FA handler - will fail if 2FA is required
                callback(nil)
            }
        )
    }
    
    /// Fetch teams for account
    func fetchTeams(for account: ALTAccount, session: ALTAppleAPISession) async throws -> [ALTTeam] {
        return try await withCheckedThrowingContinuation { continuation in
            self.fetchTeams(for: account, session: session) { teams, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.networkError(error))
                } else if let teams = teams {
                    continuation.resume(returning: teams)
                } else {
                    continuation.resume(throwing: AltSignError.noTeamsFound)
                }
            }
        }
    }
    
    /// Fetch certificates for team
    func fetchCertificates(for team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTCertificate] {
        return try await withCheckedThrowingContinuation { continuation in
            self.fetchCertificates(for: team, session: session) { certificates, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.networkError(error))
                } else if let certificates = certificates {
                    continuation.resume(returning: certificates)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Add new certificate
    func addCertificate(machineName: String, to team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
        return try await withCheckedThrowingContinuation { continuation in
            self.addCertificate(machineName: machineName, to: team, session: session) { certificate, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.certificateFailed(error.localizedDescription))
                } else if let certificate = certificate {
                    continuation.resume(returning: certificate)
                } else {
                    continuation.resume(throwing: AltSignError.certificateFailed("Unknown error"))
                }
            }
        }
    }
    
    /// Revoke certificate
    func revokeCertificate(_ certificate: ALTCertificate, for team: ALTTeam, session: ALTAppleAPISession) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.revoke(certificate, for: team, session: session) { success, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.certificateFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AltSignError.certificateFailed("Failed to revoke certificate"))
                }
            }
        }
    }
    
    /// Fetch devices for team
    func fetchDevices(for team: ALTTeam, types: ALTDeviceType, session: ALTAppleAPISession) async throws -> [ALTDevice] {
        return try await withCheckedThrowingContinuation { continuation in
            self.fetchDevices(for: team, types: types, session: session) { devices, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.networkError(error))
                } else if let devices = devices {
                    continuation.resume(returning: devices)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Register device
    func registerDevice(name: String, identifier: String, type: ALTDeviceType, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTDevice {
        return try await withCheckedThrowingContinuation { continuation in
            self.registerDevice(name: name, identifier: identifier, type: type, team: team, session: session) { device, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.networkError(error))
                } else if let device = device {
                    continuation.resume(returning: device)
                } else {
                    continuation.resume(throwing: AltSignError.provisioningFailed("Failed to register device"))
                }
            }
        }
    }
    
    /// Fetch App IDs for team
    func fetchAppIDs(for team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTAppID] {
        return try await withCheckedThrowingContinuation { continuation in
            self.fetchAppIDs(for: team, session: session) { appIDs, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.networkError(error))
                } else if let appIDs = appIDs {
                    continuation.resume(returning: appIDs)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Add App ID
    func addAppID(name: String, bundleIdentifier: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        return try await withCheckedThrowingContinuation { continuation in
            self.addAppID(withName: name, bundleIdentifier: bundleIdentifier, team: team, session: session) { appID, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.provisioningFailed(error.localizedDescription))
                } else if let appID = appID {
                    continuation.resume(returning: appID)
                } else {
                    continuation.resume(throwing: AltSignError.provisioningFailed("Failed to create App ID"))
                }
            }
        }
    }
    
    /// Fetch provisioning profile
    func fetchProvisioningProfile(for appID: ALTAppID, deviceType: ALTDeviceType, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        return try await withCheckedThrowingContinuation { continuation in
            self.fetchProvisioningProfile(for: appID, deviceType: deviceType, team: team, session: session) { profile, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.provisioningFailed(error.localizedDescription))
                } else if let profile = profile {
                    continuation.resume(returning: profile)
                } else {
                    continuation.resume(throwing: AltSignError.provisioningFailed("Failed to fetch provisioning profile"))
                }
            }
        }
    }
}

// MARK: - ALTSigner Swift Extension

extension ALTSigner {
    
    /// Sign app at URL with provisioning profiles using async/await
    func signApp(at url: URL, provisioningProfiles: [ALTProvisioningProfile]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let progress = self.signApp(at: url, provisioningProfiles: provisioningProfiles) { success, error in
                if let error = error {
                    continuation.resume(throwing: AltSignError.signingFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AltSignError.signingFailed("Unknown signing error"))
                }
            }
            
            // Could observe progress here if needed
            _ = progress
        }
    }
}

