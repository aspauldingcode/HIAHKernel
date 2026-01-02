/**
 * HIAHVPNManager.m
 * HIAH LoginWindow - VPN Management
 *
 * Manages VPN connectivity using LocalDevVPN (App Store) for JIT enablement.
 * This is the official VPN used by SideStore.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHVPNManager.h"
#import "LocalDevVPN/HIAHLocalDevVPNManager.h"
#import "../../HIAHDesktop/HIAHLogging.h"
#import <Foundation/Foundation.h>

@interface HIAHVPNManager ()

@property (nonatomic, assign, readwrite) BOOL isVPNActive;
@property (nonatomic, strong) HIAHLocalDevVPNManager *localDevVPNManager;

@end

@implementation HIAHVPNManager

+ (instancetype)sharedManager {
    static HIAHVPNManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isVPNActive = NO;
        _localDevVPNManager = [HIAHLocalDevVPNManager sharedManager];
        [self setupVPNManager];
    }
    return self;
}

- (void)setupVPNManager {
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Setting up VPN manager (LocalDevVPN mode)...");
    
    // Start monitoring LocalDevVPN status
    [self.localDevVPNManager startMonitoringVPNStatus];
    
    // Check if LocalDevVPN is installed
    if ([self.localDevVPNManager isLocalDevVPNInstalled]) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"LocalDevVPN is installed");
    } else {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"LocalDevVPN not installed - VPN/JIT will not work");
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Install LocalDevVPN from App Store for JIT support");
    }
    
    // Observe LocalDevVPN status changes
    [NSTimer scheduledTimerWithTimeInterval:2.0
                                     target:self
                                   selector:@selector(updateVPNStatus)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)updateVPNStatus {
    BOOL wasActive = self.isVPNActive;
    self.isVPNActive = self.localDevVPNManager.isVPNActive;
    
    if (wasActive != self.isVPNActive) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Status changed: %@",
                 self.isVPNActive ? @"CONNECTED" : @"DISCONNECTED");
        
        // NOTE: Do NOT update bypass coordinator here!
        // HIAHVPNStateMachine is the single source of truth and handles
        // bypass coordinator updates. Updating here causes race conditions.
    }
}

- (void)startVPNWithCompletion:(void (^)(NSError * _Nullable error))completion {
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Starting VPN (LocalDevVPN mode)...");
    
    // Check if LocalDevVPN is installed
    if (![self.localDevVPNManager isLocalDevVPNInstalled]) {
        HIAHLogEx(HIAH_LOG_WARNING, @"VPN", @"LocalDevVPN not installed - user should use setup wizard");
        
        // Don't automatically open App Store - let the setup wizard handle user interaction
        // The LocalDevVPN setup flow will guide the user through installation
        
        if (completion) {
            completion([NSError errorWithDomain:@"VPNManager"
                                           code:-1
                                       userInfo:@{
                NSLocalizedDescriptionKey: @"LocalDevVPN not installed. Use the VPN setup wizard to install and configure."
            }]);
        }
        return;
    }
    
    // Check if VPN is already active
    if (self.localDevVPNManager.isVPNActive) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"LocalDevVPN is already active");
        self.isVPNActive = YES;
        if (completion) {
            completion(nil);
        }
        return;
    }
    
    // Open LocalDevVPN app
    // User will need to manually activate the VPN
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Opening LocalDevVPN for activation...");
    [self.localDevVPNManager openLocalDevVPN];
    
    // Return success - user needs to manually enable the VPN in LocalDevVPN
    if (completion) {
        completion([NSError errorWithDomain:@"VPNManager"
                                       code:0
                                   userInfo:@{
            NSLocalizedDescriptionKey: @"Please enable the VPN in LocalDevVPN app."
        }]);
    }
}

- (void)stopVPN {
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"To stop VPN, disable it in LocalDevVPN app");
    // Cannot programmatically stop LocalDevVPN - user must do it manually
}

#pragma mark - LocalDevVPN Status

- (BOOL)isLocalDevVPNInstalled {
    return [self.localDevVPNManager isLocalDevVPNInstalled];
}

- (HIAHLocalDevVPNStatus)localDevVPNStatus {
    return self.localDevVPNManager.status;
}

- (void)openLocalDevVPNApp {
    [self.localDevVPNManager openLocalDevVPN];
}

- (void)installLocalDevVPN {
    [self.localDevVPNManager openLocalDevVPNInAppStore];
}

@end
