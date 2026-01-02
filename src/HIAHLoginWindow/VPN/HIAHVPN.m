/**
 * HIAHVPN.m
 * Simplified VPN management for HIAH Desktop
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import "HIAHVPN.h"
#import "EMProxyBridge.h"
#import "../../HIAHDesktop/HIAHLogging.h"
#import <UIKit/UIKit.h>
#import <ifaddrs.h>
#import <net/if.h>

NSNotificationName const HIAHVPNStatusDidChangeNotification = @"HIAHVPNStatusDidChange";

// LocalDevVPN (official SideStore VPN)
static NSString * const kLocalDevVPNAppStoreID = @"1537034084";

// Config (keys must match em_proxy's built-in keys for handshake to work)
// These are placeholder keys - actual functionality depends on VPN interface existing
static NSString * const kConfigPrivateKey = @"WAmgVYXkbT2bCtdcDwolI8Nqqb1OkMJ8XhkwqPGZJQg=";
static NSString * const kConfigPublicKey = @"LH+SKYOmYVYm1QRXHZ/xwTdtKuNfmGK5CxcJC5N7B3c=";

// UserDefaults key
static NSString * const kSetupCompleteKey = @"HIAHVPN.SetupComplete";

@interface HIAHVPN ()
@property (nonatomic, assign) HIAHVPNStatus status;
@property (nonatomic, strong) NSTimer *monitorTimer;
@end

@implementation HIAHVPN

#pragma mark - Singleton

+ (instancetype)shared {
    static HIAHVPN *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _status = HIAHVPNStatusDisconnected;
    }
    return self;
}

#pragma mark - Public Properties

- (BOOL)isReady {
    return self.status == HIAHVPNStatusConnected;
}

- (BOOL)isSetupComplete {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSetupCompleteKey];
}

#pragma mark - Lifecycle

- (void)start {
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Starting VPN services...");
    
    // Start em_proxy
    [self startEMProxy];
    
    // Check initial status
    [self updateStatus];
    
    // Start monitoring (every 3 seconds - less aggressive than before)
    [self startMonitoring];
}

- (void)stop {
    [self stopMonitoring];
    [EMProxyBridge stopVPN];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"VPN services stopped");
}

#pragma mark - Setup

- (BOOL)needsSetup {
    // Fresh install detection: check for marker file
    NSString *markerPath = [self markerFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:markerPath]) {
        // Fresh install - reset setup flag
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kSetupCompleteKey];
        // Create marker
        [@"1" writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    
    // If setup not complete, needs setup
    if (!self.isSetupComplete) {
        return YES;
    }
    
    // If setup complete but VPN not connected, may need re-setup
    return self.status != HIAHVPNStatusConnected;
}

- (void)completeSetup {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kSetupCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Setup completed");
}

- (void)resetSetup {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kSetupCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSFileManager defaultManager] removeItemAtPath:[self markerFilePath] error:nil];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Setup reset");
}

- (NSString *)markerFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@".hiah_vpn"];
}

#pragma mark - LocalDevVPN Config

- (NSString *)generateConfig {
    return [NSString stringWithFormat:
        @"[Interface]\n"
        @"PrivateKey = %@\n"
        @"Address = 10.7.0.2/32\n"
        @"DNS = 8.8.8.8\n"
        @"\n"
        @"[Peer]\n"
        @"PublicKey = %@\n"
        @"AllowedIPs = 0.0.0.0/0, ::/0\n"
        @"Endpoint = 127.0.0.1:65399\n"
        @"PersistentKeepalive = 25\n",
        kConfigPrivateKey, kConfigPublicKey];
}

- (NSString *)saveConfigFile {
    NSString *config = [self generateConfig];
    NSString *path = [[self configFileURL] path];
    
    NSError *error;
    if ([config writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Config saved to: %@", path);
        return path;
    }
    HIAHLogEx(HIAH_LOG_ERROR, @"VPN", @"Failed to save config: %@", error);
    return nil;
}

- (NSURL *)configFileURL {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [paths.firstObject stringByAppendingPathComponent:@"HIAH-VPN.conf"];
    return [NSURL fileURLWithPath:path];
}

- (void)copyConfigToClipboard {
    [[UIPasteboard generalPasteboard] setString:[self generateConfig]];
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Config copied to clipboard");
}

- (void)openLocalDevVPN {
    // Use private API to open LocalDevVPN directly by bundle ID
    Class launcherClass = NSClassFromString(@"HIAHPrivateAppLauncher");
    SEL openSel = NSSelectorFromString(@"openLocalDevVPN");
    
    if (launcherClass && [launcherClass respondsToSelector:openSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [launcherClass performSelector:openSel];
#pragma clang diagnostic pop
    }
}

- (void)installLocalDevVPN {
    NSString *urlStr = [NSString stringWithFormat:@"itms-apps://apps.apple.com/app/id%@", kLocalDevVPNAppStoreID];
    NSURL *url = [NSURL URLWithString:urlStr];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

#pragma mark - Status

- (void)refresh {
    [self updateStatus];
}

- (BOOL)verifyConnection {
    // Simple check: em_proxy running + VPN interface exists
    BOOL emProxyOK = [EMProxyBridge isRunning];
    BOOL vpnOK = [self hasVPNInterface];
    
    return emProxyOK && vpnOK;
}

#pragma mark - Private

- (void)startEMProxy {
    if ([EMProxyBridge isRunning]) {
        return;
    }
    
    int result = [EMProxyBridge startVPNWithBindAddress:@"127.0.0.1:65399"];
    if (result == 0) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"em_proxy started");
    } else {
        HIAHLogEx(HIAH_LOG_ERROR, @"VPN", @"em_proxy failed to start: %d", result);
    }
}

- (void)startMonitoring {
    [self stopMonitoring];
    
    // Monitor every 3 seconds (reduced from 2s)
    self.monitorTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                         target:self
                                                       selector:@selector(updateStatus)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopMonitoring {
    [self.monitorTimer invalidate];
    self.monitorTimer = nil;
}

- (void)updateStatus {
    HIAHVPNStatus oldStatus = self.status;
    
    // Simple status check
    if ([self hasVPNInterface]) {
        self.status = HIAHVPNStatusConnected;
    } else if (self.isSetupComplete) {
        self.status = HIAHVPNStatusDisconnected;
    } else {
        self.status = HIAHVPNStatusNeedsSetup;
    }
    
    // Notify on change
    if (oldStatus != self.status) {
        HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Status: %@",
                  self.status == HIAHVPNStatusConnected ? @"CONNECTED" :
                  self.status == HIAHVPNStatusDisconnected ? @"DISCONNECTED" : @"NEEDS_SETUP");
        
        // Update bypass coordinator
        [self updateBypassCoordinator];
        
        // Post notification
        [[NSNotificationCenter defaultCenter] postNotificationName:HIAHVPNStatusDidChangeNotification
                                                            object:self];
    }
}

- (BOOL)hasVPNInterface {
    // Check for VPN tunnel interface (utun*)
    struct ifaddrs *interfaces = NULL;
    BOOL found = NO;
    
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *iface = interfaces;
        while (iface) {
            if (iface->ifa_name) {
                NSString *name = @(iface->ifa_name);
                if ([name hasPrefix:@"utun"]) {
                    if ((iface->ifa_flags & IFF_UP) && (iface->ifa_flags & IFF_RUNNING)) {
                        found = YES;
                        break;
                    }
                }
            }
            iface = iface->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    
    return found;
}

- (void)updateBypassCoordinator {
    // Update HIAHBypassCoordinator with VPN status
    Class coordClass = NSClassFromString(@"HIAHBypassCoordinator");
    if (!coordClass) return;
    
    SEL sharedSel = NSSelectorFromString(@"sharedCoordinator");
    if (![coordClass respondsToSelector:sharedSel]) return;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id coordinator = [coordClass performSelector:sharedSel];
#pragma clang diagnostic pop
    if (!coordinator) return;
    
    SEL updateSel = NSSelectorFromString(@"updateVPNStatus:");
    if (![coordinator respondsToSelector:updateSel]) return;
    
    // Use NSInvocation for BOOL parameter
    BOOL active = (self.status == HIAHVPNStatusConnected);
    NSMethodSignature *sig = [coordinator methodSignatureForSelector:updateSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:coordinator];
    [inv setSelector:updateSel];
    [inv setArgument:&active atIndex:2];
    [inv invoke];
}

@end

