/**
 * HIAHProcessManager.m
 * HIAH Top - Process Manager Controller Implementation
 */

#import "HIAHProcessManager.h"
#import "HIAHResourceCollector.h"
#import "HIAHKernel.h"
#import <signal.h>
#import <sys/resource.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <errno.h>
#import <string.h>
#import <mach/mach.h>
#import <mach/thread_policy.h>
#import <mach/thread_act.h>

#pragma mark - HIAHProcessFilter Implementation

@implementation HIAHProcessFilter

+ (instancetype)defaultFilter {
    HIAHProcessFilter *filter = [[HIAHProcessFilter alloc] init];
    filter.userFilter = -1;
    filter.pidFilter = -1;
    filter.stateFilter = -1;
    filter.includeKernelTasks = NO;
    filter.aliveOnly = NO;
    return filter;
}

- (BOOL)matchesProcess:(HIAHManagedProcess *)process {
    // User filter
    if (self.userFilter != (uid_t)-1 && process.uid != self.userFilter) {
        return NO;
    }
    
    // PID filter
    if (self.pidFilter != -1 && process.pid != self.pidFilter) {
        return NO;
    }
    
    // State filter
    if ((NSInteger)self.stateFilter != -1 && process.state != self.stateFilter) {
        return NO;
    }
    
    // Name pattern filter
    if (self.namePattern) {
        NSError *error;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:self.namePattern
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:&error];
        if (regex) {
            NSRange range = [regex rangeOfFirstMatchInString:process.name
                                                     options:0
                                                       range:NSMakeRange(0, process.name.length)];
            if (range.location == NSNotFound) {
                return NO;
            }
        }
    }
    
    // Alive only filter
    if (self.aliveOnly && !process.isAlive) {
        return NO;
    }
    
    return YES;
}

@end

#pragma mark - HIAHProcessManager Implementation

@interface HIAHProcessManager ()
@property (nonatomic, strong, readwrite) HIAHSystemStats *systemStats;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, HIAHManagedProcess *> *processesByPID;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, HIAHManagedProcess *> *previousSample;
@property (nonatomic, strong, nullable) NSTimer *sampleTimer;
@property (nonatomic, strong) HIAHKernel *kernel;
@property (nonatomic, assign) pid_t nextPID;
@property (nonatomic, strong) dispatch_queue_t processingQueue;
@end

@implementation HIAHProcessManager

#pragma mark - Singleton

static HIAHProcessManager *_sharedManager = nil;

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [[self alloc] init];
    });
    return _sharedManager;
}

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _processesByPID = [NSMutableDictionary dictionary];
        _previousSample = [NSMutableDictionary dictionary];
        _systemStats = [HIAHSystemStats currentStats];
        _filter = [HIAHProcessFilter defaultFilter];
        _refreshInterval = 1.0;
        _paused = NO;
        _sortField = HIAHSortFieldPID;
        _sortAscending = YES;
        _groupingMode = HIAHGroupingModeFlat;
        _nextPID = 100;  // Start virtual PIDs at 100
        _processingQueue = dispatch_queue_create("com.hiahkernel.processmanager", DISPATCH_QUEUE_SERIAL);
        _kernel = [HIAHKernel sharedKernel];
        
        // Load existing processes from HIAHKernel
        [self loadProcessesFromKernel];
        
        // Listen for process spawn/exit notifications from HIAHKernel
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleProcessSpawned:)
                                                     name:HIAHKernelProcessSpawnedNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleProcessExited:)
                                                     name:HIAHKernelProcessExitedNotification
                                                   object:nil];
    }
    return self;
}

- (void)loadProcessesFromKernel {
    // Sync processes from HIAHKernel
    NSArray<HIAHProcess *> *kernelProcesses = [self.kernel allProcesses];
    
    for (HIAHProcess *kernelProcess in kernelProcesses) {
        // Convert HIAHProcess to HIAHManagedProcess
        HIAHManagedProcess *managedProcess = [HIAHManagedProcess processWithPID:kernelProcess.pid 
                                                                       executable:kernelProcess.executablePath];
        managedProcess.argv = kernelProcess.arguments;
        managedProcess.environment = kernelProcess.environment;
        managedProcess.physicalPid = kernelProcess.physicalPid;
        if (kernelProcess.isExited) {
            managedProcess.state = HIAHProcessStateDead;
            NSDate *exitTime = [NSDate date];
            
            // Accumulate any remaining active period
            if (managedProcess.resumeTime) {
                NSTimeInterval activePeriod = [exitTime timeIntervalSinceDate:managedProcess.resumeTime];
                managedProcess.totalActiveTime += activePeriod;
                managedProcess.resumeTime = nil;
            }
            
            managedProcess.endTime = exitTime;
            NSLog(@"[HIAHProcessManager] Loaded exited process: PID %d (%@), uptime frozen at %.2fs (totalActive: %.2fs)", 
                  managedProcess.pid, managedProcess.name, managedProcess.uptime, managedProcess.totalActiveTime);
        } else {
            managedProcess.state = HIAHProcessStateRunning;
            // Ensure resumeTime is set for running processes
            if (!managedProcess.resumeTime) {
                managedProcess.resumeTime = [NSDate date];
            }
            managedProcess.endTime = nil;
        }
        
        // Add main thread
        HIAHThread *mainThread = [HIAHThread threadWithTID:kernelProcess.pid];
        mainThread.name = @"main";
        mainThread.state = managedProcess.state;
        [managedProcess.threads addObject:mainThread];
        
        // Register in our process table
        self.processesByPID[@(kernelProcess.pid)] = managedProcess;
    }
    
    NSLog(@"[HIAHProcessManager] Loaded %lu processes from HIAHKernel", (unsigned long)kernelProcesses.count);
}

- (instancetype)initWithKernel:(HIAHKernel *)kernel {
    self = [self init];
    if (self) {
        _kernel = kernel;
    }
    return self;
}

- (void)dealloc {
    [self stopSampling];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - HIAHKernel Notifications

- (void)handleProcessSpawned:(NSNotification *)notification {
    HIAHProcess *kernelProcess = notification.userInfo[@"process"];
    if (!kernelProcess) return;
    
    dispatch_async(self.processingQueue, ^{
        // Check if we already have this process
        HIAHManagedProcess *existing = self.processesByPID[@(kernelProcess.pid)];
        if (!existing) {
            // New process - add it immediately
            HIAHManagedProcess *managedProcess = [HIAHManagedProcess processWithPID:kernelProcess.pid 
                                                                           executable:kernelProcess.executablePath];
            managedProcess.argv = kernelProcess.arguments;
            managedProcess.environment = kernelProcess.environment;
            managedProcess.physicalPid = kernelProcess.physicalPid;
            managedProcess.state = HIAHProcessStateRunning;
            managedProcess.resumeTime = [NSDate date];
            
            // Add main thread
            HIAHThread *mainThread = [HIAHThread threadWithTID:kernelProcess.pid];
            mainThread.name = @"main";
            mainThread.state = HIAHProcessStateRunning;
            [managedProcess.threads addObject:mainThread];
            
            self.processesByPID[@(kernelProcess.pid)] = managedProcess;
            
            NSLog(@"[HIAHProcessManager] Added new process from notification: PID %d (%@)", 
                  kernelProcess.pid, kernelProcess.executablePath);
            
            // Notify delegate immediately
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate processManager:self didSpawnProcess:managedProcess];
                [self.delegate processManagerDidUpdateProcesses:self];
            });
        }
    });
}

