/**
 * HIAHResourceCollector.m
 * HIAH Top - Real Resource Collection Implementation
 *
 * Uses proc_pidinfo, task_info, thread_info, and sysctl APIs.
 */

#import "HIAHResourceCollector.h"
#import <mach/mach.h>
#import <mach/task_info.h>
#import <mach/thread_info.h>
#import <mach/thread_act.h>
#import <mach/vm_map.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <errno.h>
#import <string.h>
#import <execinfo.h>

// proc_pidinfo structure definitions and function declarations
// These are from libproc.h which isn't available in iOS SDK, so we define them manually
#ifndef PROC_PIDTASKINFO
#define PROC_PIDTASKINFO      4
#define PROC_PIDTBSDINFO      3
#define PROC_PIDLISTFDS       5
#endif

#ifndef MAXCOMLEN
#define MAXCOMLEN 16
#endif

// BSD process status constants
#define SIDL    1
#define SRUN    2
#define SSLEEP  3
#define SSTOP   4
#define SZOMB   5

// Function declaration for proc_pidinfo (from libproc)
extern int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);

struct proc_taskinfo {
    uint64_t    pti_virtual_size;      // virtual memory size (bytes)
    uint64_t    pti_resident_size;     // resident memory size (bytes)
    uint64_t    pti_total_user;        // total time in user mode
    uint64_t    pti_total_system;      // total time in system mode
    uint64_t    pti_threads_user;       // aggregate time of all threads in user mode
    uint64_t    pti_threads_system;    // aggregate time of all threads in system mode
    int32_t     pti_policy;            // default policy for new threads
    int32_t     pti_faults;            // number of page faults
    int32_t     pti_pageins;           // number of actual pageins
    int32_t     pti_cow_faults;        // number of copy-on-write faults
    int32_t     pti_messages_sent;     // number of messages sent
    int32_t     pti_messages_received; // number of messages received
    int32_t     pti_syscalls_mach;     // number of mach system calls
    int32_t     pti_syscalls_unix;     // number of unix system calls
    int32_t     pti_csw;               // number of context switches
    int32_t     pti_threadnum;         // number of threads
    int32_t     pti_numrunning;        // number of running threads
    int32_t     pti_priority;           // task priority
};

struct proc_bsdinfo {
    uint32_t    pbi_flags;              // process flags
    uint32_t    pbi_status;             // process status
    uid_t       pbi_uid;                // user ID
    gid_t       pbi_gid;                // group ID
    pid_t       pbi_pid;                // process ID
    pid_t       pbi_ppid;               // parent process ID
    pid_t       pbi_pgid;               // process group ID
    pid_t       pbi_sid;                // session ID
    uint32_t    pbi_ruid;               // real user ID
    uint32_t    pbi_rgid;               // real group ID
    uint32_t    pbi_svuid;              // saved user ID
    uint32_t    pbi_svgid;              // saved group ID
    char        pbi_comm[MAXCOMLEN+1];  // command name
    char        pbi_name[MAXCOMLEN*2+1]; // full process name
    char        pbi_nfiles;             // number of open files
    uint32_t    pbi_pgfltcnt;           // page fault count
    uint32_t    pbi_pgfltcnt_peak;      // peak page fault count
    uint64_t    pbi_system_time;        // system time
    uint64_t    pbi_user_time;          // user time
};

struct proc_fdinfo {
    int32_t     proc_fd;                // file descriptor number
    uint32_t    proc_fdtype;            // file descriptor type
};

#define PROC_PIDTASKINFO      4
#define PROC_PIDTBSDINFO      3
#define PROC_PIDLISTFDS       5

@interface HIAHResourceCollector ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDate *> *lastSampleTime;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *lastTaskInfo;
@end

@implementation HIAHResourceCollector

