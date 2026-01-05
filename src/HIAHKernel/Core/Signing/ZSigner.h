/**
 * ZSigner.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Objective-C++ wrapper for zsign code signing library.
 * Uses zsign (built via Nix) for actual code signing operations.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * ZSigner provides Objective-C interface to zsign code signing functionality.
 * This is the production implementation using the zsign C++ library.
 */
@interface ZSigner : NSObject

/**
 * Check if zsign is available and properly initialized.
 */
+ (BOOL)isAvailable;

/**
 * Perform ad-hoc code signing on a Mach-O binary.
 *
 * @param path Path to the Mach-O binary to sign
 * @param bundleId Bundle identifier to embed in the signature
 * @param entitlementData Entitlements plist data to embed (may be nil)
 * @return YES if signing succeeded, NO otherwise
 */
+ (BOOL)adhocSignMachOAtPath:(NSString *)path
                    bundleId:(NSString *)bundleId
              entitlementData:(nullable NSData *)entitlementData;

/**
 * Perform ad-hoc code signing on a complete app bundle.
 *
 * @param bundlePath Path to the .app bundle
 * @param bundleId Bundle identifier to use
 * @param entitlementData Entitlements plist data (may be nil)
 * @return YES if signing succeeded, NO otherwise
 */
+ (BOOL)adhocSignBundleAtPath:(NSString *)bundlePath
                     bundleId:(NSString *)bundleId
               entitlementData:(nullable NSData *)entitlementData;

@end

NS_ASSUME_NONNULL_END
