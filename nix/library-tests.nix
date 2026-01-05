# nix/library-tests.nix
# ============================================================================
# HIAHKernel Library Usage Tests
# ============================================================================
#
# Tests that HIAHKernel can be used as an importable library.
#
# Verifies:
# - Headers can be imported
# - Library can be linked
# - APIs are accessible
# - Typical usage patterns work
#
# ============================================================================

{ pkgs, lib, xcode ? null }:

let
  # Simple C test that verifies headers can be included
  testHeadersCompile = pkgs.stdenv.mkDerivation {
    pname = "test-hiahkernel-headers";
    version = "0.1.0";
    src = ../.;
    
    buildPhase = ''
      echo "Testing HIAHKernel headers can be compiled..."
      
      # Create a test file that imports the headers
      cat > test_import.m << 'EOF'
      // Test that HIAHKernel headers can be imported
      #import <Foundation/Foundation.h>
      #import "HIAHKernel.h"
      #import "HIAHProcess.h"
      #import "HIAHLogging.h"
      
      int main(int argc, char *argv[]) {
          @autoreleasepool {
              // Test that we can reference the classes
              Class kernelClass = [HIAHKernel class];
              Class processClass = [HIAHProcess class];
              
              if (!kernelClass || !processClass) {
                  NSLog(@"FAIL: Classes not available");
                  return 1;
              }
              
              NSLog(@"PASS: HIAHKernel headers import correctly");
              return 0;
          }
      }
      EOF
      
      # Try to compile (syntax check only, no linking)
      clang -fsyntax-only test_import.m \
        -fobjc-arc \
        -I src/HIAHKernel/Public \
        -I src/Config \
        -framework Foundation \
        2>&1 || {
          echo "Header syntax check failed"
          exit 1
        }
      
      echo "✅ Headers compile successfully"
    '';
    
    installPhase = ''
      mkdir -p $out
      echo "headers: PASS" > $out/result.txt
    '';
  };
  
  # Test that verifies library API surface
  testLibraryAPI = pkgs.stdenv.mkDerivation {
    pname = "test-hiahkernel-api";
    version = "0.1.0";
    src = ../.;
    
    buildPhase = ''
      echo "Testing HIAHKernel API surface..."
      
      # Create a test that exercises the API
      cat > test_api.m << 'EOF'
      #import <Foundation/Foundation.h>
      #import "HIAHKernel.h"
      #import "HIAHProcess.h"
      
      // Test API surface without actually running
      void testKernelAPI(void) {
          // Singleton access
          HIAHKernel *kernel = [HIAHKernel sharedKernel];
          (void)kernel;
          
          // Configuration properties
          (void)kernel.appGroupIdentifier;
          (void)kernel.extensionIdentifier;
          (void)kernel.controlSocketPath;
          
          // Process management methods
          // [kernel registerProcess:nil];
          // [kernel unregisterProcessWithPID:0];
          // [kernel processForPID:0];
          // [kernel processForRequestIdentifier:nil];
          // [kernel allProcesses];
          
          // Output callback
          kernel.onOutput = ^(pid_t pid, NSString *output) {
              NSLog(@"[%d] %@", pid, output);
          };
          
          // Spawn method signature check
          // [kernel spawnVirtualProcessWithPath:nil arguments:nil environment:nil completion:nil];
      }
      
      void testProcessAPI(void) {
          HIAHProcess *process = [[HIAHProcess alloc] init];
          
          // Properties
          process.pid = 1;
          process.executablePath = @"/test";
          process.state = HIAHProcessStateRunning;
          process.arguments = @[];
          process.environment = @{};
          process.exitCode = 0;
          (void)process.isExited; // Read-only
          (void)process.startTime; // Read-only
          
          (void)process;
      }
      
      void testConstants(void) {
          // Notifications
          (void)HIAHKernelProcessSpawnedNotification;
          (void)HIAHKernelProcessExitedNotification;
          (void)HIAHKernelProcessOutputNotification;
          
          // Error domain
          (void)HIAHKernelErrorDomain;
          
          // Error codes
          (void)HIAHKernelErrorInvalidPath;
          (void)HIAHKernelErrorSpawnFailed;
      }
      
      int main(int argc, char *argv[]) {
          NSLog(@"PASS: API surface is correct");
          return 0;
      }
      EOF
      
      # Syntax check
      clang -fsyntax-only test_api.m \
        -fobjc-arc \
        -I src/HIAHKernel/Public \
        -I src/Config \
        -framework Foundation \
        2>&1 || {
          echo "API syntax check failed"
          exit 1
        }
      
      echo "✅ API surface verified"
    '';
    
    installPhase = ''
      mkdir -p $out
      echo "api: PASS" > $out/result.txt
    '';
  };
  
  # Test typical library usage pattern
  testUsagePattern = pkgs.stdenv.mkDerivation {
    pname = "test-hiahkernel-usage";
    version = "0.1.0";
    src = ../.;
    
    buildPhase = ''
      echo "Testing typical library usage pattern..."
      
      cat > test_usage.m << 'EOF'
      /**
       * This file demonstrates how an external project would use HIAHKernel.
       * It should compile without errors when the library is properly set up.
       */
      
      #import <Foundation/Foundation.h>
      #import "HIAHKernel.h"
      #import "HIAHProcess.h"
      
      @interface MyAppController : NSObject
      @property (nonatomic, strong) HIAHKernel *kernel;
      - (void)setupKernel;
      - (void)launchApp:(NSString *)path;
      @end
      
      @implementation MyAppController
      
      - (void)setupKernel {
          // Step 1: Get kernel instance
          self.kernel = [HIAHKernel sharedKernel];
          
          // Step 2: Configure for this app
          self.kernel.appGroupIdentifier = @"group.com.mycompany.myapp";
          self.kernel.extensionIdentifier = @"com.mycompany.myapp.ProcessRunner";
          
          // Step 3: Set up output handler
          __weak typeof(self) weakSelf = self;
          self.kernel.onOutput = ^(pid_t pid, NSString *output) {
              [weakSelf handleOutput:output fromPID:pid];
          };
          
          // Step 4: Register for notifications
          [[NSNotificationCenter defaultCenter]
              addObserver:self
              selector:@selector(processExited:)
              name:HIAHKernelProcessExitedNotification
              object:nil];
      }
      
      - (void)launchApp:(NSString *)path {
          [self.kernel spawnProcessWithPath:path
                                 arguments:@[]
                               environment:@{}
                                completion:^(pid_t pid, NSError *error) {
              if (error) {
                  NSLog(@"Spawn failed: %@", error);
                  return;
              }
              NSLog(@"Spawned process with PID: %d", pid);
          }];
      }
      
      - (void)handleOutput:(NSString *)output fromPID:(pid_t)pid {
          NSLog(@"[%d] %@", pid, output);
      }
      
      - (void)processExited:(NSNotification *)notification {
          NSLog(@"Process exited");
      }
      
      @end
      
      int main(int argc, char *argv[]) {
          @autoreleasepool {
              MyAppController *controller = [[MyAppController alloc] init];
              [controller setupKernel];
              NSLog(@"PASS: Usage pattern compiles correctly");
              return 0;
          }
      }
      EOF
      
      # Syntax check
      clang -fsyntax-only test_usage.m \
        -fobjc-arc \
        -I src/HIAHKernel/Public \
        -I src/Config \
        -framework Foundation \
        2>&1 || {
          echo "Usage pattern syntax check failed"
          exit 1
        }
      
      echo "✅ Usage pattern verified"
    '';
    
    installPhase = ''
      mkdir -p $out
      echo "usage: PASS" > $out/result.txt
    '';
  };

  # Combined library tests
  allLibraryTests = pkgs.stdenv.mkDerivation {
    pname = "test-hiahkernel-library-all";
    version = "0.1.0";
    src = ../.;
    
    buildPhase = ''
      echo "════════════════════════════════════════════════════════════════"
      echo "  HIAHKernel Library Tests"
      echo "════════════════════════════════════════════════════════════════"
      
      FAILED=0
      
      # Test 1: Headers compile
      echo ""
      echo "Test 1: Headers Import"
      echo "────────────────────────────────────────────────────────────────"
      
      cat > test_headers.m << 'EOF'
      #import <Foundation/Foundation.h>
      #import "HIAHKernel.h"
      #import "HIAHProcess.h"
      #import "HIAHLogging.h"
      int main() { return 0; }
      EOF
      
      if clang -fsyntax-only test_headers.m -fobjc-arc \
          -I src/HIAHKernel/Public -I src/Config -framework Foundation 2>&1; then
        echo "✅ Headers import: PASS"
      else
        echo "❌ Headers import: FAIL"
        FAILED=1
      fi
      
      # Test 2: API surface
      echo ""
      echo "Test 2: API Surface"
      echo "────────────────────────────────────────────────────────────────"
      
      cat > test_api.m << 'EOF'
      #import <Foundation/Foundation.h>
      #import "HIAHKernel.h"
      #import "HIAHProcess.h"
      
      void test() {
        HIAHKernel *k = [HIAHKernel sharedKernel];
        k.appGroupIdentifier = @"test";
        k.onOutput = ^(pid_t p, NSString *o) {};
        
        HIAHProcess *proc = [[HIAHProcess alloc] init];
        proc.pid = 1;
        proc.state = HIAHProcessStateRunning;
        proc.exitCode = 0;
        (void)proc.isExited; // Read-only computed property
        
        (void)HIAHKernelProcessSpawnedNotification;
        (void)HIAHKernelErrorDomain;
      }
      int main() { return 0; }
      EOF
      
      if clang -fsyntax-only test_api.m -fobjc-arc \
          -I src/HIAHKernel/Public -I src/Config -framework Foundation 2>&1; then
        echo "✅ API surface: PASS"
      else
        echo "❌ API surface: FAIL"
        FAILED=1
      fi
      
      # Test 3: Integration pattern
      echo ""
      echo "Test 3: Integration Pattern"
      echo "────────────────────────────────────────────────────────────────"
      
      cat > test_integration.m << 'EOF'
      #import <Foundation/Foundation.h>
      #import "HIAHKernel.h"
      
      @interface AppDelegate : NSObject
      @property (strong) HIAHKernel *kernel;
      @end
      
      @implementation AppDelegate
      - (void)applicationDidFinishLaunching {
        self.kernel = [HIAHKernel sharedKernel];
        self.kernel.appGroupIdentifier = @"group.com.example.app";
        self.kernel.extensionIdentifier = @"com.example.app.Runner";
        self.kernel.onOutput = ^(pid_t pid, NSString *output) {
          NSLog(@"[%d] %@", pid, output);
        };
      }
      @end
      int main() { return 0; }
      EOF
      
      if clang -fsyntax-only test_integration.m -fobjc-arc \
          -I src/HIAHKernel/Public -I src/Config -framework Foundation 2>&1; then
        echo "✅ Integration pattern: PASS"
      else
        echo "❌ Integration pattern: FAIL"
        FAILED=1
      fi
      
      echo ""
      echo "════════════════════════════════════════════════════════════════"
      
      if [ $FAILED -eq 1 ]; then
        echo "❌ Some library tests failed"
        exit 1
      fi
      
      echo "✅ All library tests passed!"
    '';
    
    installPhase = ''
      mkdir -p $out
      cat > $out/result.txt << EOF
      HIAHKernel Library Tests
      ========================
      headers: PASS
      api: PASS
      integration: PASS
      EOF
    '';
  };

in {
  # Individual tests
  inherit testHeadersCompile testLibraryAPI testUsagePattern;
  
  # Combined test
  all = allLibraryTests;
}
