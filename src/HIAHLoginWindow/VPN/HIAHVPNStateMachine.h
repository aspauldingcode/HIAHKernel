/**
 * HIAHVPNStateMachine.h
 * Declarative state machine for VPN/em_proxy management
 *
 * States are explicit, transitions are defined, no implicit behavior.
 * Copyright (c) 2025 Alex Spaulding - AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - State Definition

/// All possible states of the VPN system
typedef NS_ENUM(NSInteger, HIAHVPNState) {
    /// Initial state - nothing running
    HIAHVPNStateIdle = 0,
    
    /// em_proxy is starting up
    HIAHVPNStateStartingProxy,
    
    /// em_proxy running, waiting for VPN connection
    HIAHVPNStateProxyReady,
    
    /// VPN interface detected, system is fully operational
    HIAHVPNStateConnected,
    
    /// An error occurred (check lastError)
    HIAHVPNStateError
};

/// Events that trigger state transitions
typedef NS_ENUM(NSInteger, HIAHVPNEvent) {
    /// Request to start the VPN system
    HIAHVPNEventStart,
    
    /// em_proxy started successfully
    HIAHVPNEventProxyStarted,
    
    /// em_proxy failed to start
    HIAHVPNEventProxyFailed,
    
    /// VPN interface became active
    HIAHVPNEventVPNConnected,
    
    /// VPN interface went down
    HIAHVPNEventVPNDisconnected,
    
    /// Request to stop the VPN system
    HIAHVPNEventStop,
    
    /// Retry after error
    HIAHVPNEventRetry
};

#pragma mark - State Machine

/// Notification posted when state changes
extern NSNotificationName const HIAHVPNStateDidChangeNotification;

/// Key in notification userInfo for previous state (NSNumber)
extern NSString * const HIAHVPNPreviousStateKey;

/**
 * HIAHVPNStateMachine
 *
 * A declarative state machine for managing VPN and em_proxy.
 * 
 * Design principles:
 * - Single source of truth: `state` property
 * - Explicit transitions: `sendEvent:` is the only way to change state
 * - No implicit behavior: every action is triggered by a state transition
 * - Predictable: same state + same event = same result
 */
@interface HIAHVPNStateMachine : NSObject

/// Shared instance
+ (instancetype)shared;

#pragma mark - State

/// Current state (read-only, changes only via sendEvent:)
@property (nonatomic, readonly) HIAHVPNState state;

/// Human-readable state name
@property (nonatomic, readonly) NSString *stateName;

/// Whether the system is fully connected (em_proxy + VPN)
@property (nonatomic, readonly) BOOL isConnected;

/// Whether setup has been completed by user
@property (nonatomic, readonly) BOOL isSetupComplete;

/// Last error (nil if no error)
@property (nonatomic, readonly, nullable) NSError *lastError;

#pragma mark - Events

/// Send an event to trigger a state transition
/// @param event The event to process
/// @return YES if the event caused a transition, NO if ignored
- (BOOL)sendEvent:(HIAHVPNEvent)event;

/// Send an event with associated error info
- (BOOL)sendEvent:(HIAHVPNEvent)event error:(nullable NSError *)error;

#pragma mark - Setup

/// Mark setup as complete (persisted)
- (void)markSetupComplete;

/// Reset setup status (for re-running wizard)
- (void)resetSetup;

#pragma mark - Config

/// Generate configuration (not needed for LocalDevVPN - kept for API compatibility)
/// Returns empty string since LocalDevVPN doesn't require configuration files
- (NSString *)generateConfig;

/// Save config to Documents folder, returns path or nil
- (nullable NSString *)saveConfigToDocuments;

/// Copy config to clipboard
- (void)copyConfigToClipboard;

/// Config file URL in Documents
- (NSURL *)configFileURL;

#pragma mark - Detection

/// Detects if HIAH VPN is actually connected by checking em_proxy and VPN interface
/// This is more reliable than just checking state, as it verifies actual system state
- (BOOL)detectHIAHVPNConnected;

#pragma mark - Debug

/// Get a description of valid transitions from current state
- (NSString *)validTransitionsDescription;

@end

NS_ASSUME_NONNULL_END

