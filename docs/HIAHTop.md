# HIAH Top – Process Manager Documentation

**HIAH Top** is a full-featured process manager for iOS, similar to macOS Activity Monitor, Windows Task Manager, or Unix `top`/`htop`. It provides a graphical interface for monitoring and controlling processes managed by HIAH Kernel.

## Overview

HIAH Top implements the **Process Manager Specification v1.0**, providing:

- **Process Enumeration** – View all virtual processes with identity information
- **Resource Monitoring** – CPU, memory, threads, and I/O statistics
- **Temporal Tracking** – Start time, run duration, CPU time accounting
- **Control Plane** – Send signals, adjust priority, terminate processes
- **Diagnostics** – File descriptors, memory maps, stack sampling
- **Aggregation** – Per-user and per-group statistics
- **Export/Automation** – JSON, text export, and CLI mode

## Running HIAH Top

### Standalone App (via Nix)

```bash
# Run HIAH Top on iOS Simulator
nix run .#hiah-top

# Or build the app
nix build .#hiah-top
```

### Embedded in Your Application

```objc
#import "HIAHProcessManager.h"
#import "HIAHTopViewController.h"

// Present process manager UI
HIAHTopViewController *topVC = [[HIAHTopViewController alloc] init];
[self presentViewController:topVC animated:YES completion:nil];
```

### Inside HIAH Desktop

HIAH Top is included as a built-in app in HIAH Desktop. Launch it from the app dock to monitor all running processes in the desktop environment.

## Features

### Process List View

The main view displays all processes with:

| Column | Description |
|--------|-------------|
| **PID** | Virtual process ID |
| **Name** | Executable name |
| **CPU%** | Current CPU usage percentage |
| **Memory** | Resident memory (RSS) |
| **Threads** | Thread count |
| **State** | Running, Sleeping, Stopped, Zombie |
| **User** | User ID running the process |
| **Time** | Total CPU time consumed |

### Process Actions

Tap on any process to access controls:

- **Terminate (SIGTERM)** – Gracefully request termination
- **Kill (SIGKILL)** – Force immediate termination
- **Stop (SIGSTOP)** – Pause process execution
- **Continue (SIGCONT)** – Resume paused process
- **Adjust Priority** – Change nice value (-20 to +19)

### System Overview

Header bar shows system-wide statistics:

- Total CPU usage across all cores
- Memory usage (used/total)
- Active process count
- Total thread count

## API Reference

### HIAHProcessManager

The core class for process monitoring and control.

#### Initialization

```objc
// Shared instance (standalone mode)
HIAHProcessManager *manager = [HIAHProcessManager sharedManager];

// With kernel integration
HIAHProcessManager *manager = [[HIAHProcessManager alloc] initWithKernel:kernel];
```

#### Configuration Properties

```objc
// Delegate for callbacks
@property (nonatomic, weak) id<HIAHProcessManagerDelegate> delegate;

// Refresh interval in seconds (default: 2.0)
@property (nonatomic, assign) NSTimeInterval refreshInterval;

// Pause/resume sampling
@property (nonatomic, assign, getter=isPaused) BOOL paused;

// Sort configuration
@property (nonatomic, assign) HIAHSortField sortField;
@property (nonatomic, assign) BOOL sortAscending;

// Grouping mode
@property (nonatomic, assign) HIAHGroupingMode groupingMode;

// Filter predicate
@property (nonatomic, strong) HIAHProcessFilter *filter;
```

#### Process Enumeration (Section 2 of Spec)

```objc
// Get filtered and sorted process list
@property (nonatomic, strong, readonly) NSArray<HIAHManagedProcess *> *processes;

// Get all processes (unfiltered)
@property (nonatomic, strong, readonly) NSArray<HIAHManagedProcess *> *allProcesses;

// Find specific process
- (nullable HIAHManagedProcess *)processForPID:(pid_t)pid;

// Find by name
- (NSArray<HIAHManagedProcess *> *)findProcessesWithName:(NSString *)name;

// Find by regex pattern
- (NSArray<HIAHManagedProcess *> *)findProcessesMatchingPattern:(NSString *)pattern;

// Get process tree from a root PID
- (NSArray<HIAHManagedProcess *> *)processTreeForPID:(pid_t)rootPID;

// Get children of a process
- (NSArray<HIAHManagedProcess *> *)childrenOfProcess:(pid_t)pid;
```

