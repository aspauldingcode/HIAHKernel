/**
 * HIAHVPNStateMachine.m
 * Declarative state machine implementation
 *
 * Copyright (c) 2025 Alex Spaulding - AGPLv3
 */

#import "HIAHVPNStateMachine.h"
#import "EMProxyBridge.h"
#import "../../HIAHDesktop/HIAHLogging.h"
#import <UIKit/UIKit.h>
#import <ifaddrs.h>
#import <net/if.h>

NSNotificationName const HIAHVPNStateDidChangeNotification = @"HIAHVPNStateDidChange";
NSString * const HIAHVPNPreviousStateKey = @"previousState";

// UserDefaults key for setup completion
static NSString * const kSetupCompleteKey = @"HIAHVPNSetupComplete.v2";

// LocalDevVPN doesn't require configuration - it's a simple on/off VPN

#pragma mark - Transition Table

/// A transition entry: (fromState, event) -> toState
typedef struct {
    HIAHVPNState fromState;
    HIAHVPNEvent event;
    HIAHVPNState toState;
} HIAHVPNTransition;

/// The complete transition table - defines ALL valid state transitions
/// If a (state, event) pair is not in this table, the event is ignored
static const HIAHVPNTransition kTransitionTable[] = {
    // From Idle
    { HIAHVPNStateIdle,          HIAHVPNEventStart,           HIAHVPNStateStartingProxy },
    
    // From StartingProxy
    { HIAHVPNStateStartingProxy, HIAHVPNEventProxyStarted,    HIAHVPNStateProxyReady },
    { HIAHVPNStateStartingProxy, HIAHVPNEventProxyFailed,     HIAHVPNStateError },
    { HIAHVPNStateStartingProxy, HIAHVPNEventStop,            HIAHVPNStateIdle },
    
    // From ProxyReady
    { HIAHVPNStateProxyReady,    HIAHVPNEventVPNConnected,    HIAHVPNStateConnected },
    { HIAHVPNStateProxyReady,    HIAHVPNEventStop,            HIAHVPNStateIdle },
    
    // From Connected
    { HIAHVPNStateConnected,     HIAHVPNEventVPNDisconnected, HIAHVPNStateProxyReady },
    { HIAHVPNStateConnected,     HIAHVPNEventProxyFailed,     HIAHVPNStateError },
    { HIAHVPNStateConnected,     HIAHVPNEventStop,            HIAHVPNStateIdle },
    
    // From Error
    { HIAHVPNStateError,         HIAHVPNEventRetry,           HIAHVPNStateStartingProxy },
    { HIAHVPNStateError,         HIAHVPNEventStop,            HIAHVPNStateIdle },
};

static const size_t kTransitionCount = sizeof(kTransitionTable) / sizeof(kTransitionTable[0]);

#pragma mark - Implementation

@interface HIAHVPNStateMachine ()
@property (nonatomic, assign) HIAHVPNState state;
@property (nonatomic, strong, nullable) NSError *lastError;
@property (nonatomic, strong) NSTimer *monitorTimer;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@end

@implementation HIAHVPNStateMachine

#pragma mark - Singleton