+ (instancetype)sharedCollector {
    static HIAHResourceCollector *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastSampleTime = [NSMutableDictionary dictionary];
        _lastTaskInfo = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Process Statistics

- (BOOL)collectCPUStats:(HIAHCPUStats *)stats forPID:(pid_t)pid error:(NSError **)error {
    struct proc_taskinfo taskInfo;
    int ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, sizeof(taskInfo));
    
    if (ret <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHResourceCollector"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"proc_pidinfo failed: %s", strerror(errno)]}];
        }
        return NO;
    }
    
    // Get previous sample for delta calculation
    NSNumber *pidKey = @(pid);
    NSDate *now = [NSDate date];
    NSDate *lastTime = self.lastSampleTime[pidKey];
    struct proc_taskinfo lastInfo = {0};
    struct proc_taskinfo *lastInfoPtr = NULL;
    
    NSValue *lastValue = self.lastTaskInfo[pidKey];
    if (lastValue) {
        [lastValue getValue:&lastInfo];
        lastInfoPtr = &lastInfo;
    }
    
    // Calculate CPU usage percentage
    if (lastInfoPtr && lastTime) {
        NSTimeInterval timeDelta = [now timeIntervalSinceDate:lastTime];
        if (timeDelta > 0) {
            uint64_t userDelta = taskInfo.pti_total_user - lastInfoPtr->pti_total_user;
            uint64_t systemDelta = taskInfo.pti_total_system - lastInfoPtr->pti_total_system;
            uint64_t totalDelta = userDelta + systemDelta;
            
            // Convert to percentage (assuming 1 tick = 1/1000000 second)
            double cpuPercent = (double)totalDelta / (timeDelta * 1000000.0) * 100.0;
            stats.totalUsagePercent = MIN(100.0, cpuPercent);
            stats.userTimePercent = (double)userDelta / (timeDelta * 1000000.0) * 100.0;
            stats.systemTimePercent = (double)systemDelta / (timeDelta * 1000000.0) * 100.0;
            stats.deltaPercent = stats.totalUsagePercent;
        }
    }
    
    // Store absolute values
    stats.userTime = taskInfo.pti_total_user;
    stats.systemTime = taskInfo.pti_total_system;
    stats.priority = taskInfo.pti_priority;
    
    // Get nice value via sysctl
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    struct kinfo_proc kinfo;
    size_t size = sizeof(kinfo);
    if (sysctl(mib, 4, &kinfo, &size, NULL, 0) == 0) {
        stats.niceValue = kinfo.kp_proc.p_nice;
    }
    
    // Store for next delta calculation
    NSValue *taskInfoValue = [NSValue valueWithBytes:&taskInfo objCType:@encode(struct proc_taskinfo)];
    self.lastTaskInfo[pidKey] = taskInfoValue;
    self.lastSampleTime[pidKey] = now;
    
    return YES;
}

- (BOOL)collectMemoryStats:(HIAHMemoryStats *)stats forPID:(pid_t)pid error:(NSError **)error {
    struct proc_taskinfo taskInfo;
    int ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, sizeof(taskInfo));
    
    if (ret <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHResourceCollector"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"proc_pidinfo failed"}];
        }
        return NO;
    }
    
    stats.residentSize = taskInfo.pti_resident_size;
    stats.virtualSize = taskInfo.pti_virtual_size;
    stats.minorFaults = taskInfo.pti_faults;
    stats.majorFaults = taskInfo.pti_pageins;
    
    // Try to get more detailed memory info via task_info
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr == KERN_SUCCESS) {
        task_vm_info_data_t vmInfo;
        mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        kr = task_info(task, TASK_VM_INFO, (task_info_t)&vmInfo, &count);
        if (kr == KERN_SUCCESS) {
            stats.privateSize = vmInfo.phys_footprint;
            stats.sharedSize = stats.residentSize - stats.privateSize;
            
            // Calculate memory pressure (simplified)
            vm_size_t pageSize;
            host_page_size(mach_host_self(), &pageSize);
            uint64_t totalMemory = vmInfo.virtual_size;
            stats.memoryPressure = (totalMemory > 0) ? (double)stats.residentSize / totalMemory : 0.0;
        }
        mach_port_deallocate(mach_task_self(), task);
    }
    
    // Track peak RSS
    if (stats.residentSize > stats.peakResidentSize) {
        stats.peakResidentSize = stats.residentSize;
    }
    
    return YES;
}