- (void)handleProcessExited:(NSNotification *)notification {
    HIAHProcess *kernelProcess = notification.userInfo[@"process"];
    if (!kernelProcess) return;
    
    dispatch_async(self.processingQueue, ^{
        HIAHManagedProcess *existing = self.processesByPID[@(kernelProcess.pid)];
        if (existing && existing.state != HIAHProcessStateDead) {
            existing.state = HIAHProcessStateDead;
            existing.endTime = [NSDate date];
            
            // Accumulate active time
            if (existing.resumeTime) {
                NSTimeInterval activePeriod = [existing.endTime timeIntervalSinceDate:existing.resumeTime];
                existing.totalActiveTime += activePeriod;
                existing.resumeTime = nil;
            }
            
            NSLog(@"[HIAHProcessManager] Process exited from notification: PID %d", kernelProcess.pid);
            
            // Notify delegate
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate processManager:self didTerminateProcess:existing];
                [self.delegate processManagerDidUpdateProcesses:self];
            });
        }
    });
}

#pragma mark - Sampling Control

- (void)startSampling {
    [self stopSampling];
    
    // Ensure kernel is initialized before starting sampling
    if (!self.kernel) {
        self.kernel = [HIAHKernel sharedKernel];
        if (self.kernel) {
            // Load processes immediately to ensure we have initial state
            [self loadProcessesFromKernel];
            NSLog(@"[HIAHProcessManager] Loaded %lu processes before starting sampling", (unsigned long)self.processesByPID.count);
        } else {
            NSLog(@"[HIAHProcessManager] WARNING: Cannot get kernel instance, sampling may not work");
        }
    }
    
    __weak typeof(self) weakSelf = self;
    self.sampleTimer = [NSTimer scheduledTimerWithTimeInterval:self.refreshInterval
                                                       repeats:YES
                                                         block:^(NSTimer * _Nonnull timer) {
        if (!weakSelf.paused) {
            [weakSelf sample];
        }
    }];
    
    // Fire immediately
    [self sample];
}

- (void)stopSampling {
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
}

- (void)sample {
    dispatch_async(self.processingQueue, ^{
        // Store previous sample for delta calculation
        self.previousSample = [self.processesByPID mutableCopy];
        
        // Sync with HIAHKernel - add any new processes
        [self syncWithKernel];
        
        // Update system stats
        [self.systemStats refresh];
        self.systemStats.processCount = self.processesByPID.count;
        
        // Sample each process
        NSUInteger totalThreads = 0;
        for (HIAHManagedProcess *process in self.processesByPID.allValues) {
            [process sample];
            
            // Calculate deltas
            HIAHManagedProcess *previous = self.previousSample[@(process.pid)];
            [process calculateDeltasFrom:previous];
            
            totalThreads += process.threads.count;
        }
        self.systemStats.threadCount = totalThreads;
        
        // Notify delegate on main thread (throttled to prevent excessive updates)
        static NSTimeInterval lastNotificationTime = 0;
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        
        // Throttle notifications to max once per 0.2 seconds for smoother updates
        if (now - lastNotificationTime >= 0.2) {
            lastNotificationTime = now;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate processManagerDidUpdateProcesses:self];
                [self.delegate processManagerDidUpdateSystemStats:self];
            });
        }
    });
}

- (void)syncWithKernel {
    // Ensure kernel is available
    if (!self.kernel) {
        NSLog(@"[HIAHProcessManager] WARNING: Kernel is nil, reinitializing...");
        self.kernel = [HIAHKernel sharedKernel];
        if (!self.kernel) {
            NSLog(@"[HIAHProcessManager] ERROR: Cannot get kernel instance");
            return;
        }
    }
    
    // Sync processes from HIAHKernel - add new ones, update existing
    NSArray<HIAHProcess *> *kernelProcesses = [self.kernel allProcesses];
    if (!kernelProcesses) {
        NSLog(@"[HIAHProcessManager] WARNING: Kernel returned nil process list - keeping existing processes");
        // Don't return - keep existing processes in the list
        // This prevents processes from disappearing if kernel temporarily returns nil
        return;
    }
    
    // Log sync operation for debugging
    NSLog(@"[HIAHProcessManager] Syncing with kernel: %lu kernel processes, %lu managed processes", 
          (unsigned long)kernelProcesses.count, (unsigned long)self.processesByPID.count);
    
    NSMutableSet *kernelPIDs = [NSMutableSet set];
    NSMutableArray *newProcesses = [NSMutableArray array];
    BOOL hasUpdates = NO;
    
    for (HIAHProcess *kernelProcess in kernelProcesses) {
        [kernelPIDs addObject:@(kernelProcess.pid)];
        
        // Check if we already have this process
        HIAHManagedProcess *existing = self.processesByPID[@(kernelProcess.pid)];
        if (!existing) {
            // New process - add it
            HIAHManagedProcess *managedProcess = [HIAHManagedProcess processWithPID:kernelProcess.pid 
                                                                           executable:kernelProcess.executablePath];
            managedProcess.argv = kernelProcess.arguments;
            managedProcess.environment = kernelProcess.environment;
            managedProcess.physicalPid = kernelProcess.physicalPid;
            
            if (kernelProcess.isExited) {
                managedProcess.state = HIAHProcessStateDead;
                managedProcess.endTime = [NSDate date];
            } else {
                managedProcess.state = HIAHProcessStateRunning;
                if (!managedProcess.resumeTime) {
                    managedProcess.resumeTime = [NSDate date];
                }
            }
            
            // Add main thread
            HIAHThread *mainThread = [HIAHThread threadWithTID:kernelProcess.pid];
            mainThread.name = @"main";
            mainThread.state = managedProcess.state;
            [managedProcess.threads addObject:mainThread];
            
            self.processesByPID[@(kernelProcess.pid)] = managedProcess;
            [newProcesses addObject:managedProcess];
            hasUpdates = YES;
            
            NSLog(@"[HIAHProcessManager] Synced new process: PID %d (%@)", 
                  kernelProcess.pid, kernelProcess.executablePath);
        } else {
            // Update existing process state from kernel
            BOOL stateChanged = NO;
            if (kernelProcess.isExited && existing.state != HIAHProcessStateDead) {
                existing.state = HIAHProcessStateDead;
                existing.endTime = [NSDate date];
                // Accumulate active time
                if (existing.resumeTime) {
                    NSTimeInterval activePeriod = [existing.endTime timeIntervalSinceDate:existing.resumeTime];
                    existing.totalActiveTime += activePeriod;
                    existing.resumeTime = nil;
                }
                stateChanged = YES;
            } else if (!kernelProcess.isExited && existing.state == HIAHProcessStateDead) {
                // Process was restarted
                existing.state = HIAHProcessStateRunning;
                existing.resumeTime = [NSDate date];
                existing.endTime = nil;
                stateChanged = YES;
            }
            
            // Update process info if changed
            if (![existing.executablePath isEqualToString:kernelProcess.executablePath]) {
                existing.executablePath = kernelProcess.executablePath;
                hasUpdates = YES;
            }
            
            if (stateChanged) {
                hasUpdates = YES;
            }
        }
    }
    
    // Always notify delegate if there are updates or if this is a manual refresh
    if (hasUpdates || newProcesses.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (HIAHManagedProcess *proc in newProcesses) {
                if ([self.delegate respondsToSelector:@selector(processManager:didSpawnProcess:)]) {
                    [self.delegate processManager:self didSpawnProcess:proc];
                }
            }
            if ([self.delegate respondsToSelector:@selector(processManagerDidUpdateProcesses:)]) {
                [self.delegate processManagerDidUpdateProcesses:self];
            }
        });
    }
    
    // Note: We don't remove processes from our list even if they're gone from kernel
    // This preserves history and allows seeing exited processes
    
    // Log final state for debugging
    if (hasUpdates || newProcesses.count > 0) {
        NSLog(@"[HIAHProcessManager] Sync complete: %lu total managed processes (added %lu new)", 
              (unsigned long)self.processesByPID.count, (unsigned long)newProcesses.count);
    }
}

