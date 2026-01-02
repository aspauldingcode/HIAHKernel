/**
 * HIAHLocalDevVPNManager.m
 * HIAH LoginWindow - LocalDevVPN Integration
 *
 * Based on SideStore's official approach (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHLocalDevVPNManager.h"
#import "../EMProxyBridge.h"
#import "../HIAHVPNStateMachine.h"
#import "../../../HIAHDesktop/HIAHLogging.h"
#import "../HIAHPrivateAppLauncher.h"
#import <UIKit/UIKit.h>
#import <Network/Network.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <ifaddrs.h>
#import <net/if.h>

// LocalDevVPN App Store ID
static NSString * const kLocalDevVPNAppStoreID = @"1537034084";

@interface HIAHLocalDevVPNManager ()

@property (nonatomic, assign) HIAHLocalDevVPNStatus status;
@property (nonatomic, assign) BOOL isVPNActive;
@property (nonatomic, strong) NSTimer *statusTimer;
@property (nonatomic, strong) dispatch_queue_t monitorQueue;

@end

@implementation HIAHLocalDevVPNManager

+ (instancetype)sharedManager {
    static HIAHLocalDevVPNManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _status = HIAHLocalDevVPNStatusDisconnected;
        _isVPNActive = NO;
        _monitorQueue = dispatch_queue_create("com.aspauldingcode.HIAHDesktop.localdevvpn", DISPATCH_QUEUE_SERIAL);
        
        // Check for fresh install - reset setup if app was reinstalled
        [self checkForFreshInstall];
        
        // Start em_proxy automatically - it needs to be running before LocalDevVPN connects
        [self startEMProxy];
        
        // Check initial status
        [self refreshVPNStatus];
    }
    return self;
}

- (void)checkForFreshInstall {
    // Use a marker file in the app's Documents directory to detect fresh installs
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = paths.firstObject;
    NSString *markerPath = [documentsDir stringByAppendingPathComponent:@".hiah_vpn_installed"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:markerPath]) {
        // Fresh install - reset setup flag and create marker
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Fresh install detected - resetting VPN setup flag");
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"HIAHVPNSetupCompleted"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // Create marker file
        [fm createFileAtPath:markerPath contents:[@"installed" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
    }
}

#pragma mark - EM Proxy Management

- (BOOL)startEMProxy {
    if ([EMProxyBridge isRunning]) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"LocalDevVPN", @"em_proxy already running");
        return YES;
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Starting em_proxy...");
    int result = [EMProxyBridge startVPNWithBindAddress:@"127.0.0.1:65399"];
    
    if (result == 0) {
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"✅ em_proxy started successfully");
        return YES;
    } else {
        HIAHLogEx(HIAH_LOG_ERROR, @"LocalDevVPN", @"❌ Failed to start em_proxy: %d", result);
        return NO;
    }
}

- (void)stopEMProxy {
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Stopping em_proxy...");
    [EMProxyBridge stopVPN];
}

- (BOOL)isEMProxyRunning {
    return [EMProxyBridge isRunning];
}

#pragma mark - LocalDevVPN Detection

- (BOOL)isLocalDevVPNInstalled {
    return [HIAHPrivateAppLauncher isAppInstalled:kLocalDevVPNBundleID];
}

- (void)openLocalDevVPNInAppStore {
    NSString *appStoreURL = [NSString stringWithFormat:@"https://apps.apple.com/app/id%@", kLocalDevVPNAppStoreID];
    NSURL *url = [NSURL URLWithString:appStoreURL];
    
    if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Opened App Store for LocalDevVPN");
    } else {
        HIAHLogEx(HIAH_LOG_ERROR, @"LocalDevVPN", @"Failed to open App Store URL: %@", appStoreURL);
    }
}

- (void)openLocalDevVPN {
    if ([HIAHPrivateAppLauncher openAppWithBundleID:kLocalDevVPNBundleID]) {
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Opened LocalDevVPN app");
    } else {
        HIAHLogEx(HIAH_LOG_WARNING, @"LocalDevVPN", @"Failed to open LocalDevVPN app");
    }
}

#pragma mark - VPN Status Detection

- (BOOL)isVPNInterfaceActive {
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    BOOL vpnActive = NO;
    
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *interfaceName = [NSString stringWithUTF8String:temp_addr->ifa_name];
                // Check for VPN interfaces (utun, ipsec, etc.)
                if ([interfaceName hasPrefix:@"utun"] || [interfaceName hasPrefix:@"ipsec"]) {
                    vpnActive = YES;
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    
    return vpnActive;
}

- (void)refreshVPNStatus {
    dispatch_async(self.monitorQueue, ^{
        BOOL emProxyRunning = [self isEMProxyRunning];
        BOOL vpnInterfaceActive = [self isVPNInterfaceActive];
        
        // Use test_emotional_damage to verify VPN is actually connected to em_proxy
        // This is more reliable than just checking for VPN interfaces
        BOOL vpnConnected = NO;
        if (emProxyRunning) {
            // Test with multiple timeouts to ensure reliability
            int testResult1 = [EMProxyBridge testVPNWithTimeout:1];
            if (testResult1 == 0) {
                usleep(500000); // 500ms delay
                int testResult2 = [EMProxyBridge testVPNWithTimeout:1];
                if (testResult2 == 0) {
                    vpnConnected = YES;
                }
            }
        }
        
        HIAHLocalDevVPNStatus newStatus;
        BOOL newVPNActive = NO;
        
        if (![self isLocalDevVPNInstalled]) {
            newStatus = HIAHLocalDevVPNStatusNotInstalled;
        } else if (vpnConnected && emProxyRunning) {
            newStatus = HIAHLocalDevVPNStatusConnected;
            newVPNActive = YES;
        } else if (vpnInterfaceActive || emProxyRunning) {
            newStatus = HIAHLocalDevVPNStatusConnecting;
        } else {
            newStatus = HIAHLocalDevVPNStatusDisconnected;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL statusChanged = (self.status != newStatus);
            BOOL activeChanged = (self.isVPNActive != newVPNActive);
            
            self.status = newStatus;
            self.isVPNActive = newVPNActive;
            
            if (statusChanged || activeChanged) {
                HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"VPN status changed: %@ (active: %@)",
                         [self statusString:newStatus], newVPNActive ? @"YES" : @"NO");
            }
        });
    });
}

- (NSString *)statusString:(HIAHLocalDevVPNStatus)status {
    switch (status) {
        case HIAHLocalDevVPNStatusNotInstalled:
            return @"NOT_INSTALLED";
        case HIAHLocalDevVPNStatusDisconnected:
            return @"DISCONNECTED";
        case HIAHLocalDevVPNStatusConnecting:
            return @"CONNECTING";
        case HIAHLocalDevVPNStatusConnected:
            return @"CONNECTED";
        case HIAHLocalDevVPNStatusError:
            return @"ERROR";
    }
}

#pragma mark - VPN Verification

- (BOOL)verifyFullVPNConnection {
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"verifyFullVPNConnection called");
    
    // Check if em_proxy is running
    BOOL emProxyRunning = [EMProxyBridge isRunning];
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"em_proxy running: %@", emProxyRunning ? @"YES" : @"NO");
    
    if (!emProxyRunning) {
        HIAHLogEx(HIAH_LOG_WARNING, @"LocalDevVPN", @"em_proxy not running - starting it now");
        if (![self startEMProxy]) {
            HIAHLogEx(HIAH_LOG_ERROR, @"LocalDevVPN", @"Failed to start em_proxy");
            return NO;
        }
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"em_proxy started successfully");
    }
    
    // Use the reliable detectHIAHVPNConnected method from HIAHVPNStateMachine
    // This checks for active VPN interface AND test_emotional_damage passing
    HIAHVPNStateMachine *vpnSM = [HIAHVPNStateMachine shared];
    BOOL verified = [vpnSM detectHIAHVPNConnected];
    
    if (verified) {
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"✅ VPN connection verified via detectHIAHVPNConnected");
        return YES;
    }
    
    HIAHLogEx(HIAH_LOG_WARNING, @"LocalDevVPN", @"❌ VPN connection not verified");
    return NO;
}

#pragma mark - VPN Status Monitoring

- (void)startMonitoringVPNStatus {
    [self stopMonitoringVPNStatus];
    
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Starting VPN status monitoring...");
    
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                         target:self
                                                       selector:@selector(refreshVPNStatus)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopMonitoringVPNStatus {
    if (self.statusTimer) {
        [self.statusTimer invalidate];
        self.statusTimer = nil;
        HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"Stopped VPN status monitoring");
    }
}

#pragma mark - Setup State

- (BOOL)isHIAHVPNConfigured {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HIAHVPNSetupCompleted"];
}

- (void)markSetupCompleted {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HIAHVPNSetupCompleted"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"VPN setup marked as completed");
}

- (void)resetSetup {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"HIAHVPNSetupCompleted"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HIAHLogEx(HIAH_LOG_INFO, @"LocalDevVPN", @"VPN setup reset");
}

@end

