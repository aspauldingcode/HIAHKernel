/**
 * HIAHFilesystem.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Shared filesystem helper for App Group container access.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * HIAHFilesystem provides shared access to the App Group container
 * for storing installed applications and shared data.
 */
@interface HIAHFilesystem : NSObject

/**
 * Shared singleton instance
 */
+ (instancetype)shared;

/**
 * Path to the Applications folder within the shared App Group container.
 * This is where guest iOS apps are installed.
 */
- (NSString *)appsPath;

/**
 * Path to the Documents folder within the shared App Group container.
 */
- (NSString *)documentsPath;

/**
 * Path to the shared App Group container root.
 */
- (NSString *)containerPath;

@end

NS_ASSUME_NONNULL_END