+ (instancetype)shared {
    static HIAHVPNStateMachine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _state = HIAHVPNStateIdle;
        _lastError = nil;
        _stateQueue = dispatch_queue_create("com.aspauldingcode.HIAHVPN.state", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Public Properties

- (NSString *)stateName {
    switch (self.state) {
        case HIAHVPNStateIdle:          return @"Idle";
        case HIAHVPNStateStartingProxy: return @"StartingProxy";
        case HIAHVPNStateProxyReady:    return @"ProxyReady";
        case HIAHVPNStateConnected:     return @"Connected";
        case HIAHVPNStateError:         return @"Error";
    }
    return @"Unknown";
}

- (BOOL)isConnected {
    return self.state == HIAHVPNStateConnected;
}

- (BOOL)isSetupComplete {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSetupCompleteKey];
}

#pragma mark - State Transitions

- (BOOL)sendEvent:(HIAHVPNEvent)event {
    return [self sendEvent:event error:nil];
}

- (BOOL)sendEvent:(HIAHVPNEvent)event error:(NSError *)error {
    __block BOOL transitioned = NO;
    __block HIAHVPNState oldState;
    __block HIAHVPNState newState;
    
    dispatch_sync(self.stateQueue, ^{
        oldState = self.state;
        
        // Look up transition in table
        for (size_t i = 0; i < kTransitionCount; i++) {
            if (kTransitionTable[i].fromState == oldState && 
                kTransitionTable[i].event == event) {
                newState = kTransitionTable[i].toState;
                transitioned = YES;
                break;
            }
        }
        
        if (transitioned) {
            self.state = newState;
            if (error) {
                self.lastError = error;
            } else if (newState != HIAHVPNStateError) {
                self.lastError = nil;
            }
        }
    });
    
    if (transitioned) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"[%@] → %@ → [%@]",
                  [self nameForState:oldState],
                  [self nameForEvent:event],
                  [self nameForState:newState]);
        
        // Execute actions for this transition (on main thread)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self executeActionsForTransitionFrom:oldState to:newState];
            
            // Post notification
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:HIAHVPNStateDidChangeNotification
                              object:self
                            userInfo:@{HIAHVPNPreviousStateKey: @(oldState)}];
        });
    } else {
        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"Event %@ ignored in state %@",
                  [self nameForEvent:event], [self nameForState:oldState]);
    }
    
    return transitioned;
}

#pragma mark - Actions

/// Execute side effects for a state transition
/// This is the ONLY place where actions happen
- (void)executeActionsForTransitionFrom:(HIAHVPNState)from to:(HIAHVPNState)to {
    switch (to) {
        case HIAHVPNStateIdle:
            [self actionStopEverything];
            break;
            
        case HIAHVPNStateStartingProxy:
            [self actionStartProxy];
            break;
            
        case HIAHVPNStateProxyReady:
            [self actionStartMonitoring];
            [self actionUpdateBypassCoordinator:NO];
            break;
            
        case HIAHVPNStateConnected:
            [self actionUpdateBypassCoordinator:YES];
            [self actionEnableJIT];
            break;
            
        case HIAHVPNStateError:
            [self actionStopMonitoring];
            break;
    }
}

- (void)actionStartProxy {
    // Start em_proxy asynchronously, send event when done
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int result = [EMProxyBridge startVPNWithBindAddress:@"127.0.0.1:65399"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (result == 0) {
                [self sendEvent:HIAHVPNEventProxyStarted];
            } else {
                NSError *error = [NSError errorWithDomain:@"HIAHVPNStateMachine"
                                                     code:result
                                                 userInfo:@{NSLocalizedDescriptionKey: @"em_proxy failed to start"}];
                [self sendEvent:HIAHVPNEventProxyFailed error:error];
            }
        });
    });
}

- (void)actionStopEverything {
    [self actionStopMonitoring];
    [EMProxyBridge stopVPN];
    [self actionUpdateBypassCoordinator:NO];
}

- (void)actionStartMonitoring {
    [self actionStopMonitoring];
    
    // Check VPN status every 5 seconds (reduced frequency since test_emotional_damage
    // can take up to 1 second to complete)
    self.monitorTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                         target:self
                                                       selector:@selector(checkVPNStatus)
                                                       userInfo:nil
                                                        repeats:YES];
    // Check immediately
    [self checkVPNStatus];
}

- (void)actionStopMonitoring {
    [self.monitorTimer invalidate];
    self.monitorTimer = nil;
}

- (void)checkVPNStatus {
    // CRITICAL: Run expensive VPN detection on background queue to avoid blocking main thread
    // This prevents text input lag in login window and other UI operations
    dispatch_async(self.stateQueue ?: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        BOOL hiahVPNConnected = [self detectHIAHVPNConnected];
        
        // Send appropriate event based on current state and VPN status (on main queue)
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.state == HIAHVPNStateProxyReady && hiahVPNConnected) {
                [self sendEvent:HIAHVPNEventVPNConnected];
            } else if (self.state == HIAHVPNStateConnected && !hiahVPNConnected) {
                [self sendEvent:HIAHVPNEventVPNDisconnected];
            }
            // In other states, VPN status changes are not relevant
            
            // Always update the bypass coordinator so extension gets fresh status
            [self actionUpdateBypassCoordinator:hiahVPNConnected];
        });
    });
}

