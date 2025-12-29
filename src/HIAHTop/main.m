/**
 * main.m
 * HIAH Top - Process Monitor for HIAHKernel Virtual Processes
 *
 * A jailed-compatible Activity Monitor that displays processes
 * managed by the HIAHKernel virtual kernel.
 */

#import <UIKit/UIKit.h>
#import "HIAHTopViewController.h"

@interface HIAHTopAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation HIAHTopAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSLog(@"[HIAHTop] Application launching...");
    
    // Get windowScene from connected scenes (iOS 26.0+)
    UIWindowScene *windowScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            windowScene = (UIWindowScene *)scene;
            break;
        }
    }
    
    if (windowScene) {
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    } else {
        // Fallback for iOS < 26.0
        self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    }
    
    HIAHTopViewController *topVC = [[HIAHTopViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:topVC];
    
    self.window.rootViewController = navController;
    [self.window makeKeyAndVisible];
    
    NSLog(@"[HIAHTop] Application ready - showing process monitor");
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    NSLog(@"[HIAHTop] App will resign active");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    NSLog(@"[HIAHTop] App entered background");
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    NSLog(@"[HIAHTop] App will enter foreground");
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    NSLog(@"[HIAHTop] App became active");
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        NSLog(@"[HIAHTop] Starting HIAH Top Process Monitor");
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([HIAHTopAppDelegate class]));
    }
}