- (void)pause {
    self.paused = YES;
}

- (void)resume {
    self.paused = NO;
}

#pragma mark - Process Properties

- (NSArray<HIAHManagedProcess *> *)allProcesses {
    return [self.processesByPID.allValues copy];
}

- (NSArray<HIAHManagedProcess *> *)processes {
    NSArray *baseProcesses = self.allProcesses;
    
    // Apply grouping mode
    NSArray *groupedProcesses;
    switch (self.groupingMode) {
        case HIAHGroupingModeTree: {
            // Build tree structure and flatten it (parent before children)
            NSMutableArray *result = [NSMutableArray array];
            NSMutableSet *added = [NSMutableSet set];
            
            // Find root processes (PPID = 1 or PPID not in process list)
            NSMutableSet *allPIDs = [NSMutableSet set];
            for (HIAHManagedProcess *p in baseProcesses) {
                [allPIDs addObject:@(p.pid)];
            }
            
            // Add root processes first
            for (HIAHManagedProcess *process in baseProcesses) {
                if (process.ppid == 1 || process.ppid == 0 || ![allPIDs containsObject:@(process.ppid)]) {
                    [self addProcessToTree:process result:result added:added allProcesses:baseProcesses];
                }
            }
            
            // Add any remaining processes (orphans)
            for (HIAHManagedProcess *process in baseProcesses) {
                if (![added containsObject:@(process.pid)]) {
                    [result addObject:process];
                    [added addObject:@(process.pid)];
                }
            }
            
            groupedProcesses = result;
            break;
        }
        case HIAHGroupingModeUser: {
            // Group by user ID
            NSMutableArray *result = [NSMutableArray array];
            NSDictionary *byUser = [self processesByUser];
            NSArray *sortedUsers = [[byUser allKeys] sortedArrayUsingSelector:@selector(compare:)];
            
            for (NSNumber *uid in sortedUsers) {
                NSArray *userProcesses = byUser[uid];
                NSArray *sortedUserProcesses = [self sortedProcesses:userProcesses];
                [result addObjectsFromArray:sortedUserProcesses];
            }
            
            groupedProcesses = result;
            break;
        }
        case HIAHGroupingModeApplication: {
            // Group by bundle identifier or executable name
            NSMutableDictionary *byApp = [NSMutableDictionary dictionary];
            for (HIAHManagedProcess *process in baseProcesses) {
                NSString *key = process.bundleIdentifier ?: [process.executablePath lastPathComponent] ?: @"Unknown";
                if (!byApp[key]) {
                    byApp[key] = [NSMutableArray array];
                }
                [(NSMutableArray *)byApp[key] addObject:process];
            }
            
            NSMutableArray *result = [NSMutableArray array];
            NSArray *sortedApps = [[byApp allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
            for (NSString *appKey in sortedApps) {
                NSArray *appProcesses = byApp[appKey];
                NSArray *sortedAppProcesses = [self sortedProcesses:appProcesses];
                [result addObjectsFromArray:sortedAppProcesses];
            }
            
            groupedProcesses = result;
            break;
        }
        case HIAHGroupingModeFlat:
        default:
            groupedProcesses = baseProcesses;
            break;
    }
    
    // Apply filter (but don't filter out all processes - ensure at least visible processes remain)
    NSArray *filtered = [self filteredProcesses:groupedProcesses withFilter:self.filter];
    
    // Safety check: if filter removed all processes but we have processes in the dictionary,
    // return unfiltered list (filter might be too restrictive)
    if (filtered.count == 0 && baseProcesses.count > 0 && self.filter.aliveOnly) {
        NSLog(@"[HIAHProcessManager] WARNING: Filter removed all processes, temporarily disabling aliveOnly filter");
        // Temporarily disable aliveOnly to show processes
        BOOL wasAliveOnly = self.filter.aliveOnly;
        self.filter.aliveOnly = NO;
        filtered = [self filteredProcesses:groupedProcesses withFilter:self.filter];
        self.filter.aliveOnly = wasAliveOnly;
    }
    
    // Apply sorting
    return [self sortedProcesses:filtered];
}

// Helper method to recursively add process and its children to tree
- (void)addProcessToTree:(HIAHManagedProcess *)process
                  result:(NSMutableArray *)result
                   added:(NSMutableSet *)added
            allProcesses:(NSArray<HIAHManagedProcess *> *)allProcesses {
    if ([added containsObject:@(process.pid)]) {
        return; // Already added
    }
    
    // Add this process
    [result addObject:process];
    [added addObject:@(process.pid)];
    
    // Add children recursively
    for (HIAHManagedProcess *child in allProcesses) {
        if (child.ppid == process.pid) {
            [self addProcessToTree:child result:result added:added allProcesses:allProcesses];
        }
    }
}

- (NSUInteger)processCount {
    return self.processesByPID.count;
}

- (NSUInteger)threadCount {
    NSUInteger count = 0;
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        count += process.threads.count;
    }
    return count;
}

- (NSDictionary<NSNumber *, NSArray<HIAHManagedProcess *> *> *)processesByUser {
    NSMutableDictionary *byUser = [NSMutableDictionary dictionary];
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        NSNumber *uid = @(process.uid);
        if (!byUser[uid]) {
            byUser[uid] = [NSMutableArray array];
        }
        [(NSMutableArray *)byUser[uid] addObject:process];
    }
    return byUser;
}

- (NSDictionary<NSNumber *, NSArray<HIAHManagedProcess *> *> *)processTree {
    NSMutableDictionary *tree = [NSMutableDictionary dictionary];
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        NSNumber *ppid = @(process.ppid);
        if (!tree[ppid]) {
            tree[ppid] = [NSMutableArray array];
        }
        [(NSMutableArray *)tree[ppid] addObject:process];
    }
    return tree;
}

#pragma mark - Process Enumeration (Section 2)

- (NSArray<HIAHManagedProcess *> *)listAllProcesses {
    return self.processes;
}

- (HIAHManagedProcess *)processForPID:(pid_t)pid {
    return self.processesByPID[@(pid)];
}

- (NSArray<HIAHManagedProcess *> *)findProcessesWithName:(NSString *)name {
    NSMutableArray *result = [NSMutableArray array];
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        if ([process.name localizedCaseInsensitiveContainsString:name]) {
            [result addObject:process];
        }
    }
    return result;
}

- (NSArray<HIAHManagedProcess *> *)findProcessesMatchingPattern:(NSString *)pattern {
    NSError *error;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    if (!regex) return @[];
    
    NSMutableArray *result = [NSMutableArray array];
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        NSRange range = [regex rangeOfFirstMatchInString:process.name
                                                 options:0
                                                   range:NSMakeRange(0, process.name.length)];
        if (range.location != NSNotFound) {
            [result addObject:process];
        }
    }
    return result;
}

- (NSArray<HIAHManagedProcess *> *)processTreeForPID:(pid_t)rootPID {
    NSMutableArray *result = [NSMutableArray array];
    HIAHManagedProcess *root = [self processForPID:rootPID];
    if (root) {
        [result addObject:root];
        [self addDescendantsOfPID:rootPID toArray:result];
    }
    return result;
}

