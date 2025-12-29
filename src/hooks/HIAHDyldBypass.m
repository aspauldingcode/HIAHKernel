/**
 * HIAHDyldBypass.m
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Dyld library validation bypass implementation.
 * Based on LiveContainer's dyld_bypass_validation.m
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import "HIAHDyldBypass.h"
#import "../HIAHDesktop/HIAHLogging.h"
#import <TargetConditionals.h>

// This file contains ARM64-specific assembly that only works on real devices
#if TARGET_OS_SIMULATOR

// Stub implementations for simulator
void HIAHInitDyldBypass(void) {
    HIAHLogEx(HIAH_LOG_INFO, @"DyldBypass", @"Dyld bypass not supported on simulator");
}

BOOL HIAHIsJITEnabled(void) {
    return YES; // Simulator always has JIT equivalent
}

#else // Real device implementation

#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach/mach.h>

// Code signing definitions (from private headers)
#define CS_OPS_STATUS 0  // Get code signing status
#define CS_DEBUGGED 0x10000000  // Process is being debugged

// Private code signing function
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

// Signatures to search for in dyld
static char mmapSig[] = {0xB0, 0x18, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
static char fcntlSig[] = {0x90, 0x0B, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
static char syscallSig[] = {0x01, 0x10, 0x00, 0xD4};

// Patch shellcode: ldr x8, value; br x8; nops; value
static char patch[] = {0x88,0x00,0x00,0x58,0x00,0x01,0x1f,0xd6,
                       0x1f,0x20,0x03,0xd5,0x1f,0x20,0x03,0xd5,
                       0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41};

static int (*orig_fcntl)(int fildes, int cmd, void *param) = NULL;

extern void* __mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset);
extern int __fcntl(int fildes, int cmd, void* param);

// Built-in memcpy to avoid calling libc during patching
static void builtin_memcpy(char *target, char *source, size_t size) {
    for (size_t i = 0; i < size; i++) {
        target[i] = source[i];
    }
}

// Built-in vm_protect (from _kernelrpc_mach_vm_protect_trap)
__attribute__((naked))
static kern_return_t builtin_vm_protect(mach_port_t task, vm_address_t addr, 
                                        vm_size_t size, boolean_t set_max, vm_prot_t prot) {
    __asm__(
        "mov x16, #-0xe\n"
        "svc #0x80\n"
        "ret\n"
    );
}

static bool redirectFunction(const char *name, void *patchAddr, void *target) {
    kern_return_t kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, 
                                            sizeof(patch), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    if (kret != KERN_SUCCESS) {
        NSLog(@"[HIAHDyldBypass] vm_protect(RW) failed for %s", name);
        return false;
    }
    
    builtin_memcpy((char *)patchAddr, patch, sizeof(patch));
    *(void **)((char*)patchAddr + 16) = target;
    
    kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, 
                              sizeof(patch), false, PROT_READ | PROT_EXEC);
    if (kret != KERN_SUCCESS) {
        NSLog(@"[HIAHDyldBypass] vm_protect(RX) failed for %s", name);
        return false;
    }
    
    NSLog(@"[HIAHDyldBypass] Hooked %s successfully", name);
    return true;
}

static bool searchAndPatch(const char *name, char *base, char *signature, int length, void *target) {
    char *patchAddr = NULL;
    for(int i = 0; i < 0x80000; i += 4) {
        if (base[i] == signature[0] && memcmp(base + i, signature, length) == 0) {
            patchAddr = base + i;
            break;
        }
    }
    
    if (patchAddr == NULL) {
        NSLog(@"[HIAHDyldBypass] Failed to find %s signature", name);
        return false;
    }
    
    NSLog(@"[HIAHDyldBypass] Found %s at %p", name, patchAddr);
    return redirectFunction(name, patchAddr, target);
}

// Hooked mmap - fallback to anonymous memory if signature check fails
static void* hooked_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    void *map = __mmap(addr, len, prot, flags, fd, offset);
    
    // If mmap failed and we're trying to map executable code, use anonymous memory
    if (map == MAP_FAILED && fd && (prot & PROT_EXEC)) {
        NSLog(@"[HIAHDyldBypass] mmap failed for executable, using anonymous memory");
        map = __mmap(addr, len, PROT_READ | PROT_WRITE, flags | MAP_PRIVATE | MAP_ANON, 0, 0);
        
        if (map != MAP_FAILED) {
            // Load file into anonymous memory
            void *memoryLoadedFile = __mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
            if (memoryLoadedFile != MAP_FAILED) {
                memcpy(map, memoryLoadedFile, len);
                munmap(memoryLoadedFile, len);
            }
            mprotect(map, len, prot);
        }
    }
    
    return map;
}

// Hooked fcntl - bypass signature validation
static int hooked_fcntl(int fildes, int cmd, void *param) {
    // F_ADDFILESIGS_RETURN: dyld trying to attach code signature
    if (cmd == F_ADDFILESIGS_RETURN) {
#if !(TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR)
        // Try to attach signature normally first
        orig_fcntl(fildes, cmd, param);
#endif
        // Make dyld think signature covers everything
        fsignatures_t *fsig = (fsignatures_t*)param;
        fsig->fs_file_start = 0xFFFFFFFF;
        return 0;
    }
    
    // F_CHECK_LV: dyld checking library validation
    else if (cmd == F_CHECK_LV) {
        orig_fcntl(fildes, cmd, param);
        // Always return success
        return 0;
    }
    
    // Pass through other commands
    return orig_fcntl(fildes, cmd, param);
}

void HIAHInitDyldBypass(void) {
    static BOOL bypassed = NO;
    if (bypassed) {
        return;
    }
    bypassed = YES;
    
    NSLog(@"[HIAHDyldBypass] Initializing dyld bypass...");
    HIAHLogInfo(HIAHLogKernel, "Initializing dyld library validation bypass");
    
    // Check if JIT is enabled - if not, skip bypass (will need re-signing instead)
    if (!HIAHIsJITEnabled()) {
        NSLog(@"[HIAHDyldBypass] JIT not enabled - skipping dyld bypass");
        NSLog(@"[HIAHDyldBypass] Will need to use re-signing for .ipa apps");
        HIAHLogError(HIAHLogKernel, "JIT not enabled - dyld bypass skipped");
        return; // Don't attempt bypass without JIT
    }
    
    NSLog(@"[HIAHDyldBypass] JIT enabled - proceeding with bypass");
    
    // Get dyld base address by searching loaded images
    char *dyldBase = NULL;
    uint32_t imageCount = _dyld_image_count();
    
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (imageName && (strstr(imageName, "/dyld") || strstr(imageName, "dyld"))) {
            dyldBase = (char *)_dyld_get_image_header(i);
            NSLog(@"[HIAHDyldBypass] Found dyld at: %s", imageName);
            break;
        }
    }
    
    if (!dyldBase) {
        // Fallback: dyld is usually the first image or we can find it by pattern
        // Try index 0 (dyld is often first)
        const char *firstImage = _dyld_get_image_name(0);
        if (firstImage && strstr(firstImage, "dyld")) {
            dyldBase = (char *)_dyld_get_image_header(0);
        }
    }
    
    if (!dyldBase) {
        NSLog(@"[HIAHDyldBypass] ERROR: Could not find dyld base address");
        HIAHLogError(HIAHLogKernel, "Could not find dyld base address");
        return;
    }
    
    NSLog(@"[HIAHDyldBypass] dyld base address: %p", dyldBase);
    
    // Save original fcntl
    orig_fcntl = __fcntl;
    
    // Patch mmap and fcntl in dyld
    searchAndPatch("dyld_mmap", dyldBase, mmapSig, sizeof(mmapSig), hooked_mmap);
    bool fcntlSuccess = searchAndPatch("dyld_fcntl", dyldBase, fcntlSig, sizeof(fcntlSig), hooked_fcntl);
    
    // If fcntl patch failed, try to find jailbreak hook (Dopamine/etc)
    if (!fcntlSuccess) {
        NSLog(@"[HIAHDyldBypass] Standard fcntl patch failed, searching for jailbreak hook...");
        
        char *fcntlAddr = NULL;
        // Search for syscalls with branch instruction before them
        for(int i = 0; i < 0x80000; i += 4) {
            if (dyldBase[i] == syscallSig[0] && memcmp(dyldBase + i, syscallSig, 4) == 0) {
                char *syscallAddr = dyldBase + i;
                uint32_t *prev = (uint32_t*)(syscallAddr - 4);
                // Check if previous instruction is a branch (opcode >> 26 == 0x5)
                if(*prev >> 26 == 0x5) {
                    fcntlAddr = (char*)prev;
                    break;
                }
            }
        }
        
        if (fcntlAddr) {
            uint32_t *inst = (uint32_t*)fcntlAddr;
            int32_t offset = ((int32_t)((*inst) << 6)) >> 4;
            NSLog(@"[HIAHDyldBypass] Found jailbreak hook at offset 0x%x", offset);
            orig_fcntl = (void*)((char*)fcntlAddr + offset);
            redirectFunction("dyld_fcntl (jailbreak hook)", fcntlAddr, hooked_fcntl);
        } else {
            NSLog(@"[HIAHDyldBypass] WARNING: Could not find fcntl to hook");
            HIAHLogError(HIAHLogKernel, "Could not patch fcntl - signature bypass may fail");
        }
    }
    
    NSLog(@"[HIAHDyldBypass] Initialization complete");
    HIAHLogInfo(HIAHLogKernel, "Dyld bypass initialized successfully");
}

BOOL HIAHIsJITEnabled(void) {
#if TARGET_OS_SIMULATOR || TARGET_OS_MACCATALYST
    return YES; // Simulator/Catalyst always has JIT
#else
    // Check if jailbroken
    if (access("/var/mobile", R_OK) == 0) {
        return YES;
    }
    
    // Check CS_DEBUGGED flag
    int flags = 0;
    if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) == 0) {
        return (flags & CS_DEBUGGED) != 0;
    }
    
    return NO;
#endif
}

#endif // !TARGET_OS_SIMULATOR - Real device implementation

