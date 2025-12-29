/**
 * HIAHKernelBridge.h
 * Objective-C bridge for Swift to access HIAH Kernel
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HIAHKernelBridge : NSObject

+ (instancetype)shared;

- (void)spawnProcessWithExecutable:(NSString *)executable
                          arguments:(NSArray<NSString *> *)arguments
                        environment:(NSDictionary<NSString *, NSString *> *)environment
                   workingDirectory:(NSString *)workingDirectory
                         completion:(void (^)(NSString * _Nullable output, NSString * _Nullable error, NSNumber * _Nullable exitCode))completion;

@end

NS_ASSUME_NONNULL_END