- (void)addDescendantsOfPID:(pid_t)pid toArray:(NSMutableArray *)array {
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        if (process.ppid == pid) {
            [array addObject:process];
            [self addDescendantsOfPID:process.pid toArray:array];
        }
    }
}

- (NSArray<HIAHManagedProcess *> *)childrenOfProcess:(pid_t)pid {
    NSMutableArray *children = [NSMutableArray array];
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        if (process.ppid == pid) {
            [children addObject:process];
        }
    }
    return children;
}

#pragma mark - Process Spawning

- (HIAHManagedProcess *)spawnProcessWithExecutable:(NSString *)path
                                         arguments:(NSArray<NSString *> *)args
                                       environment:(NSDictionary<NSString *, NSString *> *)env
                                             error:(NSError **)error {
    // Validate path
    if (!path || path.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid executable path"}];
        }
        return nil;
    }
    
    // For now, create a virtual process without actually spawning via HIAHKernel
    // (HIAHKernel spawning requires the extension to be properly set up)
    // Assign virtual PID
    pid_t newPID;
    @synchronized (self) {
        newPID = self.nextPID++;
    }
    
    // Create managed process
    HIAHManagedProcess *managedProcess = [HIAHManagedProcess processWithPID:newPID executable:path];
    managedProcess.argv = args;
    managedProcess.environment = env;
    managedProcess.state = HIAHProcessStateRunning;
    managedProcess.physicalPid = -1;  // Virtual process
    managedProcess.endTime = nil;  // Process is starting, no end time
    // resumeTime is already set in initWithPID:executable: to startTime
    
    NSLog(@"[HIAHProcessManager] Spawning process: PID %d, executable: %@", newPID, path);
    
    // Add main thread
    HIAHThread *mainThread = [HIAHThread threadWithTID:newPID];
    mainThread.name = @"main";
    mainThread.state = HIAHProcessStateRunning;
    [managedProcess.threads addObject:mainThread];
    
    // Register process
    self.processesByPID[@(newPID)] = managedProcess;
    
    // Try to spawn via HIAHKernel (non-blocking)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.kernel spawnVirtualProcessWithPath:path
                                        arguments:args
                                      environment:env
                                       completion:^(pid_t kernelPID, NSError *kernelError) {
            if (!kernelError && kernelPID > 0) {
                // Update with kernel PID if successful
                HIAHProcess *kernelProcess = [self.kernel processForPID:kernelPID];
                if (kernelProcess) {
                    // Create new managed process with kernel PID
                    HIAHManagedProcess *kernelManagedProcess = [HIAHManagedProcess processWithPID:kernelPID executable:path];
                    kernelManagedProcess.argv = args;
                    kernelManagedProcess.environment = env;
                    kernelManagedProcess.state = HIAHProcessStateRunning;
                    // Ensure resumeTime is set for running processes
                    if (!kernelManagedProcess.resumeTime) {
                        kernelManagedProcess.resumeTime = [NSDate date];
                    }
                    kernelManagedProcess.endTime = nil;
                    kernelManagedProcess.physicalPid = kernelProcess.physicalPid;
                    
                    // Copy thread info
                    kernelManagedProcess.threads = [managedProcess.threads mutableCopy];
                    
                    // Update registration
                    [self.processesByPID removeObjectForKey:@(newPID)];
                    self.processesByPID[@(kernelPID)] = kernelManagedProcess;
                    
                    NSLog(@"[HIAHProcessManager] Process spawned successfully: PID %d -> %d (physical PID: %d), executable: %@", 
                          newPID, kernelPID, kernelProcess.physicalPid, path);
                    
                    // Notify delegate of update
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate processManager:self didSpawnProcess:kernelManagedProcess];
                    });
                } else {
                    NSLog(@"[HIAHProcessManager] WARNING: Kernel returned PID %d but process not found in kernel", kernelPID);
                }
            } else {
                NSString *errorDesc = kernelError ? kernelError.localizedDescription : @"Unknown error";
                NSLog(@"[HIAHProcessManager] ERROR: Failed to spawn process via kernel: %@", errorDesc);
            }
        }];
    });
    
    // Notify delegate
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate processManager:self didSpawnProcess:managedProcess];
    });
    
    return managedProcess;
}

#pragma mark - Control Plane (Section 5)

- (BOOL)sendSignal:(int)signal toProcess:(pid_t)pid error:(NSError **)error {
    HIAHManagedProcess *process = [self processForPID:pid];
    if (!process) {
        NSString *errorMsg = [NSString stringWithFormat:@"No such process: PID %d", pid];
        NSLog(@"[HIAHProcessManager] ERROR: %@", errorMsg);
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"No such process"}];
        }
        return NO;
    }
    
    if (!process.canSignal) {
        NSString *errorMsg = [NSString stringWithFormat:@"Process %d (%@) cannot receive signals (state: %@)", 
                             pid, process.name, [process stateString]];
        NSLog(@"[HIAHProcessManager] ERROR: %@", errorMsg);
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Process cannot receive signals"}];
        }
        return NO;
    }
    
    // Check if this is a virtual process managed by HIAHKernel
    HIAHProcess *kernelProcess = [self.kernel processForPID:pid];
    
    if (kernelProcess && kernelProcess.physicalPid > 0) {
        // Check if this is HIAH Desktop itself
        BOOL isHIAHDesktop = NO;
        NSString *executable = kernelProcess.executablePath ?: @"";
        NSString *bundleID = process.bundleIdentifier ?: @"";
        NSString *name = process.name ?: @"";
        
        isHIAHDesktop = ([executable containsString:@"HIAHDesktop"] || 
                         [executable containsString:@"HIAHDesktop.app"] ||
                         [name containsString:@"HIAH Desktop"] ||
                         [name isEqualToString:@"HIAH Desktop"] ||
                         [bundleID isEqualToString:@"com.aspauldingcode.HIAHDesktop"] ||
                         (kernelProcess.physicalPid == getpid() && [executable hasSuffix:@"HIAHDesktop"]));
        
        // CRITICAL: Don't kill the host process (windowed apps run in main process)
        // EXCEPTION: Allow killing HIAH Desktop itself
        if (kernelProcess.physicalPid == getpid() && !isHIAHDesktop) {
            NSLog(@"[HIAHProcessManager] Virtual process PID:%d runs in host (physicalPid:%d)", pid, kernelProcess.physicalPid);
            NSLog(@"[HIAHProcessManager] Terminating windowed app (virtual cleanup)");
            
            // Update state to Dead
            [self updateProcessState:process signal:signal];
            
            // Unregister from kernel
            [self.kernel unregisterProcessWithPID:pid];
            
            // CRITICAL: Post notification so HIAH Desktop closes the window!
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:HIAHKernelProcessExitedNotification
                                                                    object:self.kernel
                                                                  userInfo:@{@"pid": @(pid)}];
                NSLog(@"[HIAHProcessManager] ✅ Posted exit notification for PID %d", pid);
            });
            
            return YES;
        }
        
        // If killing HIAH Desktop itself, terminate the iOS app
        if (kernelProcess.physicalPid == getpid() && isHIAHDesktop && signal == SIGKILL) {
            NSLog(@"[HIAHProcessManager] 🛑 Killing HIAH Desktop (host process) - terminating iOS app");
            
            // Post notification before exit
            [[NSNotificationCenter defaultCenter] postNotificationName:@"HIAHDesktopWillTerminate" object:nil];
            
            // Give UI a moment to update, then exit
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                exit(0);  // Terminate the iOS app
            });
            
            return YES;
        }
        
        // Safe to kill - it's a real separate process
        int result = kill(kernelProcess.physicalPid, signal);
        if (result == 0) {
            [self updateProcessState:process signal:signal];
            NSLog(@"[HIAHProcessManager] Sent signal %d to virtual PID %d (physical PID %d)", signal, pid, kernelProcess.physicalPid);
            return YES;
        }
    }
    
    // Try direct kill on the PID (might be a real process or virtual PID)
    int result = kill(pid, signal);
    if (result == 0) {
        [self updateProcessState:process signal:signal];
        NSLog(@"[HIAHProcessManager] Sent signal %d to PID %d", signal, pid);
        return YES;
    }
    
    // If kill failed, try via HIAHKernel control socket
    if (self.kernel.controlSocketPath) {
        // Send signal command via control socket
        NSDictionary *command = @{
            @"command": @"signal",
            @"pid": @(pid),
            @"signal": @(signal)
        };
        
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:command options:0 error:&jsonError];
        if (!jsonError) {
            int sock = socket(AF_UNIX, SOCK_STREAM, 0);
            if (sock >= 0) {
                struct sockaddr_un addr;
                memset(&addr, 0, sizeof(addr));
                addr.sun_family = AF_UNIX;
                strncpy(addr.sun_path, [self.kernel.controlSocketPath UTF8String], sizeof(addr.sun_path) - 1);
                
                if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
                    write(sock, jsonData.bytes, jsonData.length);
                    write(sock, "\n", 1);
                    close(sock);
                    
                    [self updateProcessState:process signal:signal];
                    NSLog(@"[HIAHProcessManager] Sent signal %d to PID %d via control socket", signal, pid);
                    return YES;
                }
                close(sock);
            }
        }
    }
    
    // All methods failed
    NSString *errorMsg = [NSString stringWithFormat:@"Failed to send signal %d to PID %d: %s", signal, pid, strerror(errno)];
    NSLog(@"[HIAHProcessManager] ERROR: %@", errorMsg);
    if (error) {
        *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                     code:5
                                 userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
    }
    return NO;
}

