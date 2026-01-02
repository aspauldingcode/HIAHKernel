/**
 * HIAHProcess.m
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Implementation of the HIAHProcess model.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import "HIAHProcess.h"

@implementation HIAHProcess

- (instancetype)init {
    self = [super init];
    if (self) {
        _startTime = [NSDate date];
        _pid = -1;
        _physicalPid = -1;
        _ppid = -1;
        _exitCode = 0;
        _isExited = NO;
    }
    return self;
}

+ (instancetype)processWithPath:(NSString *)path
                      arguments:(NSArray<NSString *> *)arguments
                    environment:(NSDictionary<NSString *, NSString *> *)environment {
    HIAHProcess *process = [[HIAHProcess alloc] init];
    process.executablePath = path;
    process.arguments = arguments;
    process.environment = environment;
    return process;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<HIAHProcess pid=%d physical=%d path=%@ exited=%@ exit=%d>",
            self.pid, self.physicalPid, self.executablePath,
            self.isExited ? @"YES" : @"NO", self.exitCode];
}

@end

