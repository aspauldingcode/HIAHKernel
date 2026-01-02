/**
 * HIAHSignatureBypass.m
 * HIAH LoginWindow - Signature Verification Bypass Service
 *
 * Coordinates VPN, JIT, and dylib signing to bypass iOS signature verification.
 * Similar to SideStore's LiveProcess/LiveContainer approach.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHSignatureBypass.h"
#import "HIAHBypassCoordinator.h"
#import "../VPN/HIAHVPNManager.h"
#import "../VPN/HIAHVPNStateMachine.h"
#import "../JIT/HIAHJITManager.h"
#import "../../HIAHDesktop/HIAHLogging.h"
#import "../../extension/HIAHSigner.h"
#import <sys/sysctl.h>

@interface HIAHSignatureBypass ()

@property (nonatomic, assign) BOOL isReady;
@property (nonatomic, strong) dispatch_queue_t queue;

@end

@implementation HIAHSignatureBypass

+ (instancetype)sharedBypass {
    static HIAHSignatureBypass *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isReady = NO;
        _queue = dispatch_queue_create("com.aspauldingcode.HIAHDesktop.signatureBypass", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)ensureBypassReadyWithCompletion:(void (^)(BOOL, NSError *))completion {
    dispatch_async(self.queue, ^{
        HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"Ensuring bypass is ready...");
        
        // Step 1: Start VPN if not already active
        // BUT: Only if VPN setup has been completed. Don't auto-open LocalDevVPN during initial setup.
        HIAHVPNStateMachine *vpnSM = [HIAHVPNStateMachine shared];
        HIAHVPNManager *vpnManager = [HIAHVPNManager sharedManager];
        
        // Check if VPN setup is complete before trying to start VPN
        if (!vpnSM.isSetupComplete) {
            HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"VPN setup not complete - skipping auto-start. User must complete setup wizard first.");
            if (completion) {
                completion(NO, [NSError errorWithDomain:@"SignatureBypass" 
                                                   code:-1 
                                               userInfo:@{NSLocalizedDescriptionKey: @"VPN setup not complete. Please complete the LocalDevVPN setup wizard first."}]);
            }
            return;
        }
        
        if (!vpnManager.isVPNActive) {
            HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"Starting VPN...");
            
            dispatch_semaphore_t vpnSem = dispatch_semaphore_create(0);
            __block NSError *vpnError = nil;
            
            // Don't call startVPN - it opens LocalDevVPN automatically
            // Instead, just check if VPN is connected
            HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"Checking if VPN is connected...");
            
            // Check if VPN is actually connected (user may have enabled it manually)
            if (![vpnSM detectHIAHVPNConnected]) {
                HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"VPN not connected - user needs to enable it in LocalDevVPN. Not auto-opening LocalDevVPN.");
                if (completion) {
                    completion(NO, [NSError errorWithDomain:@"SignatureBypass" 
                                                       code:-1 
                                                   userInfo:@{NSLocalizedDescriptionKey: @"VPN is not connected. Please enable the VPN in LocalDevVPN."}]);
                }
                return;
            }
            
            // VPN is connected
            HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"VPN is connected - proceeding");
            
            // Update coordinator
            [[HIAHBypassCoordinator sharedCoordinator] updateVPNStatus:YES];
        } else {
            // VPN already active, update coordinator
            [[HIAHBypassCoordinator sharedCoordinator] updateVPNStatus:YES];
        }
        
        HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"VPN is active");
        
        // Step 2: Enable JIT for current process
        HIAHJITManager *jitManager = [HIAHJITManager sharedManager];
        pid_t currentPID = getpid();
        
        dispatch_semaphore_t jitSem = dispatch_semaphore_create(0);
        __block BOOL jitSuccess = NO;
        __block NSError *jitError = nil;
        
        [jitManager enableJITForPID:currentPID completion:^(BOOL success, NSError * _Nullable error) {
            jitSuccess = success;
            jitError = error;
            dispatch_semaphore_signal(jitSem);
        }];
        
        // Wait for JIT enablement (max 10 seconds)
        dispatch_time_t jitTimeout = dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC);
        if (dispatch_semaphore_wait(jitSem, jitTimeout) != 0) {
            HIAHLogEx(HIAH_LOG_ERROR, @"SignatureBypass", @"JIT enablement timeout");
            if (completion) {
                completion(NO, [NSError errorWithDomain:@"SignatureBypass" 
                                                   code:-2 
                                               userInfo:@{NSLocalizedDescriptionKey: @"JIT enablement timeout"}]);
            }
            return;
        }
        
        // Step 3: Verify bypass is working
        // Check if CS_DEBUGGED flag is set (indicates JIT is active)
        extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
        #define CS_OPS_STATUS 0
        #define CS_DEBUGGED 0x10000000
        
        int flags = 0;
        BOOL jitActive = NO;
        if (csops(currentPID, CS_OPS_STATUS, &flags, sizeof(flags)) == 0) {
            jitActive = (flags & CS_DEBUGGED) != 0;
        }
        
        // Update coordinator with actual JIT status
        [[HIAHBypassCoordinator sharedCoordinator] updateJITStatus:jitActive];
        
        if (jitActive) {
            HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"CS_DEBUGGED flag is set - JIT is active");
            self.isReady = YES;
            if (completion) {
                completion(YES, nil);
            }
            return;
        } else {
            HIAHLogEx(HIAH_LOG_WARNING, @"SignatureBypass", @"CS_DEBUGGED flag not set - JIT may not be active");
            if (!jitSuccess) {
                HIAHLogEx(HIAH_LOG_WARNING, @"SignatureBypass", @"JIT enablement failed: %@", jitError);
                HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"Will attempt to sign dylibs instead");
            }
        }
        
        // If JIT isn't active, we'll need to sign dylibs
        // Mark as ready anyway - we can sign on demand
        self.isReady = YES;
        HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"Bypass system ready (will use signing fallback if needed)");
        
        if (completion) {
            completion(YES, nil);
        }
    });
}

- (BOOL)signDylibAtPath:(NSString *)dylibPath error:(NSError **)error {
    HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"Signing dylib at: %@", dylibPath);
    
    // Use HIAHSigner to sign the binary
    BOOL success = [HIAHSigner signBinaryAtPath:dylibPath];
    
    if (!success) {
        if (error) {
            *error = [NSError errorWithDomain:@"SignatureBypass" 
                                         code:-3 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign dylib"}];
        }
        return NO;
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"Dylib signed successfully");
    return YES;
}

- (void)prepareBinaryForDlopen:(NSString *)binaryPath completion:(void (^)(BOOL, NSError *))completion {
    dispatch_async(self.queue, ^{
        HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"Preparing binary for dlopen: %@", binaryPath);
        
        // Step 1: Ensure bypass is ready
        dispatch_semaphore_t readySem = dispatch_semaphore_create(0);
        __block BOOL readySuccess = NO;
        __block NSError *readyError = nil;
        
        [self ensureBypassReadyWithCompletion:^(BOOL success, NSError * _Nullable error) {
            readySuccess = success;
            readyError = error;
            dispatch_semaphore_signal(readySem);
        }];
        
        dispatch_semaphore_wait(readySem, DISPATCH_TIME_FOREVER);
        
        if (!readySuccess) {
            HIAHLogEx(HIAH_LOG_ERROR, @"SignatureBypass", @"Failed to prepare bypass: %@", readyError);
            if (completion) {
                completion(NO, readyError);
            }
            return;
        }
        
        // Step 2: Check if JIT is actually active
        extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
        #define CS_OPS_STATUS 0
        #define CS_DEBUGGED 0x10000000
        
        int flags = 0;
        BOOL jitActive = NO;
        if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) == 0) {
            jitActive = (flags & CS_DEBUGGED) != 0;
        }
        
        // Step 3: If JIT is not active, sign the binary
        if (!jitActive) {
            HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"JIT not active - signing binary...");
            NSError *signError = nil;
            if (![self signDylibAtPath:binaryPath error:&signError]) {
                HIAHLogEx(HIAH_LOG_ERROR, @"SignatureBypass", @"Failed to sign binary: %@", signError);
                if (completion) {
                    completion(NO, signError);
                }
                return;
            }
        } else {
            HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"JIT is active - signature bypass should work");
        }
        
        HIAHLogEx(HIAH_LOG_INFO, @"SignatureBypass", @"Binary prepared for dlopen");
        if (completion) {
            completion(YES, nil);
        }
    });
}

@end

