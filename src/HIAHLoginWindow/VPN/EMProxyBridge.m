/**
 * EMProxyBridge.m
 * HIAH LoginWindow - EM Proxy Bridge
 *
 * Bridge to em_proxy Rust library for VPN loopback functionality.
 * em_proxy creates a UDP socket that LocalDevVPN connects to, enabling
 * JIT via the debugger attachment flow.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "EMProxyBridge.h"
#import "../../HIAHDesktop/HIAHLogging.h"

// em_proxy C API from the linked static library
// These functions are defined in em_proxy.h and implemented in libem_proxy-*.a
extern int start_emotional_damage(const char *bind_addr);
extern void stop_emotional_damage(void);
extern int test_emotional_damage(int timeout);

// Thread-safe state tracking
static BOOL gEMProxyRunning = NO;
static BOOL gEMProxyStarting = NO;  // Prevent concurrent start attempts
static int gEMProxyHandle = 0;
static dispatch_queue_t gEMProxyQueue = nil;

@implementation EMProxyBridge

+ (void)initialize {
    if (self == [EMProxyBridge class]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gEMProxyQueue = dispatch_queue_create("com.aspauldingcode.HIAHDesktop.emproxy", DISPATCH_QUEUE_SERIAL);
        });
    }
}

+ (BOOL)isRunning {
    __block BOOL running;
    dispatch_sync(gEMProxyQueue, ^{
        running = gEMProxyRunning;
    });
    return running;
}

+ (int)startVPNWithBindAddress:(NSString *)bindAddress {
    __block int result = -999;  // Sentinel value meaning "not handled yet"
    __block BOOL shouldStart = NO;
    
    dispatch_sync(gEMProxyQueue, ^{
        // Already running - success
        if (gEMProxyRunning) {
            HIAHLogEx(HIAH_LOG_DEBUG, @"EMProxy", @"em_proxy already running, isRunning will return YES");
            result = 0;
            return;
        }
        
        // Another thread is starting it - wait and return success
        if (gEMProxyStarting) {
            HIAHLogEx(HIAH_LOG_DEBUG, @"EMProxy", @"em_proxy is being started by another thread");
            result = 0;
            return;
        }
        
        // Mark as starting and signal to proceed
        gEMProxyStarting = YES;
        shouldStart = YES;
    });
    
    // If already handled, return early
    if (!shouldStart) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"EMProxy", @"Early return with result: %d", result);
        return result;
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"EMProxy", @"Starting em_proxy on %@", bindAddress);
    
    // Call the em_proxy library function directly
    // start_emotional_damage creates a UDP socket and returns a handle
    const char *addr = [bindAddress UTF8String];
    int startResult = start_emotional_damage(addr);
    
    dispatch_sync(gEMProxyQueue, ^{
        gEMProxyStarting = NO;
        
        if (startResult >= 0) {
            // Non-negative value indicates success
            gEMProxyHandle = startResult;
            gEMProxyRunning = YES;
            HIAHLogEx(HIAH_LOG_INFO, @"EMProxy", @"✅ em_proxy started successfully (result: %d), isRunning will return YES", startResult);
            result = 0;
        } else {
            HIAHLogEx(HIAH_LOG_ERROR, @"EMProxy", @"❌ Failed to start em_proxy: %d", startResult);
            result = startResult;
        }
    });
    
    HIAHLogEx(HIAH_LOG_INFO, @"EMProxy", @"startVPNWithBindAddress returning: %d", result);
    return result;
}

+ (void)stopVPN {
    dispatch_sync(gEMProxyQueue, ^{
        if (!gEMProxyRunning) {
            HIAHLogEx(HIAH_LOG_DEBUG, @"EMProxy", @"em_proxy not running, nothing to stop");
            return;
        }
        
        HIAHLogEx(HIAH_LOG_INFO, @"EMProxy", @"Stopping em_proxy...");
        
        // Call the stop function from em_proxy library
        stop_emotional_damage();
        
        gEMProxyRunning = NO;
        gEMProxyHandle = 0;
        
        HIAHLogEx(HIAH_LOG_INFO, @"EMProxy", @"em_proxy stopped");
    });
}

+ (int)testVPNWithTimeout:(NSInteger)timeout {
    __block BOOL running;
    dispatch_sync(gEMProxyQueue, ^{
        running = gEMProxyRunning;
    });
    
    if (!running) {
        // Don't log - this is called frequently in status checks
        return -1;
    }
    
    // Note: test_emotional_damage is thread-safe and handles concurrent calls
    // The panics in the logs are from start_emotional_damage being called multiple times
    int result = test_emotional_damage((int)timeout);
    
    if (result == 0) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"EMProxy", @"LocalDevVPN connection OK");
    }
    // Don't log failures - too noisy
    
    return result;
}

@end
