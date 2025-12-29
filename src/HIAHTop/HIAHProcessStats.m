/**
 * HIAHProcessStats.m
 * HIAH Top - Process Statistics Data Model Implementation
 */

#import "HIAHProcessStats.h"
#import <mach/mach.h>
#import <sys/sysctl.h>

#pragma mark - HIAHCPUStats

@implementation HIAHCPUStats

+ (instancetype)stats {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cpuAffinity = -1;
        _niceValue = 0;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    HIAHCPUStats *copy = [[HIAHCPUStats allocWithZone:zone] init];
    copy.totalUsagePercent = self.totalUsagePercent;
    copy.userTimePercent = self.userTimePercent;
    copy.systemTimePercent = self.systemTimePercent;
    copy.userTime = self.userTime;
    copy.systemTime = self.systemTime;
    copy.priority = self.priority;
    copy.niceValue = self.niceValue;
    copy.cpuAffinity = self.cpuAffinity;
    copy.deltaPercent = self.deltaPercent;
    copy.perCoreUsage = [self.perCoreUsage copy];
    return copy;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [@{
        @"total_usage_percent": @(self.totalUsagePercent),
        @"user_time_percent": @(self.userTimePercent),
        @"system_time_percent": @(self.systemTimePercent),
        @"user_time": @(self.userTime),
        @"system_time": @(self.systemTime),
        @"priority": @(self.priority),
        @"nice": @(self.niceValue),
        @"cpu_affinity": @(self.cpuAffinity),
        @"delta_percent": @(self.deltaPercent)
    } mutableCopy];
    
    if (self.perCoreUsage) {
        dict[@"per_core_usage"] = self.perCoreUsage;
    }
    
    return dict;
}

@end

#pragma mark - HIAHMemoryStats

@implementation HIAHMemoryStats

+ (instancetype)stats {
    return [[self alloc] init];
}

- (id)copyWithZone:(NSZone *)zone {
    HIAHMemoryStats *copy = [[HIAHMemoryStats allocWithZone:zone] init];
    copy.residentSize = self.residentSize;
    copy.virtualSize = self.virtualSize;
    copy.sharedSize = self.sharedSize;
    copy.privateSize = self.privateSize;
    copy.minorFaults = self.minorFaults;
    copy.majorFaults = self.majorFaults;
    copy.memoryPressure = self.memoryPressure;
    copy.peakResidentSize = self.peakResidentSize;
    copy.deltaResident = self.deltaResident;
    return copy;
}

- (NSDictionary *)toDictionary {
    return @{
        @"resident_size": @(self.residentSize),
        @"virtual_size": @(self.virtualSize),
        @"shared_size": @(self.sharedSize),
        @"private_size": @(self.privateSize),
        @"minor_faults": @(self.minorFaults),
        @"major_faults": @(self.majorFaults),
        @"memory_pressure": @(self.memoryPressure),
        @"peak_resident_size": @(self.peakResidentSize),
        @"resident_formatted": [self formattedResidentSize],
        @"virtual_formatted": [self formattedVirtualSize]
    };
}

- (NSString *)formattedResidentSize {
    return [self formatBytes:self.residentSize];
}

- (NSString *)formattedVirtualSize {
    return [self formatBytes:self.virtualSize];
}

- (NSString *)formatBytes:(uint64_t)bytes {
    if (bytes < 1024) {
        return [NSString stringWithFormat:@"%llu B", bytes];
    } else if (bytes < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    } else if (bytes < 1024 * 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    } else {
        return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
    }
}

@end

#pragma mark - HIAHIOStats

@implementation HIAHIOStats

+ (instancetype)stats {
    return [[self alloc] init];
}

- (id)copyWithZone:(NSZone *)zone {
    HIAHIOStats *copy = [[HIAHIOStats allocWithZone:zone] init];
    copy.bytesRead = self.bytesRead;
    copy.bytesWritten = self.bytesWritten;
    copy.readOps = self.readOps;
    copy.writeOps = self.writeOps;
    copy.readBytesPerSec = self.readBytesPerSec;
    copy.writeBytesPerSec = self.writeBytesPerSec;
    copy.networkRx = self.networkRx;
    copy.networkTx = self.networkTx;
    copy.isBlocked = self.isBlocked;
    copy.deltaBytesRead = self.deltaBytesRead;
    copy.deltaBytesWritten = self.deltaBytesWritten;
    return copy;
}

