/**
 * HIAHKernel.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Main interface for the virtual kernel that enables multi-process
 * execution on jailed iOS systems.
 *
 * HIAHKernel provides:
 * - Virtual process table management
 * - NSExtension-based process spawning
 * - Inter-process communication via Unix sockets
 * - Integration with HIAHProcessRunner for guest app execution
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <Foundation/Foundation.h>
#import "HIAHProcess.h"

NS_ASSUME_NONNULL_BEGIN

/// Notification posted when a process is spawned
extern NSNotificationName const HIAHKernelProcessSpawnedNotification;

/// Notification posted when a process exits
extern NSNotificationName const HIAHKernelProcessExitedNotification;

/// Notification posted when process output is received
extern NSNotificationName const HIAHKernelProcessOutputNotification;

/// Error domain for HIAHKernel errors
extern NSErrorDomain const HIAHKernelErrorDomain;

/// Error codes
typedef NS_ENUM(NSInteger, HIAHKernelError) {
    HIAHKernelErrorExtensionNotFound = 1,
    HIAHKernelErrorExtensionLoadFailed = 2,
    HIAHKernelErrorSocketCreationFailed = 3,
    HIAHKernelErrorSpawnFailed = 4,
    HIAHKernelErrorInvalidPath = 5,
    HIAHKernelErrorProcessNotFound = 6,
};

/**
 * HIAHKernel provides a virtual kernel abstraction for iOS.
 *
 * It manages virtual processes, handles IPC via Unix sockets,
 * and spawns guest processes using NSExtension-based isolation.
 *
 * Usage:
 * ```objc
 * HIAHKernel *kernel = [HIAHKernel sharedKernel];
 * kernel.onOutput = ^(pid_t pid, NSString *output) {
 *     NSLog(@"[%d] %@", pid, output);
 * };
 *
 * [kernel spawnVirtualProcessWithPath:@"/path/to/binary"
 *                           arguments:@[@"arg1"]
 *                         environment:@{}
 *                          completion:^(pid_t pid, NSError *error) {
 *     // Handle result
 * }];
 * ```
 */
@interface HIAHKernel : NSObject

#pragma mark - Singleton

/// Returns the shared kernel instance
+ (instancetype)sharedKernel;

#pragma mark - Configuration

/// App group identifier for IPC (must match your app's entitlements)
/// Default: "group.com.aspauldingcode.HIAH"
@property (nonatomic, copy) NSString *appGroupIdentifier;

/// Extension bundle identifier to use for spawning
/// Default: "com.aspauldingcode.HIAH.ProcessRunner"
@property (nonatomic, copy) NSString *extensionIdentifier;

/// Path to the control socket (read-only, auto-generated)
@property (nonatomic, copy, readonly, nullable) NSString *controlSocketPath;

#pragma mark - Process Management

/**
 * Registers a process in the kernel's process table.
 */
- (void)registerProcess:(HIAHProcess *)process;

/**
 * Unregisters (removes) a process from the process table.
 */
- (void)unregisterProcessWithPID:(pid_t)pid;

/**
 * Looks up a process by its virtual PID.
 */
- (nullable HIAHProcess *)processForPID:(pid_t)pid;

/**
 * Looks up a process by its NSExtension request identifier.
 */
- (nullable HIAHProcess *)processForRequestIdentifier:(NSUUID *)uuid;

/**
 * Returns all currently registered processes.
 */
- (NSArray<HIAHProcess *> *)allProcesses;

/**
 * Handles process exit notification.
 */
- (void)handleExitForPID:(pid_t)pid exitCode:(int)exitCode;

#pragma mark - Process Spawning

/**
 * Spawns a virtual process.
 *
 * This is the primary API for running binaries on iOS. The kernel will:
 * 1. Set up output capture via Unix socket
 * 2. Load the HIAHProcessRunner extension
 * 3. Pass the spawn request to the extension
 * 4. Track the process in the process table
 *
 * @param path Path to the executable or .dylib to run
 * @param arguments Command-line arguments (argv[1:])
 * @param environment Environment variables
 * @param completion Called with the virtual PID on success, or error on failure
 */
- (void)spawnVirtualProcessWithPath:(NSString *)path
                          arguments:(nullable NSArray<NSString *> *)arguments
                        environment:(nullable NSDictionary<NSString *, NSString *> *)environment
                         completion:(void (^)(pid_t pid, NSError * _Nullable error))completion;

#pragma mark - Output Observation

/// Callback invoked when a guest process produces output.
/// Called on a background queue.
@property (nonatomic, copy, nullable) void (^onOutput)(pid_t pid, NSString *output);

#pragma mark - Lifecycle

/**
 * Shuts down the kernel, closing all sockets and cleaning up.
 */
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END

