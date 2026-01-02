/**
 * HIAHVPNManager.h
 * HIAH LoginWindow - VPN Management
 *
 * Manages VPN connectivity using LocalDevVPN (App Store) for JIT enablement.
 * This is the official VPN used by SideStore.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>
#import "LocalDevVPN/HIAHLocalDevVPNManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface HIAHVPNManager : NSObject

+ (instancetype)sharedManager;

/// Whether VPN is currently active
@property (nonatomic, readonly) BOOL isVPNActive;

/// Set up VPN manager
- (void)setupVPNManager;

/// Start VPN (opens LocalDevVPN for manual activation)
- (void)startVPNWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completion;

/// Stop VPN (user must do this manually in LocalDevVPN)
- (void)stopVPN;

#pragma mark - LocalDevVPN Integration

/// Check if LocalDevVPN is installed
- (BOOL)isLocalDevVPNInstalled;

/// Current LocalDevVPN status
- (HIAHLocalDevVPNStatus)localDevVPNStatus;

/// Open LocalDevVPN app
- (void)openLocalDevVPNApp;

/// Open App Store to install LocalDevVPN
- (void)installLocalDevVPN;

@end

NS_ASSUME_NONNULL_END
