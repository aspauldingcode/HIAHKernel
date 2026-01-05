/**
 * HIAHGuestHooks.h
 * POSIX Syscall Interception for Virtual Kernel
 *
 * Hooks process-related syscalls to enable virtual multi-process execution:
 * - posix_spawn / fork / vfork → virtual process creation
 * - exec family → virtual exec
 * - wait family → virtual wait
 * - exit → virtual exit
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Install all POSIX hooks (called automatically via constructor)
void HIAHInstallHooks(void);

/// Check if hooks are installed
BOOL HIAHHooksInstalled(void);

/// Temporarily disable hooks for current thread
void HIAHDisableHooksForCurrentThread(void);

/// Re-enable hooks for current thread
void HIAHEnableHooksForCurrentThread(void);

NS_ASSUME_NONNULL_END