- (BOOL)collectIOStats:(HIAHIOStats *)stats forPID:(pid_t)pid error:(NSError **)error {
    // proc_pidinfo doesn't provide I/O stats directly
    // We'll use task_info for some I/O info
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    
    if (kr == KERN_SUCCESS) {
        task_events_info_data_t eventsInfo;
        mach_msg_type_number_t count = TASK_EVENTS_INFO_COUNT;
        kr = task_info(task, TASK_EVENTS_INFO, (task_info_t)&eventsInfo, &count);
        if (kr == KERN_SUCCESS) {
            // These are cumulative counts
            stats.readOps = eventsInfo.faults;  // Page faults as proxy for I/O
            // Note: pageouts field may not exist in all iOS versions
            stats.writeOps = 0;  // Will be populated if available
        }
        mach_port_deallocate(mach_task_self(), task);
    }
    
    // Note: Detailed disk I/O stats require additional privileges or monitoring
    // For now, we track what's available
    
    return YES;
}

- (BOOL)collectEnergyStats:(HIAHEnergyStats *)stats forPID:(pid_t)pid error:(NSError **)error {
    // Energy stats require special APIs on iOS
    // For now, use task_info for wakeup estimation
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    
    if (kr == KERN_SUCCESS) {
        task_events_info_data_t eventsInfo;
        mach_msg_type_number_t count = TASK_EVENTS_INFO_COUNT;
        kr = task_info(task, TASK_EVENTS_INFO, (task_info_t)&eventsInfo, &count);
        if (kr == KERN_SUCCESS) {
            // Use interrupts as proxy for wakeups
            stats.wakeups = eventsInfo.csw;  // Context switches
        }
        mach_port_deallocate(mach_task_self(), task);
    }
    
    return YES;
}

- (BOOL)collectAllStatsForProcess:(HIAHManagedProcess *)process error:(NSError **)error {
    pid_t pid = process.pid;
    
    // Collect CPU stats
    NSError *cpuError = nil;
    if (![self collectCPUStats:process.cpu forPID:pid error:&cpuError]) {
        if (error) *error = cpuError;
        return NO;
    }
    
    // Collect memory stats
    NSError *memError = nil;
    if (![self collectMemoryStats:process.memory forPID:pid error:&memError]) {
        // Memory stats failure is non-fatal
        process.hasLimitedAccess = YES;
    }
    
    // Collect I/O stats
    [self collectIOStats:process.io forPID:pid error:nil];
    
    // Collect energy stats
    [self collectEnergyStats:process.energy forPID:pid error:nil];
    
    // Collect thread stats
    NSError *threadError = nil;
    NSArray<HIAHThread *> *threads = [self collectThreadStatsForPID:pid error:&threadError];
    if (threads) {
        process.threads = [threads mutableCopy];
    }
    
    return YES;
}

#pragma mark - Thread Statistics

