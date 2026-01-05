/**
 * HIAHProcess.h
 * Virtual Process Representation
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Process state
typedef NS_ENUM(NSInteger, HIAHProcessState) {
    HIAHProcessStateCreated,    ///< Created but not started
    HIAHProcessStateRunning,    ///< Currently executing
    HIAHProcessStateStopped,    ///< Stopped (SIGSTOP)
    HIAHProcessStateZombie,     ///< Exited, waiting for wait()
    HIAHProcessStateTerminated, ///< Fully terminated
};

/**
 * Represents a virtual process in HIAHKernel.
 */
@interface HIAHProcess : NSObject

// MARK: Identification

/// Virtual PID (assigned by kernel)
@property (nonatomic, assign) pid_t pid;

/// Physical PID (actual iOS process/thread)
@property (nonatomic, assign) pid_t physicalPid;

/// Parent PID
@property (nonatomic, assign) pid_t ppid;

/// Process group ID
@property (nonatomic, assign) pid_t pgid;

/// Session ID
@property (nonatomic, assign) pid_t sid;

// MARK: Execution

/// Executable path
@property (nonatomic, copy) NSString *executablePath;

/// Arguments (argv)
@property (nonatomic, copy, nullable) NSArray<NSString *> *arguments;

/// Environment variables
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *environment;

/// Working directory
@property (nonatomic, copy, nullable) NSString *workingDirectory;

// MARK: State

/// Current state
@property (nonatomic, assign) HIAHProcessState state;

/// Exit code (valid when state >= Zombie)
@property (nonatomic, assign) int exitCode;

/// Exit signal (if killed by signal)
@property (nonatomic, assign) int exitSignal;

/// Start time
@property (nonatomic, strong, readonly) NSDate *startTime;

// MARK: Handle

/// dlopen handle (for dlopen-based execution)
@property (nonatomic, assign, nullable) void *handle;

/// Thread (for thread-based execution)
@property (nonatomic, assign) pthread_t thread;  // pthread_t is not a pointer type

// MARK: Legacy Compatibility

/// Whether process has exited (legacy)
@property (nonatomic, readonly) BOOL isExited;

// MARK: Factory

+ (instancetype)processWithPath:(NSString *)path
                      arguments:(nullable NSArray<NSString *> *)arguments
                    environment:(nullable NSDictionary<NSString *, NSString *> *)environment;

@end

NS_ASSUME_NONNULL_END
