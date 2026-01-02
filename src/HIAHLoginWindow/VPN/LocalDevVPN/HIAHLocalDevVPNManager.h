/**
 * HIAHLocalDevVPNManager.h
 * HIAH LoginWindow - LocalDevVPN Integration
 *
 * Integrates with LocalDevVPN (App Store) to provide VPN loopback
 * for JIT enablement without requiring a paid developer account.
 *
 * Based on SideStore's official approach (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Status of LocalDevVPN connection
typedef NS_ENUM(NSInteger, HIAHLocalDevVPNStatus) {
    HIAHLocalDevVPNStatusNotInstalled,    // LocalDevVPN app not installed
    HIAHLocalDevVPNStatusDisconnected,    // LocalDevVPN installed but VPN not active
    HIAHLocalDevVPNStatusConnecting,      // VPN is connecting
    HIAHLocalDevVPNStatusConnected,       // VPN is active
    HIAHLocalDevVPNStatusError            // Error state
};

/// Manages LocalDevVPN integration for JIT enablement
/// LocalDevVPN is the official VPN used by SideStore
@interface HIAHLocalDevVPNManager : NSObject

+ (instancetype)sharedManager;

/// Current LocalDevVPN/VPN status
@property (nonatomic, readonly) HIAHLocalDevVPNStatus status;

/// Whether LocalDevVPN is currently active
@property (nonatomic, readonly) BOOL isVPNActive;

/// Check if LocalDevVPN app is installed
- (BOOL)isLocalDevVPNInstalled;

/// Open App Store to LocalDevVPN download page
- (void)openLocalDevVPNInAppStore;

/// Open LocalDevVPN app
- (void)openLocalDevVPN;

#pragma mark - EM Proxy Control

/// Start the em_proxy loopback server (required for JIT)
/// Returns YES on success, NO on failure
- (BOOL)startEMProxy;

/// Stop the em_proxy server
- (void)stopEMProxy;

/// Check if em_proxy is currently running
- (BOOL)isEMProxyRunning;

/// Verify full VPN connection (em_proxy + LocalDevVPN)
/// Returns YES if both em_proxy is running and LocalDevVPN is connected through it
- (BOOL)verifyFullVPNConnection;

#pragma mark - VPN Status Monitoring

/// Start monitoring VPN status
- (void)startMonitoringVPNStatus;

/// Stop monitoring VPN status
- (void)stopMonitoringVPNStatus;

/// Refresh VPN status manually
- (void)refreshVPNStatus;

#pragma mark - Setup State

/// Check if HIAH VPN setup has been completed by user
- (BOOL)isHIAHVPNConfigured;

/// Mark setup as completed (called when user finishes setup wizard)
- (void)markSetupCompleted;

/// Reset setup state (for re-running setup wizard)
- (void)resetSetup;

@end

NS_ASSUME_NONNULL_END