- (NSArray<HIAHThread *> *)collectThreadStatsForPID:(pid_t)pid error:(NSError **)error {
    NSMutableArray<HIAHThread *> *threads = [NSMutableArray array];
    
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHResourceCollector"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"task_for_pid failed"}];
        }
        return nil;
    }
    
    thread_act_array_t threadList;
    mach_msg_type_number_t threadCount;
    kr = task_threads(task, &threadList, &threadCount);
    
    if (kr == KERN_SUCCESS) {
        for (mach_msg_type_number_t i = 0; i < threadCount; i++) {
            thread_basic_info_data_t threadInfo;
            mach_msg_type_number_t infoCount = THREAD_BASIC_INFO_COUNT;
            kr = thread_info(threadList[i], THREAD_BASIC_INFO, (thread_info_t)&threadInfo, &infoCount);
            
            if (kr == KERN_SUCCESS) {
                HIAHThread *thread = [HIAHThread threadWithTID:threadList[i]];
                thread.cpu.userTime = threadInfo.user_time.seconds * 1000000 + threadInfo.user_time.microseconds;
                thread.cpu.systemTime = threadInfo.system_time.seconds * 1000000 + threadInfo.system_time.microseconds;
                thread.priority = threadInfo.policy;
                
                // Map thread state
                switch (threadInfo.run_state) {
                    case TH_STATE_RUNNING:
                        thread.state = HIAHProcessStateRunning;
                        break;
                    case TH_STATE_STOPPED:
                        thread.state = HIAHProcessStateStopped;
                        break;
                    case TH_STATE_WAITING:
                        thread.state = HIAHProcessStateSleeping;
                        break;
                    default:
                        thread.state = HIAHProcessStateUnknown;
                        break;
                }
                
                [threads addObject:thread];
            }
        }
        
        // Deallocate thread list
        vm_deallocate(mach_task_self(), (vm_address_t)threadList, threadCount * sizeof(thread_act_t));
    }
    
    mach_port_deallocate(mach_task_self(), task);
    
    return threads;
}

#pragma mark - Process Info

- (BOOL)collectProcessInfo:(HIAHManagedProcess *)process error:(NSError **)error {
    struct proc_bsdinfo bsdInfo;
    int ret = proc_pidinfo(process.pid, PROC_PIDTBSDINFO, 0, &bsdInfo, sizeof(bsdInfo));
    
    if (ret <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHResourceCollector"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"proc_pidinfo failed"}];
        }
        return NO;
    }
    
    process.ppid = bsdInfo.pbi_ppid;
    process.pgid = bsdInfo.pbi_pgid;
    process.sid = bsdInfo.pbi_sid;
    process.uid = bsdInfo.pbi_uid;
    process.gid = bsdInfo.pbi_gid;
    
    // Map process status to our state enum
    process.state = [self processStateForPID:process.pid];
    
    return YES;
}

- (HIAHProcessState)processStateForPID:(pid_t)pid {
    struct proc_bsdinfo bsdInfo;
    int ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, sizeof(bsdInfo));
    
    if (ret <= 0) {
        return HIAHProcessStateUnknown;
    }
    
    // Map BSD process status to our state
    switch (bsdInfo.pbi_status) {
        case SIDL:   // Process being created
            return HIAHProcessStateRunning;
        case SRUN:   // Runnable
            return HIAHProcessStateRunning;
        case SSLEEP: // Sleeping
            return HIAHProcessStateSleeping;
        case SSTOP:  // Stopped
            return HIAHProcessStateStopped;
        case SZOMB:  // Zombie
            return HIAHProcessStateZombie;
        default:
            return HIAHProcessStateUnknown;
    }
}

#pragma mark - Diagnostics

- (NSArray<HIAHFileDescriptor *> *)fileDescriptorsForPID:(pid_t)pid error:(NSError **)error {
    NSMutableArray<HIAHFileDescriptor *> *fds = [NSMutableArray array];
    
    // Get FD count first
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    struct kinfo_proc kinfo;
    size_t size = sizeof(kinfo);
    if (sysctl(mib, 4, &kinfo, &size, NULL, 0) != 0) {
        return fds;
    }
    
    // Try to enumerate FDs (requires privileges)
    // Note: proc_pidinfo PROC_PIDLISTFDS may not be available on iOS
    // This is a best-effort implementation
    
    return fds;
}

