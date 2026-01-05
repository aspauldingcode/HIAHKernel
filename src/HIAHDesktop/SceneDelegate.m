/**
 * SceneDelegate.m
 * HIAHDesktop
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import "SceneDelegate.h"
#import "MainViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
    
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = [[UINavigationController alloc]
        initWithRootViewController:[[MainViewController alloc] init]];
    [self.window makeKeyAndVisible];
}

@end
