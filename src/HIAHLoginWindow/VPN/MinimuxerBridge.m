/**
 * MinimuxerBridge.m
 * HIAH LoginWindow - Minimuxer Objective-C Bridge
 *
 * Provides Objective-C interface to the Minimuxer Rust library
 * via the HIAHMinimuxer Swift wrapper.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "MinimuxerBridge.h"
#import "HIAHLogging.h"

// Forward declare Swift class - generated header will be imported in prefix header
@class HIAHMinimuxer;

static MinimuxerStatus gMinimuxerStatus = MinimuxerStatusNotStarted;
static NSString *gLastError = nil;

@implementation MinimuxerBridge

#pragma mark - Properties

+ (MinimuxerStatus)status {
    // Get status from Swift wrapper
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (minimuxerClass) {
        SEL sharedSel = NSSelectorFromString(@"shared");
        if ([minimuxerClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
            if (instance) {
                SEL statusSel = NSSelectorFromString(@"status");
                if ([instance respondsToSelector:statusSel]) {
                    NSMethodSignature *sig = [instance methodSignatureForSelector:statusSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:instance];
                    [inv setSelector:statusSel];
                    [inv invoke];
                    
                    NSInteger status = 0;
                    [inv getReturnValue:&status];
                    return (MinimuxerStatus)status;
                }
            }
        }
    }
    return gMinimuxerStatus;
}

+ (BOOL)isReady {
    // Get isReady from Swift wrapper
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (minimuxerClass) {
        SEL sharedSel = NSSelectorFromString(@"shared");
        if ([minimuxerClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
            if (instance) {
                SEL isReadySel = NSSelectorFromString(@"isReady");
                if ([instance respondsToSelector:isReadySel]) {
                    NSMethodSignature *sig = [instance methodSignatureForSelector:isReadySel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:instance];
                    [inv setSelector:isReadySel];
                    [inv invoke];
                    
                    BOOL isReady = NO;
                    [inv getReturnValue:&isReady];
                    return isReady;
                }
            }
        }
    }
    return NO;
}

+ (NSString *)lastError {
    // Get lastErrorMessage from Swift wrapper
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (minimuxerClass) {
        SEL sharedSel = NSSelectorFromString(@"shared");
        if ([minimuxerClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
            if (instance) {
                SEL errorSel = NSSelectorFromString(@"lastErrorMessage");
                if ([instance respondsToSelector:errorSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    return [instance performSelector:errorSel];
#pragma clang diagnostic pop
                }
            }
        }
    }
    return gLastError;
}

#pragma mark - Lifecycle

+ (BOOL)startWithPairingFile:(NSString *)pairingFilePath
                     logPath:(NSString *)logPath {
    return [self startWithPairingFile:pairingFilePath logPath:logPath consoleLogging:NO];
}

+ (BOOL)startWithPairingFile:(NSString *)pairingFilePath
                     logPath:(NSString *)logPath
              consoleLogging:(BOOL)enableConsoleLogging {
    HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Starting with pairing file: %@", pairingFilePath);
    
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (!minimuxerClass) {
        HIAHLogEx(HIAH_LOG_ERROR, @"Minimuxer", @"HIAHMinimuxer class not found");
        gMinimuxerStatus = MinimuxerStatusError;
        gLastError = @"HIAHMinimuxer class not found";
        return NO;
    }
    
    SEL sharedSel = NSSelectorFromString(@"shared");
    if (![minimuxerClass respondsToSelector:sharedSel]) {
        HIAHLogEx(HIAH_LOG_ERROR, @"Minimuxer", @"HIAHMinimuxer.shared not found");
        gMinimuxerStatus = MinimuxerStatusError;
        gLastError = @"HIAHMinimuxer.shared not found";
        return NO;
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
    
    if (!instance) {
        HIAHLogEx(HIAH_LOG_ERROR, @"Minimuxer", @"Failed to get HIAHMinimuxer instance");
        gMinimuxerStatus = MinimuxerStatusError;
        gLastError = @"Failed to get HIAHMinimuxer instance";
        return NO;
    }
    
    // Call start(pairingFile:logPath:consoleLogging:)
    SEL startSel = NSSelectorFromString(@"startWithPairingFile:logPath:consoleLogging:");
    if ([instance respondsToSelector:startSel]) {
        NSMethodSignature *sig = [instance methodSignatureForSelector:startSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:instance];
        [inv setSelector:startSel];
        [inv setArgument:&pairingFilePath atIndex:2];
        [inv setArgument:&logPath atIndex:3];
        [inv setArgument:&enableConsoleLogging atIndex:4];
        [inv invoke];
        
        BOOL result = NO;
        [inv getReturnValue:&result];
        
        if (result) {
            HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"✅ Started successfully");
            gMinimuxerStatus = MinimuxerStatusReady;
        } else {
            HIAHLogEx(HIAH_LOG_ERROR, @"Minimuxer", @"❌ Failed to start");
            gMinimuxerStatus = MinimuxerStatusError;
        }
        return result;
    }
    
    HIAHLogEx(HIAH_LOG_ERROR, @"Minimuxer", @"start method not found");
    gMinimuxerStatus = MinimuxerStatusError;
    gLastError = @"start method not found";
    return NO;
}

+ (void)stop {
    HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Stopping...");
    
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (minimuxerClass) {
        SEL sharedSel = NSSelectorFromString(@"shared");
        if ([minimuxerClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
            if (instance) {
                SEL stopSel = NSSelectorFromString(@"stop");
                if ([instance respondsToSelector:stopSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [instance performSelector:stopSel];
#pragma clang diagnostic pop
                }
            }
        }
    }
    
    gMinimuxerStatus = MinimuxerStatusNotStarted;
    gLastError = nil;
    HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Stopped");
}

#pragma mark - Device Info

+ (NSString *)fetchDeviceUDID {
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (minimuxerClass) {
        SEL sharedSel = NSSelectorFromString(@"shared");
        if ([minimuxerClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
            if (instance) {
                SEL udidSel = NSSelectorFromString(@"fetchDeviceUDID");
                if ([instance respondsToSelector:udidSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    return [instance performSelector:udidSel];
#pragma clang diagnostic pop
                }
            }
        }
    }
    return nil;
}

+ (BOOL)testDeviceConnection {
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (minimuxerClass) {
        SEL sharedSel = NSSelectorFromString(@"shared");
        if ([minimuxerClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
            if (instance) {
                SEL testSel = NSSelectorFromString(@"testDeviceConnection");
                if ([instance respondsToSelector:testSel]) {
                    NSMethodSignature *sig = [instance methodSignatureForSelector:testSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:instance];
                    [inv setSelector:testSel];
                    [inv invoke];
                    
                    BOOL result = NO;
                    [inv getReturnValue:&result];
                    return result;
                }
            }
        }
    }
    return NO;
}

#pragma mark - JIT Enablement

+ (BOOL)enableJITForApp:(NSString *)bundleID
                  error:(NSError **)error {
    HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Enabling JIT for: %@", bundleID);
    
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (!minimuxerClass) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"HIAHMinimuxer class not found"}];
        }
        return NO;
    }
    
    SEL sharedSel = NSSelectorFromString(@"shared");
    if (![minimuxerClass respondsToSelector:sharedSel]) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"HIAHMinimuxer.shared not found"}];
        }
        return NO;
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
    
    if (!instance) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to get HIAHMinimuxer instance"}];
        }
        return NO;
    }
    
    // Call enableJIT(forBundleID:) - throws
    SEL enableSel = NSSelectorFromString(@"enableJITForBundleID:error:");
    if ([instance respondsToSelector:enableSel]) {
        NSMethodSignature *sig = [instance methodSignatureForSelector:enableSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:instance];
        [inv setSelector:enableSel];
        [inv setArgument:&bundleID atIndex:2];
        
        NSError *__autoreleasing localError = nil;
        [inv setArgument:&localError atIndex:3];
        [inv invoke];
        
        BOOL result = NO;
        // The method throws, so we need to handle it differently
        // For now, assume success if no exception
        @try {
            [inv invoke];
            result = YES;
        } @catch (NSException *exception) {
            if (error) {
                *error = [NSError errorWithDomain:@"MinimuxerBridge" code:4
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown error"}];
            }
            return NO;
        }
        
        if (localError && error) {
            *error = localError;
            return NO;
        }
        
        HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"✅ JIT enabled for: %@", bundleID);
        return YES;
    }
    
    // Fallback: try the throwing version
    SEL enableThrowingSel = NSSelectorFromString(@"enableJITForBundleID:");
    if ([instance respondsToSelector:enableThrowingSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        @try {
            [instance performSelector:enableThrowingSel withObject:bundleID];
            HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"✅ JIT enabled for: %@", bundleID);
            return YES;
        } @catch (NSException *exception) {
            if (error) {
                *error = [NSError errorWithDomain:@"MinimuxerBridge" code:5
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"JIT enablement failed"}];
            }
            return NO;
        }
#pragma clang diagnostic pop
    }
    
    if (error) {
        *error = [NSError errorWithDomain:@"MinimuxerBridge" code:6
                                 userInfo:@{NSLocalizedDescriptionKey: @"enableJIT method not found"}];
    }
    return NO;
}

+ (BOOL)attachDebuggerToPID:(pid_t)pid
                      error:(NSError **)error {
    HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Attaching debugger to PID: %d", pid);
    
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (!minimuxerClass) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"HIAHMinimuxer class not found"}];
        }
        return NO;
    }
    
    SEL sharedSel = NSSelectorFromString(@"shared");
    if (![minimuxerClass respondsToSelector:sharedSel]) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"HIAHMinimuxer.shared not found"}];
        }
        return NO;
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
    
    if (!instance) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to get HIAHMinimuxer instance"}];
        }
        return NO;
    }
    
    // Call attachDebugger(toPID:)
    SEL attachSel = NSSelectorFromString(@"attachDebuggerToPID:error:");
    if ([instance respondsToSelector:attachSel]) {
        UInt32 pidValue = (UInt32)pid;
        NSError *__autoreleasing localError = nil;
        
        NSMethodSignature *sig = [instance methodSignatureForSelector:attachSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:instance];
        [inv setSelector:attachSel];
        [inv setArgument:&pidValue atIndex:2];
        [inv setArgument:&localError atIndex:3];
        
        @try {
            [inv invoke];
        } @catch (NSException *exception) {
            if (error) {
                *error = [NSError errorWithDomain:@"MinimuxerBridge" code:7
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Debugger attachment failed"}];
            }
            return NO;
        }
        
        if (localError && error) {
            *error = localError;
            return NO;
        }
        
        HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"✅ Debugger attached to PID: %d", pid);
        return YES;
    }
    
    if (error) {
        *error = [NSError errorWithDomain:@"MinimuxerBridge" code:8
                                 userInfo:@{NSLocalizedDescriptionKey: @"attachDebugger method not found"}];
    }
    return NO;
}

#pragma mark - App Installation

+ (BOOL)installIPAWithBundleID:(NSString *)bundleID
                       ipaData:(NSData *)ipaData
                         error:(NSError **)error {
    HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Installing IPA for: %@", bundleID);
    
    // Delegate to Swift wrapper
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (!minimuxerClass) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"HIAHMinimuxer class not found"}];
        }
        return NO;
    }
    
    SEL sharedSel = NSSelectorFromString(@"shared");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
    
    SEL installSel = NSSelectorFromString(@"installIPAWithBundleID:ipaData:error:");
    if ([instance respondsToSelector:installSel]) {
        NSError *__autoreleasing localError = nil;
        
        NSMethodSignature *sig = [instance methodSignatureForSelector:installSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:instance];
        [inv setSelector:installSel];
        [inv setArgument:&bundleID atIndex:2];
        [inv setArgument:&ipaData atIndex:3];
        [inv setArgument:&localError atIndex:4];
        
        @try {
            [inv invoke];
        } @catch (NSException *exception) {
            if (error) {
                *error = [NSError errorWithDomain:@"MinimuxerBridge" code:9
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"IPA installation failed"}];
            }
            return NO;
        }
        
        if (localError && error) {
            *error = localError;
            return NO;
        }
        
        return YES;
    }
    
    if (error) {
        *error = [NSError errorWithDomain:@"MinimuxerBridge" code:10
                                 userInfo:@{NSLocalizedDescriptionKey: @"installIPA method not found"}];
    }
    return NO;
}

+ (BOOL)removeApp:(NSString *)bundleID
            error:(NSError **)error {
    HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Removing app: %@", bundleID);
    
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (!minimuxerClass) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"HIAHMinimuxer class not found"}];
        }
        return NO;
    }
    
    SEL sharedSel = NSSelectorFromString(@"shared");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
    
    SEL removeSel = NSSelectorFromString(@"removeAppWithBundleID:error:");
    if ([instance respondsToSelector:removeSel]) {
        NSError *__autoreleasing localError = nil;
        
        NSMethodSignature *sig = [instance methodSignatureForSelector:removeSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:instance];
        [inv setSelector:removeSel];
        [inv setArgument:&bundleID atIndex:2];
        [inv setArgument:&localError atIndex:3];
        
        @try {
            [inv invoke];
        } @catch (NSException *exception) {
            if (error) {
                *error = [NSError errorWithDomain:@"MinimuxerBridge" code:11
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"App removal failed"}];
            }
            return NO;
        }
        
        if (localError && error) {
            *error = localError;
            return NO;
        }
        
        return YES;
    }
    
    if (error) {
        *error = [NSError errorWithDomain:@"MinimuxerBridge" code:12
                                 userInfo:@{NSLocalizedDescriptionKey: @"removeApp method not found"}];
    }
    return NO;
}

#pragma mark - Provisioning Profiles

+ (BOOL)installProvisioningProfile:(NSData *)profileData
                             error:(NSError **)error {
    // Delegate to Swift wrapper (implementation similar to above)
    HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Installing provisioning profile");
    
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (!minimuxerClass) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"HIAHMinimuxer class not found"}];
        }
        return NO;
    }
    
    SEL sharedSel = NSSelectorFromString(@"shared");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
    
    SEL installSel = NSSelectorFromString(@"installProvisioningProfile:error:");
    if ([instance respondsToSelector:installSel]) {
        NSError *__autoreleasing localError = nil;
        
        NSMethodSignature *sig = [instance methodSignatureForSelector:installSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:instance];
        [inv setSelector:installSel];
        [inv setArgument:&profileData atIndex:2];
        [inv setArgument:&localError atIndex:3];
        
        @try {
            [inv invoke];
        } @catch (NSException *exception) {
            if (error) {
                *error = [NSError errorWithDomain:@"MinimuxerBridge" code:13
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Profile installation failed"}];
            }
            return NO;
        }
        
        if (localError && error) {
            *error = localError;
            return NO;
        }
        
        return YES;
    }
    
    if (error) {
        *error = [NSError errorWithDomain:@"MinimuxerBridge" code:14
                                 userInfo:@{NSLocalizedDescriptionKey: @"installProvisioningProfile method not found"}];
    }
    return NO;
}

+ (BOOL)removeProvisioningProfile:(NSString *)profileID
                            error:(NSError **)error {
    HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Removing provisioning profile: %@", profileID);
    
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (!minimuxerClass) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridge" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"HIAHMinimuxer class not found"}];
        }
        return NO;
    }
    
    SEL sharedSel = NSSelectorFromString(@"shared");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id instance = [minimuxerClass performSelector:sharedSel];
#pragma clang diagnostic pop
    
    SEL removeSel = NSSelectorFromString(@"removeProvisioningProfileWithId:error:");
    if ([instance respondsToSelector:removeSel]) {
        NSError *__autoreleasing localError = nil;
        
        NSMethodSignature *sig = [instance methodSignatureForSelector:removeSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:instance];
        [inv setSelector:removeSel];
        [inv setArgument:&profileID atIndex:2];
        [inv setArgument:&localError atIndex:3];
        
        @try {
            [inv invoke];
        } @catch (NSException *exception) {
            if (error) {
                *error = [NSError errorWithDomain:@"MinimuxerBridge" code:15
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Profile removal failed"}];
            }
            return NO;
        }
        
        if (localError && error) {
            *error = localError;
            return NO;
        }
        
        return YES;
    }
    
    if (error) {
        *error = [NSError errorWithDomain:@"MinimuxerBridge" code:16
                                 userInfo:@{NSLocalizedDescriptionKey: @"removeProvisioningProfile method not found"}];
    }
    return NO;
}

#pragma mark - Pairing File

+ (NSString *)defaultPairingFilePath {
    Class minimuxerClass = NSClassFromString(@"HIAHMinimuxer");
    if (minimuxerClass) {
        SEL pathSel = NSSelectorFromString(@"defaultPairingFilePath");
        if ([minimuxerClass respondsToSelector:pathSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            return [minimuxerClass performSelector:pathSel];
#pragma clang diagnostic pop
        }
    }
    
    // Fallback: check Documents directory
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = paths.firstObject;
    
    NSString *pairingFile = [documentsDir stringByAppendingPathComponent:@"ALTPairingFile.mobiledevicepairing"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pairingFile]) {
        return pairingFile;
    }
    
    pairingFile = [documentsDir stringByAppendingPathComponent:@"pairing_file.plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pairingFile]) {
        return pairingFile;
    }
    
    return nil;
}

+ (BOOL)hasPairingFile {
    return [self defaultPairingFilePath] != nil;
}

@end