/// Detects if HIAH VPN is specifically connected.
/// Requires BOTH:
/// 1. em_proxy is running
    /// 2. test_emotional_damage succeeds (LocalDevVPN can communicate with em_proxy)
    /// 3. We can actually reach lockdownd through the VPN (if minimuxer is available)
    /// 
    /// Note: test_emotional_damage alone is not sufficient - it may pass even when
    /// LocalDevVPN isn't enabled in iOS Settings. We need to verify actual VPN routing.
- (BOOL)detectHIAHVPNConnected {
    // First check: em_proxy must be running
    BOOL emProxyRunning = [EMProxyBridge isRunning];
    if (!emProxyRunning) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"detectHIAHVPNConnected: em_proxy NOT running");
        return NO;
    }
    HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"detectHIAHVPNConnected: em_proxy IS running ✓");
    
    // Second check: Verify there's an active VPN interface (utun/ipsec) that's actually UP and RUNNING
    // This is REQUIRED - test_emotional_damage alone is not sufficient (it can pass even when VPN is disabled)
    BOOL vpnInterfaceActive = NO;
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *interface;
        for (interface = interfaces; interface != NULL; interface = interface->ifa_next) {
            if (interface->ifa_name != NULL) {
                NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
                // Check for VPN interfaces (utun, ipsec)
                if (([name hasPrefix:@"utun"] || [name hasPrefix:@"ipsec"]) &&
                    (interface->ifa_flags & IFF_UP) && (interface->ifa_flags & IFF_RUNNING)) {
                    // Verify it has an IP address (actually routing traffic)
                    if (interface->ifa_addr && interface->ifa_addr->sa_family == AF_INET) {
                        vpnInterfaceActive = YES;
                        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"Found active VPN interface: %@", name);
                        break;
                    }
                }
            }
        }
        freeifaddrs(interfaces);
    }
    
    if (!vpnInterfaceActive) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"❌ VPN not connected: No active VPN interface found (LocalDevVPN not enabled in iOS Settings)");
        return NO;
    }
    
    HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"Active VPN interface found ✓");
    
    // Second check: Use test_emotional_damage to verify LocalDevVPN can communicate with em_proxy
    // This tests if LocalDevVPN can send packets to em_proxy, which requires the VPN to be active.
    // We test multiple times to reduce false positives.
    int testResult1 = [EMProxyBridge testVPNWithTimeout:1]; // 1 second timeout
    if (testResult1 != 0) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"❌ VPN not connected: test_emotional_damage failed (returned: %d)", testResult1);
        return NO;
    }
    
    // Wait a moment and test again to ensure it's consistently working
    usleep(500000); // 500ms delay
    int testResult2 = [EMProxyBridge testVPNWithTimeout:1];
    if (testResult2 != 0) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"❌ VPN not connected: test_emotional_damage failed on second attempt (returned: %d)", testResult2);
        return NO;
    }
    
    HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"test_emotional_damage passed twice ✓");
    
    // Third check (optional): Try to start minimuxer and verify device connection through VPN
    // This is the MOST RELIABLE test - if we can connect to lockdownd via minimuxer, the VPN is definitely working.
    // SideStore uses this approach: test_emotional_damage confirms LocalDevVPN->em_proxy communication,
    // and minimuxer device connection confirms VPN->lockdownd routing.
    Class minimuxerJITClass = NSClassFromString(@"HIAHMinimuxerJIT");
    BOOL hasMinimuxerVerification = NO;
    
    if (minimuxerJITClass) {
        SEL sharedSel = NSSelectorFromString(@"shared");
        if ([minimuxerJITClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id minimuxerJIT = [minimuxerJITClass performSelector:sharedSel];
#pragma clang diagnostic pop
            if (minimuxerJIT) {
                // Try to start minimuxer if not already started (if pairing file exists)
                SEL isStartedSel = NSSelectorFromString(@"isStarted");
                SEL hasPairingSel = NSSelectorFromString(@"hasPairingFile");
                SEL startSel = NSSelectorFromString(@"startMinimuxerWithDefaultPairing");
                
                BOOL isStarted = NO;
                BOOL hasPairing = NO;
                
                if ([minimuxerJIT respondsToSelector:isStartedSel]) {
                    NSMethodSignature *sig = [minimuxerJIT methodSignatureForSelector:isStartedSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:minimuxerJIT];
                    [inv setSelector:isStartedSel];
                    [inv invoke];
                    [inv getReturnValue:&isStarted];
                }
                
                if (!isStarted && [minimuxerJIT respondsToSelector:hasPairingSel]) {
                    NSMethodSignature *sig = [minimuxerJIT methodSignatureForSelector:hasPairingSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:minimuxerJIT];
                    [inv setSelector:hasPairingSel];
                    [inv invoke];
                    [inv getReturnValue:&hasPairing];
                    
                    // Try to start minimuxer if pairing file exists
                    if (hasPairing && [minimuxerJIT respondsToSelector:startSel]) {
                        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"Starting minimuxer for VPN verification...");
                        @try {
                            [minimuxerJIT performSelector:startSel];
                            // Give minimuxer a moment to start
                            usleep(500000); // 500ms
                            // Re-check if started
                            if ([minimuxerJIT respondsToSelector:isStartedSel]) {
                                NSMethodSignature *sig = [minimuxerJIT methodSignatureForSelector:isStartedSel];
                                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                                [inv setTarget:minimuxerJIT];
                                [inv setSelector:isStartedSel];
                                [inv invoke];
                                [inv getReturnValue:&isStarted];
                            }
                        } @catch (NSException *exception) {
                            HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"Failed to start minimuxer: %@", exception);
                        }
                    }
                }
                
                // If minimuxer is started, verify it can actually connect to the device
                // This is the definitive test - if minimuxer can connect, the VPN is routing traffic
                if (isStarted) {
                    SEL isReadySel = NSSelectorFromString(@"isReady");
                    SEL isDeviceConnectedSel = NSSelectorFromString(@"isDeviceConnected");
                    
                    BOOL isReady = NO;
                    BOOL isDeviceConnected = NO;
                    
                    if ([minimuxerJIT respondsToSelector:isReadySel]) {
                        NSMethodSignature *sig = [minimuxerJIT methodSignatureForSelector:isReadySel];
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        [inv setTarget:minimuxerJIT];
                        [inv setSelector:isReadySel];
                        [inv invoke];
                        [inv getReturnValue:&isReady];
                    }
                    
                    if (isReady && [minimuxerJIT respondsToSelector:isDeviceConnectedSel]) {
                        NSMethodSignature *sig = [minimuxerJIT methodSignatureForSelector:isDeviceConnectedSel];
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        [inv setTarget:minimuxerJIT];
                        [inv setSelector:isDeviceConnectedSel];
                        [inv invoke];
                        [inv getReturnValue:&isDeviceConnected];
                    }
                    
                    if (isReady) {
                        hasMinimuxerVerification = YES;
                        if (!isDeviceConnected) {
                            HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"❌ VPN not connected: minimuxer ready but device not connected (VPN not routing)");
                            return NO;
                        } else {
                            HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"minimuxer device connection verified ✓ (VPN definitely working)");
                        }
                    }
                }
            }
        }
    }
    
    // If we don't have minimuxer verification, we require BOTH:
    // 1. Active VPN interface (utun/ipsec) - ensures LocalDevVPN is enabled in iOS Settings
    // 2. test_emotional_damage passing - ensures LocalDevVPN can communicate with em_proxy
    // This combination is reliable and prevents false positives.
    // CRITICAL: test_emotional_damage alone is NOT sufficient - it can pass even when VPN is disabled
    // because it just checks if em_proxy is listening, not if LocalDevVPN is actually routing traffic.
    if (!hasMinimuxerVerification) {
        // We already verified VPN interface is active (above) and test_emotional_damage passed
        // This is a reliable indicator that VPN is working
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"✅ HIAH VPN connection verified (em_proxy running + active VPN interface + test_emotional_damage passed)");
        return YES;
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"✅ HIAH VPN connection verified (em_proxy running + LocalDevVPN connected + minimuxer verified)");
    return YES;
}

