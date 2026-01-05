/**
 * HIAHBuildConfig.h
 * HIAH Kernel - Build Configuration
 *
 * Centralized compile-time feature flags for conditional compilation.
 * These flags control which features are included in the build.
 *
 * Build Configurations:
 *   MINIMAL - Core kernel only (MIT licensed, no JIT/signing)
 *   FULL    - Complete app with JIT, signing, VPN integration (AGPL)
 *   TEST    - Simulator build with stubs for CI testing
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License (this file)
 */

#ifndef HIAHBuildConfig_h
#define HIAHBuildConfig_h

#import <TargetConditionals.h>

// ============================================================================
// MARK: - Build Mode Detection
// ============================================================================

// Automatically detect simulator builds
#if TARGET_OS_SIMULATOR
    #define HIAH_IS_SIMULATOR 1
#else
    #define HIAH_IS_SIMULATOR 0
#endif

// ============================================================================
// MARK: - Feature Flags (can be overridden via GCC_PREPROCESSOR_DEFINITIONS)
// ============================================================================

/**
 * HIAH_MINIMAL_BUILD
 * When defined, builds only the core kernel without JIT/signing features.
 * This produces a smaller binary suitable for embedding as a library.
 * License: MIT (no AGPL dependencies)
 */
#ifndef HIAH_MINIMAL_BUILD
    #define HIAH_MINIMAL_BUILD 0
#endif

/**
 * HIAH_INCLUDE_JIT_SUPPORT
 * Include JIT enablement via minimuxer (requires em_proxy + LocalDevVPN)
 * Disabled in MINIMAL builds.
 */
#ifndef HIAH_INCLUDE_JIT_SUPPORT
    #if HIAH_MINIMAL_BUILD
        #define HIAH_INCLUDE_JIT_SUPPORT 0
    #else
        #define HIAH_INCLUDE_JIT_SUPPORT 1
    #endif
#endif

/**
 * HIAH_INCLUDE_SIGNING
 * Include app signing support (ZSign, certificate management)
 * Disabled in MINIMAL builds.
 */
#ifndef HIAH_INCLUDE_SIGNING
    #if HIAH_MINIMAL_BUILD
        #define HIAH_INCLUDE_SIGNING 0
    #else
        #define HIAH_INCLUDE_SIGNING 1
    #endif
#endif

/**
 * HIAH_INCLUDE_VPN
 * Include VPN/em_proxy integration for LocalDevVPN communication
 * Disabled in MINIMAL builds.
 */
#ifndef HIAH_INCLUDE_VPN
    #if HIAH_MINIMAL_BUILD
        #define HIAH_INCLUDE_VPN 0
    #else
        #define HIAH_INCLUDE_VPN 1
    #endif
#endif

/**
 * HIAH_INCLUDE_AUTH
 * Include Apple ID authentication (anisette, ALTAppleAPI)
 * Disabled in MINIMAL builds. Note: This may have AGPL implications.
 */
#ifndef HIAH_INCLUDE_AUTH
    #if HIAH_MINIMAL_BUILD
        #define HIAH_INCLUDE_AUTH 0
    #else
        #define HIAH_INCLUDE_AUTH 1
    #endif
#endif

/**
 * HIAH_USE_STUBS
 * Use stub implementations for device-only features.
 * Automatically enabled on simulator unless explicitly disabled.
 * Stubs return success for all operations, enabling CI testing.
 */
#ifndef HIAH_USE_STUBS
    #if HIAH_IS_SIMULATOR
        #define HIAH_USE_STUBS 1
    #else
        #define HIAH_USE_STUBS 0
    #endif
#endif

/**
 * HIAH_ENABLE_DYLD_BYPASS
 * Enable dyld bypass hooks for loading unsigned binaries.
 * Only works when JIT is enabled (CS_DEBUGGED flag set).
 * Can be disabled for builds that only use signed binaries.
 */
#ifndef HIAH_ENABLE_DYLD_BYPASS
    #define HIAH_ENABLE_DYLD_BYPASS 1
#endif

