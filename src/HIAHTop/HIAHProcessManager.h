/**
 * HIAHProcessManager.h
 * HIAH Top - Process Manager Controller
 *
 * Implements the full Process Manager Specification v1.0:
 * - Process enumeration and identity (Section 2)
 * - Resource accounting (Section 3)
 * - Temporal model (Section 4)
 * - Control plane (Section 5)
 * - Diagnostics (Section 6)
 * - Aggregation (Section 7)
 * - Query/interaction model (Section 8)
 * - Export/automation (Section 9)
 */

#import <Foundation/Foundation.h>
#import "HIAHProcessStats.h"
#import "HIAHManagedProcess.h"

@class HIAHKernel;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Delegate Protocol

@class HIAHProcessManager;

@protocol HIAHProcessManagerDelegate <NSObject>
@optional
/// Called when the process list has been updated
- (void)processManagerDidUpdateProcesses:(HIAHProcessManager *)manager;

/// Called when system stats have been updated
- (void)processManagerDidUpdateSystemStats:(HIAHProcessManager *)manager;

/// Called when a process spawns
- (void)processManager:(HIAHProcessManager *)manager didSpawnProcess:(HIAHManagedProcess *)process;

/// Called when a process terminates
- (void)processManager:(HIAHProcessManager *)manager didTerminateProcess:(HIAHManagedProcess *)process;

/// Called when an error occurs
- (void)processManager:(HIAHProcessManager *)manager didEncounterError:(NSError *)error;
@end

#pragma mark - Filter Predicate

@interface HIAHProcessFilter : NSObject
/// Filter by user ID (-1 = all)
@property (nonatomic, assign) uid_t userFilter;

/// Filter by name regex pattern
@property (nonatomic, copy, nullable) NSString *namePattern;

/// Filter by PID
@property (nonatomic, assign) pid_t pidFilter;

/// Filter by state
@property (nonatomic, assign) HIAHProcessState stateFilter;

/// Include kernel tasks
@property (nonatomic, assign) BOOL includeKernelTasks;

/// Show only alive processes
@property (nonatomic, assign) BOOL aliveOnly;

+ (instancetype)defaultFilter;
- (BOOL)matchesProcess:(HIAHManagedProcess *)process;
@end

#pragma mark - Process Manager

@interface HIAHProcessManager : NSObject

#pragma mark - Configuration

/// Delegate for callbacks
@property (nonatomic, weak, nullable) id<HIAHProcessManagerDelegate> delegate;

/// Current refresh interval (seconds)
@property (nonatomic, assign) NSTimeInterval refreshInterval;

/// Whether sampling is paused
@property (nonatomic, assign, getter=isPaused) BOOL paused;

/// Current sort field
@property (nonatomic, assign) HIAHSortField sortField;

/// Sort ascending
@property (nonatomic, assign) BOOL sortAscending;

/// Current grouping mode
@property (nonatomic, assign) HIAHGroupingMode groupingMode;

/// Current filter
@property (nonatomic, strong) HIAHProcessFilter *filter;

#pragma mark - State

/// System statistics
@property (nonatomic, strong, readonly) HIAHSystemStats *systemStats;

/// Current process list (filtered and sorted)
@property (nonatomic, strong, readonly) NSArray<HIAHManagedProcess *> *processes;

/// All processes (unfiltered)
@property (nonatomic, strong, readonly) NSArray<HIAHManagedProcess *> *allProcesses;

/// Process count
@property (nonatomic, readonly) NSUInteger processCount;

/// Total thread count
@property (nonatomic, readonly) NSUInteger threadCount;

/// Per-user aggregation
@property (nonatomic, strong, readonly) NSDictionary<NSNumber *, NSArray<HIAHManagedProcess *> *> *processesByUser;

/// Process tree
@property (nonatomic, strong, readonly) NSDictionary<NSNumber *, NSArray<HIAHManagedProcess *> *> *processTree;

#pragma mark - Singleton

+ (instancetype)sharedManager;

#pragma mark - Lifecycle

/// Initialize with HIAHKernel integration
- (instancetype)initWithKernel:(HIAHKernel *)kernel;

/// Start automatic sampling
- (void)startSampling;

/// Stop automatic sampling
- (void)stopSampling;

/// Perform a single sample
- (void)sample;

/// Synchronize process list with HIAHKernel (called automatically during sample)
- (void)syncWithKernel;

/// Pause/resume
- (void)pause;
- (void)resume;

#pragma mark - Process Enumeration (Section 2)

/// List all visible processes
- (NSArray<HIAHManagedProcess *> *)listAllProcesses;

/// Get process by PID
- (nullable HIAHManagedProcess *)processForPID:(pid_t)pid;

/// Find processes by name
- (NSArray<HIAHManagedProcess *> *)findProcessesWithName:(NSString *)name;

