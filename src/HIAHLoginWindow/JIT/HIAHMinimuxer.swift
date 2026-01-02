/**
 * HIAHMinimuxer.swift
 * HIAH LoginWindow - Minimuxer Swift Wrapper
 *
 * Provides a Swift-friendly interface to the minimuxer Rust library for:
 * - Device communication via lockdownd
 * - JIT enablement via debug attachment
 * - App installation/removal
 * - Provisioning profile management
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation

/// Status of the Minimuxer connection
@objc public enum HIAHMinimuxerStatus: Int {
    case notStarted = 0
    case starting = 1
    case ready = 2
    case noDevice = 3
    case noPairingFile = 4
    case error = 5
}

/// Swift wrapper for the Minimuxer Rust library
/// Provides high-level interface for device communication and JIT enablement
@objc public class HIAHMinimuxer: NSObject {
    
    // MARK: - Singleton
    
    @objc public static let shared = HIAHMinimuxer()
    
    // MARK: - Properties
    
    @objc public private(set) var status: HIAHMinimuxerStatus = .notStarted {
        didSet {
            NotificationCenter.default.post(
                name: NSNotification.Name("HIAHMinimuxerStatusChanged"),
                object: self,
                userInfo: ["status": status.rawValue]
            )
        }
    }
    @objc public private(set) var lastErrorMessage: String?
    
    @objc public var isReady: Bool {
        return ready()
    }
    
    private var isStarted = false
    
    private override init() {
        super.init()
        print("[Minimuxer] Initialized")
    }
    
    // MARK: - Lifecycle
    
    /// Initialize and start the minimuxer service
    /// - Parameters:
    ///   - pairingFilePath: Path to the mobiledevicepairing file
    ///   - logPath: Optional path for log output
    ///   - consoleLogging: Whether to enable console logging
    /// - Returns: True if started successfully
    @objc public func initialize(pairingFile pairingFilePath: String,
                                 logPath: String? = nil,
                                 consoleLogging: Bool = false) -> Bool {
        guard !isStarted else {
            print("[Minimuxer] Already started")
            return true
        }
        
        status = .starting
        
        do {
            let logPathToUse = logPath ?? ""
            
            // Use typealias to avoid name collision with instance method `start`
            typealias MinimuxerStartFunc = (String, String) throws -> ()
            typealias MinimuxerStartWithLoggerFunc = (String, String, Bool) throws -> ()
            
            if consoleLogging {
                set_debug(true)
                let startFn: MinimuxerStartWithLoggerFunc = startWithLogger
                try startFn(pairingFilePath, logPathToUse, true)
            } else {
                // Reference the global `start` function explicitly
                let startFn: MinimuxerStartFunc = { try HIAHDesktop.start($0, $1) }
                try startFn(pairingFilePath, logPathToUse)
            }
            
            isStarted = true
            
            // Check if device is connected
            if ready() {
                status = .ready
                print("[Minimuxer] ✅ Started and ready")
                return true
            } else {
                status = .noDevice
                lastErrorMessage = "No device connected"
                print("[Minimuxer] ⚠️ Started but no device connected")
                return false
            }
        } catch let error as MinimuxerError {
            handleMinimuxerError(error)
            return false
        } catch {
            status = .error
            lastErrorMessage = error.localizedDescription
            print("[Minimuxer] ❌ Failed to start: \(error)")
            return false
        }
    }
    
    /// Start minimuxer with just a pairing file
    @objc public func start(pairingFile pairingFilePath: String) -> Bool {
        return initialize(pairingFile: pairingFilePath, logPath: nil, consoleLogging: false)
    }
    
    /// Stop the minimuxer service
    @objc public func stop() {
        isStarted = false
        status = .notStarted
        print("[Minimuxer] Stopped")
    }
    
    // MARK: - Device Info
    
    /// Fetch the connected device's UDID
    @objc public func fetchDeviceUDID() -> String? {
        guard let rustString = fetch_udid() else {
            print("[Minimuxer] ⚠️ No UDID available (no device?)")
            return nil
        }
        let udid = rustString.toString()
        print("[Minimuxer] Device UDID: \(udid)")
        return udid
    }
    
    /// Test if a device is connected and responding
    @objc public func testDeviceConnection() -> Bool {
        let connected = test_device_connection()
        print("[Minimuxer] Device connection test: \(connected ? "✅" : "❌")")
        return connected
    }
    
    // MARK: - JIT Enablement
    
    /// Enable JIT for an app by bundle ID
    /// This works by attaching a debugger to the app process
    @objc public func enableJIT(forBundleID bundleID: String) throws {
        print("[Minimuxer] Enabling JIT for: \(bundleID)")
        
        guard isReady else {
            throw NSError(domain: "HIAHMinimuxer", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Minimuxer is not ready"])
        }
        
        do {
            try debug_app(bundleID)
            print("[Minimuxer] ✅ JIT enabled for \(bundleID)")
        } catch let error as MinimuxerError {
            let description = describe_error(error).toString()
            print("[Minimuxer] ❌ JIT failed for \(bundleID): \(description)")
            throw NSError(domain: "HIAHMinimuxer", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "JIT failed: \(description)"])
        }
    }
    
    /// Attach debugger to a process by PID (enables JIT)
    @objc public func attachDebugger(toPID pid: UInt32) throws {
        print("[Minimuxer] Attaching debugger to PID: \(pid)")
        
        guard isReady else {
            throw NSError(domain: "HIAHMinimuxer", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Minimuxer is not ready"])
        }
        
        do {
            try attach_debugger(pid)
            print("[Minimuxer] ✅ Debugger attached to PID \(pid)")
        } catch let error as MinimuxerError {
            let description = describe_error(error).toString()
            print("[Minimuxer] ❌ Attach failed for PID \(pid): \(description)")
            throw NSError(domain: "HIAHMinimuxer", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Attach failed: \(description)"])
        }
    }
    
    // MARK: - App Installation
    
    /// Install an IPA file
    /// - Parameters:
    ///   - bundleID: Bundle identifier for the app
    ///   - ipaData: Raw IPA data
    @objc public func installIPA(bundleID: String, ipaData: Data) throws {
        print("[Minimuxer] Installing IPA for: \(bundleID)")
        
        guard isReady else {
            throw NSError(domain: "HIAHMinimuxer", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Minimuxer is not ready"])
        }
        
        do {
            // First, yeet the IPA data to the device via AFC
            try ipaData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let buffer = ptr.bindMemory(to: UInt8.self)
                try yeet_app_afc(bundleID, buffer)
            }
            
            // Then install it
            try install_ipa(bundleID)
            print("[Minimuxer] ✅ IPA installed: \(bundleID)")
        } catch let error as MinimuxerError {
            let description = describe_error(error).toString()
            print("[Minimuxer] ❌ Install failed for \(bundleID): \(description)")
            throw NSError(domain: "HIAHMinimuxer", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Install failed: \(description)"])
        }
    }
    
    /// Remove an installed app
    @objc public func removeApp(bundleID: String) throws {
        print("[Minimuxer] Removing app: \(bundleID)")
        
        guard isReady else {
            throw NSError(domain: "HIAHMinimuxer", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Minimuxer is not ready"])
        }
        
        do {
            try remove_app(bundleID)
            print("[Minimuxer] ✅ App removed: \(bundleID)")
        } catch let error as MinimuxerError {
            let description = describe_error(error).toString()
            print("[Minimuxer] ❌ Remove failed for \(bundleID): \(description)")
            throw NSError(domain: "HIAHMinimuxer", code: 5,
                         userInfo: [NSLocalizedDescriptionKey: "Remove failed: \(description)"])
        }
    }
    
    // MARK: - Provisioning Profiles
    
    /// Install a provisioning profile
    @objc public func installProvisioningProfile(_ profileData: Data) throws {
        print("[Minimuxer] Installing provisioning profile")
        
        guard isReady else {
            throw NSError(domain: "HIAHMinimuxer", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Minimuxer is not ready"])
        }
        
        do {
            try profileData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let buffer = ptr.bindMemory(to: UInt8.self)
                try install_provisioning_profile(buffer)
            }
            print("[Minimuxer] ✅ Profile installed")
        } catch let error as MinimuxerError {
            let description = describe_error(error).toString()
            print("[Minimuxer] ❌ Profile install failed: \(description)")
            throw NSError(domain: "HIAHMinimuxer", code: 6,
                         userInfo: [NSLocalizedDescriptionKey: "Profile install failed: \(description)"])
        }
    }
    
    /// Remove a provisioning profile by ID
    @objc public func removeProvisioningProfile(id profileID: String) throws {
        print("[Minimuxer] Removing provisioning profile: \(profileID)")
        
        guard isReady else {
            throw NSError(domain: "HIAHMinimuxer", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Minimuxer is not ready"])
        }
        
        do {
            try remove_provisioning_profile(profileID)
            print("[Minimuxer] ✅ Profile removed: \(profileID)")
        } catch let error as MinimuxerError {
            let description = describe_error(error).toString()
            print("[Minimuxer] ❌ Profile remove failed: \(description)")
            throw NSError(domain: "HIAHMinimuxer", code: 7,
                         userInfo: [NSLocalizedDescriptionKey: "Profile remove failed: \(description)"])
        }
    }
    
    // MARK: - Pairing File
    
    /// Get the default location for the pairing file
    @objc public class func defaultPairingFilePath() -> String? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documentsDir = paths.first else { return nil }
        
        // Check various pairing file names
        let pairingFileNames = [
            "ALTPairingFile.mobiledevicepairing",
            "pairing_file.plist",
            "pairing.plist"
        ]
        
        for name in pairingFileNames {
            let path = documentsDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) {
                return path.path
            }
        }
        
        return nil
    }
    
    /// Check if a pairing file exists
    @objc public class func hasPairingFile() -> Bool {
        return defaultPairingFilePath() != nil
    }
    
    // MARK: - Availability
    
    /// Check if minimuxer is available
    @objc public class func isAvailable() -> Bool {
        return true  // Now available with real implementation
    }
    
    /// Get information about why minimuxer might not work
    /// (Kept for backward compatibility - now returns helpful info instead of disabled message)
    @objc public class func disabledReason() -> String {
        if !hasPairingFile() {
            return "No pairing file found. Please pair your device using SideStore or AltServer."
        }
        return "Minimuxer is available. If issues occur, check: 1) Device connected 2) VPN/Tunnel active 3) Valid pairing file"
    }
    
    // MARK: - Error Handling
    
    private func handleMinimuxerError(_ error: MinimuxerError) {
        let description = describe_error(error).toString()
        lastErrorMessage = description
        
        switch error {
        case .NoDevice:
            status = .noDevice
        case .PairingFile:
            status = .noPairingFile
        default:
            status = .error
        }
        
        print("[Minimuxer] ❌ Error: \(description)")
    }
}
