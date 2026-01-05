/**
 * SimulatorStubs.h
 * HIAH Kernel - Test Support
 *
 * Provides compile-time detection for simulator builds and stub implementations
 * for device-only features that cannot run in the iOS Simulator.
 *
 * Usage:
 *   #if HIAH_USE_SIMULATOR_STUBS
 *       // Use stub implementations
 *   #else
 *       // Use real implementations
 *   #endif
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License (test support code)
 */

#ifndef SimulatorStubs_h
#define SimulatorStubs_h

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

// Automatically enable stubs on simulator unless explicitly disabled
#if TARGET_OS_SIMULATOR && !defined(HIAH_FORCE_REAL_IMPLEMENTATIONS)
    #define HIAH_USE_SIMULATOR_STUBS 1
#else
    #define HIAH_USE_SIMULATOR_STUBS 0
#endif

// Also allow manual override via build settings
#if defined(HIAH_ENABLE_STUBS) && HIAH_ENABLE_STUBS
    #undef HIAH_USE_SIMULATOR_STUBS
    #define HIAH_USE_SIMULATOR_STUBS 1
#endif

#pragma mark - Stub Configuration

/// Configuration for how stubs should behave in tests
@interface HIAHStubConfiguration : NSObject

/// Shared configuration instance
@property (class, readonly) HIAHStubConfiguration *shared;

/// Whether stub operations should simulate success (default: YES)
@property (nonatomic, assign) BOOL simulateSuccess;

/// Whether to log stub calls for debugging (default: YES in DEBUG)
@property (nonatomic, assign) BOOL logStubCalls;

/// Simulated delay for async operations in seconds (default: 0.1)
@property (nonatomic, assign) NSTimeInterval simulatedDelay;

/// Reset configuration to defaults
- (void)reset;

@end

#pragma mark - Stub Logging

/// Log a stub call if logging is enabled
NS_INLINE void HIAHLogStubCall(NSString *stubName, NSString *method) {
    if (HIAHStubConfiguration.shared.logStubCalls) {
        NSLog(@"[STUB:%@] %@", stubName, method);
    }
}

#endif /* SimulatorStubs_h */
