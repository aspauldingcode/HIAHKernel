/**
 * HIAHProcess.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Virtual process representation for iOS multi-process emulation.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents a virtual process managed by HIAHKernel.
 *
 * Each HIAHProcess tracks both the virtual PID (used by the kernel)
 * and the physical PID (actual iOS process, typically an NSExtension).
 */
@interface HIAHProcess : NSObject

/// Virtual PID assigned by HIAHKernel (or physical PID if mapped 1:1)
@property (nonatomic, assign) pid_t pid;

/// The actual PID of the extension process running the guest
@property (nonatomic, assign) pid_t physicalPid;

/// Parent PID (for process hierarchy tracking)
@property (nonatomic, assign) pid_t ppid;

/// Path to the executable being run
@property (nonatomic, copy) NSString *executablePath;

/// Command-line arguments passed to the process
@property (nonatomic, copy, nullable) NSArray<NSString *> *arguments;

/// Environment variables for the process
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *environment;

/// Exit code (valid only if isExited is YES)
@property (nonatomic, assign) int exitCode;

/// Whether the process has exited
@property (nonatomic, assign) BOOL isExited;

/// NSExtension request identifier (used to track extension lifecycle)
@property (nonatomic, strong, nullable) NSUUID *requestIdentifier;

/// Timestamp when process was spawned
@property (nonatomic, strong, readonly) NSDate *startTime;

/// Working directory for the process
@property (nonatomic, copy, nullable) NSString *workingDirectory;

/**
 * Creates a new virtual process with the specified executable.
 */
+ (instancetype)processWithPath:(NSString *)path
                      arguments:(nullable NSArray<NSString *> *)arguments
                    environment:(nullable NSDictionary<NSString *, NSString *> *)environment;

@end

NS_ASSUME_NONNULL_END