// ============================================================================
// MARK: - Debug Flags
// ============================================================================

/**
 * HIAH_DEBUG_LOGGING
 * Enable verbose debug logging throughout the codebase.
 */
#ifndef HIAH_DEBUG_LOGGING
    #if DEBUG
        #define HIAH_DEBUG_LOGGING 1
    #else
        #define HIAH_DEBUG_LOGGING 0
    #endif
#endif

/**
 * HIAH_LOG_HOOKS
 * Log all hook invocations (posix_spawn, execve, etc.)
 * Very verbose - only for debugging hook issues.
 */
#ifndef HIAH_LOG_HOOKS
    #define HIAH_LOG_HOOKS 0
#endif

/**
 * HIAH_LOG_MACH_O
 * Log Mach-O parsing and patching operations.
 */
#ifndef HIAH_LOG_MACH_O
    #define HIAH_LOG_MACH_O 0
#endif

// ============================================================================
// MARK: - Convenience Macros
// ============================================================================

/// Log only if debug logging is enabled
#if HIAH_DEBUG_LOGGING
    #define HIAHLog(fmt, ...) NSLog(@"[HIAH] " fmt, ##__VA_ARGS__)
#else
    #define HIAHLog(fmt, ...) ((void)0)
#endif

/// Log hook calls if hook logging is enabled
#if HIAH_LOG_HOOKS
    #define HIAHHookLog(fmt, ...) NSLog(@"[HIAH:Hook] " fmt, ##__VA_ARGS__)
#else
    #define HIAHHookLog(fmt, ...) ((void)0)
#endif

/// Log Mach-O operations if enabled
#if HIAH_LOG_MACH_O
    #define HIAHMachOLog(fmt, ...) NSLog(@"[HIAH:MachO] " fmt, ##__VA_ARGS__)
#else
    #define HIAHMachOLog(fmt, ...) ((void)0)
#endif

// ============================================================================
// MARK: - Feature Availability Checks
// ============================================================================

/// Check if JIT features are available at runtime
NS_INLINE BOOL HIAHIsJITAvailable(void) {
#if HIAH_INCLUDE_JIT_SUPPORT && !HIAH_USE_STUBS
    return YES;
#else
    return NO;
#endif
}

/// Check if signing features are available at runtime
NS_INLINE BOOL HIAHIsSigningAvailable(void) {
#if HIAH_INCLUDE_SIGNING
    return YES;
#else
    return NO;
#endif
}

/// Check if running with stubs (simulator/test mode)
NS_INLINE BOOL HIAHIsUsingStubs(void) {
#if HIAH_USE_STUBS
    return YES;
#else
    return NO;
#endif
}

// ============================================================================
// MARK: - Build Configuration Summary
// ============================================================================

/**
 * Print build configuration at startup (debug builds only)
 */
NS_INLINE void HIAHPrintBuildConfig(void) {
#if HIAH_DEBUG_LOGGING
    NSLog(@"[HIAH] Build Configuration:");
    NSLog(@"[HIAH]   MINIMAL_BUILD: %d", HIAH_MINIMAL_BUILD);
    NSLog(@"[HIAH]   INCLUDE_JIT_SUPPORT: %d", HIAH_INCLUDE_JIT_SUPPORT);
    NSLog(@"[HIAH]   INCLUDE_SIGNING: %d", HIAH_INCLUDE_SIGNING);
    NSLog(@"[HIAH]   INCLUDE_VPN: %d", HIAH_INCLUDE_VPN);
    NSLog(@"[HIAH]   INCLUDE_AUTH: %d", HIAH_INCLUDE_AUTH);
    NSLog(@"[HIAH]   USE_STUBS: %d", HIAH_USE_STUBS);
    NSLog(@"[HIAH]   ENABLE_DYLD_BYPASS: %d", HIAH_ENABLE_DYLD_BYPASS);
    NSLog(@"[HIAH]   IS_SIMULATOR: %d", HIAH_IS_SIMULATOR);
#endif
}

#endif /* HIAHBuildConfig_h */

