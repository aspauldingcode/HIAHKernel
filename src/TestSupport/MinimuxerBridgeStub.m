/**
 * MinimuxerBridgeStub.m
 * HIAH Kernel - Test Support
 *
 * Stub implementation of MinimuxerBridge for iOS Simulator builds.
 * This provides mock behavior for device-only minimuxer functionality.
 *
 * When HIAH_USE_SIMULATOR_STUBS is defined, this file is compiled
 * instead of the real MinimuxerBridge.m which requires libminimuxer.a.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3 (follows MinimuxerBridge licensing)
 */

#import "SimulatorStubs.h"

// Only compile stub implementation when stubs are enabled
#if HIAH_USE_SIMULATOR_STUBS

#import "../HIAHLoginWindow/VPN/MinimuxerBridge.h"

static MinimuxerStatus gStubStatus = MinimuxerStatusNotStarted;
static NSString *gStubLastError = nil;
static NSString *gStubUDID = @"SIMULATOR-STUB-UDID-00000000";
static BOOL gStubIsStarted = NO;

@implementation MinimuxerBridge

#pragma mark - Properties

+ (MinimuxerStatus)status {
    HIAHLogStubCall(@"MinimuxerBridge", @"status");
    return gStubStatus;
}

+ (BOOL)isReady {
    HIAHLogStubCall(@"MinimuxerBridge", @"isReady");
    return gStubStatus == MinimuxerStatusReady;
}

+ (NSString *)lastError {
    HIAHLogStubCall(@"MinimuxerBridge", @"lastError");
    return gStubLastError;
}

#pragma mark - Lifecycle

+ (BOOL)startWithPairingFile:(NSString *)pairingFilePath
                     logPath:(NSString *)logPath {
    return [self startWithPairingFile:pairingFilePath logPath:logPath consoleLogging:NO];
}

+ (BOOL)startWithPairingFile:(NSString *)pairingFilePath
                     logPath:(NSString *)logPath
              consoleLogging:(BOOL)enableConsoleLogging {
    HIAHLogStubCall(@"MinimuxerBridge", [NSString stringWithFormat:@"startWithPairingFile:%@ logPath:%@ consoleLogging:%@",
                                         pairingFilePath, logPath, enableConsoleLogging ? @"YES" : @"NO"]);
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        gStubStatus = MinimuxerStatusError;
        gStubLastError = @"[STUB] Simulated failure";
        return NO;
    }
    
    // Simulate async startup delay
    if (HIAHStubConfiguration.shared.simulatedDelay > 0) {
        gStubStatus = MinimuxerStatusStarting;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(HIAHStubConfiguration.shared.simulatedDelay * NSEC_PER_SEC)),
                      dispatch_get_main_queue(), ^{
            gStubStatus = MinimuxerStatusReady;
            gStubIsStarted = YES;
        });
    } else {
        gStubStatus = MinimuxerStatusReady;
        gStubIsStarted = YES;
    }
    
    gStubLastError = nil;
    return YES;
}

+ (void)stop {
    HIAHLogStubCall(@"MinimuxerBridge", @"stop");
    gStubStatus = MinimuxerStatusNotStarted;
    gStubIsStarted = NO;
    gStubLastError = nil;
}

#pragma mark - Device Info

+ (NSString *)fetchDeviceUDID {
    HIAHLogStubCall(@"MinimuxerBridge", @"fetchDeviceUDID");
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        return nil;
    }
    
    return gStubUDID;
}

+ (BOOL)testDeviceConnection {
    HIAHLogStubCall(@"MinimuxerBridge", @"testDeviceConnection");
    return HIAHStubConfiguration.shared.simulateSuccess && gStubIsStarted;
}

#pragma mark - JIT Enablement

+ (BOOL)enableJITForApp:(NSString *)bundleID
                  error:(NSError **)error {
    HIAHLogStubCall(@"MinimuxerBridge", [NSString stringWithFormat:@"enableJITForApp:%@", bundleID]);
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridgeStub"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"[STUB] Simulated JIT enablement failure"}];
        }
        return NO;
    }
    
    // Simulate successful JIT enablement
    NSLog(@"[STUB:MinimuxerBridge] JIT enabled for app: %@ (simulated)", bundleID);
    return YES;
}

+ (BOOL)attachDebuggerToPID:(pid_t)pid
                      error:(NSError **)error {
    HIAHLogStubCall(@"MinimuxerBridge", [NSString stringWithFormat:@"attachDebuggerToPID:%d", pid]);
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridgeStub"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"[STUB] Simulated debugger attachment failure"}];
        }
        return NO;
    }
    
    NSLog(@"[STUB:MinimuxerBridge] Debugger attached to PID %d (simulated)", pid);
    return YES;
}

#pragma mark - App Installation

+ (BOOL)installIPAWithBundleID:(NSString *)bundleID
                       ipaData:(NSData *)ipaData
                         error:(NSError **)error {
    HIAHLogStubCall(@"MinimuxerBridge", [NSString stringWithFormat:@"installIPAWithBundleID:%@ dataSize:%lu",
                                         bundleID, (unsigned long)ipaData.length]);
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridgeStub"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"[STUB] Simulated installation failure"}];
        }
        return NO;
    }
    
    return YES;
}

+ (BOOL)removeApp:(NSString *)bundleID
            error:(NSError **)error {
    HIAHLogStubCall(@"MinimuxerBridge", [NSString stringWithFormat:@"removeApp:%@", bundleID]);
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridgeStub"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"[STUB] Simulated app removal failure"}];
        }
        return NO;
    }
    
    return YES;
}

#pragma mark - Provisioning Profiles

+ (BOOL)installProvisioningProfile:(NSData *)profileData
                             error:(NSError **)error {
    HIAHLogStubCall(@"MinimuxerBridge", [NSString stringWithFormat:@"installProvisioningProfile dataSize:%lu",
                                         (unsigned long)profileData.length]);
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridgeStub"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"[STUB] Simulated profile installation failure"}];
        }
        return NO;
    }
    
    return YES;
}

+ (BOOL)removeProvisioningProfile:(NSString *)profileID
                            error:(NSError **)error {
    HIAHLogStubCall(@"MinimuxerBridge", [NSString stringWithFormat:@"removeProvisioningProfile:%@", profileID]);
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"MinimuxerBridgeStub"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"[STUB] Simulated profile removal failure"}];
        }
        return NO;
    }
    
    return YES;
}

#pragma mark - Pairing File

+ (NSString *)defaultPairingFilePath {
    HIAHLogStubCall(@"MinimuxerBridge", @"defaultPairingFilePath");
    
    // Return a path in the documents directory for simulator testing
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = paths.firstObject;
    NSString *pairingFile = [documentsDir stringByAppendingPathComponent:@"stub_pairing_file.plist"];
    
    // Create a stub pairing file if it doesn't exist (for testing)
    if (![[NSFileManager defaultManager] fileExistsAtPath:pairingFile]) {
        NSDictionary *stubData = @{
            @"DeviceUDID": gStubUDID,
            @"HostID": [[NSUUID UUID] UUIDString],
            @"SystemBUID": [[NSUUID UUID] UUIDString],
            @"WiFiMACAddress": @"00:00:00:00:00:00"
        };
        [stubData writeToFile:pairingFile atomically:YES];
    }
    
    return pairingFile;
}

+ (BOOL)hasPairingFile {
    HIAHLogStubCall(@"MinimuxerBridge", @"hasPairingFile");
    return [[NSFileManager defaultManager] fileExistsAtPath:[self defaultPairingFilePath]];
}

@end

#endif // HIAH_USE_SIMULATOR_STUBS