- (void)updateProcessState:(HIAHManagedProcess *)process signal:(int)signal {
    // Update process state based on signal
    
    if (signal == SIGTERM || signal == SIGKILL) {
        process.state = HIAHProcessStateDead;
        NSDate *deathTime = [NSDate date];
        
        // Accumulate any remaining active period before death
        if (process.resumeTime) {
            NSTimeInterval activePeriod = [deathTime timeIntervalSinceDate:process.resumeTime];
            process.totalActiveTime += activePeriod;
            process.resumeTime = nil;
        }
        
        process.endTime = deathTime;
        NSTimeInterval finalUptime = process.uptime;
        NSLog(@"[HIAHProcessManager] Process %d (%@) killed - state: %@ -> Dead, uptime frozen at %.2fs (totalActive: %.2fs)", 
              process.pid, process.name, [process stateString], finalUptime, process.totalActiveTime);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate processManager:self didTerminateProcess:process];
        });
        // Remove immediately for SIGKILL
        if (signal == SIGKILL) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self.processesByPID removeObjectForKey:@(process.pid)];
                [self.kernel unregisterProcessWithPID:process.pid];
                NSLog(@"[HIAHProcessManager] Removed killed process %d from process table", process.pid);
            });
        }
    } else if (signal == SIGSTOP) {
        process.state = HIAHProcessStateStopped;
        NSDate *stopTime = [NSDate date];
        
        // Accumulate the active period before stopping
        if (process.resumeTime) {
            NSTimeInterval activePeriod = [stopTime timeIntervalSinceDate:process.resumeTime];
            process.totalActiveTime += activePeriod;
            process.resumeTime = nil;  // No longer running
        }
        
        process.endTime = stopTime;
        NSTimeInterval frozenUptime = process.uptime;
        NSLog(@"[HIAHProcessManager] Process %d (%@) stopped - state: %@ -> Stopped, uptime frozen at %.2fs (totalActive: %.2fs)", 
              process.pid, process.name, [process stateString], frozenUptime, process.totalActiveTime);
    } else if (signal == SIGCONT) {
        if (process.state == HIAHProcessStateStopped) {
            NSTimeInterval frozenUptime = process.uptime;
            process.state = HIAHProcessStateRunning;
            
            // Resume tracking active time
            process.resumeTime = [NSDate date];
            process.endTime = nil;  // No longer stopped
            
            NSTimeInterval newUptime = process.uptime;
            NSLog(@"[HIAHProcessManager] Process %d (%@) resumed - state: Stopped -> Running, uptime resumed (was %.2fs frozen, now %.2fs active, totalActive: %.2fs)", 
                  process.pid, process.name, frozenUptime, newUptime, process.totalActiveTime);
        }
    }
}


- (BOOL)terminateProcess:(pid_t)pid error:(NSError **)error {
    return [self sendSignal:SIGTERM toProcess:pid error:error];
}

- (BOOL)killProcess:(pid_t)pid error:(NSError **)error {
    HIAHManagedProcess *process = self.processesByPID[@(pid)];
    
    // Check if this is HIAH Desktop process
    BOOL isHIAHDesktop = NO;
    if (process) {
        NSString *executable = process.executablePath ?: @"";
        NSString *name = process.name ?: @"";
        NSString *bundleID = process.bundleIdentifier ?: @"";
        
        // Check multiple ways to identify HIAH Desktop
        isHIAHDesktop = ([executable containsString:@"HIAHDesktop"] || 
                        [executable containsString:@"HIAHDesktop.app"] ||
                        [name containsString:@"HIAH Desktop"] ||
                        [name isEqualToString:@"HIAH Desktop"] ||
                        [bundleID isEqualToString:@"com.aspauldingcode.HIAHDesktop"] ||
                        (pid == getpid() && [executable hasSuffix:@"HIAHDesktop"]));
    }
    
    // Allow killing HIAH Desktop even if it's the host process
    if (pid == getpid() && !isHIAHDesktop) {
        NSLog(@"[HIAHProcessManager] ⚠️ Cannot kill host process - skipping");
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot kill host process"}];
        }
        return NO;
    }
    
    // If killing HIAH Desktop (the host app), terminate the iOS app
    if (pid == getpid() && isHIAHDesktop) {
        NSLog(@"[HIAHProcessManager] 🛑 Killing HIAH Desktop (host process) - terminating iOS app");
        
        // Post notification before exit so UI can update
        [[NSNotificationCenter defaultCenter] postNotificationName:@"HIAHDesktopWillTerminate" object:nil];
        
        // Give UI a moment to update, then exit
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exit(0);  // Terminate the iOS app
        });
        
        return YES;
    }
    
    return [self sendSignal:SIGKILL toProcess:pid error:error];
}

