/**
 * HIAHGuestHooks.h
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * System call interception for guest processes.
 * Hooks posix_spawn, execve, and waitpid to enable virtual process control.
 */

#import <Foundation/Foundation.h>
#import "HIAHHook.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Installs all HIAH system hooks.
 *
 * This function should be called early in the process lifecycle,
 * typically in a +load method or __attribute__((constructor)).
 *
 * Hooks installed:
 * - posix_spawn: Intercepts process creation, redirects to dlopen or kernel
 * - posix_spawn_file_actions_adddup2/addclose: Tracks pipe setup
 * - execve: Intercepts exec calls, handles SSH specially
 * - waitpid: Handles thread-based pseudo-PIDs
 */
__attribute__((visibility("default")))
void HIAHInstallHooks(void);

/**
 * Checks if hooks are currently installed.
 */
__attribute__((visibility("default")))
BOOL HIAHHooksInstalled(void);

/**
 * Temporarily disables hooks for the current thread.
 * Useful when calling original functions from within hooks.
 */
__attribute__((visibility("default")))
void HIAHDisableHooksForCurrentThread(void);

/**
 * Re-enables hooks for the current thread.
 */
__attribute__((visibility("default")))
void HIAHEnableHooksForCurrentThread(void);

NS_ASSUME_NONNULL_END

