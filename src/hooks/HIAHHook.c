/**
 * HIAHHook.c
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Runtime function interception implementation.
 *
 * This is HIAH's own implementation that works by:
 * 1. Walking Mach-O load commands to find pointer tables
 * 2. Scanning for matching function addresses
 * 3. Safely rewriting pointers with memory protection changes
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#include "HIAHHook.h"
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>

// Pointer authentication support
#if __arm64e__
#include <ptrauth.h>
#define HIAH_STRIP_PTR(ptr) ptrauth_strip(ptr, ptrauth_key_asia)
#else
#define HIAH_STRIP_PTR(ptr) (ptr)
#endif

/**
 * Rewrites function pointers in a symbol pointer section.
 */
static void HIAHHookRewriteSection(const HIAHMachHeader *header,
                                    HIAHSection *section,
                                    void *target,
                                    void *replacement) {
    // Get the actual section data location
    unsigned long dataSize = 0;
    void *sectionData = getsectiondata(header, section->segname, section->sectname, &dataSize);
    
    if (!sectionData || dataSize == 0) {
        return;
    }
    
    // Calculate number of pointers in section
    size_t pointerCount = dataSize / sizeof(void *);
    void **pointers = (void **)sectionData;
    
    // Strip pointer auth from target for comparison
    void *strippedTarget = HIAH_STRIP_PTR(target);
    
    // Scan and replace matching pointers
    for (size_t i = 0; i < pointerCount; i++) {
        void *current = HIAH_STRIP_PTR(pointers[i]);
        
        if (current == strippedTarget) {
            // Temporarily make memory writable
            mach_vm_address_t addr = (mach_vm_address_t)&pointers[i];
            kern_return_t kr;
            
            kr = vm_protect(mach_task_self(), addr, sizeof(void *), 
                           FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
            if (kr != KERN_SUCCESS) {
                continue;
            }
            
            // Write the replacement
            pointers[i] = HIAH_STRIP_PTR(replacement);
            
            // Restore read-only protection
            vm_protect(mach_task_self(), addr, sizeof(void *), 
                      FALSE, VM_PROT_READ);
        }
    }
}

/**
 * Processes a single Mach-O image for hook installation.
 */
static void HIAHHookProcessImage(const HIAHMachHeader *header,
                                  void *target,
                                  void *replacement) {
    if (!header || !target || !replacement) {
        return;
    }
    
    // Walk through load commands
    uintptr_t cmdPtr = (uintptr_t)header + sizeof(HIAHMachHeader);
    
    for (uint32_t i = 0; i < header->ncmds; i++) {
        struct load_command *cmd = (struct load_command *)cmdPtr;
        
        if (cmd->cmd == HIAH_LC_SEGMENT) {
            HIAHSegmentCommand *segment = (HIAHSegmentCommand *)cmd;
            
            // We're interested in __DATA and __DATA_CONST segments
            // These contain the symbol pointer tables
            bool isDataSegment = (strncmp(segment->segname, "__DATA", 6) == 0);
            
            if (isDataSegment) {
                // Iterate through sections in this segment
                HIAHSection *sections = (HIAHSection *)(cmdPtr + sizeof(HIAHSegmentCommand));
                
                for (uint32_t j = 0; j < segment->nsects; j++) {
                    uint32_t sectionType = sections[j].flags & SECTION_TYPE;
                    
                    // Process lazy and non-lazy symbol pointer sections
                    if (sectionType == S_LAZY_SYMBOL_POINTERS ||
                        sectionType == S_NON_LAZY_SYMBOL_POINTERS) {
                        HIAHHookRewriteSection(header, &sections[j], target, replacement);
                    }
                }
            }
        }
        
        cmdPtr += cmd->cmdsize;
    }
}

HIAHHookResult HIAHHookIntercept(HIAHHookScope scope,
                                  const HIAHMachHeader *image,
                                  void *original,
                                  void *replacement) {
    if (!original || !replacement) {
        return HIAHHookResultInvalidArgument;
    }
    
    if (scope == HIAHHookScopeGlobal) {
        // Apply to all loaded images
        uint32_t imageCount = _dyld_image_count();
        
        for (uint32_t i = 0; i < imageCount; i++) {
            const HIAHMachHeader *header = (const HIAHMachHeader *)_dyld_get_image_header(i);
            if (header) {
                HIAHHookProcessImage(header, original, replacement);
            }
        }
    } else if (image) {
        // Apply to specific image only
        HIAHHookProcessImage(image, original, replacement);
    } else {
        return HIAHHookResultInvalidArgument;
    }
    
    return HIAHHookResultSuccess;
}

void *HIAHHookFindSymbol(const HIAHMachHeader *header, const char *name) {
    if (!header || !name) {
        return NULL;
    }
    
    // Use dlsym for runtime symbol resolution
    // This is the most reliable method for finding exported symbols
    void *result = dlsym(RTLD_DEFAULT, name);
    return result;
}

const HIAHMachHeader *HIAHHookGetMainImage(void) {
    return (const HIAHMachHeader *)_dyld_get_image_header(0);
}

uint32_t HIAHHookGetImageCount(void) {
    return _dyld_image_count();
}

const HIAHMachHeader *HIAHHookGetImageAtIndex(uint32_t index) {
    if (index >= _dyld_image_count()) {
        return NULL;
    }
    return (const HIAHMachHeader *)_dyld_get_image_header(index);
}