- (BOOL)stopProcess:(pid_t)pid error:(NSError **)error {
    HIAHManagedProcess *process = self.processesByPID[@(pid)];
    
    // Check if this is HIAH Desktop process
    BOOL isHIAHDesktop = NO;
    if (process) {
        NSString *executable = process.executablePath ?: @"";
        NSString *name = process.name ?: @"";
        NSString *bundleID = process.bundleIdentifier ?: @"";
        
        isHIAHDesktop = ([executable containsString:@"HIAHDesktop"] || 
                        [executable containsString:@"HIAHDesktop.app"] ||
                        [name containsString:@"HIAH Desktop"] ||
                        [name isEqualToString:@"HIAH Desktop"] ||
                        [bundleID isEqualToString:@"com.aspauldingcode.HIAHDesktop"] ||
                        (pid == getpid() && [executable hasSuffix:@"HIAHDesktop"]));
    }
    
    // Allow stopping HIAH Desktop (though stopping the host app is unusual)
    if (pid == getpid() && !isHIAHDesktop) {
        NSLog(@"[HIAHProcessManager] ⚠️ Cannot stop host process - skipping");
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot stop host process"}];
        }
        return NO;
    }
    
    // If stopping HIAH Desktop, just send SIGSTOP (won't actually stop iOS app, but will mark it)
    if (pid == getpid() && isHIAHDesktop) {
        NSLog(@"[HIAHProcessManager] ⚠️ Cannot stop HIAH Desktop host process - use Kill instead");
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot stop HIAH Desktop host process - use Kill to terminate"}];
        }
        return NO;
    }
    
    return [self sendSignal:SIGSTOP toProcess:pid error:error];
}

- (BOOL)continueProcess:(pid_t)pid error:(NSError **)error {
    return [self sendSignal:SIGCONT toProcess:pid error:error];
}

- (BOOL)killProcessTree:(pid_t)pid error:(NSError **)error {
    NSArray *tree = [self processTreeForPID:pid];
    
    // Kill children first (reverse order)
    for (NSInteger i = tree.count - 1; i >= 0; i--) {
        HIAHManagedProcess *process = tree[i];
        [self sendSignal:SIGKILL toProcess:process.pid error:nil];
    }
    
    return YES;
}

- (BOOL)setNiceValue:(int)nice forProcess:(pid_t)pid error:(NSError **)error {
    HIAHManagedProcess *process = [self processForPID:pid];
    if (!process) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"No such process"}];
        }
        return NO;
    }
    
    // Clamp nice value
    nice = MAX(-20, MIN(19, nice));
    
    // Set real nice value via setpriority()
    int result = setpriority(PRIO_PROCESS, pid, nice);
    if (result != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"setpriority failed: %s", strerror(errno)]}];
        }
        return NO;
    }
    
    process.cpu.niceValue = nice;
    return YES;
}

- (BOOL)setCPUAffinity:(NSInteger)core forProcess:(pid_t)pid error:(NSError **)error {
    HIAHManagedProcess *process = [self processForPID:pid];
    if (!process) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"No such process"}];
        }
        return NO;
    }
    
    // Get the task port for this process
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS) {
        // If task_for_pid fails, still update the local state
        process.cpu.cpuAffinity = core;
        NSLog(@"[HIAHProcessManager] Cannot get task port for PID %d (simulated affinity set)", pid);
        return YES;
    }
    
    // Get threads for this task
    thread_act_array_t threadList;
    mach_msg_type_number_t threadCount;
    kr = task_threads(task, &threadList, &threadCount);
    
    if (kr == KERN_SUCCESS) {
        BOOL success = YES;
        
        for (mach_msg_type_number_t i = 0; i < threadCount; i++) {
            // Set CPU affinity using thread_policy_set
            thread_affinity_policy_data_t policy;
            policy.affinity_tag = (integer_t)core;
            
            kr = thread_policy_set(threadList[i],
                                   THREAD_AFFINITY_POLICY,
                                   (thread_policy_t)&policy,
                                   THREAD_AFFINITY_POLICY_COUNT);
            
            if (kr != KERN_SUCCESS) {
                NSLog(@"[HIAHProcessManager] thread_policy_set failed for thread %d: %s",
                      i, mach_error_string(kr));
                success = NO;
            }
            
            mach_port_deallocate(mach_task_self(), threadList[i]);
        }
        
        vm_deallocate(mach_task_self(), (vm_address_t)threadList, threadCount * sizeof(thread_act_t));
        
        if (success) {
            process.cpu.cpuAffinity = core;
            NSLog(@"[HIAHProcessManager] Set CPU affinity to core %ld for PID %d (%lu threads)",
                  (long)core, pid, (unsigned long)threadCount);
        }
        
        mach_port_deallocate(mach_task_self(), task);
        return success;
    }
    
    mach_port_deallocate(mach_task_self(), task);
    
    if (error) {
        *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                     code:7
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to enumerate threads"}];
    }
    return NO;
}

- (BOOL)setThreadPriority:(int)priority forThread:(uint64_t)tid inProcess:(pid_t)pid error:(NSError **)error {
    HIAHManagedProcess *process = [self processForPID:pid];
    if (!process) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"No such process"}];
        }
        return NO;
    }
    
    // Get the task port
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot get task port"}];
        }
        return NO;
    }
    
    // Get threads
    thread_act_array_t threadList;
    mach_msg_type_number_t threadCount;
    kr = task_threads(task, &threadList, &threadCount);
    
    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), task);
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to enumerate threads"}];
        }
        return NO;
    }
    
    BOOL found = NO;
    
    for (mach_msg_type_number_t i = 0; i < threadCount; i++) {
        // Check if this is the thread we're looking for
        if ((uint64_t)threadList[i] == tid) {
            found = YES;
            
            // Set thread priority using thread_policy_set with THREAD_PRECEDENCE_POLICY
            thread_precedence_policy_data_t policy;
            policy.importance = priority;
            
            kr = thread_policy_set(threadList[i],
                                   THREAD_PRECEDENCE_POLICY,
                                   (thread_policy_t)&policy,
                                   THREAD_PRECEDENCE_POLICY_COUNT);
            
            if (kr == KERN_SUCCESS) {
                // Update local thread state
                for (HIAHThread *thread in process.threads) {
                    if (thread.tid == tid) {
                        thread.priority = priority;
                        break;
                    }
                }
                NSLog(@"[HIAHProcessManager] Set thread priority to %d for TID %llu in PID %d",
                      priority, tid, pid);
            } else {
                NSLog(@"[HIAHProcessManager] thread_policy_set failed: %s", mach_error_string(kr));
                if (error) {
                    *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                                 code:9
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 [NSString stringWithFormat:@"thread_policy_set failed: %s",
                                                  mach_error_string(kr)]}];
                }
            }
        }
        mach_port_deallocate(mach_task_self(), threadList[i]);
    }
    
    vm_deallocate(mach_task_self(), (vm_address_t)threadList, threadCount * sizeof(thread_act_t));
    mach_port_deallocate(mach_task_self(), task);
    
    if (!found) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"Thread not found"}];
        }
        return NO;
    }
    
    return kr == KERN_SUCCESS;
}

#pragma mark - Sorting (Section 8)

- (void)sortByField:(HIAHSortField)field ascending:(BOOL)ascending {
    self.sortField = field;
    self.sortAscending = ascending;
}