#### Lifecycle Control

```objc
// Start automatic sampling at refreshInterval
- (void)startSampling;

// Stop automatic sampling
- (void)stopSampling;

// Perform single sample
- (void)sample;

// Sync with HIAH Kernel process table
- (void)syncWithKernel;

// Pause/resume
- (void)pause;
- (void)resume;
```

#### Control Plane (Section 5 of Spec)

```objc
// Send any signal
- (BOOL)sendSignal:(int)signal toProcess:(pid_t)pid error:(NSError **)error;

// Convenience methods
- (BOOL)terminateProcess:(pid_t)pid error:(NSError **)error;  // SIGTERM
- (BOOL)killProcess:(pid_t)pid error:(NSError **)error;       // SIGKILL
- (BOOL)stopProcess:(pid_t)pid error:(NSError **)error;       // SIGSTOP
- (BOOL)continueProcess:(pid_t)pid error:(NSError **)error;   // SIGCONT

// Kill entire process tree
- (BOOL)killProcessTree:(pid_t)pid error:(NSError **)error;

// Priority adjustment
- (BOOL)setNiceValue:(int)nice forProcess:(pid_t)pid error:(NSError **)error;

// CPU affinity (thread_policy_set with THREAD_AFFINITY_POLICY)
- (BOOL)setCPUAffinity:(NSInteger)core forProcess:(pid_t)pid error:(NSError **)error;

// Thread priority
- (BOOL)setThreadPriority:(int)priority 
                forThread:(uint64_t)tid 
                inProcess:(pid_t)pid 
                    error:(NSError **)error;
```

#### Sorting & Filtering (Section 8 of Spec)

```objc
// Sort fields
typedef NS_ENUM(NSInteger, HIAHSortField) {
    HIAHSortFieldPID,
    HIAHSortFieldName,
    HIAHSortFieldCPU,
    HIAHSortFieldMemory,
    HIAHSortFieldThreads,
    HIAHSortFieldState,
    HIAHSortFieldUser,
    HIAHSortFieldTime,
    HIAHSortFieldStartTime
};

// Apply sort
- (void)sortByField:(HIAHSortField)field ascending:(BOOL)ascending;

// Filter by user
- (NSArray<HIAHManagedProcess *> *)processesForUser:(uid_t)uid;
```

#### Aggregation (Section 7 of Spec)

```objc
// System-wide totals
- (HIAHSystemStats *)systemTotals;

// Per-user aggregation
- (NSDictionary<NSNumber *, NSDictionary *> *)userAggregatedStats;

// Per-group aggregation  
- (NSDictionary<NSNumber *, NSDictionary *> *)groupAggregatedStats;

// Detect orphaned children (PPID = 1)
- (NSArray<HIAHManagedProcess *> *)detectOrphanedChildren;

// Totals
- (double)totalCPUUsage;
- (uint64_t)totalMemoryUsage;
```

#### Diagnostics (Section 6 of Spec)

```objc
// Detailed process diagnostics
- (nullable NSDictionary *)diagnosticsForProcess:(pid_t)pid;

// Open file descriptors
- (nullable NSArray<HIAHFileDescriptor *> *)fileDescriptorsForProcess:(pid_t)pid;

// Memory map regions
- (nullable NSArray<NSDictionary *> *)memoryMapForProcess:(pid_t)pid;

// Stack sampling (best-effort)
- (nullable NSArray<NSString *> *)sampleStackForProcess:(pid_t)pid;
```

#### Export (Section 9 of Spec)

```objc
// Export formats
typedef NS_ENUM(NSInteger, HIAHExportFormat) {
    HIAHExportFormatJSON,
    HIAHExportFormatText,
    HIAHExportFormatCSV
};

// Export current state
- (NSData *)exportAsJSON;
- (NSString *)exportAsText;
- (NSDictionary *)exportSnapshot;

// Export to file
- (BOOL)exportToFile:(NSString *)path 
              format:(HIAHExportFormat)format 
               error:(NSError **)error;

// CLI-style output (like top/htop)
- (NSString *)cliOutput;
- (NSString *)cliOutputWithOptions:(NSDictionary *)options;

// Non-interactive single sample
- (NSString *)nonInteractiveSample;

// Print to stdout (for CLI mode)
- (void)printToStdout;
```

