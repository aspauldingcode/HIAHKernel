/**
 * HIAHMachOUtils.m
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Mach-O binary manipulation implementation.
 *
 * This implementation uses a straightforward approach:
 * 1. Read the binary into memory
 * 2. Parse the Mach-O header (supporting both thin and fat binaries)
 * 3. Change the filetype field to a dlopen-compatible type (MH_BUNDLE)
 * 4. Write the modified binary back
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import "HIAHMachOUtils.h"
#import "HIAHLogging.h"
#import <mach-o/loader.h>
#import <mach-o/fat.h>

@implementation HIAHMachOUtils

+ (BOOL)patchBinaryToDylib:(NSString *)path {
    // Read binary into memory
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path 
                                          options:NSDataReadingMappedIfSafe 
                                            error:&readError];
    
    if (!data || data.length < sizeof(struct mach_header_64)) {
        HIAHLogError(HIAHLogFilesystem, "Failed to read binary: %s", readError ? [[readError description] UTF8String] : "(null)");
        return NO;
    }
    
    // Create mutable copy for patching
    NSMutableData *mutableData = [data mutableCopy];
    uint8_t *bytes = (uint8_t *)mutableData.mutableBytes;
    
    // Perform the patch
    BOOL success = [self patchMachOBytes:bytes length:mutableData.length];
    
    if (success) {
        // Write patched binary back
        NSError *writeError = nil;
        if (![mutableData writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
            HIAHLogError(HIAHLogFilesystem, "Failed to write patched binary: %s", writeError ? [[writeError description] UTF8String] : "(null)");
            return NO;
        }
        return YES;
    }
    
    return NO;
}

/**
 * Internal method to patch Mach-O bytes in memory.
 * Handles both fat (universal) and thin binaries.
 */
+ (BOOL)patchMachOBytes:(uint8_t *)bytes length:(NSUInteger)length {
    uint32_t magic = *(uint32_t *)bytes;
    
    // Check if this is a fat (universal) binary
    BOOL isFatBinary = (magic == FAT_MAGIC || magic == FAT_CIGAM);
    
    if (isFatBinary) {
        // Parse fat header and patch each architecture slice
        struct fat_header *fatHeader = (struct fat_header *)bytes;
        uint32_t archCount = OSSwapBigToHostInt32(fatHeader->nfat_arch);
        struct fat_arch *archs = (struct fat_arch *)(bytes + sizeof(struct fat_header));
        
        BOOL anySlicePatched = NO;
        
        for (uint32_t i = 0; i < archCount; i++) {
            uint32_t sliceOffset = OSSwapBigToHostInt32(archs[i].offset);
            
            if (sliceOffset < length) {
                uint8_t *sliceBytes = bytes + sliceOffset;
                NSUInteger sliceLength = length - sliceOffset;
                
                if ([self patchMachOBytes:sliceBytes length:sliceLength]) {
                    anySlicePatched = YES;
                }
            }
        }
        
        return anySlicePatched;
    }
    
    // Handle 64-bit Mach-O
    if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        struct mach_header_64 *header = (struct mach_header_64 *)bytes;
        
        // Make executable images dlopen-compatible by converting to MH_BUNDLE.
        // (MH_DYLIB requires LC_ID_DYLIB; we do not rewrite load commands here.)
        if (header->filetype == MH_EXECUTE || header->filetype == MH_DYLIB) {
            uint32_t oldType = header->filetype;
            header->filetype = MH_BUNDLE;
            HIAHLogDebug(HIAHLogFilesystem, "Patched Mach-O filetype %u to MH_BUNDLE (64-bit)", oldType);
            return YES;
        }
        
        return NO; // Already MH_BUNDLE or other type
    }
    
    // Handle 32-bit Mach-O (legacy support)
    if (magic == MH_MAGIC || magic == MH_CIGAM) {
        struct mach_header *header = (struct mach_header *)bytes;
        
        if (header->filetype == MH_EXECUTE || header->filetype == MH_DYLIB) {
            uint32_t oldType = header->filetype;
            header->filetype = MH_BUNDLE;
            HIAHLogDebug(HIAHLogFilesystem, "Patched Mach-O filetype %u to MH_BUNDLE (32-bit)", oldType);
            return YES;
        }
        
        return NO; // Already MH_BUNDLE or other type
    }
    
    HIAHLogError(HIAHLogFilesystem, "Unknown Mach-O magic: 0x%x", magic);
    return NO;
}

