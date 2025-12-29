/**
 * HIAHResourceCollector.h
 * HIAH Top - Real Resource Collection via iOS/macOS APIs
 *
 * Implements Section 3 (Resource Accounting) and Section 11 (Platform Mapping)
 * using proc_pidinfo, task_info, thread_info, and sysctl.
 */

#import <Foundation/Foundation.h>
#import "HIAHProcessStats.h"
#import "HIAHManagedProcess.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Collects real resource statistics from iOS/macOS kernel APIs.
 *
 * Uses:
 * - proc_pidinfo() for process info
 * - task_info() for memory stats
 * - thread_info() for thread CPU stats
 * - sysctl() for system-wide stats
 */
@interface HIAHResourceCollector : NSObject

#pragma mark - Singleton

+ (instancetype)sharedCollector;

#pragma mark - Process Statistics

/**
 * Collect CPU statistics for a process using proc_pidinfo.
 * Implements Section 3.1: CPU accounting.
 */
- (BOOL)collectCPUStats:(HIAHCPUStats *)stats forPID:(pid_t)pid error:(NSError **)error;

/**
 * Collect memory statistics for a process using task_info.
 * Implements Section 3.2: Memory accounting.
 */
- (BOOL)collectMemoryStats:(HIAHMemoryStats *)stats forPID:(pid_t)pid error:(NSError **)error;

/**
 * Collect I/O statistics for a process using proc_pidinfo.
 * Implements Section 3.3: I/O accounting.
 */
- (BOOL)collectIOStats:(HIAHIOStats *)stats forPID:(pid_t)pid error:(NSError **)error;

/**
 * Collect energy statistics for a process.
 * Implements Section 3.4: Energy/Power accounting.
 */
- (BOOL)collectEnergyStats:(HIAHEnergyStats *)stats forPID:(pid_t)pid error:(NSError **)error;

/**
 * Collect all statistics for a process.
 */
- (BOOL)collectAllStatsForProcess:(HIAHManagedProcess *)process error:(NSError **)error;

#pragma mark - Thread Statistics

/**
 * Enumerate threads and collect per-thread CPU stats.
 * Implements Section 3.1: Per-thread CPU usage.
 */
- (NSArray<HIAHThread *> *)collectThreadStatsForPID:(pid_t)pid error:(NSError **)error;

#pragma mark - Process Info

/**
 * Get process identity info (PID, PPID, UID, GID, etc.)
 * Implements Section 2: Process Enumeration & Identity.
 */
- (BOOL)collectProcessInfo:(HIAHManagedProcess *)process error:(NSError **)error;

/**
 * Get process state (running, sleeping, stopped, zombie).
 */
- (HIAHProcessState)processStateForPID:(pid_t)pid;

#pragma mark - Diagnostics (Section 6)

/**
 * Get open file descriptors for a process.
 */
- (NSArray<HIAHFileDescriptor *> *)fileDescriptorsForPID:(pid_t)pid error:(NSError **)error;

/**
 * Get memory map regions for a process.
 */
- (NSArray<NSDictionary *> *)memoryMapForPID:(pid_t)pid error:(NSError **)error;

/**
 * Sample stack trace for a process (best-effort).
 */
- (NSArray<NSString *> *)sampleStackForPID:(pid_t)pid error:(NSError **)error;

#pragma mark - Privilege Checking (Section 12)

/**
 * Check if we have permission to access process info.
 */
- (BOOL)canAccessProcess:(pid_t)pid;

/**
 * Check if we have permission to signal a process.
 */
- (BOOL)canSignalProcess:(pid_t)pid;

/**
 * Check if we can get task port for a process (required for detailed stats).
 */
- (BOOL)canGetTaskPortForProcess:(pid_t)pid;

/**
 * Check available privilege level for a process.
 * Returns a dictionary with capability flags.
 */
- (NSDictionary *)privilegeLevelForProcess:(pid_t)pid;

/**
 * Get a human-readable description of access limitations.
 */
- (NSString *)accessLimitationsForProcess:(pid_t)pid;

@end

NS_ASSUME_NONNULL_END

