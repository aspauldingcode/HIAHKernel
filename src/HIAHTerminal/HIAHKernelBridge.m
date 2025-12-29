/**
 * HIAHKernelBridge.m
 * Objective-C bridge implementation for Swift to access HIAH Kernel
 */

#import "HIAHKernelBridge.h"
#import "../HIAHKernel.h"

@implementation HIAHKernelBridge

+ (instancetype)shared {
    static HIAHKernelBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)spawnProcessWithExecutable:(NSString *)executable
                          arguments:(NSArray<NSString *> *)arguments
                        environment:(NSDictionary<NSString *, NSString *> *)environment
                   workingDirectory:(NSString *)workingDirectory
                         completion:(void (^)(NSString * _Nullable output, NSString * _Nullable error, NSNumber * _Nullable exitCode))completion {
    
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    
    // Resolve executable path in virtual filesystem
    NSString *resolvedPath = executable;
    if (![executable hasPrefix:@"/"]) {
        // Try to find in PATH
        NSString *pathEnv = environment[@"PATH"] ?: @"";
        NSArray<NSString *> *pathComponents = [pathEnv componentsSeparatedByString:@":"];
        
        for (NSString *pathComponent in pathComponents) {
            NSString *fullPath = [pathComponent stringByAppendingPathComponent:executable];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
                resolvedPath = fullPath;
                break;
            }
        }
    }
    
    // Convert arguments array
    NSMutableArray<NSString *> *argsArray = [arguments mutableCopy];
    
    // Spawn process via HIAH Kernel
    // Note: HIAHKernel doesn't support workingDirectory parameter
    [kernel spawnVirtualProcessWithPath:resolvedPath
                              arguments:argsArray
                            environment:environment
                             completion:^(pid_t pid, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error.localizedDescription, nil);
            }
            return;
        }
        
        // For now, we don't capture output synchronously
        // In a real implementation, you'd set up pipes to capture stdout/stderr
        // and monitor the process until it exits
        
        // Simulate completion for now
        if (completion) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                completion(@"Process spawned successfully", nil, @0);
            });
        }
    }];
}

@end