/// Find processes matching regex
- (NSArray<HIAHManagedProcess *> *)findProcessesMatchingPattern:(NSString *)pattern;

/// Build process tree starting from PID
- (NSArray<HIAHManagedProcess *> *)processTreeForPID:(pid_t)rootPID;

/// Get children of a process
- (NSArray<HIAHManagedProcess *> *)childrenOfProcess:(pid_t)pid;

#pragma mark - Process Spawning

/// Spawn a new virtual process
- (nullable HIAHManagedProcess *)spawnProcessWithExecutable:(NSString *)path
                                                  arguments:(nullable NSArray<NSString *> *)args
                                                environment:(nullable NSDictionary<NSString *, NSString *> *)env
                                                      error:(NSError **)error;

#pragma mark - Control Plane (Section 5)

/// Send signal to process
- (BOOL)sendSignal:(int)signal toProcess:(pid_t)pid error:(NSError **)error;

/// Send SIGTERM
- (BOOL)terminateProcess:(pid_t)pid error:(NSError **)error;

/// Send SIGKILL
- (BOOL)killProcess:(pid_t)pid error:(NSError **)error;

/// Send SIGSTOP
- (BOOL)stopProcess:(pid_t)pid error:(NSError **)error;

/// Send SIGCONT
- (BOOL)continueProcess:(pid_t)pid error:(NSError **)error;

/// Kill process and all its descendants
- (BOOL)killProcessTree:(pid_t)pid error:(NSError **)error;

/// Adjust priority (nice value)
- (BOOL)setNiceValue:(int)nice forProcess:(pid_t)pid error:(NSError **)error;

/// Set CPU affinity (uses thread_policy_set with THREAD_AFFINITY_POLICY)
- (BOOL)setCPUAffinity:(NSInteger)core forProcess:(pid_t)pid error:(NSError **)error;

/// Set thread priority (uses thread_policy_set with THREAD_PRECEDENCE_POLICY)
- (BOOL)setThreadPriority:(int)priority forThread:(uint64_t)tid inProcess:(pid_t)pid error:(NSError **)error;

#pragma mark - Sorting (Section 8)

/// Sort processes by field
- (void)sortByField:(HIAHSortField)field ascending:(BOOL)ascending;

/// Apply current sort
- (NSArray<HIAHManagedProcess *> *)sortedProcesses:(NSArray<HIAHManagedProcess *> *)processes;

#pragma mark - Filtering (Section 8)

/// Apply filter predicate
- (NSArray<HIAHManagedProcess *> *)filteredProcesses:(NSArray<HIAHManagedProcess *> *)processes
                                          withFilter:(HIAHProcessFilter *)filter;

/// Filter by user
- (NSArray<HIAHManagedProcess *> *)processesForUser:(uid_t)uid;

#pragma mark - Aggregation (Section 7)

/// Get system totals
- (HIAHSystemStats *)systemTotals;

/// Get per-user aggregated stats
- (NSDictionary<NSNumber *, NSDictionary *> *)userAggregatedStats;

/// Get per-group aggregated stats (Section 7)
- (NSDictionary<NSNumber *, NSDictionary *> *)groupAggregatedStats;

/// Detect orphaned children (Section 5.3)
- (NSArray<HIAHManagedProcess *> *)detectOrphanedChildren;

/// Get total CPU usage across all processes
- (double)totalCPUUsage;

/// Get total memory usage across all processes
- (uint64_t)totalMemoryUsage;

#pragma mark - Export (Section 9)

/// Export all processes as JSON
- (NSData *)exportAsJSON;

/// Export all processes as text
- (NSString *)exportAsText;

/// Export current snapshot
- (NSDictionary *)exportSnapshot;

/// Export to file
- (BOOL)exportToFile:(NSString *)path format:(HIAHExportFormat)format error:(NSError **)error;

#pragma mark - CLI/Non-Interactive Mode (Section 9)

/// Generate CLI-style output (like top/htop)
- (NSString *)cliOutput;

/// Generate CLI output with options
- (NSString *)cliOutputWithOptions:(NSDictionary *)options;

/// Run a single non-interactive sample and return formatted output
- (NSString *)nonInteractiveSample;

/// Print processes to stdout (CLI mode)
- (void)printToStdout;

#pragma mark - Diagnostics (Section 6)

/// Get detailed diagnostics for process
- (nullable NSDictionary *)diagnosticsForProcess:(pid_t)pid;

/// Get open file descriptors
- (nullable NSArray<HIAHFileDescriptor *> *)fileDescriptorsForProcess:(pid_t)pid;

/// Get memory map
- (nullable NSArray<NSDictionary *> *)memoryMapForProcess:(pid_t)pid;

/// Sample stack for process (best-effort)
- (nullable NSArray<NSString *> *)sampleStackForProcess:(pid_t)pid;

@end

NS_ASSUME_NONNULL_END