- (void)actionUpdateBypassCoordinator:(BOOL)connected {
    Class coordClass = NSClassFromString(@"HIAHBypassCoordinator");
    if (!coordClass) return;
    
    SEL sharedSel = NSSelectorFromString(@"sharedCoordinator");
    if (![coordClass respondsToSelector:sharedSel]) return;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id coordinator = [coordClass performSelector:sharedSel];
#pragma clang diagnostic pop
    if (!coordinator) return;
    
    SEL updateSel = NSSelectorFromString(@"updateVPNStatus:");
    if (![coordinator respondsToSelector:updateSel]) return;
    
    NSMethodSignature *sig = [coordinator methodSignatureForSelector:updateSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:coordinator];
    [inv setSelector:updateSel];
    [inv setArgument:&connected atIndex:2];
    [inv invoke];
}

/// Enable JIT when VPN connects - this is critical for signature bypass
- (void)actionEnableJIT {
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"VPN connected - enabling JIT for signature bypass...");
    
    // Step 1: Start minimuxer if pairing file exists
    Class minimuxerJITClass = NSClassFromString(@"HIAHMinimuxerJIT");
    if (!minimuxerJITClass) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"HIAHMinimuxerJIT class not found - JIT may not work");
        return;
    }
    
    SEL sharedSel = NSSelectorFromString(@"shared");
    if (![minimuxerJITClass respondsToSelector:sharedSel]) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"HIAHMinimuxerJIT.shared not found");
        return;
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id minimuxerJIT = [minimuxerJITClass performSelector:sharedSel];
#pragma clang diagnostic pop
    if (!minimuxerJIT) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"Failed to get HIAHMinimuxerJIT instance");
        return;
    }
    
    // Check if minimuxer is already started
    SEL isStartedSel = NSSelectorFromString(@"isStarted");
    BOOL isStarted = NO;
    if ([minimuxerJIT respondsToSelector:isStartedSel]) {
        NSMethodSignature *sig = [minimuxerJIT methodSignatureForSelector:isStartedSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:minimuxerJIT];
        [inv setSelector:isStartedSel];
        [inv invoke];
        [inv getReturnValue:&isStarted];
    }
    
    if (!isStarted) {
        // Check for pairing file
        SEL hasPairingSel = NSSelectorFromString(@"hasPairingFile");
        BOOL hasPairing = NO;
        if ([minimuxerJIT respondsToSelector:hasPairingSel]) {
            NSMethodSignature *sig = [minimuxerJIT methodSignatureForSelector:hasPairingSel];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:minimuxerJIT];
            [inv setSelector:hasPairingSel];
            [inv invoke];
            [inv getReturnValue:&hasPairing];
        }
        
        if (hasPairing) {
            HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Starting minimuxer with default pairing file...");
            SEL startSel = NSSelectorFromString(@"startMinimuxerWithDefaultPairing");
            if ([minimuxerJIT respondsToSelector:startSel]) {
                // Use performSelector with error handling
                @try {
                    [minimuxerJIT performSelector:startSel];
                    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"✅ Minimuxer started successfully");
                } @catch (NSException *exception) {
                    HIAHLogEx(HIAH_LOG_ERROR, @"VPN", @"Failed to start minimuxer: %@", exception);
                }
            }
        } else {
            HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"No pairing file found - JIT enablement will not work");
            HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Pairing file required: ALTPairingFile.mobiledevicepairing in Documents");
        }
    } else {
        HIAHLogEx(HIAH_LOG_DEBUG, @"VPN", @"Minimuxer already started");
    }
    
    // Step 2: Enable JIT for main app process
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self enableJITForCurrentProcess];
    });
}

