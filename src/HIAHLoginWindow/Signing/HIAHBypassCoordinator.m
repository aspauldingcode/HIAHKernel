/**
 * HIAHBypassCoordinator.m
 * HIAH LoginWindow - Shared Bypass Status Coordinator
 *
 * Coordinates VPN/JIT status between main app and ProcessRunner extension
 * using App Group shared storage.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHBypassCoordinator.h"
#import "HIAHLogging.h"
#import <sys/sysctl.h>

static NSString * const kAppGroupIdentifier = @"group.com.aspauldingcode.HIAHDesktop";
static NSString * const kBypassStatusFile = @"HIAH_BypassStatus.plist";
static NSString * const kVPNActiveKey = @"VPNActive";
static NSString * const kJITEnabledKey = @"JITEnabled";
static NSString * const kBypassReadyKey = @"BypassReady";
static NSString * const kLastUpdateKey = @"LastUpdate";

@interface HIAHBypassCoordinator ()

@property (nonatomic, assign) BOOL isVPNActive;
@property (nonatomic, assign) BOOL isJITEnabled;
@property (nonatomic, assign) BOOL isBypassReady;
@property (nonatomic, strong) NSURL *statusFileURL;
@property (nonatomic, strong) dispatch_queue_t queue;

@end

@implementation HIAHBypassCoordinator

+ (instancetype)sharedCoordinator {
    static HIAHBypassCoordinator *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.aspauldingcode.HIAHDesktop.bypassCoordinator", DISPATCH_QUEUE_SERIAL);
        
        // Get app group URL
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:kAppGroupIdentifier];
        if (groupURL) {
            _statusFileURL = [groupURL URLByAppendingPathComponent:kBypassStatusFile];
            // Ensure directory exists
            [fm createDirectoryAtPath:groupURL.path withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        // Load initial status
        [self loadStatus];
    }
    return self;
}

- (void)loadStatus {
    if (!self.statusFileURL) return;
    
    NSDictionary *status = [NSDictionary dictionaryWithContentsOfURL:self.statusFileURL];
    if (status) {
        _isVPNActive = [status[kVPNActiveKey] boolValue];
        _isJITEnabled = [status[kJITEnabledKey] boolValue];
        _isBypassReady = [status[kBypassReadyKey] boolValue];
        
        // Check if status is stale (older than 30 seconds)
        NSDate *lastUpdate = status[kLastUpdateKey];
        if (lastUpdate && [[NSDate date] timeIntervalSinceDate:lastUpdate] > 30.0) {
            HIAHLogEx(HIAH_LOG_WARNING, @"BypassCoordinator", @"Status is stale, resetting");
            _isVPNActive = NO;
            _isJITEnabled = NO;
            _isBypassReady = NO;
        }
    }
}

- (void)saveStatus {
    if (!self.statusFileURL) return;
    
    NSDictionary *status = @{
        kVPNActiveKey: @(self.isVPNActive),
        kJITEnabledKey: @(self.isJITEnabled),
        kBypassReadyKey: @(self.isBypassReady),
        kLastUpdateKey: [NSDate date]
    };
    
    [status writeToURL:self.statusFileURL atomically:YES];
}

- (void)updateVPNStatus:(BOOL)active {
    dispatch_async(self.queue, ^{
        self->_isVPNActive = active;
        self->_isBypassReady = (self.isVPNActive && self.isJITEnabled);
        [self saveStatus];
        HIAHLogEx(HIAH_LOG_INFO, @"BypassCoordinator", @"VPN status updated: %@", active ? @"active" : @"inactive");
    });
}

- (void)updateJITStatus:(BOOL)enabled {
    dispatch_async(self.queue, ^{
        self->_isJITEnabled = enabled;
        self->_isBypassReady = (self.isVPNActive && self.isJITEnabled);
        [self saveStatus];
        HIAHLogEx(HIAH_LOG_INFO, @"BypassCoordinator", @"JIT status updated: %@", enabled ? @"enabled" : @"disabled");
    });
}

- (BOOL)requestBypassActivation {
    // Check current status
    [self loadStatus];
    
    if (self.isBypassReady) {
        return YES;
    }
    
    // Check if JIT is actually enabled (verify CS_DEBUGGED flag)
    extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
    #define CS_OPS_STATUS 0
    #define CS_DEBUGGED 0x10000000
    
    int flags = 0;
    BOOL jitActive = NO;
    if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) == 0) {
        jitActive = (flags & CS_DEBUGGED) != 0;
    }
    
    // Update local status
    dispatch_async(self.queue, ^{
        self->_isJITEnabled = jitActive;
        self->_isBypassReady = (self.isVPNActive && self.isJITEnabled);
        [self saveStatus];
    });
    
    return self.isBypassReady;
}

- (BOOL)checkBypassReady {
    [self loadStatus];
    
    // Also verify JIT status directly
    extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
    #define CS_OPS_STATUS 0
    #define CS_DEBUGGED 0x10000000
    
    int flags = 0;
    BOOL jitActive = NO;
    if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) == 0) {
        jitActive = (flags & CS_DEBUGGED) != 0;
    }
    
    // Update if status changed
    if (jitActive != self.isJITEnabled) {
        [self updateJITStatus:jitActive];
    }
    
    return (self.isVPNActive && jitActive);
}

@end

