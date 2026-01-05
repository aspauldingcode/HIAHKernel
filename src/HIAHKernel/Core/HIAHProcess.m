/**
 * HIAHProcess.m
 * Virtual Process Implementation
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import "HIAHProcess.h"
#import <pthread.h>

@implementation HIAHProcess

- (instancetype)init {
    if (self = [super init]) {
        _pid = 0;
        _physicalPid = 0;
        _ppid = 1; // Init as parent by default
        _pgid = 0;
        _sid = 0;
        _state = HIAHProcessStateCreated;
        _exitCode = 0;
        _exitSignal = 0;
        _startTime = [NSDate date];
        _handle = NULL;
        _thread = NULL;
    }
    return self;
}

+ (instancetype)processWithPath:(NSString *)path
                      arguments:(NSArray<NSString *> *)arguments
                    environment:(NSDictionary<NSString *, NSString *> *)environment {
    HIAHProcess *proc = [[self alloc] init];
    proc.executablePath = path;
    proc.arguments = arguments;
    proc.environment = environment;
    proc.workingDirectory = [[NSFileManager defaultManager] currentDirectoryPath];
    return proc;
}

- (BOOL)isExited {
    return _state == HIAHProcessStateTerminated || _state == HIAHProcessStateZombie;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<HIAHProcess pid=%d path=%@ state=%ld>",
            _pid, _executablePath.lastPathComponent, (long)_state];
}

@end
