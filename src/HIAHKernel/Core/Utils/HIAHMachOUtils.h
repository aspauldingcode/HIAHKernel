/**
 * HIAHMachOUtils.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Mach-O binary manipulation utilities.
 * 
 * This module provides functionality to patch iOS application binaries
 * so they can be loaded dynamically via dlopen. Standard iOS apps are
 * compiled as MH_EXECUTE type which cannot be dlopen'd. Naively changing
 * the filetype to MH_DYLIB is not sufficient on iOS because dyld expects
 * a valid LC_ID_DYLIB load command for MH_DYLIB images.
 *
 * For HIAH's "load an app binary via dlopen" use-case, we patch the
 * binary to MH_BUNDLE, which is dlopen-compatible without requiring
 * LC_ID_DYLIB injection.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HIAHMachOUtils : NSObject

/**
 * Patches a Mach-O binary into a dlopen-compatible type (MH_BUNDLE).
 *
 * This allows the binary to be loaded via dlopen() instead of only
 * being executable via execve(). Supports both thin and fat binaries.
 *
 * @param path Path to the binary to patch
 * @return YES if patch was successful, NO otherwise
 */
+ (BOOL)patchBinaryToDylib:(NSString *)path;

/**
 * Checks if a binary is of MH_EXECUTE type.
 *
 * @param path Path to the binary to check
 * @return YES if the binary is MH_EXECUTE, NO otherwise
 */
+ (BOOL)isMHExecute:(NSString *)path;

/**
 * Removes the code signature from a Mach-O binary.
 *
 * This is necessary after patching a binary because modifying the binary
 * invalidates its code signature, causing iOS to reject it during dlopen.
 * 
 * CRITICAL: This must be called after patchBinaryToDylib for .ipa apps.
 *
 * @param path Path to the binary
 * @return YES if signature was removed or wasn't present, NO on error
 */
+ (BOOL)removeCodeSignature:(NSString *)path;

/**
 * Patches a Mach-O executable for JIT-less mode (like LiveContainer).
 * 
 * This performs the following patches:
 * 1. Changes MH_EXECUTE to MH_DYLIB (or MH_BUNDLE if MH_DYLIB not supported)
 * 2. Patches __PAGEZERO segment: vmaddr to 0xFFFFC000, vmsize to 0x4000
 * 
 * This allows the binary to be dlopen'd even without JIT enabled.
 *
 * @param path Path to the binary to patch
 * @return YES if patch was successful, NO otherwise
 */
+ (BOOL)patchBinaryForJITLessMode:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
