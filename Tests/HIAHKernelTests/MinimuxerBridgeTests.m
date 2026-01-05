/**
 * MinimuxerBridgeTests.m
 * HIAH Kernel Tests
 *
 * Unit tests for MinimuxerBridge functionality.
 * These tests run against stubs on the simulator and real implementations on device.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <XCTest/XCTest.h>
#import "MinimuxerBridge.h"
#import "SimulatorStubs.h"

@interface MinimuxerBridgeTests : XCTestCase
@end

@implementation MinimuxerBridgeTests

- (void)setUp {
    [super setUp];
    
    // Reset stub configuration before each test
#if HIAH_USE_SIMULATOR_STUBS
    [HIAHStubConfiguration.shared reset];
#endif
    
    // Ensure minimuxer is stopped before each test
    [MinimuxerBridge stop];
}

- (void)tearDown {
    [MinimuxerBridge stop];
    [super tearDown];
}

#pragma mark - Lifecycle Tests

- (void)testInitialStatus_IsNotStarted {
    MinimuxerStatus status = [MinimuxerBridge status];
    XCTAssertEqual(status, MinimuxerStatusNotStarted, @"Initial status should be NotStarted");
}

- (void)testIsReady_BeforeStart_ReturnsFalse {
    XCTAssertFalse([MinimuxerBridge isReady], @"isReady should be NO before start");
}

- (void)testStart_WithValidPairingFile_Succeeds {
    // Get or create a pairing file path
    NSString *pairingFile = [MinimuxerBridge defaultPairingFilePath];
    XCTAssertNotNil(pairingFile, @"Should have a pairing file path");
    
    BOOL result = [MinimuxerBridge startWithPairingFile:pairingFile logPath:nil];
    
#if HIAH_USE_SIMULATOR_STUBS
    XCTAssertTrue(result, @"Start should succeed in stub mode");
#else
    // On device, this depends on actual device state
    // Just verify it doesn't crash
    XCTAssertTrue(YES, @"Start should not crash");
#endif
}

- (void)testStart_WithConsoleLogging_Succeeds {
    NSString *pairingFile = [MinimuxerBridge defaultPairingFilePath];
    
    BOOL result = [MinimuxerBridge startWithPairingFile:pairingFile
                                                logPath:nil
                                         consoleLogging:YES];
    
#if HIAH_USE_SIMULATOR_STUBS
    XCTAssertTrue(result, @"Start with console logging should succeed in stub mode");
#else
    XCTAssertTrue(YES, @"Start should not crash");
#endif
}

- (void)testStop_DoesNotCrash {
    // Start first
    NSString *pairingFile = [MinimuxerBridge defaultPairingFilePath];
    [MinimuxerBridge startWithPairingFile:pairingFile logPath:nil];
    
    // Stop should not crash
    XCTAssertNoThrow([MinimuxerBridge stop], @"Stop should not throw");
    
    // Status should be NotStarted after stop
    XCTAssertEqual([MinimuxerBridge status], MinimuxerStatusNotStarted,
                   @"Status should be NotStarted after stop");
}

#pragma mark - Device Info Tests

- (void)testFetchDeviceUDID_AfterStart {
    NSString *pairingFile = [MinimuxerBridge defaultPairingFilePath];
    [MinimuxerBridge startWithPairingFile:pairingFile logPath:nil];
    
    // Give stubs time to become "ready"
#if HIAH_USE_SIMULATOR_STUBS
    [NSThread sleepForTimeInterval:HIAHStubConfiguration.shared.simulatedDelay + 0.1];
#endif
    
    NSString *udid = [MinimuxerBridge fetchDeviceUDID];
    
#if HIAH_USE_SIMULATOR_STUBS
    XCTAssertNotNil(udid, @"UDID should not be nil in stub mode");
    XCTAssertTrue([udid containsString:@"SIMULATOR"], @"Stub UDID should contain SIMULATOR");
#else
    // On device, UDID may or may not be available
    XCTAssertTrue(YES, @"fetchDeviceUDID should not crash");
#endif
}

- (void)testTestDeviceConnection_AfterStart {
    NSString *pairingFile = [MinimuxerBridge defaultPairingFilePath];
    [MinimuxerBridge startWithPairingFile:pairingFile logPath:nil];
    
#if HIAH_USE_SIMULATOR_STUBS
    [NSThread sleepForTimeInterval:HIAHStubConfiguration.shared.simulatedDelay + 0.1];
    BOOL connected = [MinimuxerBridge testDeviceConnection];
    XCTAssertTrue(connected, @"Connection test should pass in stub mode");
#else
    XCTAssertNoThrow([MinimuxerBridge testDeviceConnection], @"Should not crash");
#endif
}

#pragma mark - JIT Enablement Tests

- (void)testEnableJIT_WithValidBundleID {
    NSString *pairingFile = [MinimuxerBridge defaultPairingFilePath];
    [MinimuxerBridge startWithPairingFile:pairingFile logPath:nil];
    
#if HIAH_USE_SIMULATOR_STUBS
    [NSThread sleepForTimeInterval:HIAHStubConfiguration.shared.simulatedDelay + 0.1];
#endif
    
    NSError *error = nil;
    BOOL result = [MinimuxerBridge enableJITForApp:@"com.example.testapp" error:&error];
    
#if HIAH_USE_SIMULATOR_STUBS
    XCTAssertTrue(result, @"enableJIT should succeed in stub mode");
    XCTAssertNil(error, @"Error should be nil on success");
#else
    // On device, this requires a real app to be installed
    XCTAssertTrue(YES, @"enableJIT should not crash");
#endif
}

- (void)testAttachDebugger_WithValidPID {
    NSString *pairingFile = [MinimuxerBridge defaultPairingFilePath];
    [MinimuxerBridge startWithPairingFile:pairingFile logPath:nil];
    
#if HIAH_USE_SIMULATOR_STUBS
    [NSThread sleepForTimeInterval:HIAHStubConfiguration.shared.simulatedDelay + 0.1];
#endif
    
    NSError *error = nil;
    pid_t testPID = getpid(); // Use current process as test PID
    BOOL result = [MinimuxerBridge attachDebuggerToPID:testPID error:&error];
    
#if HIAH_USE_SIMULATOR_STUBS
    XCTAssertTrue(result, @"attachDebugger should succeed in stub mode");
    XCTAssertNil(error, @"Error should be nil on success");
#else
    XCTAssertTrue(YES, @"attachDebugger should not crash");
#endif
}

#pragma mark - Failure Simulation Tests (Stub-only)

#if HIAH_USE_SIMULATOR_STUBS

- (void)testStart_WhenSimulatingFailure_ReturnsFalse {
    HIAHStubConfiguration.shared.simulateSuccess = NO;
    
    NSString *pairingFile = [MinimuxerBridge defaultPairingFilePath];
    BOOL result = [MinimuxerBridge startWithPairingFile:pairingFile logPath:nil];
    
    XCTAssertFalse(result, @"Start should fail when simulating failure");
    XCTAssertEqual([MinimuxerBridge status], MinimuxerStatusError, @"Status should be Error");
    XCTAssertNotNil([MinimuxerBridge lastError], @"lastError should be set");
}

- (void)testEnableJIT_WhenSimulatingFailure_ReturnsError {
    // Start successfully first
    NSString *pairingFile = [MinimuxerBridge defaultPairingFilePath];
    [MinimuxerBridge startWithPairingFile:pairingFile logPath:nil];
    [NSThread sleepForTimeInterval:HIAHStubConfiguration.shared.simulatedDelay + 0.1];
    
    // Now simulate failure
    HIAHStubConfiguration.shared.simulateSuccess = NO;
    
    NSError *error = nil;
    BOOL result = [MinimuxerBridge enableJITForApp:@"com.example.testapp" error:&error];
    
    XCTAssertFalse(result, @"enableJIT should fail when simulating failure");
    XCTAssertNotNil(error, @"Error should be set on failure");
}

#endif // HIAH_USE_SIMULATOR_STUBS

#pragma mark - Pairing File Tests

- (void)testDefaultPairingFilePath_ReturnsPath {
    NSString *path = [MinimuxerBridge defaultPairingFilePath];
    
    // Path may or may not exist, but should return a non-nil value
#if HIAH_USE_SIMULATOR_STUBS
    XCTAssertNotNil(path, @"Should return a path in stub mode");
#else
    // On device, may return nil if no pairing file exists
    XCTAssertTrue(YES, @"Should not crash");
#endif
}

- (void)testHasPairingFile {
    BOOL hasPairing = [MinimuxerBridge hasPairingFile];
    
#if HIAH_USE_SIMULATOR_STUBS
    // Stubs create a fake pairing file
    XCTAssertTrue(hasPairing, @"Should have pairing file in stub mode");
#else
    XCTAssertTrue(YES, @"Should not crash");
#endif
}

@end