/// Enable JIT for the current process (main app)
- (void)enableJITForCurrentProcess {
    pid_t currentPID = getpid();
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Enabling JIT for main app process (PID: %d)...", currentPID);
    
    // Check if already enabled
    extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
    #define CS_OPS_STATUS 0
    #define CS_DEBUGGED 0x10000000
    
    int flags = 0;
    if (csops(currentPID, CS_OPS_STATUS, &flags, sizeof(flags)) == 0) {
        if ((flags & CS_DEBUGGED) != 0) {
            HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"JIT already enabled for PID: %d", currentPID);
            return;
        }
    }
    
    // Get bundle ID
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"Could not get bundle ID for JIT enablement");
        return;
    }
    
    // Use HIAHJITManager to enable JIT
    Class jitManagerClass = NSClassFromString(@"HIAHJITManager");
    if (!jitManagerClass) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"HIAHJITManager class not found");
        return;
    }
    
    SEL sharedSel = NSSelectorFromString(@"sharedManager");
    if (![jitManagerClass respondsToSelector:sharedSel]) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"HIAHJITManager.sharedManager not found");
        return;
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id jitManager = [jitManagerClass performSelector:sharedSel];
#pragma clang diagnostic pop
    if (!jitManager) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"Failed to get HIAHJITManager instance");
        return;
    }
    
    SEL enableSel = NSSelectorFromString(@"enableJITForPID:completion:");
    if (![jitManager respondsToSelector:enableSel]) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"enableJITForPID:completion: not found");
        return;
    }
    
    void (^completion)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
        if (success) {
            HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"✅ JIT enabled successfully for main app (PID: %d)", currentPID);
        } else {
            HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"❌ Failed to enable JIT: %@", error);
        }
    };
    
    NSMethodSignature *sig = [jitManager methodSignatureForSelector:enableSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:jitManager];
    [inv setSelector:enableSel];
    [inv setArgument:&currentPID atIndex:2];
    [inv setArgument:&completion atIndex:3];
    [inv invoke];
}

