/**
 * AppDelegate.h
 * HIAHDesktop - Example app using HIAHKernel library
 *
 * Demonstrates how to integrate HIAHKernel into an iOS app.
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import <UIKit/UIKit.h>
#import "HIAHKernel.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>

/// The HIAHKernel instance for this app
@property (nonatomic, strong, readonly) HIAHKernel *kernel;

@end
