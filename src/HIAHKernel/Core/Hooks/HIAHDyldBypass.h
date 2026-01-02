/**
 * HIAHDyldBypass.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Dyld library validation bypass for loading unsigned/modified binaries.
 * Based on LiveContainer's dyld_bypass_validation.m
 *
 * This allows loading binaries with invalid code signatures when running
 * with CS_DEBUGGED flag (debugger/JIT enabled).
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 *
 * Based on:
 * - https://blog.xpnsec.com/restoring-dyld-memory-loading
 * - https://github.com/xpn/DyldDeNeuralyzer
 * - LiveContainer's dyld_bypass_validation.m
 */

#ifndef HIAHDyldBypass_h
#define HIAHDyldBypass_h

#import <Foundation/Foundation.h>

/**
 * Initialize dyld library validation bypass.
 * 
 * This patches dyld's fcntl and mmap implementations to allow loading
 * binaries with invalid code signatures. Must be called before loading
 * any guest app binaries.
 *
 * This only works when:
 * - Running with debugger attached
 * - CS_DEBUGGED flag is set (JIT enabled)
 * - Device is jailbroken
 *
 * Thread-safe: Can be called multiple times (will only patch once).
 */
void HIAHInitDyldBypass(void);

/**
 * Check if JIT/CS_DEBUGGED is enabled.
 *
 * @return YES if CS_DEBUGGED flag is set, NO otherwise
 */
BOOL HIAHIsJITEnabled(void);

/**
 * Set the guest executable path for @executable_path resolution.
 * This hooks into dyld's _NSGetExecutablePath to return the guest app's path
 * instead of the host app's path.
 *
 * @param guestExecutablePath Path to the guest app's executable
 */
void HIAHSetGuestExecutablePath(NSString *guestExecutablePath);

#endif /* HIAHDyldBypass_h */

