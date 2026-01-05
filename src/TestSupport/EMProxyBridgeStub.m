/**
 * EMProxyBridgeStub.m
 * HIAH Kernel - Test Support
 *
 * Stub implementation of EMProxyBridge for iOS Simulator builds.
 * This provides mock behavior for the em_proxy VPN loopback functionality.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3 (follows EMProxyBridge licensing)
 */

#import "SimulatorStubs.h"

// Only compile stub implementation when stubs are enabled
#if HIAH_USE_SIMULATOR_STUBS

#import "../HIAHLoginWindow/VPN/EMProxyBridge.h"

static BOOL gEMProxyRunning = NO;
static dispatch_queue_t gEMProxyQueue = nil;

@implementation EMProxyBridge

+ (void)initialize {
    if (self == [EMProxyBridge class]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gEMProxyQueue = dispatch_queue_create("com.hiah.emproxy.stub", DISPATCH_QUEUE_SERIAL);
        });
    }
}

+ (BOOL)isRunning {
    HIAHLogStubCall(@"EMProxyBridge", @"isRunning");
    return gEMProxyRunning;
}

+ (int)startVPNWithBindAddress:(NSString *)bindAddress {
    HIAHLogStubCall(@"EMProxyBridge", [NSString stringWithFormat:@"startVPNWithBindAddress:%@", bindAddress]);
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        NSLog(@"[STUB:EMProxyBridge] Simulated VPN start failure");
        return -1;
    }
    
    // Simulate async startup
    dispatch_async(gEMProxyQueue, ^{
        if (HIAHStubConfiguration.shared.simulatedDelay > 0) {
            [NSThread sleepForTimeInterval:HIAHStubConfiguration.shared.simulatedDelay];
        }
        gEMProxyRunning = YES;
        NSLog(@"[STUB:EMProxyBridge] VPN started on %@ (simulated)", bindAddress);
    });
    
    return 0;
}

+ (void)stopVPN {
    HIAHLogStubCall(@"EMProxyBridge", @"stopVPN");
    
    dispatch_sync(gEMProxyQueue, ^{
        gEMProxyRunning = NO;
        NSLog(@"[STUB:EMProxyBridge] VPN stopped (simulated)");
    });
}

+ (int)testVPNWithTimeout:(NSInteger)timeout {
    HIAHLogStubCall(@"EMProxyBridge", [NSString stringWithFormat:@"testVPNWithTimeout:%ld", (long)timeout]);
    
    if (!HIAHStubConfiguration.shared.simulateSuccess) {
        return -1;
    }
    
    // Simulate waiting for VPN to be ready
    __block int result = -1;
    dispatch_sync(gEMProxyQueue, ^{
        if (gEMProxyRunning) {
            result = 0;
        }
    });
    
    if (result == 0) {
        NSLog(@"[STUB:EMProxyBridge] VPN test passed (simulated)");
    } else {
        NSLog(@"[STUB:EMProxyBridge] VPN test failed - not running (simulated)");
    }
    
    return result;
}

@end

#endif // HIAH_USE_SIMULATOR_STUBS