### HIAHManagedProcess

Represents a process with full statistics.

```objc
@interface HIAHManagedProcess : NSObject

// Identity (Section 2)
@property (readonly) pid_t pid;
@property (readonly) pid_t ppid;
@property (readonly) uid_t uid;
@property (readonly) gid_t gid;
@property (readonly) NSString *name;
@property (readonly) NSString *executablePath;
@property (readonly) NSArray<NSString *> *arguments;
@property (readonly) NSDictionary<NSString *, NSString *> *environment;

// State
@property (readonly) HIAHProcessState state;
@property (readonly) BOOL isZombie;
@property (readonly) BOOL isStopped;

// Resource Usage (Section 3)
@property (readonly) double cpuPercent;
@property (readonly) uint64_t residentMemory;      // RSS
@property (readonly) uint64_t virtualMemory;       // VSZ
@property (readonly) uint64_t sharedMemory;
@property (readonly) NSUInteger threadCount;
@property (readonly) uint64_t ioReadBytes;
@property (readonly) uint64_t ioWriteBytes;
@property (readonly) NSUInteger openFileCount;

// Temporal (Section 4)
@property (readonly) NSDate *startTime;
@property (readonly) NSTimeInterval userTime;      // User CPU time
@property (readonly) NSTimeInterval systemTime;    // System CPU time
@property (readonly) NSTimeInterval totalCPUTime;  // Combined
@property (readonly) NSTimeInterval runDuration;   // Wall clock since start

// Nice value
@property (readonly) int niceValue;

@end
```

### HIAHProcessFilter

Filter predicate for process queries.

```objc
@interface HIAHProcessFilter : NSObject

// Filter by user ID (-1 = all)
@property (nonatomic, assign) uid_t userFilter;

// Filter by name regex
@property (nonatomic, copy, nullable) NSString *namePattern;

// Filter by specific PID
@property (nonatomic, assign) pid_t pidFilter;

// Filter by state
@property (nonatomic, assign) HIAHProcessState stateFilter;

// Include kernel tasks
@property (nonatomic, assign) BOOL includeKernelTasks;

// Show only alive processes
@property (nonatomic, assign) BOOL aliveOnly;

// Factory for default filter
+ (instancetype)defaultFilter;

// Check if process matches
- (BOOL)matchesProcess:(HIAHManagedProcess *)process;

@end
```

### HIAHProcessManagerDelegate

```objc
@protocol HIAHProcessManagerDelegate <NSObject>
@optional

// Process list updated
- (void)processManagerDidUpdateProcesses:(HIAHProcessManager *)manager;

// System stats updated
- (void)processManagerDidUpdateSystemStats:(HIAHProcessManager *)manager;

// New process spawned
- (void)processManager:(HIAHProcessManager *)manager 
       didSpawnProcess:(HIAHManagedProcess *)process;

// Process terminated
- (void)processManager:(HIAHProcessManager *)manager 
   didTerminateProcess:(HIAHManagedProcess *)process;

// Error occurred
- (void)processManager:(HIAHProcessManager *)manager 
      didEncounterError:(NSError *)error;

@end
```

## HIAHTopViewController

The pre-built UI component for process monitoring.

### Basic Usage

```objc
HIAHTopViewController *topVC = [[HIAHTopViewController alloc] init];

// Optional: customize appearance
topVC.showSystemProcesses = NO;  // Hide system processes
topVC.autoRefresh = YES;         // Auto-refresh enabled
topVC.refreshInterval = 2.0;     // 2 second refresh

[self presentViewController:topVC animated:YES completion:nil];
```

### Customization

```objc
// Change visible columns
topVC.visibleColumns = @[
    @(HIAHColumnPID),
    @(HIAHColumnName),
    @(HIAHColumnCPU),
    @(HIAHColumnMemory)
];

// Set default sort
topVC.defaultSortField = HIAHSortFieldCPU;
topVC.defaultSortAscending = NO;  // Highest CPU first

// Custom actions for process selection
topVC.onProcessSelected = ^(HIAHManagedProcess *process) {
    NSLog(@"Selected: %@ (PID %d)", process.name, process.pid);
};
```