- (NSArray<HIAHManagedProcess *> *)sortedProcesses:(NSArray<HIAHManagedProcess *> *)processes {
    return [processes sortedArrayUsingComparator:^NSComparisonResult(HIAHManagedProcess *a, HIAHManagedProcess *b) {
        NSComparisonResult result;
        
        switch (self.sortField) {
            case HIAHSortFieldPID:
                result = [@(a.pid) compare:@(b.pid)];
                break;
            case HIAHSortFieldPPID:
                result = [@(a.ppid) compare:@(b.ppid)];
                break;
            case HIAHSortFieldName:
                result = [a.name localizedCaseInsensitiveCompare:b.name];
                break;
            case HIAHSortFieldState:
                result = [@(a.state) compare:@(b.state)];
                break;
            case HIAHSortFieldCPU:
                result = [@(a.cpu.totalUsagePercent) compare:@(b.cpu.totalUsagePercent)];
                break;
            case HIAHSortFieldMemory:
                result = [@(a.memory.residentSize) compare:@(b.memory.residentSize)];
                break;
            case HIAHSortFieldIORead:
                result = [@(a.io.bytesRead) compare:@(b.io.bytesRead)];
                break;
            case HIAHSortFieldIOWrite:
                result = [@(a.io.bytesWritten) compare:@(b.io.bytesWritten)];
                break;
            case HIAHSortFieldStartTime:
                result = [a.startTime compare:b.startTime];
                break;
            case HIAHSortFieldUptime:
                result = [@(a.uptime) compare:@(b.uptime)];
                break;
            case HIAHSortFieldThreads:
                result = [@(a.threads.count) compare:@(b.threads.count)];
                break;
            case HIAHSortFieldUser:
                result = [@(a.uid) compare:@(b.uid)];
                break;
        }
        
        // Apply sort direction
        if (!self.sortAscending) {
            result = -result;
        }
        
        // Secondary sort by PID for stability (Section 4)
        if (result == NSOrderedSame) {
            result = [@(a.pid) compare:@(b.pid)];
        }
        
        return result;
    }];
}

#pragma mark - Filtering (Section 8)

- (NSArray<HIAHManagedProcess *> *)filteredProcesses:(NSArray<HIAHManagedProcess *> *)processes
                                          withFilter:(HIAHProcessFilter *)filter {
    if (!filter) return processes;
    
    return [processes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(HIAHManagedProcess *process, NSDictionary *bindings) {
        return [filter matchesProcess:process];
    }]];
}

- (NSArray<HIAHManagedProcess *> *)processesForUser:(uid_t)uid {
    HIAHProcessFilter *filter = [HIAHProcessFilter defaultFilter];
    filter.userFilter = uid;
    return [self filteredProcesses:self.allProcesses withFilter:filter];
}

#pragma mark - Aggregation (Section 7)

- (HIAHSystemStats *)systemTotals {
    [self.systemStats refresh];
    return self.systemStats;
}

- (NSDictionary<NSNumber *, NSDictionary *> *)userAggregatedStats {
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        NSNumber *uid = @(process.uid);
        NSMutableDictionary *userStats = stats[uid];
        if (!userStats) {
            userStats = [NSMutableDictionary dictionaryWithDictionary:@{
                @"process_count": @0,
                @"thread_count": @0,
                @"cpu_percent": @0.0,
                @"memory_bytes": @0ULL
            }];
            stats[uid] = userStats;
        }
        
        userStats[@"process_count"] = @([userStats[@"process_count"] integerValue] + 1);
        userStats[@"thread_count"] = @([userStats[@"thread_count"] integerValue] + process.threads.count);
        userStats[@"cpu_percent"] = @([userStats[@"cpu_percent"] doubleValue] + process.cpu.totalUsagePercent);
        userStats[@"memory_bytes"] = @([userStats[@"memory_bytes"] unsignedLongLongValue] + process.memory.residentSize);
    }
    
    return stats;
}

/// Get per-group aggregated stats (Section 7)
- (NSDictionary<NSNumber *, NSDictionary *> *)groupAggregatedStats {
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        NSNumber *gid = @(process.gid);
        NSMutableDictionary *groupStats = stats[gid];
        if (!groupStats) {
            groupStats = [NSMutableDictionary dictionaryWithDictionary:@{
                @"process_count": @0,
                @"thread_count": @0,
                @"cpu_percent": @0.0,
                @"memory_bytes": @0ULL
            }];
            stats[gid] = groupStats;
        }
        
        groupStats[@"process_count"] = @([groupStats[@"process_count"] integerValue] + 1);
        groupStats[@"thread_count"] = @([groupStats[@"thread_count"] integerValue] + process.threads.count);
        groupStats[@"cpu_percent"] = @([groupStats[@"cpu_percent"] doubleValue] + process.cpu.totalUsagePercent);
        groupStats[@"memory_bytes"] = @([groupStats[@"memory_bytes"] unsignedLongLongValue] + process.memory.residentSize);
    }
    
    return stats;
}

/// Detect orphaned children (Section 5.3)
- (NSArray<HIAHManagedProcess *> *)detectOrphanedChildren {
    NSMutableArray *orphans = [NSMutableArray array];
    
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        // Check if parent still exists
        HIAHManagedProcess *parent = [self processForPID:process.ppid];
        if (!parent && process.ppid != 1 && process.ppid != 0) {
            // Parent doesn't exist and it's not init/kernel
            [orphans addObject:process];
        }
    }
    
    return orphans;
}

- (double)totalCPUUsage {
    double total = 0;
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        total += process.cpu.totalUsagePercent;
    }
    return total;
}

- (uint64_t)totalMemoryUsage {
    uint64_t total = 0;
    for (HIAHManagedProcess *process in self.processesByPID.allValues) {
        total += process.memory.residentSize;
    }
    return total;
}

#pragma mark - Export (Section 9)

- (NSData *)exportAsJSON {
    NSDictionary *snapshot = [self exportSnapshot];
    NSError *error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    return data;
}

- (NSString *)exportAsText {
    NSMutableString *text = [NSMutableString string];
    
    // Header
    [text appendString:@"  PID  PPID   UID  %CPU  %MEM      RSS STATE    NAME\n"];
    [text appendString:@"───────────────────────────────────────────────────────────────\n"];
    
    // Process lines
    for (HIAHManagedProcess *process in self.processes) {
        [text appendString:[process toTextLine]];
        [text appendString:@"\n"];
    }
    
    // Footer
    [text appendFormat:@"\nTotal: %lu processes, %lu threads\n",
     (unsigned long)self.processCount, (unsigned long)self.threadCount];
    
    return text;
}

- (NSDictionary *)exportSnapshot {
    NSMutableArray *processDicts = [NSMutableArray array];
    for (HIAHManagedProcess *process in self.processes) {
        [processDicts addObject:[process toDictionary]];
    }
    
    return @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"system": [self.systemStats toDictionary],
        @"processes": processDicts,
        @"summary": @{
            @"process_count": @(self.processCount),
            @"thread_count": @(self.threadCount),
            @"total_cpu": @([self totalCPUUsage]),
            @"total_memory": @([self totalMemoryUsage])
        }
    };
}

- (BOOL)exportToFile:(NSString *)path format:(HIAHExportFormat)format error:(NSError **)error {
    NSData *data;
    
    switch (format) {
        case HIAHExportFormatJSON:
            data = [self exportAsJSON];
            break;
        case HIAHExportFormatText:
            data = [[self exportAsText] dataUsingEncoding:NSUTF8StringEncoding];
            break;
        case HIAHExportFormatSnapshot:
            data = [self exportAsJSON];  // Snapshot is also JSON
            break;
    }
    
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHProcessManager"
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate export data"}];
        }
        return NO;
    }
    
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

#pragma mark - CLI/Non-Interactive Mode (Section 9)

- (NSString *)cliOutput {
    return [self cliOutputWithOptions:@{}];
}

