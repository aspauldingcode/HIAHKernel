/**
 * HIAHProcessStats.h
 * HIAH Top - Process Statistics Data Model
 *
 * Implements the Process Manager Specification v1.0 data model
 * for resource accounting and process introspection.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Enumerations

/// Process state enumeration (Section 1.2)
typedef NS_ENUM(NSInteger, HIAHProcessState) {
    HIAHProcessStateRunning,
    HIAHProcessStateSleeping,
    HIAHProcessStateStopped,
    HIAHProcessStateZombie,
    HIAHProcessStateDead,
    HIAHProcessStateUnknown
};

/// Sort field enumeration (Section 8)
typedef NS_ENUM(NSInteger, HIAHSortField) {
    HIAHSortFieldPID,
    HIAHSortFieldPPID,
    HIAHSortFieldName,
    HIAHSortFieldState,
    HIAHSortFieldCPU,
    HIAHSortFieldMemory,
    HIAHSortFieldIORead,
    HIAHSortFieldIOWrite,
    HIAHSortFieldStartTime,
    HIAHSortFieldUptime,
    HIAHSortFieldThreads,
    HIAHSortFieldUser
};

/// Grouping mode enumeration (Section 8)
typedef NS_ENUM(NSInteger, HIAHGroupingMode) {
    HIAHGroupingModeFlat,
    HIAHGroupingModeTree,
    HIAHGroupingModeUser,
    HIAHGroupingModeApplication
};

/// Export format enumeration (Section 9)
typedef NS_ENUM(NSInteger, HIAHExportFormat) {
    HIAHExportFormatText,
    HIAHExportFormatJSON,
    HIAHExportFormatSnapshot
};

#pragma mark - CPU Statistics (Section 3.1)

@interface HIAHCPUStats : NSObject <NSCopying>
@property (nonatomic, assign) double totalUsagePercent;      // Total CPU usage (%)
@property (nonatomic, assign) double userTimePercent;        // User mode time (%)
@property (nonatomic, assign) double systemTimePercent;      // System/kernel time (%)
@property (nonatomic, assign) uint64_t userTime;             // User time in ticks
@property (nonatomic, assign) uint64_t systemTime;           // System time in ticks
@property (nonatomic, assign) int priority;                  // Scheduler priority
@property (nonatomic, assign) int niceValue;                 // Nice value (-20 to 19)
@property (nonatomic, assign) NSInteger cpuAffinity;         // CPU core affinity (-1 = any)

/// Delta since last sample
@property (nonatomic, assign) double deltaPercent;

/// Per-core usage breakdown (Section 3.1)
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *perCoreUsage;

+ (instancetype)stats;
- (NSDictionary *)toDictionary;
@end

#pragma mark - Memory Statistics (Section 3.2)

@interface HIAHMemoryStats : NSObject <NSCopying>
@property (nonatomic, assign) uint64_t residentSize;         // RSS in bytes
@property (nonatomic, assign) uint64_t virtualSize;          // Virtual size in bytes
@property (nonatomic, assign) uint64_t sharedSize;           // Shared memory
@property (nonatomic, assign) uint64_t privateSize;          // Private memory
@property (nonatomic, assign) uint64_t minorFaults;          // Minor page faults
@property (nonatomic, assign) uint64_t majorFaults;          // Major page faults
@property (nonatomic, assign) double memoryPressure;         // Memory pressure (0.0-1.0)
@property (nonatomic, assign) uint64_t peakResidentSize;     // Peak RSS

/// Delta since last sample
@property (nonatomic, assign) int64_t deltaResident;

+ (instancetype)stats;
- (NSDictionary *)toDictionary;
- (NSString *)formattedResidentSize;
- (NSString *)formattedVirtualSize;
@end

#pragma mark - I/O Statistics (Section 3.3)

@interface HIAHIOStats : NSObject <NSCopying>
@property (nonatomic, assign) uint64_t bytesRead;            // Disk bytes read
@property (nonatomic, assign) uint64_t bytesWritten;         // Disk bytes written
@property (nonatomic, assign) uint64_t readOps;              // Read operations
@property (nonatomic, assign) uint64_t writeOps;             // Write operations
@property (nonatomic, assign) double readBytesPerSec;        // Read rate
@property (nonatomic, assign) double writeBytesPerSec;       // Write rate
@property (nonatomic, assign) uint64_t networkRx;            // Network received
@property (nonatomic, assign) uint64_t networkTx;            // Network transmitted
@property (nonatomic, assign) BOOL isBlocked;                // In I/O wait state

/// Delta since last sample
@property (nonatomic, assign) uint64_t deltaBytesRead;
@property (nonatomic, assign) uint64_t deltaBytesWritten;

+ (instancetype)stats;
- (NSDictionary *)toDictionary;
@end

#pragma mark - Energy Statistics (Section 3.4)

@interface HIAHEnergyStats : NSObject <NSCopying>
@property (nonatomic, assign) uint64_t wakeups;              // CPU wakeups
@property (nonatomic, assign) double timerFrequency;         // Timer frequency (Hz)
@property (nonatomic, assign) double powerScore;             // OS power impact (0-100)
@property (nonatomic, assign) double energyImpact;           // Energy impact rating
@property (nonatomic, assign) BOOL isBackgroundTask;         // Background activity

+ (instancetype)stats;
- (NSDictionary *)toDictionary;
@end

#pragma mark - Thread Object (Section 1.2)

@interface HIAHThread : NSObject <NSCopying>
@property (nonatomic, assign) uint64_t tid;                  // Thread ID
@property (nonatomic, assign) HIAHProcessState state;        // Thread state
@property (nonatomic, strong) HIAHCPUStats *cpu;             // Thread CPU stats
@property (nonatomic, assign) int priority;                  // Thread priority
@property (nonatomic, copy, nullable) NSString *name;        // Thread name

+ (instancetype)threadWithTID:(uint64_t)tid;
- (NSDictionary *)toDictionary;
@end

#pragma mark - File Descriptor (Section 6)

@interface HIAHFileDescriptor : NSObject
@property (nonatomic, assign) int fd;                        // FD number
@property (nonatomic, copy) NSString *type;                  // file/socket/pipe/etc
@property (nonatomic, copy, nullable) NSString *path;        // Path if applicable
@property (nonatomic, copy, nullable) NSString *details;     // Additional info

+ (instancetype)fdWithNumber:(int)fd type:(NSString *)type;
- (NSDictionary *)toDictionary;
@end

#pragma mark - System Totals (Section 7)

@interface HIAHSystemStats : NSObject
@property (nonatomic, assign) double cpuUsagePercent;        // Total CPU
@property (nonatomic, assign) uint64_t totalMemory;          // Total RAM
@property (nonatomic, assign) uint64_t usedMemory;           // Used RAM
@property (nonatomic, assign) uint64_t freeMemory;           // Free RAM
@property (nonatomic, assign) uint64_t swapUsed;             // Swap used
@property (nonatomic, assign) uint64_t swapTotal;            // Swap total
@property (nonatomic, assign) double loadAverage1;           // 1-min load
@property (nonatomic, assign) double loadAverage5;           // 5-min load
@property (nonatomic, assign) double loadAverage15;          // 15-min load
@property (nonatomic, assign) NSUInteger processCount;       // Process count
@property (nonatomic, assign) NSUInteger threadCount;        // Thread count
@property (nonatomic, strong) NSDate *bootTime;              // System boot time

/// Per-core CPU usage breakdown (Section 3.1)
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *perCoreUsage;

/// Number of CPU cores
@property (nonatomic, assign) NSUInteger coreCount;

+ (instancetype)currentStats;
- (void)refresh;
- (NSDictionary *)toDictionary;
@end

NS_ASSUME_NONNULL_END

