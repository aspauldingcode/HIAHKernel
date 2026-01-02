/**
 * HIAHMinimuxerJIT.swift
 * HIAH LoginWindow - JIT Enablement via Minimuxer
 *
 * Provides JIT enablement functionality using the minimuxer library.
 * JIT is enabled by attaching a debugger to the target process.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation

/// Errors that can occur during JIT enablement
public enum HIAHJITError: Error, LocalizedError {
    case minimuxerNotStarted
    case minimuxerNotReady
    case noPairingFile
    case vpnNotConnected
    case debugFailed(String)
    case attachFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .minimuxerNotStarted:
            return "Minimuxer service not started. Call startMinimuxer() first."
        case .minimuxerNotReady:
            return "Minimuxer not ready. Check device connection and VPN status."
        case .noPairingFile:
            return "No pairing file found. Device must be paired with a computer first."
        case .vpnNotConnected:
            return "VPN not connected. Enable LocalDevVPN first."
        case .debugFailed(let msg):
            return "Failed to enable JIT for app: \(msg)"
        case .attachFailed(let msg):
            return "Failed to attach debugger: \(msg)"
        }
    }
}

/// Manages JIT enablement via Minimuxer
/// 
/// JIT is enabled by attaching a debugger to the target process via lockdownd.
/// This requires:
/// 1. A valid pairing file from a trusted computer
/// 2. The em_proxy VPN tunnel to be connected
/// 3. Minimuxer service to be started
@objc public class HIAHMinimuxerJIT: NSObject {
    
    /// Shared instance
    @objc public static let shared = HIAHMinimuxerJIT()
    
    /// Whether minimuxer has been started
    @objc public private(set) var isStarted = false
    
    /// Notification posted when JIT is successfully enabled
    @objc public static let JITEnabledNotification = Notification.Name("HIAHJITEnabled")
    
    /// Notification posted when JIT enablement fails
    @objc public static let JITFailedNotification = Notification.Name("HIAHJITFailed")
    
    private let minimuxer = HIAHMinimuxer.shared
    
    private override init() {
        super.init()
        print("[MinimuxerJIT] Initialized")
    }
    
    // MARK: - Minimuxer Lifecycle
    
    /// Starts the minimuxer service
    /// - Parameters:
    ///   - pairingFile: Path to the mobiledevicepairing file
    ///   - logPath: Optional path for log output
    ///   - consoleLogging: Whether to enable console logging
    @objc public func startMinimuxer(pairingFile: String, logPath: String = "", consoleLogging: Bool = false) throws {
        print("[MinimuxerJIT] Starting minimuxer...")
        
        let success = minimuxer.initialize(
            pairingFile: pairingFile,
            logPath: logPath.isEmpty ? nil : logPath,
            consoleLogging: consoleLogging
        )
        
        if success {
            isStarted = true
            print("[MinimuxerJIT] ✅ Minimuxer started successfully")
        } else {
            let error = minimuxer.lastErrorMessage ?? "Unknown error"
            print("[MinimuxerJIT] ❌ Failed to start minimuxer: \(error)")
            throw HIAHJITError.debugFailed(error)
        }
    }
    
    /// Starts minimuxer with the default pairing file
    @objc public func startMinimuxerWithDefaultPairing() throws {
        guard let pairingFile = HIAHMinimuxer.defaultPairingFilePath() else {
            throw HIAHJITError.noPairingFile
        }
        try startMinimuxer(pairingFile: pairingFile)
    }
    
    /// Checks if minimuxer is ready
    @objc public var isReady: Bool {
        return minimuxer.isReady
    }
    
    /// Checks if device is connected
    @objc public var isDeviceConnected: Bool {
        return minimuxer.testDeviceConnection()
    }
    
    /// Gets the device UDID
    @objc public var deviceUDID: String? {
        return minimuxer.fetchDeviceUDID()
    }
    
    // MARK: - JIT Enablement
    
    /// Enables JIT for an app by bundle ID
    /// - Parameter bundleID: The bundle identifier of the app
    @objc public func enableJIT(forBundleID bundleID: String) throws {
        print("[MinimuxerJIT] Enabling JIT for: \(bundleID)")
        
        // Check prerequisites
        guard isStarted else {
            throw HIAHJITError.minimuxerNotStarted
        }
        
        guard isReady else {
            throw HIAHJITError.minimuxerNotReady
        }
        
        do {
            try minimuxer.enableJIT(forBundleID: bundleID)
            
            // Post success notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: HIAHMinimuxerJIT.JITEnabledNotification,
                    object: self,
                    userInfo: ["bundleID": bundleID]
                )
            }
            
            print("[MinimuxerJIT] ✅ JIT enabled for \(bundleID)")
        } catch {
            let message = error.localizedDescription
            
            // Post failure notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: HIAHMinimuxerJIT.JITFailedNotification,
                    object: self,
                    userInfo: ["bundleID": bundleID, "error": message]
                )
            }
            
            throw HIAHJITError.debugFailed(message)
        }
    }
    
    /// Enables JIT for a process by PID
    /// - Parameter pid: The process ID
    @objc public func enableJIT(forPID pid: UInt32) throws {
        print("[MinimuxerJIT] Enabling JIT for PID: \(pid)")
        
        guard isStarted else {
            throw HIAHJITError.minimuxerNotStarted
        }
        
        guard isReady else {
            throw HIAHJITError.minimuxerNotReady
        }
        
        do {
            try minimuxer.attachDebugger(toPID: pid)
            
            // Post success notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: HIAHMinimuxerJIT.JITEnabledNotification,
                    object: self,
                    userInfo: ["pid": pid]
                )
            }
            
            print("[MinimuxerJIT] ✅ JIT enabled for PID \(pid)")
        } catch {
            throw HIAHJITError.attachFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Pairing File Management
    
    /// Gets the path to the pairing file in Documents
    @objc public var pairingFilePath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ALTPairingFile.mobiledevicepairing").path
    }
    
    /// Checks if a pairing file exists
    @objc public var hasPairingFile: Bool {
        return HIAHMinimuxer.hasPairingFile()
    }
    
    /// Loads the pairing file contents
    @objc public func loadPairingFile() -> String? {
        guard let path = HIAHMinimuxer.defaultPairingFilePath() else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
    
    /// Saves a pairing file
    @objc public func savePairingFile(_ contents: String) throws {
        try contents.write(toFile: pairingFilePath, atomically: true, encoding: .utf8)
        print("[MinimuxerJIT] Pairing file saved")
    }
    
    // MARK: - Availability
    
    /// Check if minimuxer-based JIT is available
    @objc public class func isAvailable() -> Bool {
        return HIAHMinimuxer.isAvailable()
    }
    
    /// Get information about minimuxer status
    @objc public class func statusInfo() -> String {
        return HIAHMinimuxer.disabledReason()
    }
}
