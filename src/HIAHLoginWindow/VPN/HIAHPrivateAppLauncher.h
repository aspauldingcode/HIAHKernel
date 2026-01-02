/**
 * HIAHPrivateAppLauncher.h
 * Private API wrapper for launching apps by bundle ID
 * 
 * Uses LSApplicationWorkspace private API - works on sideloaded/jailbroken apps
 * Does NOT work on App Store apps (sandbox restrictions)
 *
 * Copyright (c) 2025 Alex Spaulding - AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// LocalDevVPN iOS app bundle identifier
extern NSString * const kLocalDevVPNBundleID;

/**
 * HIAHPrivateAppLauncher
 * 
 * Provides methods to launch apps by bundle ID using private iOS APIs.
 * This only works in sideloaded/jailbroken contexts where sandbox
 * restrictions on private APIs are relaxed.
 */
@interface HIAHPrivateAppLauncher : NSObject

/// Check if an app is installed by bundle ID
+ (BOOL)isAppInstalled:(NSString *)bundleID;

/// Get the localized name of an installed app
+ (nullable NSString *)appNameForBundleID:(NSString *)bundleID;

/// Open an app by bundle ID using private LSApplicationWorkspace API
/// @param bundleID The bundle identifier of the app to open
/// @return YES if the app was successfully launched, NO otherwise
+ (BOOL)openAppWithBundleID:(NSString *)bundleID;

/// Convenience method to open LocalDevVPN app
+ (BOOL)openLocalDevVPN;

/// Check if LocalDevVPN is installed
+ (BOOL)isLocalDevVPNInstalled;

@end

NS_ASSUME_NONNULL_END

