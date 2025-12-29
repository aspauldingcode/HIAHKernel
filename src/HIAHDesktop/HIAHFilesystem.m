/**
 * HIAHFilesystem.m
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Virtual Unix filesystem implementation.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import "HIAHFilesystem.h"
#import "HIAHMachOUtils.h"
#import "HIAHLogging.h"
#import <sys/stat.h>

static NSString * const kHIAHAppGroupIdentifier = @"group.com.aspauldingcode.HIAHDesktop";

@interface HIAHFilesystem ()
@property (nonatomic, strong) NSString *appGroupPath;
@end

@implementation HIAHFilesystem

+ (instancetype)shared {
    static HIAHFilesystem *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
        [instance initialize];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _rootPath = paths.firstObject;
        
        NSURL *groupURL = [[NSFileManager defaultManager] 
                           containerURLForSecurityApplicationGroupIdentifier:kHIAHAppGroupIdentifier];
        if (groupURL) {
            _appGroupPath = groupURL.path;
        } else {
            HIAHLogError(HIAHLogFilesystem, "App Group not available - .ipa loading will not work");
            _appGroupPath = nil;
        }
    }
    return self;
}

- (void)initialize {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSArray *directories = @[
        @"bin", @"sbin", @"usr/bin", @"usr/sbin", @"usr/lib", @"usr/share",
        @"usr/local/bin", @"usr/local/lib", @"lib", @"etc", @"tmp",
        @"var/tmp", @"var/log", @"home", @"Applications", @"dev", @"proc"
    ];
    
    for (NSString *dir in directories) {
        NSString *fullPath = [self.rootPath stringByAppendingPathComponent:dir];
        if (![fm fileExistsAtPath:fullPath]) {
            NSError *error = nil;
            [fm createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                HIAHLogError(HIAHLogFilesystem, "Failed to create directory %s: %s", [dir UTF8String], error ? [[error description] UTF8String] : "(null)");
            }
        }
    }
    
    if (self.appGroupPath) {
        NSString *stagingPath = [self.appGroupPath stringByAppendingPathComponent:@"staging"];
        if (![fm fileExistsAtPath:stagingPath]) {
            [fm createDirectoryAtPath:stagingPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    
    [self installBundledBinaries];
    [self installBundledApps];
    
    HIAHLogInfo(HIAHLogFilesystem, "Virtual filesystem initialized at %s", [self.rootPath UTF8String]);
}

- (void)installBundledBinaries {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *bundledBinPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"bin"];
        NSString *bundledUsrBinPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"usr/bin"];
        
        if ([fm fileExistsAtPath:bundledBinPath]) {
            NSArray *binaries = [fm contentsOfDirectoryAtPath:bundledBinPath error:nil];
            for (NSString *binary in binaries) {
                NSString *source = [bundledBinPath stringByAppendingPathComponent:binary];
                NSString *dest = [self.binPath stringByAppendingPathComponent:binary];
                
                if (![fm fileExistsAtPath:dest]) {
                    [fm copyItemAtPath:source toPath:dest error:nil];
                    chmod([dest UTF8String], 0755);
                    [HIAHMachOUtils patchBinaryToDylib:dest];
                }
            }
        }
        
        if ([fm fileExistsAtPath:bundledUsrBinPath]) {
            NSArray *binaries = [fm contentsOfDirectoryAtPath:bundledUsrBinPath error:nil];
            for (NSString *binary in binaries) {
                NSString *source = [bundledUsrBinPath stringByAppendingPathComponent:binary];
                NSString *dest = [self.usrBinPath stringByAppendingPathComponent:binary];
                
                if (![fm fileExistsAtPath:dest]) {
                    [fm copyItemAtPath:source toPath:dest error:nil];
                    chmod([dest UTF8String], 0755);
                }
            }
        }
    } @catch (NSException *exception) {
        HIAHLogError(HIAHLogFilesystem, "Exception during binary installation: %s", [[exception description] UTF8String]);
    }
}

- (void)installBundledApps {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *bundledAppsPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"BundledApps"];
        
        if (![fm fileExistsAtPath:bundledAppsPath]) {
            return;
        }
        
        NSArray *apps = [fm contentsOfDirectoryAtPath:bundledAppsPath error:nil];
        for (NSString *appName in apps) {
            if (![appName hasSuffix:@".app"]) {
                continue;
            }
            
            NSString *sourcePath = [bundledAppsPath stringByAppendingPathComponent:appName];
            NSString *destPath = [self.appsPath stringByAppendingPathComponent:appName];
            
            if ([fm fileExistsAtPath:destPath]) {
                [fm removeItemAtPath:destPath error:nil];
            }
            
            NSError *error = nil;
            if ([fm copyItemAtPath:sourcePath toPath:destPath error:&error]) {
                HIAHLogDebug(HIAHLogFilesystem, "Installed app: %s", [appName UTF8String]);
            } else {
                HIAHLogError(HIAHLogFilesystem, "Failed to install %s: %s", [appName UTF8String], error ? [[error description] UTF8String] : "(null)");
            }
        }
    } @catch (NSException *exception) {
        HIAHLogError(HIAHLogFilesystem, "Exception during app installation: %s", [[exception description] UTF8String]);
    }
}

#pragma mark - Path Accessors

- (NSString *)binPath { return [self.rootPath stringByAppendingPathComponent:@"bin"]; }
- (NSString *)usrBinPath { return [self.rootPath stringByAppendingPathComponent:@"usr/bin"]; }
- (NSString *)usrLibPath { return [self.rootPath stringByAppendingPathComponent:@"usr/lib"]; }
- (NSString *)libPath { return [self.rootPath stringByAppendingPathComponent:@"lib"]; }
- (NSString *)etcPath { return [self.rootPath stringByAppendingPathComponent:@"etc"]; }
- (NSString *)tmpPath { return [self.rootPath stringByAppendingPathComponent:@"tmp"]; }
- (NSString *)homePath { return [self.rootPath stringByAppendingPathComponent:@"home"]; }
- (NSString *)appsPath { return [self.rootPath stringByAppendingPathComponent:@"Applications"]; }

#pragma mark - Extension Staging

- (NSString *)stagingPath {
    if (!self.appGroupPath) return nil;
    return [self.appGroupPath stringByAppendingPathComponent:@"staging"];
}

- (NSString *)stageAppForExtension:(NSString *)appPath {
    if (!self.appGroupPath) {
        HIAHLogError(HIAHLogFilesystem, "Cannot stage app - App Group not available");
        return nil;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appName = [appPath lastPathComponent];
    NSString *stagingDir = [self stagingPath];
    NSString *stagedPath = [stagingDir stringByAppendingPathComponent:appName];
    
    [fm removeItemAtPath:stagedPath error:nil];
    
    NSError *error = nil;
    if ([fm copyItemAtPath:appPath toPath:stagedPath error:&error]) {
        HIAHLogDebug(HIAHLogFilesystem, "Staged app: %s", [appName UTF8String]);
        return stagedPath;
    } else {
        HIAHLogError(HIAHLogFilesystem, "Failed to stage app %s: %s", [appName UTF8String], error ? [[error description] UTF8String] : "(null)");
        return nil;
    }
}

- (void)cleanupStagedApps {
    if (!self.appGroupPath) return;
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *stagingDir = [self stagingPath];
    
    NSError *error = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:stagingDir error:&error];
    if (error) {
        HIAHLogError(HIAHLogFilesystem, "Failed to list staging directory: %s", error ? [[error description] UTF8String] : "(null)");
        return;
    }
    
    for (NSString *item in contents) {
        NSString *itemPath = [stagingDir stringByAppendingPathComponent:item];
        [fm removeItemAtPath:itemPath error:nil];
    }
}

#pragma mark - Path Resolution

- (NSString *)resolveVirtualPath:(NSString *)virtualPath {
    if (!virtualPath) return nil;
    
    if ([virtualPath hasPrefix:self.rootPath]) {
        return virtualPath;
    }
    
    if ([virtualPath hasPrefix:@"/"]) {
        NSString *relativePath = [virtualPath substringFromIndex:1];
        return [self.rootPath stringByAppendingPathComponent:relativePath];
    }
    
    return [self.homePath stringByAppendingPathComponent:virtualPath];
}

- (BOOL)isVirtualPath:(NSString *)path {
    if (!path) return NO;
    
    NSArray *virtualPrefixes = @[@"/bin", @"/usr", @"/lib", @"/etc", @"/tmp", @"/var", @"/home", @"/Applications"];
    for (NSString *prefix in virtualPrefixes) {
        if ([path hasPrefix:prefix]) {
            return YES;
        }
    }
    
    return [path hasPrefix:self.rootPath];
}

@end