+ (BOOL)isMHExecute:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path 
                                          options:NSDataReadingMappedIfSafe 
                                            error:nil];
    
    if (!data || data.length < sizeof(struct mach_header_64)) {
        return NO;
    }
    
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    uint32_t magic = *(uint32_t *)bytes;
    
    // For fat binaries, check the first arm64 slice
    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        struct fat_header *fatHeader = (struct fat_header *)bytes;
        uint32_t archCount = OSSwapBigToHostInt32(fatHeader->nfat_arch);
        struct fat_arch *archs = (struct fat_arch *)(bytes + sizeof(struct fat_header));
        
        for (uint32_t i = 0; i < archCount; i++) {
            uint32_t sliceOffset = OSSwapBigToHostInt32(archs[i].offset);
            
            if (sliceOffset < data.length) {
                const uint8_t *sliceBytes = bytes + sliceOffset;
                uint32_t sliceMagic = *(uint32_t *)sliceBytes;
                
                if (sliceMagic == MH_MAGIC_64 || sliceMagic == MH_CIGAM_64) {
                    struct mach_header_64 *header = (struct mach_header_64 *)sliceBytes;
                    return header->filetype == MH_EXECUTE;
                }
            }
        }
        
        return NO;
    }
    
    // Thin 64-bit binary
    if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        struct mach_header_64 *header = (struct mach_header_64 *)bytes;
        return header->filetype == MH_EXECUTE;
    }
    
    return NO;
}

+ (BOOL)removeCodeSignature:(NSString *)path {
    // Read the binary
    NSError *readError = nil;
    NSMutableData *data = [[NSMutableData alloc] initWithContentsOfFile:path 
                                                                options:NSDataReadingMappedIfSafe 
                                                                  error:&readError];
    
    if (!data || data.length < sizeof(struct mach_header_64)) {
        HIAHLogError(HIAHLogFilesystem, "Failed to read binary for signature removal: %s", 
                    readError ? [[readError description] UTF8String] : "(null)");
        return NO;
    }
    
    uint8_t *bytes = (uint8_t *)data.mutableBytes;
    uint32_t magic = *(uint32_t *)bytes;
    
    // Handle fat binaries
    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        struct fat_header *fatHeader = (struct fat_header *)bytes;
        uint32_t archCount = OSSwapBigToHostInt32(fatHeader->nfat_arch);
        struct fat_arch *archs = (struct fat_arch *)(bytes + sizeof(struct fat_header));
        
        for (uint32_t i = 0; i < archCount; i++) {
            uint32_t sliceOffset = OSSwapBigToHostInt32(archs[i].offset);
            if (sliceOffset < data.length) {
                [self removeCodeSignatureFromSlice:(bytes + sliceOffset) maxLength:(data.length - sliceOffset)];
            }
        }
    } else if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        // Thin 64-bit binary
        [self removeCodeSignatureFromSlice:bytes maxLength:data.length];
    } else {
        HIAHLogError(HIAHLogFilesystem, "Unknown binary format for signature removal");
        return NO;
    }
    
    // Write the modified binary back
    NSError *writeError = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
        HIAHLogError(HIAHLogFilesystem, "Failed to write binary after signature removal: %s",
                    writeError ? [[writeError description] UTF8String] : "(null)");
        return NO;
    }
    
    HIAHLogInfo(HIAHLogFilesystem, "Removed code signature from: %s", [path UTF8String]);
    return YES;
}

/**
 * Helper method to remove code signature from a single Mach-O slice
 */
+ (void)removeCodeSignatureFromSlice:(uint8_t *)bytes maxLength:(NSUInteger)maxLength {
    struct mach_header_64 *header = (struct mach_header_64 *)bytes;
    
    if (header->magic != MH_MAGIC_64 && header->magic != MH_CIGAM_64) {
        return;
    }
    
    uint8_t *cmdPtr = bytes + sizeof(struct mach_header_64);
    uint32_t cmdsSizeTotal = 0;
    
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if ((cmdPtr - bytes) + sizeof(struct load_command) > maxLength) {
            break;
        }
        
        struct load_command *cmd = (struct load_command *)cmdPtr;
        
        // Found LC_CODE_SIGNATURE command
        if (cmd->cmd == LC_CODE_SIGNATURE) {
            HIAHLogDebug(HIAHLogFilesystem, "Found LC_CODE_SIGNATURE at offset %lu, size %u", 
                        (cmdPtr - bytes), cmd->cmdsize);
            
            // Save original cmdsize before we modify it
            uint32_t originalCmdSize = cmd->cmdsize;
            
            // Method: Shift all remaining load commands over this one
            uint8_t *nextCmd = cmdPtr + originalCmdSize;
            uint32_t remainingSize = header->sizeofcmds - cmdsSizeTotal - originalCmdSize;
            
            if (remainingSize > 0) {
                // Shift remaining commands left to overwrite LC_CODE_SIGNATURE
                memmove(cmdPtr, nextCmd, remainingSize);
            }
            
            // Update header
            header->ncmds--;
            header->sizeofcmds -= originalCmdSize;
            
            HIAHLogInfo(HIAHLogFilesystem, "Removed LC_CODE_SIGNATURE (size: %u bytes)", originalCmdSize);
            return;
        }
        
        cmdsSizeTotal += cmd->cmdsize;
        cmdPtr += cmd->cmdsize;
    }
    
    HIAHLogDebug(HIAHLogFilesystem, "No LC_CODE_SIGNATURE found in binary");
}

@end