- (NSArray<NSDictionary *> *)memoryMapForPID:(pid_t)pid error:(NSError **)error {
    NSMutableArray<NSDictionary *> *regions = [NSMutableArray array];
    
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS) {
        return regions;
    }
    
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName;
    
    while (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &infoCount, &objectName) == KERN_SUCCESS) {
        NSString *protection = @"";
        if (info.protection & VM_PROT_READ) protection = [protection stringByAppendingString:@"r"];
        if (info.protection & VM_PROT_WRITE) protection = [protection stringByAppendingString:@"w"];
        if (info.protection & VM_PROT_EXECUTE) protection = [protection stringByAppendingString:@"x"];
        
        [regions addObject:@{
            @"start": [NSString stringWithFormat:@"0x%llx", (unsigned long long)address],
            @"size": [NSString stringWithFormat:@"%llu bytes", (unsigned long long)size],
            @"permissions": protection,
            @"shared": @(info.shared),
            @"reserved": @(info.reserved)
        }];
        
        address += size;
        size = 0;
    }
    
    mach_port_deallocate(mach_task_self(), task);
    
    return regions;
}

- (NSArray<NSString *> *)sampleStackForPID:(pid_t)pid error:(NSError **)error {
    NSMutableArray<NSString *> *stackFrames = [NSMutableArray array];
    
    // Get task port for the process
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    
    if (kr != KERN_SUCCESS) {
        // For sandboxed iOS apps, task_for_pid often fails
        // Use fallback: we can only sample our own process or child processes
        if (pid == getpid()) {
            // Sample current process using backtrace
            void *callstack[128];
            int frames = backtrace(callstack, 128);
            char **symbols = backtrace_symbols(callstack, frames);
            
            if (symbols) {
                for (int i = 0; i < frames; i++) {
                    [stackFrames addObject:[NSString stringWithFormat:@"frame #%d: %s", i, symbols[i]]];
                }
                free(symbols);
            }
        } else {
            // Cannot sample external process without task port
            if (error) {
                *error = [NSError errorWithDomain:@"HIAHResourceCollector"
                                             code:11
                                         userInfo:@{NSLocalizedDescriptionKey: 
                                             @"Cannot sample stack: task_for_pid denied (sandbox restriction)"}];
            }
            [stackFrames addObject:@"[Stack sampling requires task_for_pid access]"];
            [stackFrames addObject:@"[Consider using virtual process sampling instead]"];
            return stackFrames;
        }
        return stackFrames;
    }
    
    // Get threads for the task
    thread_act_array_t threadList;
    mach_msg_type_number_t threadCount;
    kr = task_threads(task, &threadList, &threadCount);
    
    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), task);
        if (error) {
            *error = [NSError errorWithDomain:@"HIAHResourceCollector"
                                         code:12
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to enumerate threads"}];
        }
        return @[@"[Failed to enumerate threads]"];
    }
    
    // Sample each thread
    for (mach_msg_type_number_t i = 0; i < threadCount && i < 8; i++) { // Limit to 8 threads
        thread_act_t thread = threadList[i];
        
        // Suspend thread for sampling (required for accurate stack trace)
        thread_suspend(thread);
        
        // Get thread state
#if defined(__arm64__) || defined(__aarch64__)
        arm_thread_state64_t state;
        mach_msg_type_number_t stateCount = ARM_THREAD_STATE64_COUNT;
        kr = thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, &stateCount);
        
        if (kr == KERN_SUCCESS) {
            uint64_t pc = arm_thread_state64_get_pc(state);
            uint64_t fp = arm_thread_state64_get_fp(state);
            uint64_t lr = arm_thread_state64_get_lr(state);
            
            [stackFrames addObject:[NSString stringWithFormat:@"--- Thread %d ---", i]];
            [stackFrames addObject:[NSString stringWithFormat:@"frame #0: pc=0x%llx", pc]];
            [stackFrames addObject:[NSString stringWithFormat:@"frame #1: lr=0x%llx (return addr)", lr]];
            
            // Walk the frame pointer chain
            uint64_t currentFP = fp;
            int frameNum = 2;
            int maxFrames = 16;
            
            while (currentFP != 0 && frameNum < maxFrames) {
                // Read frame pointer and return address from stack
                uint64_t frameData[2] = {0, 0}; // [saved fp, return addr]
                vm_size_t bytesRead = 0;
                
                kr = vm_read_overwrite(task, currentFP, sizeof(frameData),
                                       (vm_address_t)frameData, &bytesRead);
                
                if (kr != KERN_SUCCESS || bytesRead != sizeof(frameData)) {
                    break;
                }
                
                uint64_t savedFP = frameData[0];
                uint64_t returnAddr = frameData[1];
                
                if (returnAddr != 0) {
                    [stackFrames addObject:[NSString stringWithFormat:@"frame #%d: 0x%llx", 
                                           frameNum, returnAddr]];
                }
                
                // Move to next frame
                if (savedFP == 0 || savedFP == currentFP) {
                    break; // End of stack or invalid frame
                }
                currentFP = savedFP;
                frameNum++;
            }
        }
