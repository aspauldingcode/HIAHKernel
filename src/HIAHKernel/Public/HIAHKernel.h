/**
 * HIAHKernel.h
 * Virtual Kernel for iOS Multi-Process Execution
 *
 * Provides POSIX-compliant virtual process management on jailed iOS.
 * Intercepts syscalls to enable fork, exec, and multi-process semantics.
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import <Foundation/Foundation.h>

// Forward declarations (headers are automatically exported by module system)
@class HIAHProcess;

NS_ASSUME_NONNULL_BEGIN

// MARK: - Notifications

extern NSNotificationName const HIAHKernelProcessSpawnedNotification;
extern NSNotificationName const HIAHKernelProcessExitedNotification;
extern NSNotificationName const HIAHKernelProcessOutputNotification;

// MARK: - Error Domain

extern NSErrorDomain const HIAHKernelErrorDomain;

typedef NS_ENUM(NSInteger, HIAHKernelError) {
    HIAHKernelErrorInvalidPath = 1,
    HIAHKernelErrorSpawnFailed,
    HIAHKernelErrorSocketFailed,
    HIAHKernelErrorProcessNotFound,
    HIAHKernelErrorBinaryPatchFailed,
};

// MARK: - HIAHKernel Interface

/**
 * Virtual kernel singleton managing processes on iOS.
 *
 * Example:
 * ```objc
 * HIAHKernel *kernel = [HIAHKernel sharedKernel];
 * kernel.appGroupIdentifier = @"group.com.yourapp";
 *
 * kernel.onOutput = ^(pid_t pid, NSString *output) {
 *     NSLog(@"[%d] %@", pid, output);
 * };
 *
 * [kernel spawnProcessWithPath:@"/path/to/binary"
 *                    arguments:@[@"--help"]
 *                   completion:^(pid_t pid, NSError *error) {
 *     if (!error) NSLog(@"Started PID %d", pid);
 * }];
 * ```
 */
@interface HIAHKernel : NSObject

// MARK: Singleton
+ (instancetype)sharedKernel;

// MARK: Configuration

/// App Group for IPC (required)
@property (nonatomic, copy) NSString *appGroupIdentifier;

/// Extension bundle ID (optional, for NSExtension mode)
@property (nonatomic, copy, nullable) NSString *extensionIdentifier;

/// Control socket path (read-only)
@property (nonatomic, copy, readonly, nullable) NSString *controlSocketPath;

// MARK: Process Table

/// Register a process
- (void)registerProcess:(HIAHProcess *)process;

/// Unregister by PID
- (void)unregisterProcessWithPID:(pid_t)pid;

/// Find process by virtual PID
- (nullable HIAHProcess *)processForPID:(pid_t)pid;

/// All active processes
- (NSArray<HIAHProcess *> *)allProcesses;

/// Get next available PID
- (pid_t)allocatePID;

// MARK: Process Lifecycle

/**
 * Spawn a virtual process.
 *
 * @param path        Executable path (binary or .app bundle)
 * @param arguments   Command-line arguments (optional)
 * @param environment Environment variables (optional)
 * @param completion  Called with PID on success or error
 */
- (void)spawnProcessWithPath:(NSString *)path
                   arguments:(nullable NSArray<NSString *> *)arguments
                 environment:(nullable NSDictionary<NSString *, NSString *> *)environment
                  completion:(void (^)(pid_t pid, NSError * _Nullable error))completion;

/**
 * Terminate a process.
 *
 * @param pid      Virtual PID
 * @param signal   Signal number (SIGTERM, SIGKILL, etc.)
 */
- (void)killProcess:(pid_t)pid signal:(int)signal;

/**
 * Wait for process exit.
 *
 * @param pid      Virtual PID (-1 for any)
 * @param options  WNOHANG, WUNTRACED, etc.
 * @return         PID that exited, 0 if WNOHANG and none ready, -1 on error
 */
- (pid_t)waitForProcess:(pid_t)pid status:(int *)status options:(int)options;

/**
 * Handle process exit notification.
 */
- (void)handleExitForPID:(pid_t)pid exitCode:(int)exitCode;

// MARK: Output

/// Callback for process output (background queue)
@property (nonatomic, copy, nullable) void (^onOutput)(pid_t pid, NSString *output);

// MARK: Lifecycle

/// Shutdown kernel, cleanup resources
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
