/**
 * HIAHVPN.h
 * Simplified VPN management for HIAH Desktop
 *
 * Single unified manager for VPN + em_proxy.
 * Inspired by SideStore's clean approach.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// VPN connection status
typedef NS_ENUM(NSInteger, HIAHVPNStatus) {
    HIAHVPNStatusDisconnected = 0,  // No VPN active
    HIAHVPNStatusConnected = 1,     // VPN is active
    HIAHVPNStatusNeedsSetup = 2     // User needs to configure LocalDevVPN
};

/// Notification posted when VPN status changes
extern NSNotificationName const HIAHVPNStatusDidChangeNotification;

/**
 * HIAHVPN - Unified VPN manager
 *
 * Handles:
 * - em_proxy lifecycle
 * - VPN status monitoring
 * - LocalDevVPN configuration
 * - Bypass coordinator updates
 */
@interface HIAHVPN : NSObject

/// Shared instance
+ (instancetype)shared;

/// Current VPN status
@property (nonatomic, readonly) HIAHVPNStatus status;

/// Whether VPN is connected and ready for JIT
@property (nonatomic, readonly) BOOL isReady;

/// Whether setup has been completed
@property (nonatomic, readonly) BOOL isSetupComplete;

#pragma mark - Lifecycle

/// Start VPN services (call on app launch)
- (void)start;

/// Stop VPN services (call on app termination)
- (void)stop;

#pragma mark - Setup

/// Check if setup is needed
- (BOOL)needsSetup;

/// Mark setup as complete
- (void)completeSetup;

/// Reset setup (for debugging/re-setup)
- (void)resetSetup;

#pragma mark - LocalDevVPN

/// Open LocalDevVPN app
- (void)openLocalDevVPN;

/// Open App Store to install LocalDevVPN
- (void)installLocalDevVPN;

#pragma mark - Status

/// Force refresh VPN status
- (void)refresh;

/// Verify VPN is fully connected (em_proxy + interface)
- (BOOL)verifyConnection;

@end

NS_ASSUME_NONNULL_END