#elif defined(__x86_64__)
        x86_thread_state64_t state;
        mach_msg_type_number_t stateCount = x86_THREAD_STATE64_COUNT;
        kr = thread_get_state(thread, x86_THREAD_STATE64, (thread_state_t)&state, &stateCount);
        
        if (kr == KERN_SUCCESS) {
            [stackFrames addObject:[NSString stringWithFormat:@"--- Thread %d ---", i]];
            [stackFrames addObject:[NSString stringWithFormat:@"frame #0: rip=0x%llx", state.__rip]];
            
            // Walk x86_64 stack frames
            uint64_t currentFP = state.__rbp;
            int frameNum = 1;
            int maxFrames = 16;
            
            while (currentFP != 0 && frameNum < maxFrames) {
                uint64_t frameData[2] = {0, 0};
                vm_size_t bytesRead = 0;
                
                kr = vm_read_overwrite(task, currentFP, sizeof(frameData),
                                       (vm_address_t)frameData, &bytesRead);
                
                if (kr != KERN_SUCCESS || bytesRead != sizeof(frameData)) {
                    break;
                }
                
                uint64_t savedFP = frameData[0];
                uint64_t returnAddr = frameData[1];
                
                if (returnAddr != 0) {
                    [stackFrames addObject:[NSString stringWithFormat:@"frame #%d: 0x%llx", 
                                           frameNum, returnAddr]];
                }
                
                if (savedFP == 0 || savedFP == currentFP) {
                    break;
                }
                currentFP = savedFP;
                frameNum++;
            }
        }
#endif
        
        // Resume thread
        thread_resume(thread);
        mach_port_deallocate(mach_task_self(), thread);
    }
    
    // Clean up remaining thread ports
    for (mach_msg_type_number_t i = 8; i < threadCount; i++) {
        mach_port_deallocate(mach_task_self(), threadList[i]);
    }
    
    vm_deallocate(mach_task_self(), (vm_address_t)threadList, threadCount * sizeof(thread_act_t));
    mach_port_deallocate(mach_task_self(), task);
    
    if (stackFrames.count == 0) {
        [stackFrames addObject:@"[No stack frames captured]"];
    }
    
    return stackFrames;
}

#pragma mark - Privilege Checking (Section 12)

- (BOOL)canAccessProcess:(pid_t)pid {
    struct proc_bsdinfo bsdInfo;
    int ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, sizeof(bsdInfo));
    return ret > 0;
}

- (BOOL)canSignalProcess:(pid_t)pid {
    // Check if we can signal by attempting to send signal 0 (no-op)
    int result = kill(pid, 0);
    if (result == 0) return YES;
    // EPERM means process exists but we lack permission
    // ESRCH means process doesn't exist
    return errno == EPERM;
}