- (NSDictionary *)toDictionary {
    return @{
        @"bytes_read": @(self.bytesRead),
        @"bytes_written": @(self.bytesWritten),
        @"read_ops": @(self.readOps),
        @"write_ops": @(self.writeOps),
        @"read_bytes_per_sec": @(self.readBytesPerSec),
        @"write_bytes_per_sec": @(self.writeBytesPerSec),
        @"network_rx": @(self.networkRx),
        @"network_tx": @(self.networkTx),
        @"is_blocked": @(self.isBlocked)
    };
}

@end

#pragma mark - HIAHEnergyStats

@implementation HIAHEnergyStats

+ (instancetype)stats {
    return [[self alloc] init];
}

- (id)copyWithZone:(NSZone *)zone {
    HIAHEnergyStats *copy = [[HIAHEnergyStats allocWithZone:zone] init];
    copy.wakeups = self.wakeups;
    copy.timerFrequency = self.timerFrequency;
    copy.powerScore = self.powerScore;
    copy.energyImpact = self.energyImpact;
    copy.isBackgroundTask = self.isBackgroundTask;
    return copy;
}

- (NSDictionary *)toDictionary {
    return @{
        @"wakeups": @(self.wakeups),
        @"timer_frequency": @(self.timerFrequency),
        @"power_score": @(self.powerScore),
        @"energy_impact": @(self.energyImpact),
        @"is_background_task": @(self.isBackgroundTask)
    };
}

@end

#pragma mark - HIAHThread

@implementation HIAHThread

+ (instancetype)threadWithTID:(uint64_t)tid {
    HIAHThread *thread = [[HIAHThread alloc] init];
    thread.tid = tid;
    thread.cpu = [HIAHCPUStats stats];
    thread.state = HIAHProcessStateUnknown;
    return thread;
}

- (id)copyWithZone:(NSZone *)zone {
    HIAHThread *copy = [[HIAHThread allocWithZone:zone] init];
    copy.tid = self.tid;
    copy.state = self.state;
    copy.cpu = [self.cpu copy];
    copy.priority = self.priority;
    copy.name = self.name;
    return copy;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"tid"] = @(self.tid);
    dict[@"state"] = @(self.state);
    dict[@"priority"] = @(self.priority);
    if (self.name) dict[@"name"] = self.name;
    if (self.cpu) dict[@"cpu"] = [self.cpu toDictionary];
    return dict;
}

@end

#pragma mark - HIAHFileDescriptor

@implementation HIAHFileDescriptor

+ (instancetype)fdWithNumber:(int)fd type:(NSString *)type {
    HIAHFileDescriptor *descriptor = [[HIAHFileDescriptor alloc] init];
    descriptor.fd = fd;
    descriptor.type = type;
    return descriptor;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"fd"] = @(self.fd);
    dict[@"type"] = self.type;
    if (self.path) dict[@"path"] = self.path;
    if (self.details) dict[@"details"] = self.details;
    return dict;
}

@end

#pragma mark - HIAHSystemStats

@implementation HIAHSystemStats

+ (instancetype)currentStats {
    HIAHSystemStats *stats = [[HIAHSystemStats alloc] init];
    [stats refresh];
    return stats;
}

