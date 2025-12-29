/**
 * HIAHManagedProcess.h
 * HIAH Top - Full Process Object Model
 *
 * Implements Process Object from Section 1.2 of the Process Manager Specification.
 * This represents a virtual process managed by HIAHKernel.
 */

#import <Foundation/Foundation.h>
#import "HIAHProcessStats.h"

NS_ASSUME_NONNULL_BEGIN

@interface HIAHManagedProcess : NSObject <NSCopying>

#pragma mark - Identity (Section 2)

/// Virtual process ID assigned by HIAHKernel
@property (nonatomic, assign, readonly) pid_t pid;

/// Parent process ID
@property (nonatomic, assign) pid_t ppid;

/// Process group ID
@property (nonatomic, assign) pid_t pgid;

/// Session ID
@property (nonatomic, assign) pid_t sid;

/// User ID
@property (nonatomic, assign) uid_t uid;

/// Group ID
@property (nonatomic, assign) gid_t gid;

/// Process state
@property (nonatomic, assign) HIAHProcessState state;

#pragma mark - Executable Info

/// Full path to executable
@property (nonatomic, copy) NSString *executablePath;

/// Executable name (basename)
@property (nonatomic, readonly) NSString *name;

/// Command line arguments
@property (nonatomic, copy, nullable) NSArray<NSString *> *argv;

/// Environment variables (gated - may require privilege)
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *environment;

/// Working directory
@property (nonatomic, copy, nullable) NSString *workingDirectory;

/// Bundle identifier (for iOS app extensions)
@property (nonatomic, copy, nullable) NSString *bundleIdentifier;

#pragma mark - Timing (Section 4)

/// Process start timestamp
@property (nonatomic, strong, readonly) NSDate *startTime;

/// Process end timestamp (when process died/stopped, nil if still running)
@property (nonatomic, strong, nullable) NSDate *endTime;

/// Total cumulative active time (excluding stopped periods)
@property (nonatomic, assign) NSTimeInterval totalActiveTime;

/// Last resume timestamp (when process last started/resumed)
@property (nonatomic, strong, nullable) NSDate *resumeTime;

/// Current uptime (only counts active running time, excludes stopped periods)
@property (nonatomic, readonly) NSTimeInterval uptime;

/// Last sample timestamp
@property (nonatomic, strong, nullable) NSDate *lastSampleTime;

#pragma mark - Resource Statistics (Section 3)

/// CPU statistics
@property (nonatomic, strong) HIAHCPUStats *cpu;

/// Memory statistics
@property (nonatomic, strong) HIAHMemoryStats *memory;

/// I/O statistics
@property (nonatomic, strong) HIAHIOStats *io;

/// Energy statistics
@property (nonatomic, strong) HIAHEnergyStats *energy;

#pragma mark - Hierarchy

/// Thread list
@property (nonatomic, strong) NSMutableArray<HIAHThread *> *threads;

/// Child process PIDs
@property (nonatomic, strong) NSMutableArray<NSNumber *> *childPIDs;

#pragma mark - Diagnostics (Section 6)

/// Open file descriptors
@property (nonatomic, strong, nullable) NSArray<HIAHFileDescriptor *> *fileDescriptors;

/// Memory map regions
@property (nonatomic, strong, nullable) NSArray<NSDictionary *> *memoryMaps;

#pragma mark - Internal

/// Physical PID (if this is a virtual process)
@property (nonatomic, assign) pid_t physicalPid;

/// Stability identifier for UI (Section 10)
@property (nonatomic, readonly) NSString *stableIdentifier;

/// Privilege-limited field indicator
@property (nonatomic, assign) BOOL hasLimitedAccess;

#pragma mark - Lifecycle

/// Create a new managed process with the given PID
+ (instancetype)processWithPID:(pid_t)pid executable:(NSString *)path;

/// Initialize internal state
- (instancetype)initWithPID:(pid_t)pid executable:(NSString *)path;

#pragma mark - Sampling

/// Update statistics from underlying process
- (void)sample;

/// Calculate deltas from previous sample
- (void)calculateDeltasFrom:(HIAHManagedProcess *)previous;

#pragma mark - Serialization (Section 9)

/// Export as dictionary (for JSON)
- (NSDictionary *)toDictionary;

/// Export as text line (for text output)
- (NSString *)toTextLine;

/// Full detailed text representation
- (NSString *)toDetailedText;

#pragma mark - State Helpers

/// Human-readable state string
- (NSString *)stateString;

/// State color hint (for UI)
- (NSString *)stateColorHint;

/// Whether the process is alive
@property (nonatomic, readonly) BOOL isAlive;

/// Whether the process can be signaled
@property (nonatomic, readonly) BOOL canSignal;

@end

NS_ASSUME_NONNULL_END

