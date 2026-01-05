/**
 * SimulatorStubs.m
 * HIAH Kernel - Test Support
 *
 * Implementation of stub configuration for simulator builds.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License (test support code)
 */

#import "SimulatorStubs.h"

@implementation HIAHStubConfiguration

+ (HIAHStubConfiguration *)shared {
    static HIAHStubConfiguration *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HIAHStubConfiguration alloc] init];
        [instance reset];
    });
    return instance;
}

- (void)reset {
    self.simulateSuccess = YES;
    self.simulatedDelay = 0.1;
#if DEBUG
    self.logStubCalls = YES;
#else
    self.logStubCalls = NO;
#endif
}

@end
