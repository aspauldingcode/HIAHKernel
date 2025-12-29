/**
 * HIAHFilesystem.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Virtual Unix filesystem manager for HIAH Desktop.
 * 
 * Primary storage: Documents folder (visible in iOS Files.app)
 * Extension staging: App Group container (for launching .ipa apps)
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HIAHFilesystem : NSObject

/// Shared filesystem instance
+ (instancetype)shared;

/// Root of the virtual filesystem (Documents - visible in Files.app)
@property (nonatomic, readonly) NSString *rootPath;

/// Standard Unix paths (all in Documents)
@property (nonatomic, readonly) NSString *binPath;      // /bin
@property (nonatomic, readonly) NSString *usrBinPath;   // /usr/bin
@property (nonatomic, readonly) NSString *usrLibPath;   // /usr/lib
@property (nonatomic, readonly) NSString *libPath;      // /lib
@property (nonatomic, readonly) NSString *etcPath;      // /etc
@property (nonatomic, readonly) NSString *tmpPath;      // /tmp
@property (nonatomic, readonly) NSString *homePath;     // /home
@property (nonatomic, readonly) NSString *appsPath;     // /Applications

/// Initialize the virtual filesystem (creates all directories)
- (void)initialize;

/// Resolve a virtual path to actual filesystem path
/// e.g., "/bin/bash" -> "<Documents>/bin/bash"
- (nullable NSString *)resolveVirtualPath:(NSString *)virtualPath;

/// Check if a path is within the virtual filesystem
- (BOOL)isVirtualPath:(NSString *)path;

#pragma mark - Extension Staging (App Group)

/// Path to App Group staging area (for extension access)
@property (nonatomic, readonly, nullable) NSString *stagingPath;

/// Stage an app from Documents to App Group for extension access
/// Returns the staged path, or nil on failure
- (nullable NSString *)stageAppForExtension:(NSString *)appPath;

/// Clean up all staged apps
- (void)cleanupStagedApps;

@end

NS_ASSUME_NONNULL_END
