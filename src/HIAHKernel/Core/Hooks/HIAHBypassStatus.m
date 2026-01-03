/**
 * HIAHBypassStatus.m
 * HIAH ProcessRunner Extension - Bypass Status Reader
 *
 * Lightweight status reader that works in extension context.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import "HIAHBypassStatus.h"
#import "HIAHLogging.h"
#import <sys/sysctl.h>

static NSString *const kAppGroupIdentifier =
    @"group.com.aspauldingcode.HIAHDesktop";
static NSString *const kBypassStatusFile = @"HIAH_BypassStatus.plist";
static NSString *const kVPNActiveKey = @"VPNActive";
static NSString *const kJITEnabledKey = @"JITEnabled";
static NSString *const kBypassReadyKey = @"BypassReady";
static NSString *const kLastUpdateKey = @"LastUpdate";

@interface HIAHBypassStatus ()

@property(nonatomic, assign) BOOL isVPNActive;
@property(nonatomic, assign) BOOL isJITEnabled;
@property(nonatomic, assign) BOOL isBypassReady;
@property(nonatomic, strong) NSURL *statusFileURL;

@end

@implementation HIAHBypassStatus

+ (instancetype)sharedStatus {
  static HIAHBypassStatus *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    // Get app group URL
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *groupURL = [fm
        containerURLForSecurityApplicationGroupIdentifier:kAppGroupIdentifier];
    if (groupURL) {
      _statusFileURL = [groupURL URLByAppendingPathComponent:kBypassStatusFile];
    }

    // Load initial status
    [self refreshStatus];
  }
  return self;
}

- (void)refreshStatus {
  if (!self.statusFileURL) {
    // No app group - assume not ready
    _isVPNActive = NO;
    _isJITEnabled = NO;
    _isBypassReady = NO;
    return;
  }

  NSDictionary *status =
      [NSDictionary dictionaryWithContentsOfURL:self.statusFileURL];
  if (status) {
    _isVPNActive = [status[kVPNActiveKey] boolValue];
    _isJITEnabled = [status[kJITEnabledKey] boolValue];
    _isBypassReady = [status[kBypassReadyKey] boolValue];

    // Check if status is stale (older than 30 seconds)
    NSDate *lastUpdate = status[kLastUpdateKey];
    if (lastUpdate && [[NSDate date] timeIntervalSinceDate:lastUpdate] > 30.0) {
      HIAHLogEx(HIAH_LOG_WARNING, @"BypassStatus",
                @"Status is stale (>30s), resetting");
      _isVPNActive = NO;
      _isJITEnabled = NO;
      _isBypassReady = NO;
    }
  } else {
    // No status file - assume not ready
    _isVPNActive = NO;
    _isJITEnabled = NO;
    _isBypassReady = NO;
  }

  // Always verify JIT status directly (more reliable)
  extern int csops(pid_t pid, unsigned int ops, void *useraddr,
                   size_t usersize);
#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000

  int flags = 0;
  BOOL jitActive = NO;
  if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) == 0) {
    jitActive = (flags & CS_DEBUGGED) != 0;
  }

  // Use direct check if it differs from stored value
  if (jitActive != _isJITEnabled) {
    _isJITEnabled = jitActive;
    HIAHLogEx(HIAH_LOG_INFO, @"BypassStatus",
              @"JIT status updated from direct check: %@",
              jitActive ? @"enabled" : @"disabled");
  }

  // Bypass is ready if VPN is active AND JIT is enabled
  _isBypassReady = (_isVPNActive && _isJITEnabled);
}

@end