- (BOOL)canGetTaskPortForProcess:(pid_t)pid {
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr == KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), task);
        return YES;
    }
    return NO;
}

- (NSDictionary *)privilegeLevelForProcess:(pid_t)pid {
    NSMutableDictionary *privs = [NSMutableDictionary dictionary];
    
    // Basic process info (proc_pidinfo)
    struct proc_bsdinfo bsdInfo;
    privs[@"canReadBasicInfo"] = @(proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, sizeof(bsdInfo)) > 0);
    
    // Task info (requires task_for_pid)
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    privs[@"canGetTaskPort"] = @(kr == KERN_SUCCESS);
    
    if (kr == KERN_SUCCESS) {
        // Memory stats (task_info)
        task_vm_info_data_t vmInfo;
        mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        privs[@"canReadMemoryStats"] = @(task_info(task, TASK_VM_INFO, (task_info_t)&vmInfo, &count) == KERN_SUCCESS);
        
        // Thread enumeration
        thread_act_array_t threadList;
        mach_msg_type_number_t threadCount;
        kr = task_threads(task, &threadList, &threadCount);
        privs[@"canEnumerateThreads"] = @(kr == KERN_SUCCESS);
        if (kr == KERN_SUCCESS) {
            vm_deallocate(mach_task_self(), (vm_address_t)threadList, threadCount * sizeof(thread_act_t));
        }
        
        // Memory maps
        vm_address_t address = 0;
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t objectName;
        privs[@"canReadMemoryMaps"] = @(vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO,
                                                      (vm_region_info_t)&info, &infoCount, &objectName) == KERN_SUCCESS);
        
        mach_port_deallocate(mach_task_self(), task);
    } else {
        privs[@"canReadMemoryStats"] = @NO;
        privs[@"canEnumerateThreads"] = @NO;
        privs[@"canReadMemoryMaps"] = @NO;
    }
    
    // Signal capability
    privs[@"canSignal"] = @([self canSignalProcess:pid]);
    
    // Scheduling (requires privileges)
    privs[@"canAdjustPriority"] = @(getuid() == 0 || geteuid() == 0);
    
    // Overall access level
    BOOL fullAccess = [privs[@"canGetTaskPort"] boolValue];
    BOOL basicAccess = [privs[@"canReadBasicInfo"] boolValue];
    
    if (fullAccess) {
        privs[@"accessLevel"] = @"full";
    } else if (basicAccess) {
        privs[@"accessLevel"] = @"basic";
    } else {
        privs[@"accessLevel"] = @"none";
    }
    
    return privs;
}

- (NSString *)accessLimitationsForProcess:(pid_t)pid {
    NSDictionary *privs = [self privilegeLevelForProcess:pid];
    NSMutableArray *limitations = [NSMutableArray array];
    
    if (![privs[@"canGetTaskPort"] boolValue]) {
        [limitations addObject:@"Cannot access detailed memory/thread stats (task_for_pid denied)"];
    }
    if (![privs[@"canReadBasicInfo"] boolValue]) {
        [limitations addObject:@"Cannot read basic process info (proc_pidinfo denied)"];
    }
    if (![privs[@"canSignal"] boolValue]) {
        [limitations addObject:@"Cannot send signals to this process"];
    }
    if (![privs[@"canEnumerateThreads"] boolValue]) {
        [limitations addObject:@"Cannot enumerate threads"];
    }
    if (![privs[@"canReadMemoryMaps"] boolValue]) {
        [limitations addObject:@"Cannot read memory maps"];
    }
    if (![privs[@"canAdjustPriority"] boolValue]) {
        [limitations addObject:@"Cannot adjust process priority (not root)"];
    }
    
    if (limitations.count == 0) {
        return @"Full access";
    }
    
    return [NSString stringWithFormat:@"Limited access:\n  - %@",
            [limitations componentsJoinedByString:@"\n  - "]];
}

@end