#pragma mark - Setup

- (void)markSetupComplete {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kSetupCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Setup marked complete");
}

- (void)resetSetup {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kSetupCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Setup reset");
}

#pragma mark - Config Generation (Not Needed for LocalDevVPN)

// LocalDevVPN doesn't require configuration files - it's a simple on/off VPN
// These methods are kept for API compatibility but return nil/empty

- (NSString *)generateConfig {
    // LocalDevVPN doesn't require configuration
    return @"";
}

- (NSString *)saveConfigToDocuments {
    // LocalDevVPN doesn't require configuration files
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"LocalDevVPN doesn't require config files");
    return nil;
}

- (void)copyConfigToClipboard {
    // LocalDevVPN doesn't require configuration
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"LocalDevVPN doesn't require config files");
}

- (NSURL *)configFileURL {
    // LocalDevVPN doesn't require configuration files
    return nil;
}

#pragma mark - Debug Helpers

- (NSString *)nameForState:(HIAHVPNState)state {
    switch (state) {
        case HIAHVPNStateIdle:          return @"Idle";
        case HIAHVPNStateStartingProxy: return @"StartingProxy";
        case HIAHVPNStateProxyReady:    return @"ProxyReady";
        case HIAHVPNStateConnected:     return @"Connected";
        case HIAHVPNStateError:         return @"Error";
    }
    return @"?";
}

- (NSString *)nameForEvent:(HIAHVPNEvent)event {
    switch (event) {
        case HIAHVPNEventStart:           return @"Start";
        case HIAHVPNEventProxyStarted:    return @"ProxyStarted";
        case HIAHVPNEventProxyFailed:     return @"ProxyFailed";
        case HIAHVPNEventVPNConnected:    return @"VPNConnected";
        case HIAHVPNEventVPNDisconnected: return @"VPNDisconnected";
        case HIAHVPNEventStop:            return @"Stop";
        case HIAHVPNEventRetry:           return @"Retry";
    }
    return @"?";
}

- (NSString *)validTransitionsDescription {
    NSMutableArray *transitions = [NSMutableArray array];
    HIAHVPNState current = self.state;
    
    for (size_t i = 0; i < kTransitionCount; i++) {
        if (kTransitionTable[i].fromState == current) {
            [transitions addObject:[NSString stringWithFormat:@"%@ → %@",
                [self nameForEvent:kTransitionTable[i].event],
                [self nameForState:kTransitionTable[i].toState]]];
        }
    }
    
    return [NSString stringWithFormat:@"[%@] can: %@", 
            [self nameForState:current],
            [transitions componentsJoinedByString:@", "]];
}

@end

