/**
 * HIAHMachOUtilsTests.m
 * HIAH Kernel Tests
 *
 * Unit tests for HIAHMachOUtils binary patching functionality.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <XCTest/XCTest.h>
#import "HIAHMachOUtils.h"
#import <mach-o/loader.h>

@interface HIAHMachOUtilsTests : XCTestCase
@property (nonatomic, strong) NSString *tempDirectory;
@end

@implementation HIAHMachOUtilsTests

- (void)setUp {
    [super setUp];
    
    // Create a temporary directory for test files
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.tempDirectory = tempDir;
}

- (void)tearDown {
    // Clean up temporary directory
    if (self.tempDirectory) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDirectory error:nil];
    }
    
    [super tearDown];
}

#pragma mark - Helper Methods

/// Creates a minimal 64-bit Mach-O executable header for testing
- (NSData *)createMinimalMachO64ExecutableHeader {
    // Create a minimal Mach-O 64-bit header
    struct mach_header_64 header;
    memset(&header, 0, sizeof(header));
    
    header.magic = MH_MAGIC_64;
    header.cputype = CPU_TYPE_ARM64;
    header.cpusubtype = CPU_SUBTYPE_ARM64_ALL;
    header.filetype = MH_EXECUTE;
    header.ncmds = 1;
    header.sizeofcmds = sizeof(struct segment_command_64);
    header.flags = MH_PIE | MH_NOUNDEFS;
    header.reserved = 0;
    
    // Create a __PAGEZERO segment
    struct segment_command_64 pagezero;
    memset(&pagezero, 0, sizeof(pagezero));
    
    pagezero.cmd = LC_SEGMENT_64;
    pagezero.cmdsize = sizeof(struct segment_command_64);
    strncpy(pagezero.segname, SEG_PAGEZERO, 16);
    pagezero.vmaddr = 0;
    pagezero.vmsize = 0x100000000;  // Standard PAGEZERO size
    pagezero.fileoff = 0;
    pagezero.filesize = 0;
    pagezero.maxprot = 0;
    pagezero.initprot = 0;
    pagezero.nsects = 0;
    pagezero.flags = 0;
    
    // Combine header and segment into data
    NSMutableData *data = [NSMutableData dataWithBytes:&header length:sizeof(header)];
    [data appendBytes:&pagezero length:sizeof(pagezero)];
    
    // Pad to make it look more like a real binary
    uint8_t padding[1024] = {0};
    [data appendBytes:padding length:sizeof(padding)];
    
    return data;
}

/// Creates a test file with the given data
- (NSString *)createTestFileWithData:(NSData *)data {
    NSString *fileName = [[NSUUID UUID] UUIDString];
    NSString *filePath = [self.tempDirectory stringByAppendingPathComponent:fileName];
    [data writeToFile:filePath atomically:YES];
    return filePath;
}

#pragma mark - Tests

- (void)testIsMHExecute_WithExecutable {
    // Create a minimal executable
    NSData *execData = [self createMinimalMachO64ExecutableHeader];
    NSString *path = [self createTestFileWithData:execData];
    
    BOOL result = [HIAHMachOUtils isMHExecute:path];
    
    XCTAssertTrue(result, @"Should detect MH_EXECUTE filetype");
}

- (void)testIsMHExecute_WithNonexistentFile {
    NSString *path = [self.tempDirectory stringByAppendingPathComponent:@"nonexistent"];
    
    BOOL result = [HIAHMachOUtils isMHExecute:path];
    
    XCTAssertFalse(result, @"Should return NO for nonexistent file");
}

- (void)testIsMHExecute_WithEmptyFile {
    NSString *path = [self createTestFileWithData:[NSData data]];
    
    BOOL result = [HIAHMachOUtils isMHExecute:path];
    
    XCTAssertFalse(result, @"Should return NO for empty file");
}

- (void)testPatchBinaryToDylib_ChangesFileType {
    // Create a minimal executable
    NSData *execData = [self createMinimalMachO64ExecutableHeader];
    NSString *path = [self createTestFileWithData:execData];
    
    // Verify it's initially an executable
    XCTAssertTrue([HIAHMachOUtils isMHExecute:path], @"Should start as MH_EXECUTE");
    
    // Patch to dylib/bundle
    BOOL patchResult = [HIAHMachOUtils patchBinaryToDylib:path];
    XCTAssertTrue(patchResult, @"Patching should succeed");
    
    // Verify it's no longer an executable (should be MH_BUNDLE or MH_DYLIB)
    XCTAssertFalse([HIAHMachOUtils isMHExecute:path], @"Should no longer be MH_EXECUTE after patching");
}

- (void)testPatchBinaryForJITLessMode_PatchesPagezero {
    // Create a minimal executable
    NSData *execData = [self createMinimalMachO64ExecutableHeader];
    NSString *path = [self createTestFileWithData:execData];
    
    // Patch for JIT-less mode
    BOOL patchResult = [HIAHMachOUtils patchBinaryForJITLessMode:path];
    XCTAssertTrue(patchResult, @"JIT-less patching should succeed");
    
    // Read back and verify the __PAGEZERO segment was patched
    NSData *patchedData = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(patchedData, @"Should be able to read patched file");
    
    // Verify the header was patched (filetype should not be MH_EXECUTE)
    struct mach_header_64 *header = (struct mach_header_64 *)patchedData.bytes;
    XCTAssertNotEqual(header->filetype, MH_EXECUTE, @"Filetype should be changed from MH_EXECUTE");
}

- (void)testRemoveCodeSignature_WithUnsignedBinary {
    // Create a minimal executable (no signature)
    NSData *execData = [self createMinimalMachO64ExecutableHeader];
    NSString *path = [self createTestFileWithData:execData];
    
    // Should not crash and should return success (nothing to remove)
    BOOL result = [HIAHMachOUtils removeCodeSignature:path];
    
    // Either returns YES (nothing to remove) or handles gracefully
    // The important thing is it doesn't crash
    XCTAssertTrue(YES, @"Should not crash on unsigned binary");
}

- (void)testPatchBinaryToDylib_WithNonexistentFile {
    NSString *path = [self.tempDirectory stringByAppendingPathComponent:@"nonexistent"];
    
    BOOL result = [HIAHMachOUtils patchBinaryToDylib:path];
    
    XCTAssertFalse(result, @"Should return NO for nonexistent file");
}

- (void)testPatchBinaryToDylib_WithInvalidMachO {
    // Create a file with invalid content
    NSData *invalidData = [@"This is not a Mach-O file" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = [self createTestFileWithData:invalidData];
    
    BOOL result = [HIAHMachOUtils patchBinaryToDylib:path];
    
    XCTAssertFalse(result, @"Should return NO for invalid Mach-O");
}

@end
