/**
 * HIAHCertificateManager.swift
 * HIAH LoginWindow - Certificate Management
 *
 * Manages development certificates and app signing using AltSign.
 * Handles certificate lifecycle: fetch, create, revoke, and persist.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation
import UIKit

/// Manages development certificates for app signing
class HIAHCertificateManager {
    static let shared = HIAHCertificateManager()
    
    // MARK: - Properties
    
    /// Current signing certificate
    private(set) var certificate: ALTCertificate?
    
    /// Certificate expiration date
    var expirationDate: Date? {
        // Free developer certificates expire in 7 days
        // We store the creation date and calculate expiration
        guard certificate != nil else { return nil }
        return UserDefaults.standard.object(forKey: "HIAH_Certificate_Expiration") as? Date
    }
    
    /// Whether we have a valid certificate
    var hasCertificate: Bool {
        guard certificate != nil, let expiration = expirationDate else {
            return false
        }
        return expiration > Date()
    }
    
    private let keychainService = "com.aspauldingcode.HIAHDesktop.certificate"
    
    private init() {
        // Try to load cached certificate
        loadCachedCertificate()
    }
    
    // MARK: - Certificate Management
    
    /// Fetch or create a signing certificate
    func fetchCertificate() async throws -> ALTCertificate {
        guard HIAHAccountManager.shared.account != nil,
              let team = HIAHAccountManager.shared.team,
              let session = HIAHAccountManager.shared.session else {
            throw AltSignError.authenticationFailed("Not logged in")
        }
        
        print("[Certificate] Fetching certificate for team: \(team.name)")
        
        // Fetch existing certificates
        let existingCerts = try await ALTAppleAPI.shared.fetchCertificates(for: team, session: session)
        
        // Look for a certificate we created (by machine name)
        let machineName = await "HIAH-\(UIDevice.current.name)"
        if let existingCert = existingCerts.first(where: { $0.machineName == machineName }) {
            print("[Certificate] Found existing certificate: \(existingCert.serialNumber)")
            
            // Load private key from keychain if we have it
            if let cachedCert = loadCachedCertificate(), cachedCert.serialNumber == existingCert.serialNumber {
                self.certificate = cachedCert
                return cachedCert
            }
            
            // We found a cert but don't have the private key - need to revoke and recreate
            print("[Certificate] Don't have private key for existing cert - revoking...")
            try await ALTAppleAPI.shared.revokeCertificate(existingCert, for: team, session: session)
        }
        
        // Check if we're at the certificate limit (2 for free accounts)
        if existingCerts.count >= 2 {
            print("[Certificate] At certificate limit - revoking oldest...")
            if let oldestCert = existingCerts.last {
                try await ALTAppleAPI.shared.revokeCertificate(oldestCert, for: team, session: session)
            }
        }
        
        // Create new certificate
        print("[Certificate] Creating new certificate...")
        let newCert = try await ALTAppleAPI.shared.addCertificate(machineName: machineName, to: team, session: session)
        
        // Cache the certificate
        saveCertificate(newCert)
        self.certificate = newCert
        
        // Set expiration (7 days for free accounts)
        let expiration = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        UserDefaults.standard.set(expiration, forKey: "HIAH_Certificate_Expiration")
        
        print("[Certificate] ✅ Certificate created: \(newCert.serialNumber)")
        return newCert
    }
    
    /// Revoke current certificate
    func revokeCertificate() async throws {
        guard let certificate = certificate,
              let team = HIAHAccountManager.shared.team,
              let session = HIAHAccountManager.shared.session else {
            return
        }
        
        print("[Certificate] Revoking certificate: \(certificate.serialNumber)")
        
        try await ALTAppleAPI.shared.revokeCertificate(certificate, for: team, session: session)
        
        // Clear cached certificate
        clearCachedCertificate()
        self.certificate = nil
        
        print("[Certificate] Certificate revoked")
    }
    
    /// Check if certificate needs refresh (expiring within 2 days)
    func needsRefresh() -> Bool {
        guard let expiration = expirationDate else {
            return true
        }
        
        let refreshThreshold = Calendar.current.date(byAdding: .day, value: -2, to: expiration)!
        return Date() > refreshThreshold
    }
    
    // MARK: - Keychain Persistence
    
    private func saveCertificate(_ certificate: ALTCertificate) {
        guard let p12Data = certificate.p12Data() else {
            print("[Certificate] Warning: No P12 data to save")
            return
        }
        
        // Save P12 data
        let p12Query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "p12Data",
            kSecValueData as String: p12Data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
        
        SecItemDelete(p12Query as CFDictionary)
        SecItemAdd(p12Query as CFDictionary, nil)
        
        // Save serial number
        if let serial = certificate.serialNumber.data(using: .utf8) {
            let serialQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: "serialNumber",
                kSecValueData as String: serial,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrSynchronizable as String: kCFBooleanTrue as Any
            ]
            
            SecItemDelete(serialQuery as CFDictionary)
            SecItemAdd(serialQuery as CFDictionary, nil)
        }
        
        // Save machine identifier (used as P12 password)
        if let machineId = certificate.machineIdentifier?.data(using: .utf8) {
            let machineQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: "machineIdentifier",
                kSecValueData as String: machineId,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrSynchronizable as String: kCFBooleanTrue as Any
            ]
            
            SecItemDelete(machineQuery as CFDictionary)
            SecItemAdd(machineQuery as CFDictionary, nil)
        }
        
        print("[Certificate] Saved to keychain")
    }
    
    @discardableResult
    private func loadCachedCertificate() -> ALTCertificate? {
        // Load P12 data
        let p12Query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "p12Data",
            kSecReturnData as String: true
        ]
        
        var p12Result: AnyObject?
        guard SecItemCopyMatching(p12Query as CFDictionary, &p12Result) == errSecSuccess,
              let p12Data = p12Result as? Data else {
            return nil
        }
        
        // Load machine identifier (P12 password)
        let machineQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "machineIdentifier",
            kSecReturnData as String: true
        ]
        
        var machineResult: AnyObject?
        let password: String?
        if SecItemCopyMatching(machineQuery as CFDictionary, &machineResult) == errSecSuccess,
           let machineData = machineResult as? Data {
            password = String(data: machineData, encoding: .utf8)
        } else {
            password = nil
        }
        
        // Create certificate from P12
        guard let cert = ALTCertificate(p12Data: p12Data, password: password) else {
            print("[Certificate] Failed to load certificate from P12")
            return nil
        }
        
        self.certificate = cert
        print("[Certificate] Loaded from keychain: \(cert.serialNumber)")
        return cert
    }
    
    private func clearCachedCertificate() {
        let items = ["p12Data", "serialNumber", "machineIdentifier"]
        for item in items {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: item
            ]
            SecItemDelete(query as CFDictionary)
        }
        
        UserDefaults.standard.removeObject(forKey: "HIAH_Certificate_Expiration")
    }
}
