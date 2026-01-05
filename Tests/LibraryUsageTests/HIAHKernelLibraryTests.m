/**
 * HIAHKernelLibraryTests.m
 * Tests that HIAHKernel can be imported and used as a library.
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import <XCTest/XCTest.h>
#import "HIAHKernel.h"
#import "HIAHProcess.h"
#import "HIAHLogging.h"

@interface HIAHKernelLibraryTests : XCTestCase
@end

@implementation HIAHKernelLibraryTests

#pragma mark - Header Import Tests

- (void)testHeadersImportable {
    Class kernelClass = [HIAHKernel class];
    XCTAssertNotNil(kernelClass, @"HIAHKernel class should be importable");
    
    Class processClass = [HIAHProcess class];
    XCTAssertNotNil(processClass, @"HIAHProcess class should be importable");
}

- (void)testNotificationsExported {
    XCTAssertNotNil(HIAHKernelProcessSpawnedNotification);
    XCTAssertNotNil(HIAHKernelProcessExitedNotification);
    XCTAssertNotNil(HIAHKernelProcessOutputNotification);
}

- (void)testErrorDomainExported {
    XCTAssertNotNil(HIAHKernelErrorDomain);
}

#pragma mark - Singleton Tests

- (void)testSharedKernelAccessible {
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    XCTAssertNotNil(kernel);
}

- (void)testSharedKernelIsSingleton {
    HIAHKernel *kernel1 = [HIAHKernel sharedKernel];
    HIAHKernel *kernel2 = [HIAHKernel sharedKernel];
    XCTAssertEqual(kernel1, kernel2);
}

#pragma mark - Configuration Tests

- (void)testAppGroupIdentifierConfigurable {
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    XCTAssertNotNil(kernel.appGroupIdentifier);
    
    NSString *customGroup = @"group.com.example.myapp";
    kernel.appGroupIdentifier = customGroup;
    XCTAssertEqualObjects(kernel.appGroupIdentifier, customGroup);
    
    // Restore default
    kernel.appGroupIdentifier = @"group.com.aspauldingcode.HIAHDesktop";
}

- (void)testExtensionIdentifierConfigurable {
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    XCTAssertNotNil(kernel.extensionIdentifier);
    
    NSString *customExtension = @"com.example.myapp.ProcessRunner";
    kernel.extensionIdentifier = customExtension;
    XCTAssertEqualObjects(kernel.extensionIdentifier, customExtension);
    
    // Restore default
    kernel.extensionIdentifier = @"com.aspauldingcode.HIAHDesktop.ProcessRunner";
}

#pragma mark - Process Table Tests

- (void)testProcessTableOperations {
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    
    HIAHProcess *process = [[HIAHProcess alloc] init];
    process.pid = 12345;
    process.executablePath = @"/test/path";
    process.state = HIAHProcessStateRunning;
    
    [kernel registerProcess:process];
    
    HIAHProcess *found = [kernel processForPID:12345];
    XCTAssertNotNil(found);
    XCTAssertEqual(found.pid, 12345);
    
    NSArray *all = [kernel allProcesses];
    XCTAssertTrue([all containsObject:process]);
    
    [kernel unregisterProcessWithPID:12345];
    HIAHProcess *notFound = [kernel processForPID:12345];
    XCTAssertNil(notFound);
}

#pragma mark - Output Callback Tests

- (void)testOutputCallbackSettable {
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    
    kernel.onOutput = ^(pid_t pid, NSString *output) {};
    XCTAssertNotNil(kernel.onOutput);
    kernel.onOutput = nil;
}

#pragma mark - HIAHProcess Tests

- (void)testProcessCreation {
    HIAHProcess *process = [[HIAHProcess alloc] init];
    XCTAssertNotNil(process);
}

- (void)testProcessProperties {
    HIAHProcess *process = [[HIAHProcess alloc] init];
    
    process.pid = 1234;
    XCTAssertEqual(process.pid, 1234);
    
    process.executablePath = @"/test/path";
    XCTAssertEqualObjects(process.executablePath, @"/test/path");
    
    process.state = HIAHProcessStateRunning;
    XCTAssertEqual(process.state, HIAHProcessStateRunning);
    XCTAssertFalse(process.isExited);
    
    process.state = HIAHProcessStateTerminated;
    XCTAssertTrue(process.isExited);
    
    process.exitCode = 42;
    XCTAssertEqual(process.exitCode, 42);
}

- (void)testProcessFactoryMethod {
    HIAHProcess *process = [HIAHProcess processWithPath:@"/bin/test"
                                              arguments:@[@"--help"]
                                            environment:@{@"HOME": @"/tmp"}];
    
    XCTAssertNotNil(process);
    XCTAssertEqualObjects(process.executablePath, @"/bin/test");
    XCTAssertEqualObjects(process.arguments, (@[@"--help"]));
    XCTAssertEqualObjects(process.environment[@"HOME"], @"/tmp");
}

#pragma mark - Integration Pattern Tests

- (void)testTypicalUsagePattern {
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    XCTAssertNotNil(kernel);
    
    kernel.appGroupIdentifier = @"group.com.example.testapp";
    kernel.extensionIdentifier = @"com.example.testapp.ProcessRunner";
    
    kernel.onOutput = ^(pid_t pid, NSString *output) {
        NSLog(@"[%d] %@", pid, output);
    };
    
    XCTAssertEqualObjects(kernel.appGroupIdentifier, @"group.com.example.testapp");
    XCTAssertNotNil(kernel.onOutput);
    
    // Reset
    kernel.appGroupIdentifier = @"group.com.aspauldingcode.HIAHDesktop";
    kernel.extensionIdentifier = @"com.aspauldingcode.HIAHDesktop.ProcessRunner";
    kernel.onOutput = nil;
}

#pragma mark - Error Codes Tests

- (void)testErrorCodesAccessible {
    XCTAssertEqual(HIAHKernelErrorInvalidPath, 1);
    XCTAssertEqual(HIAHKernelErrorSpawnFailed, 2);
    XCTAssertEqual(HIAHKernelErrorSocketFailed, 3);
    XCTAssertEqual(HIAHKernelErrorProcessNotFound, 4);
    XCTAssertEqual(HIAHKernelErrorBinaryPatchFailed, 5);
}

- (void)testCanCreateKernelErrors {
    NSError *error = [NSError errorWithDomain:HIAHKernelErrorDomain
                                         code:HIAHKernelErrorInvalidPath
                                     userInfo:@{NSLocalizedDescriptionKey: @"Test"}];
    
    XCTAssertEqualObjects(error.domain, HIAHKernelErrorDomain);
    XCTAssertEqual(error.code, HIAHKernelErrorInvalidPath);
}

#pragma mark - Shutdown

- (void)testShutdown {
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    XCTAssertNoThrow([kernel shutdown]);
}

@end