- (NSString *)cliOutputWithOptions:(NSDictionary *)options {
    NSMutableString *output = [NSMutableString string];
    
    // Options parsing
    BOOL showHeader = options[@"header"] ? [options[@"header"] boolValue] : YES;
    BOOL showSystemStats = options[@"system"] ? [options[@"system"] boolValue] : YES;
    NSInteger maxProcesses = options[@"limit"] ? [options[@"limit"] integerValue] : 0;
    NSString *format = options[@"format"] ?: @"default";
    
    // System stats header (like top)
    if (showSystemStats) {
        HIAHSystemStats *sys = self.systemStats;
        [sys refresh];
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *timeStr = [formatter stringFromDate:[NSDate date]];
        
        [output appendFormat:@"HIAH Top - %@ up %@\n",
         timeStr, [self formatUptime:sys.bootTime]];
        
        [output appendFormat:@"Processes: %lu total, %lu threads\n",
         (unsigned long)self.processCount, (unsigned long)self.threadCount];
        
        [output appendFormat:@"CPU: %5.1f%% used",
         sys.cpuUsagePercent];
        
        // Per-core breakdown
        if (sys.perCoreUsage.count > 0) {
            [output appendString:@" ["];
            for (NSUInteger i = 0; i < sys.perCoreUsage.count; i++) {
                if (i > 0) [output appendString:@" "];
                [output appendFormat:@"%.0f%%", [sys.perCoreUsage[i] doubleValue]];
            }
            [output appendString:@"]"];
        }
        [output appendString:@"\n"];
        
        [output appendFormat:@"Mem: %@ used / %@ total (%.1f%%)\n",
         [self formatBytes:sys.usedMemory],
         [self formatBytes:sys.totalMemory],
         (sys.totalMemory > 0) ? (double)sys.usedMemory / sys.totalMemory * 100 : 0];
        
        [output appendFormat:@"Load: %.2f %.2f %.2f\n\n",
         sys.loadAverage1, sys.loadAverage5, sys.loadAverage15];
    }
    
    // Process list header
    if (showHeader) {
        if ([format isEqualToString:@"wide"]) {
            [output appendString:@"  PID  PPID   UID STATE     %CPU   %MEM        RSS       VIRT   THR CMD\n"];
            [output appendString:@"-------------------------------------------------------------------------------\n"];
        } else {
            [output appendString:@"  PID  PPID   UID  %CPU  %MEM      RSS STATE    CMD\n"];
            [output appendString:@"---------------------------------------------------------------\n"];
        }
    }
    
    // Process list
    NSArray<HIAHManagedProcess *> *procs = self.processes;
    NSUInteger count = (maxProcesses > 0) ? MIN((NSUInteger)maxProcesses, procs.count) : procs.count;
    
    for (NSUInteger i = 0; i < count; i++) {
        HIAHManagedProcess *p = procs[i];
        
        double memPercent = 0;
        if (self.systemStats.totalMemory > 0) {
            memPercent = (double)p.memory.residentSize / self.systemStats.totalMemory * 100;
        }
        
        if ([format isEqualToString:@"wide"]) {
            [output appendFormat:@"%5d %5d %5d %-9s %5.1f %6.1f %10s %10s %5lu %@\n",
             p.pid,
             p.ppid,
             p.uid,
             [[p stateString] UTF8String],
             p.cpu.totalUsagePercent,
             memPercent,
             [[p.memory formattedResidentSize] UTF8String],
             [[p.memory formattedVirtualSize] UTF8String],
             (unsigned long)p.threads.count,
             p.name];
        } else {
            [output appendFormat:@"%5d %5d %5d %5.1f %5.1f %8s %-8s %@\n",
             p.pid,
             p.ppid,
             p.uid,
             p.cpu.totalUsagePercent,
             memPercent,
             [[p.memory formattedResidentSize] UTF8String],
             [[p stateString] UTF8String],
             p.name];
        }
        
        // Show children in tree mode
        if (self.groupingMode == HIAHGroupingModeTree && p.childPIDs.count > 0) {
            // Children are already in the list following parent in tree mode
        }
    }
    
    return output;
}

- (NSString *)nonInteractiveSample {
    // Perform a single sample
    [self sample];
    
    // Wait for sample to complete (synchronous wrapper)
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(self.processingQueue, ^{
        dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
    
    // Return CLI output
    return [self cliOutput];
}

- (void)printToStdout {
    NSString *output = [self cliOutput];
    printf("%s", [output UTF8String]);
    fflush(stdout);
}

#pragma mark - Formatting Helpers

- (NSString *)formatUptime:(NSDate *)bootTime {
    if (!bootTime) return @"?";
    
    NSTimeInterval uptime = [[NSDate date] timeIntervalSinceDate:bootTime];
    NSInteger days = (NSInteger)(uptime / 86400);
    NSInteger hours = (NSInteger)((NSInteger)uptime % 86400) / 3600;
    NSInteger minutes = (NSInteger)((NSInteger)uptime % 3600) / 60;
    
    if (days > 0) {
        return [NSString stringWithFormat:@"%ldd %ldh %ldm", (long)days, (long)hours, (long)minutes];
    } else if (hours > 0) {
        return [NSString stringWithFormat:@"%ldh %ldm", (long)hours, (long)minutes];
    } else {
        return [NSString stringWithFormat:@"%ldm", (long)minutes];
    }
}

- (NSString *)formatBytes:(uint64_t)bytes {
    if (bytes < 1024) {
        return [NSString stringWithFormat:@"%llu B", bytes];
    } else if (bytes < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f K", bytes / 1024.0];
    } else if (bytes < 1024 * 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f M", bytes / (1024.0 * 1024.0)];
    } else {
        return [NSString stringWithFormat:@"%.2f G", bytes / (1024.0 * 1024.0 * 1024.0)];
    }
}

#pragma mark - Diagnostics (Section 6)

- (NSDictionary *)diagnosticsForProcess:(pid_t)pid {
    HIAHManagedProcess *process = [self processForPID:pid];
    if (!process) return nil;
    
    NSMutableDictionary *diag = [[process toDictionary] mutableCopy];
    diag[@"file_descriptors"] = [[self fileDescriptorsForProcess:pid] valueForKey:@"toDictionary"] ?: @[];
    diag[@"memory_map"] = [self memoryMapForProcess:pid] ?: @[];
    diag[@"stack_sample"] = [self sampleStackForProcess:pid] ?: @[];
    
    return diag;
}

- (NSArray<HIAHFileDescriptor *> *)fileDescriptorsForProcess:(pid_t)pid {
    HIAHManagedProcess *process = [self processForPID:pid];
    if (!process) return nil;
    
    // Use real resource collector
    HIAHResourceCollector *collector = [HIAHResourceCollector sharedCollector];
    NSError *error = nil;
    NSArray<HIAHFileDescriptor *> *fds = [collector fileDescriptorsForPID:pid error:&error];
    
    if (!fds || fds.count == 0) {
        // Fallback to empty array if collection fails
        return @[];
    }
    
    return fds;
}

- (NSArray<NSDictionary *> *)memoryMapForProcess:(pid_t)pid {
    HIAHManagedProcess *process = [self processForPID:pid];
    if (!process) return nil;
    
    // Use real resource collector
    HIAHResourceCollector *collector = [HIAHResourceCollector sharedCollector];
    NSError *error = nil;
    NSArray<NSDictionary *> *maps = [collector memoryMapForPID:pid error:&error];
    
    return maps ?: @[];
}

- (NSArray<NSString *> *)sampleStackForProcess:(pid_t)pid {
    // Use real resource collector
    HIAHResourceCollector *collector = [HIAHResourceCollector sharedCollector];
    NSError *error = nil;
    NSArray<NSString *> *stack = [collector sampleStackForPID:pid error:&error];
    
    return stack ?: @[@"[Stack sampling unavailable]"];
}

@end