- (void)refresh {
    // Get CPU core count
    host_basic_info_data_t hostInfo;
    mach_msg_type_number_t count = HOST_BASIC_INFO_COUNT;
    if (host_info(mach_host_self(), HOST_BASIC_INFO, (host_info_t)&hostInfo, &count) == KERN_SUCCESS) {
        self.coreCount = hostInfo.logical_cpu;
    }
    
    // Get per-core CPU usage using processor_info
    natural_t numCPUs = 0;
    processor_info_array_t cpuInfoArray;
    mach_msg_type_number_t numCpuInfo;
    
    kern_return_t kr = host_processor_info(mach_host_self(),
                                           PROCESSOR_CPU_LOAD_INFO,
                                           &numCPUs,
                                           &cpuInfoArray,
                                           &numCpuInfo);
    
    if (kr == KERN_SUCCESS) {
        NSMutableArray<NSNumber *> *perCoreUsage = [NSMutableArray arrayWithCapacity:numCPUs];
        double totalUsed = 0;
        double totalTicks = 0;
        
        for (natural_t i = 0; i < numCPUs; i++) {
            processor_cpu_load_info_t cpuLoad = (processor_cpu_load_info_t)cpuInfoArray + i;
            
            uint64_t user = cpuLoad->cpu_ticks[CPU_STATE_USER];
            uint64_t system = cpuLoad->cpu_ticks[CPU_STATE_SYSTEM];
            uint64_t idle = cpuLoad->cpu_ticks[CPU_STATE_IDLE];
            uint64_t nice = cpuLoad->cpu_ticks[CPU_STATE_NICE];
            
            uint64_t total = user + system + idle + nice;
            uint64_t used = user + system + nice;
            
            double coreUsage = (total > 0) ? (double)used / total * 100.0 : 0.0;
            [perCoreUsage addObject:@(coreUsage)];
            
            totalUsed += used;
            totalTicks += total;
        }
        
        self.perCoreUsage = perCoreUsage;
        self.cpuUsagePercent = (totalTicks > 0) ? (double)totalUsed / totalTicks * 100.0 : 0.0;
        
        // Deallocate the CPU info array
        vm_deallocate(mach_task_self(), (vm_address_t)cpuInfoArray, numCpuInfo * sizeof(integer_t));
    } else {
        // Fallback to aggregate CPU stats
        host_cpu_load_info_data_t cpuInfo;
        count = HOST_CPU_LOAD_INFO_COUNT;
        if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, (host_info_t)&cpuInfo, &count) == KERN_SUCCESS) {
            uint64_t total = cpuInfo.cpu_ticks[CPU_STATE_USER] + cpuInfo.cpu_ticks[CPU_STATE_SYSTEM] +
                             cpuInfo.cpu_ticks[CPU_STATE_IDLE] + cpuInfo.cpu_ticks[CPU_STATE_NICE];
            uint64_t used = cpuInfo.cpu_ticks[CPU_STATE_USER] + cpuInfo.cpu_ticks[CPU_STATE_SYSTEM] +
                            cpuInfo.cpu_ticks[CPU_STATE_NICE];
            self.cpuUsagePercent = (total > 0) ? (double)used / total * 100.0 : 0.0;
        }
    }
    
    // Get memory info
    vm_size_t pageSize;
    host_page_size(mach_host_self(), &pageSize);
    
    vm_statistics64_data_t vmStats;
    count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vmStats, &count) == KERN_SUCCESS) {
        self.freeMemory = (uint64_t)vmStats.free_count * pageSize;
        uint64_t active = (uint64_t)vmStats.active_count * pageSize;
        uint64_t inactive = (uint64_t)vmStats.inactive_count * pageSize;
        uint64_t wired = (uint64_t)vmStats.wire_count * pageSize;
        self.usedMemory = active + wired;
        self.totalMemory = self.freeMemory + active + inactive + wired;
    }
    
    // Get load averages
    double loadAvg[3];
    if (getloadavg(loadAvg, 3) != -1) {
        self.loadAverage1 = loadAvg[0];
        self.loadAverage5 = loadAvg[1];
        self.loadAverage15 = loadAvg[2];
    }
    
    // Get boot time
    struct timeval boottime;
    size_t size = sizeof(boottime);
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &boottime, &size, NULL, 0) == 0) {
        self.bootTime = [NSDate dateWithTimeIntervalSince1970:boottime.tv_sec];
    }
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"cpu_usage_percent"] = @(self.cpuUsagePercent);
    dict[@"core_count"] = @(self.coreCount);
    if (self.perCoreUsage) {
        dict[@"per_core_usage"] = self.perCoreUsage;
    }
    dict[@"total_memory"] = @(self.totalMemory);
    dict[@"used_memory"] = @(self.usedMemory);
    dict[@"free_memory"] = @(self.freeMemory);
    dict[@"swap_used"] = @(self.swapUsed);
    dict[@"swap_total"] = @(self.swapTotal);
    dict[@"load_average_1"] = @(self.loadAverage1);
    dict[@"load_average_5"] = @(self.loadAverage5);
    dict[@"load_average_15"] = @(self.loadAverage15);
    dict[@"process_count"] = @(self.processCount);
    dict[@"thread_count"] = @(self.threadCount);
    if (self.bootTime) dict[@"boot_time"] = @([self.bootTime timeIntervalSince1970]);
    return dict;
}

@end

