/**
 * HIAHFilesystem.m
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Shared filesystem helper for App Group container access.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import "HIAHFilesystem.h"

static NSString * const kAppGroup = @"group.com.aspauldingcode.HIAHDesktop";

@implementation HIAHFilesystem

+ (instancetype)shared {
    static HIAHFilesystem *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HIAHFilesystem alloc] init];
    });
    return instance;
}

- (NSString *)containerPath {
    NSURL *containerURL = [[NSFileManager defaultManager] 
        containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    
    if (containerURL) {
        return containerURL.path;
    }
    
    // Fallback to Documents
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

- (NSString *)appsPath {
    NSString *container = [self containerPath];
    NSString *appsPath = [container stringByAppendingPathComponent:@"Applications"];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:appsPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return appsPath;
}

- (NSString *)documentsPath {
    NSString *container = [self containerPath];
    NSString *docsPath = [container stringByAppendingPathComponent:@"Documents"];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:docsPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return docsPath;
}

@end
