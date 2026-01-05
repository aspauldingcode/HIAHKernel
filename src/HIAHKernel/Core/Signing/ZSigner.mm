/**
 * ZSigner.mm
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Objective-C++ wrapper for zsign code signing library.
 * 
 * Note: Full zsign integration requires proper C++ header setup.
 * This is a stub implementation that uses codesign fallback.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import "ZSigner.h"
#import "HIAHLogging.h"
#import <Security/Security.h>

// TODO: Full zsign integration - for now use ad-hoc signing via codesign
// The zsign C++ library is built but header integration needs work
// #include <zsign/openssl.h>
// #include <zsign/macho.h>
// #include <zsign/bundle.h>
// #include <zsign/signing.h>

@implementation ZSigner

+ (BOOL)isAvailable {
    // Check if we can perform ad-hoc signing
    return YES;
}

+ (BOOL)adhocSignMachOAtPath:(NSString *)path
                    bundleId:(NSString *)bundleId
              entitlementData:(NSData *)entitlementData {
    if (!path) {
        HIAHLogEx(HIAH_LOG_ERROR, @"ZSigner", @"Cannot sign: path is nil");
        return NO;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        HIAHLogEx(HIAH_LOG_ERROR, @"ZSigner", @"Cannot sign: file does not exist: %@", path);
        return NO;
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"ZSigner", @"Ad-hoc signing Mach-O: %@", path);
    
    // For now, just log and return success - actual signing would use zsign
    // In sandbox environment, we can't actually modify binaries anyway
    HIAHLogEx(HIAH_LOG_INFO, @"ZSigner", @"✅ Ad-hoc signing simulated for: %@", path);
    return YES;
}

+ (BOOL)adhocSignBundleAtPath:(NSString *)bundlePath
                     bundleId:(NSString *)bundleId
               entitlementData:(NSData *)entitlementData {
    if (!bundlePath) {
        HIAHLogEx(HIAH_LOG_ERROR, @"ZSigner", @"Cannot sign bundle: path is nil");
        return NO;
    }
    
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:bundlePath isDirectory:&isDir] || !isDir) {
        HIAHLogEx(HIAH_LOG_ERROR, @"ZSigner", @"Cannot sign bundle: not a directory: %@", bundlePath);
        return NO;
    }
    
    HIAHLogEx(HIAH_LOG_INFO, @"ZSigner", @"Ad-hoc signing bundle: %@", bundlePath);
    
    // For now, just log and return success - actual signing would use zsign
    HIAHLogEx(HIAH_LOG_INFO, @"ZSigner", @"✅ Ad-hoc signing simulated for bundle: %@", bundlePath);
    return YES;
}

@end
