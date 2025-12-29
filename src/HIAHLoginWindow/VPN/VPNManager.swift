/**
 * VPNManager.swift
 * HIAH LoginWindow - VPN Management
 *
 * Manages EM Proxy VPN tunnel for untethered app installation.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation
import NetworkExtension

class VPNManager: ObservableObject {
    static let shared = VPNManager()
    
    @Published var isVPNActive = false
    @Published var vpnStatus: NEVPNStatus = .disconnected
    
    private var vpnManager: NETunnelProviderManager?
    private let serverBindAddress = "127.0.0.1:65399"
    
    private init() {
        setupVPNManager()
    }
    
    // MARK: - VPN Setup
    
    private func setupVPNManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                print("[VPN] Failed to load VPN managers: \(error)")
                return
            }
            
            if let existingManager = managers?.first {
                self?.vpnManager = existingManager
                self?.observeVPNStatus()
            } else {
                self?.createVPNConfiguration()
            }
        }
    }
    
    private func createVPNConfiguration() {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "HIAH Desktop VPN"
        
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.aspauldingcode.HIAHDesktop.VPNExtension"
        proto.serverAddress = "127.0.0.1"
        
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        
        manager.saveToPreferences { [weak self] error in
            if let error = error {
                print("[VPN] Failed to save VPN configuration: \(error)")
                return
            }
            
            self?.vpnManager = manager
            self?.observeVPNStatus()
            print("[VPN] VPN configuration created")
        }
    }
    
    private func observeVPNStatus() {
        guard let manager = vpnManager else { return }
        
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            self?.updateVPNStatus()
        }
        
        updateVPNStatus()
    }
    
    private func updateVPNStatus() {
        guard let manager = vpnManager else { return }
        vpnStatus = manager.connection.status
        isVPNActive = (vpnStatus == .connected)
        
        print("[VPN] Status: \(vpnStatus.description)")
    }
    
    // MARK: - VPN Control
    
    func startVPN() async throws {
        print("[VPN] Starting VPN tunnel...")
        
        // Start em_proxy using bridge
        let result = EMProxyBridge.startVPN(withBindAddress: serverBindAddress)
        guard result == 0 else {
            throw NSError(domain: "VPNManager", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to start em_proxy"])
        }
        
        print("[VPN] EM Proxy started on \(serverBindAddress)")
        
        // Test connection
        let testResult = EMProxyBridge.testVPN(withTimeout: 5000) // 5 second timeout
        guard testResult == 0 else {
            EMProxyBridge.stopVPN()
            throw NSError(domain: "VPNManager", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "VPN tunnel test failed"])
        }
        
        print("[VPN] VPN tunnel active and tested")
        isVPNActive = true
    }
    
    func stopVPN() {
        print("[VPN] Stopping VPN tunnel...")
        EMProxyBridge.stopVPN()
        isVPNActive = false
        print("[VPN] VPN tunnel stopped")
    }
    
    func testVPN() async throws -> Bool {
        let result = EMProxyBridge.testVPN(withTimeout: 5000)
        return result == 0
    }
}

// MARK: - NEVPNStatus Description

extension NEVPNStatus {
    var description: String {
        switch self {
        case .invalid: return "Invalid"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reasserting: return "Reasserting"
        case .disconnecting: return "Disconnecting"
        @unknown default: return "Unknown"
        }
    }
}

