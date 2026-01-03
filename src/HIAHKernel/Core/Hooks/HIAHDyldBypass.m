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
#import "HIAHHook.h"
#import "HIAHLogging.h"
#import <TargetConditionals.h>

// This file contains ARM64-specific assembly that only works on real devices
#if TARGET_OS_SIMULATOR

// Stub implementations for simulator
void HIAHInitDyldBypass(void) {
  HIAHLogEx(HIAH_LOG_INFO, @"DyldBypass",
            @"Dyld bypass not supported on simulator");
}

BOOL HIAHIsJITEnabled(void) {
  return YES; // Simulator always has JIT equivalent
}

void HIAHSetGuestExecutablePath(NSString *guestExecutablePath) {
  // Stub
}

#else // Real device implementation

#include <dlfcn.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysctl.h>

// Code signing definitions (from private headers)
#define CS_OPS_STATUS 0        // Get code signing status
#define CS_DEBUGGED 0x10000000 // Process is being debugged

// Private code signing function
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

// Signatures to search for in dyld
static char mmapSig[] = {0xB0, 0x18, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
static char fcntlSig[] = {0x90, 0x0B, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
static char syscallSig[] = {0x01, 0x10, 0x00, 0xD4};

// Patch shellcode: ldr x8, value; br x8; nops; value
static char patch[] = {0x88, 0x00, 0x00, 0x58, 0x00, 0x01, 0x1f, 0xd6,
                       0x1f, 0x20, 0x03, 0xd5, 0x1f, 0x20, 0x03, 0xd5,
                       0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41};

static int (*orig_fcntl)(int fildes, int cmd, void *param) = NULL;

extern void *__mmap(void *addr, size_t len, int prot, int flags, int fd,
                    off_t offset);
extern int __fcntl(int fildes, int cmd, void *param);

// Built-in memcpy to avoid calling libc during patching
static void builtin_memcpy(char *target, char *source, size_t size) {
  for (size_t i = 0; i < size; i++) {
    target[i] = source[i];
  }
}

// Built-in vm_protect (from _kernelrpc_mach_vm_protect_trap)
__attribute__((naked)) static kern_return_t
builtin_vm_protect(mach_port_t task, vm_address_t addr, vm_size_t size,
                   boolean_t set_max, vm_prot_t prot) {
  __asm__("mov x16, #-0xe\n"
          "svc #0x80\n"
          "ret\n");
}

static bool redirectFunction(const char *name, void *patchAddr, void *target) {
  kern_return_t kret = builtin_vm_protect(
      mach_task_self(), (vm_address_t)patchAddr, sizeof(patch), false,
      PROT_READ | PROT_WRITE | VM_PROT_COPY);
  if (kret != KERN_SUCCESS) {
    NSLog(@"[HIAHDyldBypass] vm_protect(RW) failed for %s", name);
    return false;
  }

  builtin_memcpy((char *)patchAddr, patch, sizeof(patch));
  *(void **)((char *)patchAddr + 16) = target;

  kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr,
                            sizeof(patch), false, PROT_READ | PROT_EXEC);
  if (kret != KERN_SUCCESS) {
    NSLog(@"[HIAHDyldBypass] vm_protect(RX) failed for %s", name);
    return false;
  }

  NSLog(@"[HIAHDyldBypass] Hooked %s successfully", name);
  return true;
}

static bool searchAndPatch(const char *name, char *base, char *signature,
                           int length, void *target) {
  char *patchAddr = NULL;
  for (int i = 0; i < 0x80000; i += 4) {
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
static void *hooked_mmap(void *addr, size_t len, int prot, int flags, int fd,
                         off_t offset) {
  static int callCount = 0;
  callCount++;

  void *map = __mmap(addr, len, prot, flags, fd, offset);

  // If mmap failed and we're trying to map executable code, use anonymous
  // memory
  if (map == MAP_FAILED && fd && (prot & PROT_EXEC)) {
    NSLog(@"[HIAHDyldBypass] ✅ Hooked mmap called - mmap failed for "
          @"executable (fd=%d, len=%zu), using anonymous memory - call #%d",
          fd, len, callCount);
    map = __mmap(addr, len, PROT_READ | PROT_WRITE,
                 flags | MAP_PRIVATE | MAP_ANON, 0, 0);

    if (map != MAP_FAILED) {
      NSLog(@"[HIAHDyldBypass] Anonymous mmap succeeded, loading file "
            @"content...");
      // Load file into anonymous memory
      void *memoryLoadedFile =
          __mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
      if (memoryLoadedFile != MAP_FAILED) {
        memcpy(map, memoryLoadedFile, len);
        munmap(memoryLoadedFile, len);
        NSLog(@"[HIAHDyldBypass] File content loaded into anonymous memory");
      }
      mprotect(map, len, prot);
    } else {
      NSLog(@"[HIAHDyldBypass] ❌ Anonymous mmap also failed!");
    }
  } else if (map != MAP_FAILED && fd && (prot & PROT_EXEC) && callCount <= 10) {
    NSLog(@"[HIAHDyldBypass] Hooked mmap succeeded (fd=%d, len=%zu) - call #%d",
          fd, len, callCount);
  }

  return map;
}

// Hooked fcntl - bypass signature validation
static int hooked_fcntl(int fildes, int cmd, void *param) {
  // Log all fcntl calls to verify hooks are working
  static int callCount = 0;
  callCount++;

  // F_ADDFILESIGS_RETURN: dyld trying to attach code signature
  if (cmd == F_ADDFILESIGS_RETURN) {
    NSLog(@"[HIAHDyldBypass] ✅ Hooked fcntl called (F_ADDFILESIGS_RETURN) - "
          @"call #%d, fd=%d",
          callCount, fildes);
#if !(TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR)
    // Try to attach signature normally first
    int result = orig_fcntl(fildes, cmd, param);
    NSLog(@"[HIAHDyldBypass] Original fcntl returned: %d", result);
#endif
    // Make dyld think signature covers everything
    fsignatures_t *fsig = (fsignatures_t *)param;
    if (fsig) {
      fsig->fs_file_start = 0xFFFFFFFF;
      NSLog(@"[HIAHDyldBypass] Modified fs_file_start to 0xFFFFFFFF to bypass "
            @"validation");
    }
    return 0;
  }

  // F_CHECK_LV: dyld checking library validation
  else if (cmd == F_CHECK_LV) {
    NSLog(@"[HIAHDyldBypass] ✅ Hooked fcntl called (F_CHECK_LV) - call #%d, "
          @"fd=%d",
          callCount, fildes);
    int result = orig_fcntl(fildes, cmd, param);
    NSLog(@"[HIAHDyldBypass] Original F_CHECK_LV returned: %d, forcing success",
          result);
    // Always return success (bypass library validation)
    return 0;
  }

  // Log other commands for debugging
  if (callCount <= 10) { // Only log first 10 to avoid spam
    NSLog(@"[HIAHDyldBypass] Hooked fcntl called (cmd=%d) - call #%d, fd=%d",
          cmd, callCount, fildes);
  }

  // Pass through other commands
  return orig_fcntl(fildes, cmd, param);
}

void HIAHInitDyldBypass(void) {
  static BOOL bypassed = NO;
  static BOOL attempted = NO;

  // Check if JIT is enabled - if not, skip bypass (will need re-signing
  // instead)
  BOOL jitEnabled = HIAHIsJITEnabled();

  // If we already attempted and JIT wasn't enabled, check again now
  // This allows re-initialization when JIT becomes enabled later
  if (attempted && !bypassed && jitEnabled) {
    NSLog(@"[HIAHDyldBypass] JIT is now enabled - re-initializing bypass");
    bypassed = NO; // Reset to allow initialization
  }

  if (bypassed) {
    return;
  }

  attempted = YES;

  NSLog(@"[HIAHDyldBypass] Initializing dyld bypass...");
  HIAHLogInfo(HIAHLogKernel, "Initializing dyld library validation bypass");

  if (!jitEnabled) {
    NSLog(@"[HIAHDyldBypass] JIT not enabled - skipping dyld bypass");
    NSLog(@"[HIAHDyldBypass] Will need to use re-signing for .ipa apps");
    HIAHLogError(HIAHLogKernel, "JIT not enabled - dyld bypass skipped");
    return; // Don't attempt bypass without JIT
  }

  bypassed = YES;

  NSLog(@"[HIAHDyldBypass] JIT enabled - proceeding with bypass");

  // Get dyld base address by searching loaded images
  char *dyldBase = NULL;
  uint32_t imageCount = _dyld_image_count();

  for (uint32_t i = 0; i < imageCount; i++) {
    const char *imageName = _dyld_get_image_name(i);
    if (imageName &&
        (strstr(imageName, "/dyld") || strstr(imageName, "dyld"))) {
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
  bool fcntlSuccess = searchAndPatch("dyld_fcntl", dyldBase, fcntlSig,
                                     sizeof(fcntlSig), hooked_fcntl);

  // If fcntl patch failed, try to find jailbreak hook (Dopamine/etc)
  if (!fcntlSuccess) {
    NSLog(@"[HIAHDyldBypass] Standard fcntl patch failed, searching for "
          @"jailbreak hook...");

    char *fcntlAddr = NULL;
    // Search for syscalls with branch instruction before them
    for (int i = 0; i < 0x80000; i += 4) {
      if (dyldBase[i] == syscallSig[0] &&
          memcmp(dyldBase + i, syscallSig, 4) == 0) {
        char *syscallAddr = dyldBase + i;
        uint32_t *prev = (uint32_t *)(syscallAddr - 4);
        // Check if previous instruction is a branch (opcode >> 26 == 0x5)
        if (*prev >> 26 == 0x5) {
          fcntlAddr = (char *)prev;
          break;
        }
      }
    }

    if (fcntlAddr) {
      uint32_t *inst = (uint32_t *)fcntlAddr;
      int32_t offset = ((int32_t)((*inst) << 6)) >> 4;
      NSLog(@"[HIAHDyldBypass] Found jailbreak hook at offset 0x%x", offset);
      orig_fcntl = (void *)((char *)fcntlAddr + offset);
      redirectFunction("dyld_fcntl (jailbreak hook)", fcntlAddr, hooked_fcntl);
    } else {
      NSLog(@"[HIAHDyldBypass] WARNING: Could not find fcntl to hook");
      HIAHLogError(HIAHLogKernel,
                   "Could not patch fcntl - signature bypass may fail");
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

// Guest executable path for @executable_path resolution
static NSString *gGuestExecutablePath = nil;
static int (*orig_NSGetExecutablePath)(char *buf, uint32_t *bufsize) = NULL;
static BOOL gNSGetExecutablePathHooked = NO;

// Hook _NSGetExecutablePath to return guest app's path
// This is what LiveContainer does to patch @executable_path
static int hooked_NSGetExecutablePath(char *buf, uint32_t *bufsize) {
  if (gGuestExecutablePath && bufsize) {
    const char *guestPath = [gGuestExecutablePath UTF8String];
    size_t guestPathLen = strlen(guestPath);

    if (*bufsize >= guestPathLen + 1) {
      strncpy(buf, guestPath, *bufsize - 1);
      buf[*bufsize - 1] = '\0';
      *bufsize = (uint32_t)guestPathLen;
      NSLog(@"[HIAHDyldBypass] _NSGetExecutablePath returning guest path: %s",
            guestPath);
      return 0;
    } else {
      *bufsize = (uint32_t)guestPathLen + 1;
      return -1; // Buffer too small
    }
  }

  // Fallback to original implementation
  if (orig_NSGetExecutablePath) {
    return orig_NSGetExecutablePath(buf, bufsize);
  }

  return -1;
}

void HIAHSetGuestExecutablePath(NSString *guestExecutablePath) {
  gGuestExecutablePath = guestExecutablePath;
  NSLog(@"[HIAHDyldBypass] Set guest executable path: %@", guestExecutablePath);

  if (gNSGetExecutablePathHooked) {
    NSLog(
        @"[HIAHDyldBypass] _NSGetExecutablePath already hooked, updating path");
    return; // Already hooked, just update the path
  }

  // Get original function pointer
  orig_NSGetExecutablePath = dlsym(RTLD_DEFAULT, "_NSGetExecutablePath");
  if (!orig_NSGetExecutablePath) {
    NSLog(@"[HIAHDyldBypass] ERROR: Could not find _NSGetExecutablePath");
    HIAHLogError(HIAHLogKernel, "Could not find _NSGetExecutablePath");
    return;
  }

  NSLog(@"[HIAHDyldBypass] Found _NSGetExecutablePath at %p",
        orig_NSGetExecutablePath);

  // Method 1: Use HIAHHookIntercept to hook via symbol pointer tables
  // This works if _NSGetExecutablePath is called through symbol pointers
  HIAHHookResult result =
      HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_NSGetExecutablePath,
                        (void *)hooked_NSGetExecutablePath);
  if (result == HIAHHookResultSuccess) {
    gNSGetExecutablePathHooked = YES;
    NSLog(@"[HIAHDyldBypass] ✅ Hooked _NSGetExecutablePath via "
          @"HIAHHookIntercept");
    HIAHLogInfo(HIAHLogKernel,
                "Hooked _NSGetExecutablePath for @executable_path resolution");
    return;
  }

  NSLog(@"[HIAHDyldBypass] HIAHHookIntercept failed (result: %d), trying "
        @"direct patching...",
        result);

  // Method 2: Patch call sites in dyld (like LiveContainer does)
  // LiveContainer hooks dyld4::APIs::_NSGetExecutablePath, which means
  // they patch where dyld calls _NSGetExecutablePath, not the function itself
  char *dyldBase = NULL;
  uint32_t imageCount = _dyld_image_count();

  for (uint32_t i = 0; i < imageCount; i++) {
    const char *imageName = _dyld_get_image_name(i);
    if (imageName &&
        (strstr(imageName, "/dyld") || strstr(imageName, "dyld"))) {
      dyldBase = (char *)_dyld_get_image_header(i);
      NSLog(@"[HIAHDyldBypass] Found dyld for patching call sites: %s",
            imageName);
      break;
    }
  }

  if (dyldBase) {
    // Search for calls to _NSGetExecutablePath in dyld
    // We look for bl (branch with link) instructions that might call it
    // This is a heuristic - we search for patterns that might be calls
    BOOL foundCallSite = NO;

    // Search for the function pointer in dyld's data sections
    // If dyld stores a pointer to _NSGetExecutablePath, we can patch it
    for (int i = 0; i < 0x100000;
         i += 8) { // Search in 8-byte increments (pointer-aligned)
      void **ptr = (void **)(dyldBase + i);
      if (*ptr == orig_NSGetExecutablePath) {
        NSLog(@"[HIAHDyldBypass] Found _NSGetExecutablePath pointer in dyld at "
              @"offset 0x%x",
              i);

        // Patch the pointer to point to our hook
        kern_return_t kret = builtin_vm_protect(
            mach_task_self(), (vm_address_t)ptr, sizeof(void *), false,
            PROT_READ | PROT_WRITE | VM_PROT_COPY);
        if (kret == KERN_SUCCESS) {
          *ptr = (void *)hooked_NSGetExecutablePath;
          builtin_vm_protect(mach_task_self(), (vm_address_t)ptr,
                             sizeof(void *), false, PROT_READ);
          foundCallSite = YES;
          gNSGetExecutablePathHooked = YES;
          NSLog(@"[HIAHDyldBypass] ✅ Patched _NSGetExecutablePath pointer in "
                @"dyld");
          HIAHLogInfo(HIAHLogKernel,
                      "Patched _NSGetExecutablePath pointer in dyld");
          break;
        }
      }
    }

    if (!foundCallSite) {
      NSLog(@"[HIAHDyldBypass] Could not find _NSGetExecutablePath call site "
            @"in dyld");
    }
  } else {
    NSLog(@"[HIAHDyldBypass] Could not find dyld base address for call site "
          @"patching");
  }

  // Method 3: If both methods failed, at least we have the path stored
  // Some code paths might check gGuestExecutablePath directly
  if (!gNSGetExecutablePathHooked) {
    NSLog(@"[HIAHDyldBypass] ⚠️ Could not hook _NSGetExecutablePath, but path "
          @"is stored");
    NSLog(@"[HIAHDyldBypass] ⚠️ @executable_path resolution may not work for "
          @"all cases");
    HIAHLogWarning(
        HIAHLogKernel,
        "Could not hook _NSGetExecutablePath - @executable_path may not work");
  }
}

#endif // !TARGET_OS_SIMULATOR - Real device implementation
