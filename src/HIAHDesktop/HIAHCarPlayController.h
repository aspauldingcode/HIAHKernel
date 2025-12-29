/**
 * HIAHCarPlayController.h
 * CarPlay Interface Controller for HIAHDesktop
 * 
 * Provides full CarPlay Kit integration for HIAHDesktop:
 * - Complete CarPlay interface for HIAH Desktop
 * - View running processes/apps
 * - Launch apps directly from CarPlay
 * - Control windows (minimize, maximize, rollup, close)
 * - System statistics and monitoring
 * 
 * When CarPlay is connected, HIAH Desktop runs directly on the CarPlay display
 * with a native CarPlay interface optimized for in-vehicle use.
 */

#import <Foundation/Foundation.h>
#import <CarPlay/CarPlay.h>

@class HIAHKernel;

// Forward declaration - DesktopViewController is defined in HIAHDesktopApp.m
@class DesktopViewController;

NS_ASSUME_NONNULL_BEGIN

@interface HIAHCarPlayController : NSObject

@property (nonatomic, strong, nullable) CPInterfaceController *interfaceController;
@property (nonatomic, strong, nullable) CPWindow *carWindow;
@property (nonatomic, weak, nullable) DesktopViewController *mainDesktop;
@property (nonatomic, assign, readonly) BOOL isCarPlayConnected;

+ (instancetype)sharedController;

/// Handle CarPlay connection (called by AppDelegate)
- (void)application:(UIApplication *)application didConnectCarInterfaceController:(CPInterfaceController *)interfaceController toWindow:(CPWindow *)window API_AVAILABLE(ios(12.0));

/// Handle CarPlay disconnection (called by AppDelegate)
- (void)application:(UIApplication *)application didDisconnectCarInterfaceController:(CPInterfaceController *)interfaceController fromWindow:(CPWindow *)window API_AVAILABLE(ios(12.0));

/// Setup the CarPlay interface
- (void)setupCarPlayInterface;

/// Update the process list display
- (void)updateProcessList;

/// Launch an app from CarPlay
- (void)launchAppWithBundleID:(NSString *)bundleID name:(NSString *)name;

@end

NS_ASSUME_NONNULL_END

