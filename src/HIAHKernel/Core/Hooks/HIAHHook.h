/**
 * HIAHHook.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Runtime function interception for iOS.
 * 
 * This is HIAH's own implementation of runtime symbol interception,
 * designed specifically for the HIAH Desktop environment.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#ifndef HIAH_HOOK_H
#define HIAH_HOOK_H

#include <stdbool.h>
#include <stdint.h>
#include <mach/mach.h>
#include <mach-o/loader.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Architecture-specific type definitions
 */
#ifdef __LP64__
typedef struct mach_header_64 HIAHMachHeader;
typedef struct segment_command_64 HIAHSegmentCommand;
typedef struct section_64 HIAHSection;
#define HIAH_LC_SEGMENT LC_SEGMENT_64
#else
typedef struct mach_header HIAHMachHeader;
typedef struct segment_command HIAHSegmentCommand;
typedef struct section HIAHSection;
#define HIAH_LC_SEGMENT LC_SEGMENT
#endif

/**
 * Hook installation scope
 */
typedef enum {
    HIAHHookScopeImage,   // Hook within a specific image
    HIAHHookScopeGlobal   // Hook in all loaded images
} HIAHHookScope;

/**
 * Hook result codes
 */
typedef enum {
    HIAHHookResultSuccess = 0,
    HIAHHookResultNotFound,
    HIAHHookResultProtectionFailed,
    HIAHHookResultInvalidArgument
} HIAHHookResult;

/**
 * Intercept a function by replacing symbol pointers.
 *
 * This scans the specified image (or all images if scope is HIAHHookScopeGlobal)
 * for symbol pointer tables and replaces occurrences of `original` with `replacement`.
 *
 * @param scope Whether to hook globally or in a specific image
 * @param image The image to hook in (ignored if scope is HIAHHookScopeGlobal)
 * @param original The original function pointer to intercept
 * @param replacement The replacement function
 * @return HIAHHookResultSuccess on success
 */
HIAHHookResult HIAHHookIntercept(HIAHHookScope scope,
                                  const HIAHMachHeader *image,
                                  void *original,
                                  void *replacement);

/**
 * Find a function address by name in the specified image.
 *
 * @param image The Mach-O header to search in
 * @param name The symbol name (without leading underscore)
 * @return The function address, or NULL if not found
 */
void *HIAHHookFindSymbol(const HIAHMachHeader *image, const char *name);

/**
 * Get the Mach-O header for the main executable.
 */
const HIAHMachHeader *HIAHHookGetMainImage(void);

/**
 * Get the number of loaded images.
 */
uint32_t HIAHHookGetImageCount(void);

/**
 * Get the Mach-O header at the specified index.
 */
const HIAHMachHeader *HIAHHookGetImageAtIndex(uint32_t index);

/**
 * Convenience macro for declaring hooks.
 * Declares the original function pointer and hook function.
 * 
 * Usage:
 * ```c
 * DEFINE_HOOK(posix_spawn, int, (pid_t *pid, const char *path, ...));
 * 
 * static int hook_posix_spawn(pid_t *pid, const char *path, ...) {
 *     return orig_posix_spawn(pid, path, ...);
 * }
 * ```
 */
#define DEFINE_HOOK(func, return_type, signature) \
    static return_type (*orig_##func) signature; \
    static return_type hook_##func signature

/**
 * Call the original function.
 */
#define ORIG_FUNC(func) orig_##func

#ifdef __cplusplus
}
#endif

#endif /* HIAH_HOOK_H */

