/**
 * AppDelegate.m
 * HIAHDesktop - Example app using HIAHKernel library
 *
 * This file demonstrates the recommended way to integrate HIAHKernel
 * into your iOS application.
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import "AppDelegate.h"
#import "HIAHKernel.h"
#import "HIAHProcess.h"

@interface AppDelegate ()
@property (nonatomic, strong, readwrite) HIAHKernel *kernel;
@end

@implementation AppDelegate

#pragma mark - Application Lifecycle

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // =========================================================================
    // Step 1: Initialize HIAHKernel
    // =========================================================================
    
    self.kernel = [HIAHKernel sharedKernel];
    
    // =========================================================================
    // Step 2: Configure for your app
    // =========================================================================
    
    // Set your app's App Group identifier (must match entitlements)
    self.kernel.appGroupIdentifier = @"group.com.aspauldingcode.HIAHDesktop";
    
    // Set the ProcessRunner extension identifier (must match Info.plist)
    self.kernel.extensionIdentifier = @"com.aspauldingcode.HIAHDesktop.ProcessRunner";
    
    // =========================================================================
    // Step 3: Set up output handler
    // =========================================================================
    
    self.kernel.onOutput = ^(pid_t pid, NSString *output) {
        // Handle output from spawned processes
        // This is called on a background queue
        NSLog(@"[Process %d] %@", pid, output);
        
        // Post to main thread if you need to update UI
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"HIAHProcessOutput"
                              object:nil
                            userInfo:@{@"pid": @(pid), @"output": output}];
        });
    };
    
    // =========================================================================
    // Step 4: Register for kernel notifications
    // =========================================================================
    
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(processSpawned:)
               name:HIAHKernelProcessSpawnedNotification
             object:nil];
    
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(processExited:)
               name:HIAHKernelProcessExitedNotification
             object:nil];
    
    NSLog(@"[HIAHDesktop] Kernel initialized");
    NSLog(@"[HIAHDesktop] App Group: %@", self.kernel.appGroupIdentifier);
    NSLog(@"[HIAHDesktop] Extension: %@", self.kernel.extensionIdentifier);
    
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Clean up kernel resources
    [self.kernel shutdown];
}

#pragma mark - Process Notifications

- (void)processSpawned:(NSNotification *)notification {
    HIAHProcess *process = notification.userInfo[@"process"];
    NSLog(@"[HIAHDesktop] Process spawned: PID %d (%@)",
          process.pid, process.executablePath.lastPathComponent);
}

- (void)processExited:(NSNotification *)notification {
    HIAHProcess *process = notification.userInfo[@"process"];
    NSNumber *exitCode = notification.userInfo[@"exitCode"];
    NSLog(@"[HIAHDesktop] Process exited: PID %d (code: %@)",
          process.pid, exitCode);
}

#pragma mark - UISceneSession Lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                          sessionRole:connectingSceneSession.role];
}

@end