## CLI Mode

HIAH Top can run in non-interactive CLI mode for scripting:

```objc
// Single snapshot
NSString *output = [[HIAHProcessManager sharedManager] nonInteractiveSample];
NSLog(@"%@", output);

// Options for CLI output
NSDictionary *options = @{
    @"format": @"text",        // or "json"
    @"sortBy": @"cpu",
    @"limit": @20,
    @"showHeaders": @YES
};
NSString *customOutput = [[HIAHProcessManager sharedManager] cliOutputWithOptions:options];
```

## Integration with HIAH Kernel

When initialized with a kernel reference, HIAH Top automatically:

1. **Syncs process table** – Matches virtual PIDs with kernel's process table
2. **Tracks spawns** – Receives notifications when kernel spawns processes
3. **Handles exits** – Updates when processes terminate
4. **Provides control** – Signals are sent through kernel for virtual processes

```objc
HIAHKernel *kernel = [HIAHKernel sharedKernel];
HIAHProcessManager *manager = [[HIAHProcessManager alloc] initWithKernel:kernel];

// Now process list includes both:
// - Real processes (from system)
// - Virtual processes (from HIAH Kernel)
```

## Example: Complete Integration

```objc
@interface ProcessMonitorController () <HIAHProcessManagerDelegate>
@property (nonatomic, strong) HIAHProcessManager *processManager;
@property (nonatomic, weak) IBOutlet UITableView *tableView;
@end

@implementation ProcessMonitorController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Initialize with kernel
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    self.processManager = [[HIAHProcessManager alloc] initWithKernel:kernel];
    self.processManager.delegate = self;
    self.processManager.refreshInterval = 2.0;
    
    // Configure sorting
    [self.processManager sortByField:HIAHSortFieldCPU ascending:NO];
    
    // Start monitoring
    [self.processManager startSampling];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.processManager stopSampling];
}

#pragma mark - HIAHProcessManagerDelegate

- (void)processManagerDidUpdateProcesses:(HIAHProcessManager *)manager {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        [self updateSummaryLabel];
    });
}

- (void)processManager:(HIAHProcessManager *)manager didSpawnProcess:(HIAHManagedProcess *)process {
    NSLog(@"New process: %@ (PID %d)", process.name, process.pid);
}

- (void)processManager:(HIAHProcessManager *)manager didTerminateProcess:(HIAHManagedProcess *)process {
    NSLog(@"Process exited: %@ (PID %d, exit %d)", process.name, process.pid, process.exitCode);
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.processManager.processes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ProcessCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ProcessCell"];
    HIAHManagedProcess *process = self.processManager.processes[indexPath.row];
    
    cell.nameLabel.text = process.name;
    cell.pidLabel.text = [NSString stringWithFormat:@"PID %d", process.pid];
    cell.cpuLabel.text = [NSString stringWithFormat:@"%.1f%%", process.cpuPercent];
    cell.memoryLabel.text = [self formatBytes:process.residentMemory];
    
    return cell;
}

#pragma mark - Actions

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    HIAHManagedProcess *process = self.processManager.processes[indexPath.row];
    [self showActionsForProcess:process];
}

- (void)showActionsForProcess:(HIAHManagedProcess *)process {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:process.name
                                                                   message:[NSString stringWithFormat:@"PID: %d", process.pid]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Terminate" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error;
        [self.processManager terminateProcess:process.pid error:&error];
        if (error) NSLog(@"Terminate error: %@", error);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Kill" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error;
        [self.processManager killProcess:process.pid error:&error];
        if (error) NSLog(@"Kill error: %@", error);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end
```

## Requirements

- iOS 16.0+
- HIAH Kernel (for virtual process integration)
- Xcode 15.0+

## See Also

- [HIAH Kernel Documentation](./HIAHKernel.md) – Core Library
- [HIAH Desktop Documentation](./HIAHDesktop.md) – Desktop Environment
- [HIAHProcessRunner Documentation](./HIAHProcessRunner.md) – Guest App Extension
- [Virtual Filesystem Documentation](./VirtualFilesystem.md) – Storage & Files.app Integration

