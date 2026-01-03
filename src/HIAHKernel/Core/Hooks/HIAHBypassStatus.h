/**
 * HIAHBypassStatus.h
 * HIAH ProcessRunner Extension - Bypass Status Reader
 *
 * Lightweight status reader for ProcessRunner extension.
 * Reads bypass status from App Group shared storage.
 * This allows the extension to check VPN/JIT status without
 * importing LoginWindow classes.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Lightweight bypass status checker for extension
@interface HIAHBypassStatus : NSObject

+ (instancetype)sharedStatus;

/// Whether VPN is currently active (from shared storage)
@property (nonatomic, readonly) BOOL isVPNActive;

/// Whether JIT is currently enabled (from shared storage + direct check)
@property (nonatomic, readonly) BOOL isJITEnabled;

/// Whether bypass system is fully ready
@property (nonatomic, readonly) BOOL isBypassReady;

/// Refresh status from shared storage
- (void)refreshStatus;

@end

NS_ASSUME_NONNULL_END

