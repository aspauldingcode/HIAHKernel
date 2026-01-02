/**
 * HIAHPrivateAppLauncher.m
 * Private API wrapper for launching apps by bundle ID
 *
 * Copyright (c) 2025 Alex Spaulding - AGPLv3
 */

#import "HIAHPrivateAppLauncher.h"
#import "../HIAHDesktop/HIAHLogging.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString * const kLocalDevVPNBundleID = @"com.rileytestut.LocalDevVPN";

@implementation HIAHPrivateAppLauncher

#pragma mark - Private API Access

/// Get LSApplicationWorkspace class (private API)
+ (Class)applicationWorkspaceClass {
    return objc_getClass("LSApplicationWorkspace");
}

/// Get LSApplicationProxy class (private API)
+ (Class)applicationProxyClass {
    return objc_getClass("LSApplicationProxy");
}

/// Get the default workspace instance
+ (id)defaultWorkspace {
    Class cls = [self applicationWorkspaceClass];
    if (!cls) {
        HIAHLogEx(HIAH_LOG_WARNING, @"AppLauncher", @"LSApplicationWorkspace class not found");
        return nil;
    }
    
    SEL sel = NSSelectorFromString(@"defaultWorkspace");
    if (![cls respondsToSelector:sel]) {
        HIAHLogEx(HIAH_LOG_WARNING, @"AppLauncher", @"defaultWorkspace selector not found");
        return nil;
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [cls performSelector:sel];
#pragma clang diagnostic pop
}

#pragma mark - App Detection

+ (BOOL)isAppInstalled:(NSString *)bundleID {
    Class proxyClass = [self applicationProxyClass];
    if (!proxyClass) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"AppLauncher", @"LSApplicationProxy not available, checking via workspace");
        return [self isAppInstalledViaWorkspace:bundleID];
    }
    
    SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (![proxyClass respondsToSelector:sel]) {
        return [self isAppInstalledViaWorkspace:bundleID];
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id proxy = [proxyClass performSelector:sel withObject:bundleID];
#pragma clang diagnostic pop
    
    if (proxy) {
        HIAHLogEx(HIAH_LOG_DEBUG, @"AppLauncher", @"App %@ is installed", bundleID);
        return YES;
    }
    
    HIAHLogEx(HIAH_LOG_DEBUG, @"AppLauncher", @"App %@ is NOT installed", bundleID);
    return NO;
}

+ (BOOL)isAppInstalledViaWorkspace:(NSString *)bundleID {
    id workspace = [self defaultWorkspace];
    if (!workspace) return NO;
    
    // Try applicationIsInstalled: selector
    SEL sel = NSSelectorFromString(@"applicationIsInstalled:");
    if ([workspace respondsToSelector:sel]) {
        // Use objc_msgSend for BOOL return type
        BOOL (*msgSend)(id, SEL, id) = (BOOL (*)(id, SEL, id))objc_msgSend;
        return msgSend(workspace, sel, bundleID);
    }
    
    // Try allInstalledApplications and search
    SEL allAppsSel = NSSelectorFromString(@"allInstalledApplications");
    if ([workspace respondsToSelector:allAppsSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *apps = [workspace performSelector:allAppsSel];
#pragma clang diagnostic pop
        
        for (id app in apps) {
            SEL bundleSel = NSSelectorFromString(@"bundleIdentifier");
            if ([app respondsToSelector:bundleSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                NSString *appBundleID = [app performSelector:bundleSel];
#pragma clang diagnostic pop
                if ([appBundleID isEqualToString:bundleID]) {
                    return YES;
                }
            }
        }
    }
    
    return NO;
}

+ (NSString *)appNameForBundleID:(NSString *)bundleID {
    Class proxyClass = [self applicationProxyClass];
    if (!proxyClass) return nil;
    
    SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (![proxyClass respondsToSelector:sel]) return nil;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id proxy = [proxyClass performSelector:sel withObject:bundleID];
#pragma clang diagnostic pop
    
    if (!proxy) return nil;
    
    SEL nameSel = NSSelectorFromString(@"localizedName");
    if ([proxy respondsToSelector:nameSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        return [proxy performSelector:nameSel];
#pragma clang diagnostic pop
    }
    
    return nil;
}

#pragma mark - App Launching

+ (BOOL)openAppWithBundleID:(NSString *)bundleID {
    HIAHLogEx(HIAH_LOG_INFO, @"AppLauncher", @"Attempting to open app: %@", bundleID);
    
    id workspace = [self defaultWorkspace];
    if (!workspace) {
        HIAHLogEx(HIAH_LOG_ERROR, @"AppLauncher", @"Failed to get LSApplicationWorkspace");
        return NO;
    }
    
    SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (![workspace respondsToSelector:openSel]) {
        HIAHLogEx(HIAH_LOG_ERROR, @"AppLauncher", @"openApplicationWithBundleID: selector not available");
        return NO;
    }
    
    // Use objc_msgSend for BOOL return type
    BOOL (*msgSend)(id, SEL, id) = (BOOL (*)(id, SEL, id))objc_msgSend;
    BOOL success = msgSend(workspace, openSel, bundleID);
    
    if (success) {
        HIAHLogEx(HIAH_LOG_INFO, @"AppLauncher", @"✅ Successfully opened app: %@", bundleID);
    } else {
        HIAHLogEx(HIAH_LOG_WARNING, @"AppLauncher", @"❌ Failed to open app: %@", bundleID);
    }
    
    return success;
}

#pragma mark - LocalDevVPN Convenience

+ (BOOL)openLocalDevVPN {
    return [self openAppWithBundleID:kLocalDevVPNBundleID];
}

+ (BOOL)isLocalDevVPNInstalled {
    return [self isAppInstalled:kLocalDevVPNBundleID];
}

@end

