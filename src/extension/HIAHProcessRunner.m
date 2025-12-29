/**
 * HIAHProcessRunner.m
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * XPC Extension for running guest iOS applications within HIAH Desktop.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import <Foundation/Foundation.h>
// UIKit not available in extension context - use Foundation only
// #import <UIKit/UIKit.h>
#import "../HIAHDesktop/HIAHLogging.h"
#import "../HIAHDesktop/HIAHMachOUtils.h"
#import "../hooks/HIAHDyldBypass.h"
#import "../hooks/HIAHHook.h"
#import "HIAHSigner.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <objc/runtime.h>
#import <stdarg.h>

#pragma mark - Logging

static HIAHLogSubsystem GetExtensionLog(void) { return HIAHLogExtension(); }

// Force linkage of HIAHExtensionHandler class by referencing it
static Class gHIAHExtensionHandlerClass = nil;

__attribute__((constructor(101))) static void ExtensionStartup(void) {
  // Log to file immediately
  NSFileManager *fm = [NSFileManager defaultManager];
  NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:
                            @"group.com.aspauldingcode.HIAHDesktop"];
  NSString *logPath = nil;
  if (groupURL) {
    logPath =
        [[groupURL.path stringByAppendingPathComponent:@"HIAHExtension.log"]
            stringByStandardizingPath];
    [fm createDirectoryAtPath:groupURL.path
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  } else {
    logPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"HIAHExtension.log"];
  }

  FILE *logFile = fopen([logPath UTF8String], "a");
  if (logFile) {
    fprintf(logFile,
            "[HIAHExtension] Extension loaded (constructor) (PID=%d)\n",
            getpid());
    fprintf(logFile, "[HIAHExtension] Log file: %s\n", [logPath UTF8String]);
    fprintf(logFile, "[HIAHExtension] About to initialize dyld bypass...\n");
    fflush(logFile);
  }

  fprintf(stderr, "[HIAHExtension] Extension loaded (PID=%d)\n", getpid());
  fprintf(stdout, "[HIAHExtension] Extension loaded (PID=%d)\n", getpid());
  fflush(stdout);
  fflush(stderr);
  HIAHLogInfo(GetExtensionLog, "HIAHProcessRunner extension loaded (PID=%d)",
              getpid());

  // CRITICAL: Initialize dyld bypass BEFORE loading any guest apps
  // This patches dyld to allow loading binaries with invalid signatures
  fprintf(stdout, "[HIAHExtension] Initializing dyld bypass...\n");
  fflush(stdout);

  if (logFile) {
    fprintf(logFile, "[HIAHExtension] Calling HIAHInitDyldBypass()...\n");
    fflush(logFile);
  }

  @try {
    HIAHInitDyldBypass();
    fprintf(stdout, "[HIAHExtension] Dyld bypass initialized\n");
    if (logFile) {
      fprintf(logFile,
              "[HIAHExtension] Dyld bypass initialized successfully\n");
      fflush(logFile);
    }
  } @catch (NSException *ex) {
    fprintf(stdout, "[HIAHExtension] ERROR: Dyld bypass failed: %s\n",
            [[ex description] UTF8String]);
    if (logFile) {
      fprintf(logFile, "[HIAHExtension] ERROR: Dyld bypass failed: %s\n",
              [[ex description] UTF8String]);
      fflush(logFile);
    }
  }
  fflush(stdout);

  // Check JIT status
  BOOL jitEnabled = HIAHIsJITEnabled();
  if (jitEnabled) {
    fprintf(stdout, "[HIAHExtension] ✓ JIT/CS_DEBUGGED enabled\n");
    if (logFile) {
      fprintf(logFile, "[HIAHExtension] ✓ JIT/CS_DEBUGGED enabled\n");
      fflush(logFile);
    }
  } else {
    fprintf(stdout, "[HIAHExtension] ⚠️  JIT not enabled - may have issues "
                    "loading .ipa apps\n");
    if (logFile) {
      fprintf(logFile, "[HIAHExtension] ⚠️  JIT not enabled - may have issues "
                       "loading .ipa apps\n");
      fflush(logFile);
    }
  }
  fflush(stdout);

  if (logFile) {
    fclose(logFile);
  }

  // Force class to load by referencing it (this ensures it's linked)
  gHIAHExtensionHandlerClass = NSClassFromString(@"HIAHExtensionHandler");
  if (gHIAHExtensionHandlerClass) {
    fprintf(stderr, "[HIAHExtension] HIAHExtensionHandler class found via "
                    "NSClassFromString\n");
    fprintf(stdout, "[HIAHExtension] HIAHExtensionHandler class found via "
                    "NSClassFromString\n");
    fflush(stdout);
    fflush(stderr);
  } else {
    fprintf(stderr,
            "[HIAHExtension] ERROR: HIAHExtensionHandler class NOT found!\n");
    fprintf(stdout,
            "[HIAHExtension] ERROR: HIAHExtensionHandler class NOT found!\n");
    fflush(stdout);
    fflush(stderr);
  }
}

#pragma mark - UIApplicationMain Interception

static int (*gOriginalUIApplicationMain)(int, char *[], NSString *,
                                         NSString *) = NULL;
static BOOL gGuestActive = NO;

static int InterceptedUIApplicationMain(int argc, char *argv[],
                                        NSString *principalClass,
                                        NSString *delegateClass) {
  fprintf(stdout, "[HIAHExtension] *** Guest called UIApplicationMain ***\n");
  fprintf(stdout, "[HIAHExtension]   Principal: %s\n",
          principalClass ? [principalClass UTF8String] : "nil");
  fprintf(stdout, "[HIAHExtension]   Delegate: %s\n",
          delegateClass ? [delegateClass UTF8String] : "nil");
  fprintf(stdout, "[HIAHExtension]   argc: %d\n", argc);
  for (int i = 0; i < argc; i++) {
    fprintf(stdout, "[HIAHExtension]   argv[%d]: %s\n", i, argv[i] ?: "(null)");
  }
  fflush(stdout);

  HIAHLogInfo(GetExtensionLog,
              "Guest called UIApplicationMain (principal=%s, delegate=%s)",
              principalClass ? [principalClass UTF8String] : "nil",
              delegateClass ? [delegateClass UTF8String] : "nil");

  if (gOriginalUIApplicationMain) {
    fprintf(stdout, "[HIAHExtension] Calling original UIApplicationMain...\n");
    fflush(stdout);
    int result =
        gOriginalUIApplicationMain(argc, argv, principalClass, delegateClass);
    fprintf(stdout, "[HIAHExtension] UIApplicationMain returned: %d\n", result);
    fflush(stdout);
    return result;
  }

  fprintf(stdout,
          "[HIAHExtension] ERROR: Original UIApplicationMain not available!\n");
  fflush(stdout);
  HIAHLogError(GetExtensionLog, "Original UIApplicationMain not available");
  return 1;
}

static void InstallUIApplicationMainHook(void) {
  fprintf(stdout, "[HIAHExtension] Installing UIApplicationMain hook...\n");
  fflush(stdout);

  gOriginalUIApplicationMain = dlsym(RTLD_DEFAULT, "UIApplicationMain");

  if (!gOriginalUIApplicationMain) {
    fprintf(stdout,
            "[HIAHExtension] ERROR: UIApplicationMain not found via dlsym\n");
    fflush(stdout);
    HIAHLogError(GetExtensionLog,
                 "UIApplicationMain not found (UIKit may not be loaded)");
    return;
  }

  fprintf(stdout, "[HIAHExtension] Found UIApplicationMain at %p\n",
          (void *)gOriginalUIApplicationMain);
  fflush(stdout);

  HIAHHookResult result =
      HIAHHookIntercept(HIAHHookScopeGlobal, NULL, gOriginalUIApplicationMain,
                        InterceptedUIApplicationMain);

  if (result == HIAHHookResultSuccess) {
    fprintf(stdout,
            "[HIAHExtension] UIApplicationMain hook installed successfully\n");
    fflush(stdout);
    HIAHLogInfo(GetExtensionLog, "UIApplicationMain hook installed");
  } else {
    fprintf(stdout,
            "[HIAHExtension] ERROR: Failed to install hook (code: %d)\n",
            result);
    fflush(stdout);
    HIAHLogError(GetExtensionLog, "Failed to install hook (code: %d)", result);
  }
}

#pragma mark - Bundle Override Support

/**
 * Override NSBundle.mainBundle to point to the guest app's bundle.
 * This is critical for guest apps to find their resources correctly.
 * Inspired by LiveContainer's approach.
 */
static void OverrideMainBundle(NSBundle *guestBundle) {
  if (!guestBundle) {
    fprintf(stderr,
            "[HIAHExtension] WARNING: Cannot override mainBundle with nil\n");
    return;
  }

  // Method 1: Use class_replaceMethod to replace the mainBundle method
  Class bundleClass = [NSBundle class];
  Method originalMethod =
      class_getClassMethod(bundleClass, @selector(mainBundle));

  if (originalMethod) {
    IMP newImplementation = imp_implementationWithBlock(^NSBundle * {
      return guestBundle;
    });

    method_setImplementation(originalMethod, newImplementation);

    fprintf(
        stdout,
        "[HIAHExtension] Overrode NSBundle.mainBundle to point to guest app\n");
    fprintf(stdout, "[HIAHExtension]   Guest bundle path: %s\n",
            [guestBundle.bundlePath UTF8String]);
    fprintf(stdout, "[HIAHExtension]   Guest bundle ID: %s\n",
            guestBundle.bundleIdentifier
                ? [guestBundle.bundleIdentifier UTF8String]
                : "(none)");
    fflush(stdout);
  } else {
    fprintf(stderr,
            "[HIAHExtension] ERROR: Could not find mainBundle method\n");
    fflush(stderr);
  }
}

/**
 * Override CFBundleGetMainBundle to point to the guest app's CFBundle.
 * This ensures CF-level bundle APIs also work correctly.
 */
static void OverrideCFBundle(NSBundle *guestBundle) {
  if (!guestBundle)
    return;

  // Get the CFBundle from NSBundle using CFBundleCreate
  CFBundleRef guestCFBundle = CFBundleCreate(
      kCFAllocatorDefault,
      (__bridge CFURLRef)[NSURL fileURLWithPath:guestBundle.bundlePath]);
  if (!guestCFBundle) {
    fprintf(stderr,
            "[HIAHExtension] WARNING: Could not create CFBundle from path\n");
    return;
  }

  fprintf(stdout, "[HIAHExtension] Created CFBundle for guest app\n");
  fflush(stdout);

  // Note: Actual override of CFBundleGetMainBundle would require hooking,
  // which is complex. For now, we rely on NSBundle.mainBundle override.
  CFRelease(guestCFBundle);
}

#pragma mark - Environment Management

extern char **environ;

static void ClearEnvironment(void) {
  while (environ && environ[0]) {
    char *separator = strchr(environ[0], '=');
    if (separator) {
      size_t keyLength = separator - environ[0];
      char key[keyLength + 1];
      memcpy(key, environ[0], keyLength);
      key[keyLength] = '\0';
      unsetenv(key);
    } else {
      break;
    }
  }
}

static void SetupEnvironment(NSDictionary *environment) {
  if (!environment || environment.count == 0) {
    return;
  }

  ClearEnvironment();

  for (NSString *key in environment) {
    NSString *value = environment[key];
    if ([value isKindOfClass:[NSString class]]) {
      setenv(key.UTF8String, value.UTF8String, 1);
    }
  }

  HIAHLogDebug(GetExtensionLog, "Configured %{public}lu environment variables",
               (unsigned long)environment.count);
}

#pragma mark - Entry Point Discovery

static void *FindEntryPoint(void *dlHandle, NSString *binaryPath) {
  // Try dlsym first
  void *mainSymbol = dlsym(dlHandle, "main");
  if (mainSymbol) {
    HIAHLogDebug(GetExtensionLog, "Found main() via dlsym at %{public}p",
                 mainSymbol);
    return mainSymbol;
  }

  // Parse LC_MAIN from Mach-O
  const char *binaryName = binaryPath.lastPathComponent.UTF8String;
  uint32_t imageCount = _dyld_image_count();

  for (uint32_t i = 0; i < imageCount; i++) {
    const char *imageName = _dyld_get_image_name(i);
    if (!imageName || !strstr(imageName, binaryName)) {
      continue;
    }

    const struct mach_header_64 *header = (void *)_dyld_get_image_header(i);
    if (!header || header->magic != MH_MAGIC_64) {
      continue;
    }

    uint8_t *cmdPtr = (uint8_t *)header + sizeof(struct mach_header_64);

    for (uint32_t j = 0; j < header->ncmds; j++) {
      struct load_command *cmd = (struct load_command *)cmdPtr;

      if (cmd->cmd == LC_MAIN) {
        struct entry_point_command *entryCmd =
            (struct entry_point_command *)cmd;
        void *entryPoint = (void *)header + entryCmd->entryoff;
        HIAHLogDebug(GetExtensionLog, "Found LC_MAIN entry at offset 0x%llx",
                     (uint64_t)entryCmd->entryoff);
        return entryPoint;
      }

      cmdPtr += cmd->cmdsize;
    }
  }

  HIAHLogError(GetExtensionLog, "Could not locate entry point for %s",
               [binaryPath UTF8String]);
  return NULL;
}

#pragma mark - Guest Application Execution

static FILE *GetExtensionLogFile(void) {
  static FILE *logFile = NULL;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:
                              @"group.com.aspauldingcode.HIAHDesktop"];
    NSString *logPath = nil;
    if (groupURL) {
      logPath =
          [[groupURL.path stringByAppendingPathComponent:@"HIAHExtension.log"]
              stringByStandardizingPath];
      [fm createDirectoryAtPath:groupURL.path
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
    } else {
      logPath = [NSTemporaryDirectory()
          stringByAppendingPathComponent:@"HIAHExtension.log"];
    }
    logFile = fopen([logPath UTF8String], "a");
  });
  return logFile;
}

static void ExtLog(FILE *logFile, const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vfprintf(stdout, fmt, args);
  va_end(args);
  fflush(stdout);

  if (logFile) {
    va_start(args, fmt);
    vfprintf(logFile, fmt, args);
    va_end(args);
    fflush(logFile);
  }
}

static void ExecuteGuestApplication(NSDictionary *spawnRequest) {
  FILE *logFile = GetExtensionLogFile();
  ExtLog(logFile, "[HIAHExtension] ========================================\n");
  ExtLog(logFile, "[HIAHExtension] ExecuteGuestApplication CALLED\n");
  ExtLog(logFile, "[HIAHExtension] spawnRequest: %p\n", spawnRequest);
  ExtLog(logFile, "[HIAHExtension] ========================================\n");

  if (!spawnRequest) {
    ExtLog(logFile, "[HIAHExtension] ERROR: spawnRequest is nil!\n");
    HIAHLogError(GetExtensionLog, "spawnRequest is nil");
    return;
  }

  // Extract values with exception handling
  NSString *executablePath = nil;
  NSString *serviceMode = nil;
  NSDictionary *environment = nil;
  NSArray *arguments = nil;

  @try {
    ExtLog(logFile, "[HIAHExtension] Getting spawnRequest keys...\n");

    NSArray *keys = spawnRequest.allKeys;
    if (keys) {
      NSString *keysStr = [keys componentsJoinedByString:@", "];
      ExtLog(logFile, "[HIAHExtension] spawnRequest keys: %s\n",
             [keysStr UTF8String]);
    } else {
      ExtLog(logFile,
             "[HIAHExtension] WARNING: spawnRequest.allKeys returned nil\n");
    }

    HIAHLogInfo(GetExtensionLog, "Starting guest application execution");

    ExtLog(logFile, "[HIAHExtension] Extracting values from spawnRequest...\n");

    executablePath = spawnRequest[@"LSExecutablePath"];
    serviceMode = spawnRequest[@"LSServiceMode"];
    environment = spawnRequest[@"LSEnvironment"];
    arguments = spawnRequest[@"LSArguments"];

    ExtLog(logFile, "[HIAHExtension] Extracted from spawnRequest:\n");
    ExtLog(logFile, "[HIAHExtension]   executablePath: %s\n",
           executablePath ? [executablePath UTF8String] : "(nil)");
    ExtLog(logFile, "[HIAHExtension]   serviceMode: %s\n",
           serviceMode ? [serviceMode UTF8String] : "(nil)");
    ExtLog(logFile, "[HIAHExtension]   environment: %p\n", environment);
    ExtLog(logFile, "[HIAHExtension]   arguments: %p\n", arguments);
    ExtLog(logFile, "[HIAHExtension] Executable path: %s\n",
           executablePath ? [executablePath UTF8String] : "(null)");
    ExtLog(logFile, "[HIAHExtension] Service mode: %s\n",
           serviceMode ? [serviceMode UTF8String] : "(null)");
  } @catch (NSException *exception) {
    ExtLog(logFile,
           "[HIAHExtension] FATAL: Exception accessing spawnRequest: %s - %s\n",
           exception.name ? [exception.name UTF8String] : "(null)",
           exception.reason ? [exception.reason UTF8String] : "(null)");
    HIAHLogError(GetExtensionLog, "Exception accessing spawnRequest: %s - %s",
                 exception.name ? [exception.name UTF8String] : "(null)",
                 exception.reason ? [exception.reason UTF8String] : "(null)");
    return;
  }

  HIAHLogDebug(GetExtensionLog, "Request: mode=%s path=%s",
               serviceMode ? [serviceMode UTF8String] : "(null)",
               executablePath ? [executablePath UTF8String] : "(null)");

  if (![serviceMode isEqualToString:@"spawn"]) {
    ExtLog(logFile, "[HIAHExtension] ERROR: Unsupported service mode: %s\n",
           serviceMode ? [serviceMode UTF8String] : "(null)");
    HIAHLogError(GetExtensionLog, "Unsupported service mode: %s",
                 serviceMode ? [serviceMode UTF8String] : "(null)");
    return;
  }

  if (!executablePath || executablePath.length == 0) {
    ExtLog(logFile, "[HIAHExtension] ERROR: Missing executable path\n");
    HIAHLogError(GetExtensionLog, "Missing executable path in spawn request");
    return;
  }

  if (environment) {
    SetupEnvironment(environment);
  }

  // Resolve the actual executable path
  // If we receive a path to a .app bundle, we need to find the executable
  // inside it
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *actualExecutablePath = executablePath;

  BOOL isDir = NO;
  if ([fm fileExistsAtPath:executablePath isDirectory:&isDir] && isDir) {
    // We were given a .app bundle, need to find the executable
    ExtLog(
        logFile,
        "[HIAHExtension] Received .app bundle path, locating executable...\n");

    NSString *infoPlistPath =
        [executablePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *infoPlist =
        [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    NSString *executableName = infoPlist[@"CFBundleExecutable"];

    if (executableName) {
      // Try direct path: App.app/ExecutableName
      NSString *candidatePath =
          [executablePath stringByAppendingPathComponent:executableName];
      if ([fm fileExistsAtPath:candidatePath]) {
        actualExecutablePath = candidatePath;
        ExtLog(logFile, "[HIAHExtension] Found executable at: %s\n",
               [actualExecutablePath UTF8String]);
      } else {
        // Try macOS-style path: App.app/Contents/MacOS/ExecutableName
        candidatePath =
            [executablePath stringByAppendingPathComponent:@"Contents/MacOS"];
        candidatePath =
            [candidatePath stringByAppendingPathComponent:executableName];
        if ([fm fileExistsAtPath:candidatePath]) {
          actualExecutablePath = candidatePath;
          ExtLog(logFile, "[HIAHExtension] Found executable at: %s\n",
                 [actualExecutablePath UTF8String]);
        } else {
          ExtLog(logFile,
                 "[HIAHExtension] ERROR: Could not find executable '%s' in "
                 "bundle\n",
                 [executableName UTF8String]);
          HIAHLogError(GetExtensionLog, "Could not find executable in bundle");
          return;
        }
      }
    } else {
      ExtLog(logFile,
             "[HIAHExtension] ERROR: No CFBundleExecutable in Info.plist\n");
      HIAHLogError(GetExtensionLog, "No CFBundleExecutable in Info.plist");
      return;
    }
  } else if (![fm fileExistsAtPath:executablePath]) {
    ExtLog(logFile, "[HIAHExtension] ERROR: Path does not exist: %s\n",
           [executablePath UTF8String]);
    HIAHLogError(GetExtensionLog, "Executable path does not exist: %s",
                 [executablePath UTF8String]);
    return;
  }

  // Update executablePath to the actual binary
  executablePath = actualExecutablePath;
  ExtLog(logFile, "[HIAHExtension] Final executable path: %s\n",
         [executablePath UTF8String]);

  BOOL exists = [fm fileExistsAtPath:executablePath];
  ExtLog(logFile, "[HIAHExtension] Binary exists: %s\n", exists ? "YES" : "NO");

  if (!exists) {
    ExtLog(logFile, "[HIAHExtension] ERROR: Binary not found at: %s\n",
           [executablePath UTF8String]);
    HIAHLogError(GetExtensionLog, "Binary not found at: %s",
                 [executablePath UTF8String]);
    return;
  }

  // Patch binary for dlopen compatibility.
  // We must also handle binaries that were previously patched to MH_DYLIB
  // without LC_ID_DYLIB.
  ExtLog(logFile, "[HIAHExtension] Patching binary for dlopen compatibility "
                  "(MH_BUNDLE)...\n");

  if (![HIAHMachOUtils patchBinaryToDylib:executablePath]) {
    ExtLog(logFile, "[HIAHExtension] Note: binary patch not applied (already "
                    "compatible or unsupported)\n");
  } else {
    ExtLog(logFile, "[HIAHExtension] Binary patched to MH_BUNDLE\n");
  }

  // Remove code signature - the patching invalidates it
  // NOTE: We try dyld bypass first (initialized in ExtensionStartup)
  // But if that doesn't work (no JIT), we fall back to removing the signature
  ExtLog(logFile,
         "[HIAHExtension] Invoking HIAHSigner to sanitize signature...\n");
  if ([HIAHSigner signBinaryAtPath:executablePath]) {
    ExtLog(logFile, "[HIAHExtension] HIAHSigner completed successfully\n");
  } else {
    ExtLog(logFile, "[HIAHExtension] WARNING: HIAHSigner reported failure\n");
  }

  // Set up bundle context for the guest app
  // The executable path might be:
  // 1. Direct path to executable: /path/to/App.app/AppBinary
  // 2. iOS-style path: /path/to/App.app/Contents/MacOS/AppBinary (rare on iOS)
  // 3. Just the executable itself (for bundled apps)

  NSString *appBundlePath = nil;

  // Walk up the directory tree to find the .app bundle
  NSString *searchPath = executablePath;
  while (searchPath.length > 1) {
    if ([searchPath hasSuffix:@".app"]) {
      appBundlePath = searchPath;
      break;
    }
    searchPath = [searchPath stringByDeletingLastPathComponent];

    // Stop if we've gone too far up
    if ([searchPath isEqualToString:@"/"] || searchPath.length == 0) {
      break;
    }
  }

  // If we couldn't find .app in the path, assume the executable is inside an
  // .app bundle
  if (!appBundlePath) {
    // Try assuming it's directly in the .app bundle
    appBundlePath = [executablePath stringByDeletingLastPathComponent];
    if (![appBundlePath hasSuffix:@".app"]) {
      // Not found, this might be a problem
      ExtLog(logFile,
             "[HIAHExtension] WARNING: Could not determine .app bundle path "
             "from %s\n",
             [executablePath UTF8String]);
      appBundlePath = executablePath; // Fallback
    }
  }

  ExtLog(logFile, "[HIAHExtension] Guest app bundle path: %s\n",
         [appBundlePath UTF8String]);

  // Verify the bundle exists
  BOOL isBundleDir = NO;
  if (![fm fileExistsAtPath:appBundlePath isDirectory:&isBundleDir] ||
      !isBundleDir) {
    ExtLog(logFile,
           "[HIAHExtension] ERROR: Bundle path does not exist or is not a "
           "directory: %s\n",
           [appBundlePath UTF8String]);
  }

  // Load the Info.plist to get bundle information
  NSString *infoPlistPath =
      [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
  NSDictionary *bundleInfo = nil;
  if ([fm fileExistsAtPath:infoPlistPath]) {
    bundleInfo = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    if (bundleInfo) {
      ExtLog(logFile, "[HIAHExtension] Loaded Info.plist: %lu keys\n",
             (unsigned long)bundleInfo.count);
      ExtLog(logFile, "[HIAHExtension]   Bundle ID: %s\n",
             bundleInfo[@"CFBundleIdentifier"]
                 ? [bundleInfo[@"CFBundleIdentifier"] UTF8String]
                 : "(none)");
      ExtLog(logFile, "[HIAHExtension]   Bundle Name: %s\n",
             bundleInfo[@"CFBundleName"]
                 ? [bundleInfo[@"CFBundleName"] UTF8String]
                 : "(none)");
      ExtLog(logFile, "[HIAHExtension]   Executable: %s\n",
             bundleInfo[@"CFBundleExecutable"]
                 ? [bundleInfo[@"CFBundleExecutable"] UTF8String]
                 : "(none)");
    } else {
      ExtLog(logFile,
             "[HIAHExtension] WARNING: Could not parse Info.plist at %s\n",
             [infoPlistPath UTF8String]);
    }
  } else {
    ExtLog(logFile, "[HIAHExtension] WARNING: Info.plist not found at %s\n",
           [infoPlistPath UTF8String]);
  }

  // Load the app bundle to make resources available
  NSBundle *guestBundle = [NSBundle bundleWithPath:appBundlePath];
  if (guestBundle) {
    ExtLog(logFile, "[HIAHExtension] Guest bundle loaded successfully\n");
    ExtLog(logFile, "[HIAHExtension]   Bundle path: %s\n",
           [guestBundle.bundlePath UTF8String]);
    ExtLog(logFile, "[HIAHExtension]   Bundle ID: %s\n",
           guestBundle.bundleIdentifier
               ? [guestBundle.bundleIdentifier UTF8String]
               : "(none)");
    ExtLog(logFile, "[HIAHExtension]   Executable path: %s\n",
           guestBundle.executablePath ? [guestBundle.executablePath UTF8String]
                                      : "(none)");
    ExtLog(logFile, "[HIAHExtension]   Resource path: %s\n",
           guestBundle.resourcePath ? [guestBundle.resourcePath UTF8String]
                                    : "(none)");

    // CRITICAL: Override NSBundle.mainBundle BEFORE loading the dylib
    // This ensures the guest app sees itself as the main bundle
    ExtLog(logFile, "[HIAHExtension] Overriding NSBundle.mainBundle to point "
                    "to guest app...\n");
    OverrideMainBundle(guestBundle);
    OverrideCFBundle(guestBundle);

    // Preload the bundle to ensure resources are available
    [guestBundle load];
    ExtLog(logFile, "[HIAHExtension] Guest bundle loaded and ready\n");
  } else {
    ExtLog(logFile,
           "[HIAHExtension] WARNING: Could not create NSBundle for path: %s\n",
           [appBundlePath UTF8String]);
  }

  // Install UIApplicationMain hook BEFORE loading the guest binary
  // This ensures the hook is in place when the guest app's code runs
  ExtLog(logFile, "[HIAHExtension] Installing UIApplicationMain hook...\n");
  InstallUIApplicationMainHook();

  // Load guest binary as a dylib
  // RTLD_NOW: Resolve all symbols immediately
  // RTLD_GLOBAL: Make symbols available to other loaded libraries
  // RTLD_NOLOAD: Don't load if already loaded (we want fresh load)
  ExtLog(logFile, "[HIAHExtension] Loading guest binary via dlopen: %s\n",
         [executablePath UTF8String]);
  HIAHLogInfo(GetExtensionLog, "Loading guest binary as dylib via dlopen");

  void *guestHandle = dlopen(executablePath.UTF8String, RTLD_NOW | RTLD_GLOBAL);

  if (!guestHandle) {
    const char *error = dlerror();
    ExtLog(logFile, "[HIAHExtension] ERROR: dlopen failed: %s\n",
           error ?: "unknown error");
    HIAHLogError(GetExtensionLog, "dlopen failed: %s",
                 error ?: "unknown error");
    return;
  }

  fprintf(stdout,
          "[HIAHExtension] Guest binary loaded successfully as dylib at "
          "handle: %p\n",
          guestHandle);
  fprintf(stdout,
          "[HIAHExtension] Dylib constructors should have run during dlopen\n");
  fflush(stdout);
  HIAHLogDebug(GetExtensionLog, "Guest binary loaded as dylib at handle: %p",
               guestHandle);

  // Locate entry point (main function) in the loaded dylib
  fprintf(stdout,
          "[HIAHExtension] Locating guest entry point (main function)...\n");
  fflush(stdout);
  void *entryPoint = FindEntryPoint(guestHandle, executablePath);
  if (!entryPoint) {
    fprintf(stdout,
            "[HIAHExtension] ERROR: Could not find guest entry point\n");
    fflush(stdout);
    HIAHLogError(GetExtensionLog, "Could not find guest entry point");
    return;
  }

  fprintf(stdout, "[HIAHExtension] Found main() entry point at: %p\n",
          entryPoint);
  fprintf(stdout, "[HIAHExtension] The dylib is loaded and ready to execute\n");
  fflush(stdout);

  // Build argument vector for main()
  NSMutableArray *fullArguments =
      [NSMutableArray arrayWithObject:executablePath];
  if (arguments) {
    [fullArguments addObjectsFromArray:arguments];
  }

  int guestArgc = (int)fullArguments.count;
  char **guestArgv = malloc(sizeof(char *) * (guestArgc + 1));

  fprintf(stdout,
          "[HIAHExtension] Building argv (%d arguments) for guest main():\n",
          guestArgc);
  for (int i = 0; i < guestArgc; i++) {
    guestArgv[i] = strdup([fullArguments[i] UTF8String]);
    fprintf(stdout, "[HIAHExtension]   argv[%d] = %s\n", i, guestArgv[i]);
  }
  guestArgv[guestArgc] = NULL;
  fflush(stdout);

  fprintf(stdout, "[HIAHExtension] *** INVOKING GUEST main() - This will call "
                  "UIApplicationMain ***\n");
  fprintf(stdout, "[HIAHExtension] Our UIApplicationMain hook will intercept "
                  "and handle it\n");
  fflush(stdout);
  HIAHLogInfo(GetExtensionLog,
              "Invoking guest main() with %d arguments (will trigger "
              "UIApplicationMain)",
              guestArgc);

  int (*guestMain)(int, char **) = entryPoint;

  // Set guest active BEFORE calling main
  gGuestActive = YES;

  fprintf(stdout, "[HIAHExtension] Calling guest main(%d, %p)...\n", guestArgc,
          guestArgv);
  fprintf(stdout, "[HIAHExtension] Guest app will now initialize and call "
                  "UIApplicationMain\n");
  fprintf(stdout,
          "[HIAHExtension] Our UIApplicationMain hook will intercept it\n");
  fflush(stdout);

  // Call guest main() - this will trigger UIApplicationMain which our hook will
  // intercept We're already on the main queue, so we can call it directly
  // However, UIApplicationMain will start its own runloop, so we need to ensure
  // our hook handles it
  __block int guestExitCode = 0;

  // Use dispatch_async to ensure it runs in the next runloop cycle
  // This allows the current function to set up the runloop first
  dispatch_async(dispatch_get_main_queue(), ^{
    @try {
      fprintf(stdout, "[HIAHExtension] *** CALLING GUEST main() NOW ***\n");
      fprintf(stdout, "[HIAHExtension] This will call UIApplicationMain, which "
                      "our hook intercepts\n");
      fflush(stdout);

      // Call main() - this will eventually call UIApplicationMain which our
      // hook intercepts
      guestExitCode = guestMain(guestArgc, guestArgv);

      fprintf(stdout, "[HIAHExtension] Guest main() returned with code: %d\n",
              guestExitCode);
      fflush(stdout);
      HIAHLogInfo(GetExtensionLog, "Guest main() returned with code: %d",
                  guestExitCode);
    } @catch (NSException *exception) {
      fprintf(stdout, "[HIAHExtension] ERROR: Guest threw exception: %s - %s\n",
              exception.name ? [exception.name UTF8String] : "(null)",
              exception.reason ? [exception.reason UTF8String] : "(null)");
      fflush(stdout);
      HIAHLogError(GetExtensionLog, "Guest threw exception: %s - %s",
                   exception.name ? [exception.name UTF8String] : "(null)",
                   exception.reason ? [exception.reason UTF8String] : "(null)");
      guestExitCode = 1;
    } @finally {
      gGuestActive = NO;

      fprintf(stdout,
              "[HIAHExtension] Guest execution completed (exit code: %d)\n",
              guestExitCode);
      fflush(stdout);

      // Cleanup
      for (int i = 0; i < guestArgc; i++) {
        free(guestArgv[i]);
      }
      free(guestArgv);
    }
  });

  // CRITICAL: Run runloop to keep extension alive while guest app runs
  // This must run on the main thread and keep running until guest completes
  fprintf(stdout,
          "[HIAHExtension] Starting runloop to keep extension alive...\n");
  fprintf(stdout, "[HIAHExtension] Guest active flag: %s\n",
          gGuestActive ? "YES" : "NO");
  fprintf(stdout, "[HIAHExtension] Runloop will process the async dispatch and "
                  "execute guest main()\n");
  fflush(stdout);

  // Run runloop until guest app completes (gGuestActive becomes NO)
  NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
  NSDate *futureDate =
      [NSDate dateWithTimeIntervalSinceNow:3600.0]; // 1 hour max

  // Keep running the runloop while guest is active
  // This will process the async dispatch and run the guest app
  while (gGuestActive && [futureDate timeIntervalSinceNow] > 0) {
    @autoreleasepool {
      // Run the runloop for a short time, then check again
      // This allows the async dispatch to execute and the guest app to run
      NSDate *nextDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
      BOOL didRun = [runLoop runMode:NSDefaultRunLoopMode beforeDate:nextDate];
      if (!didRun) {
        // Runloop didn't process any events, give it a moment
        usleep(10000); // 10ms
      }
    }
  }

  fprintf(stdout,
          "[HIAHExtension] Runloop exited (guest active: %s, exit code: %d)\n",
          gGuestActive ? "YES" : "NO", guestExitCode);
  fflush(stdout);
}

#pragma mark - Extension Request Handler

@interface HIAHExtensionHandler : NSObject <NSExtensionRequestHandling>
@end

@implementation HIAHExtensionHandler

+ (void)load {
  // Log to file immediately when class loads
  NSFileManager *fm = [NSFileManager defaultManager];
  NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:
                            @"group.com.aspauldingcode.HIAHDesktop"];
  NSString *logPath = nil;
  if (groupURL) {
    logPath =
        [[groupURL.path stringByAppendingPathComponent:@"HIAHExtension.log"]
            stringByStandardizingPath];
    [fm createDirectoryAtPath:groupURL.path
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  } else {
    logPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"HIAHExtension.log"];
  }

  FILE *logFile = fopen([logPath UTF8String], "a");
  if (logFile) {
    fprintf(logFile,
            "[HIAHExtension] HIAHExtensionHandler class loaded (PID=%d)\n",
            getpid());
    fprintf(logFile, "[HIAHExtension] Log file: %s\n", [logPath UTF8String]);
    fflush(logFile);
    fclose(logFile);
  }

  fprintf(stderr,
          "[HIAHExtension] HIAHExtensionHandler class loaded (PID=%d)\n",
          getpid());
  fprintf(stdout,
          "[HIAHExtension] HIAHExtensionHandler class loaded (PID=%d)\n",
          getpid());
  fflush(stdout);
  fflush(stderr);
}

+ (void)initialize {
  fprintf(stderr,
          "[HIAHExtension] HIAHExtensionHandler class initialized (PID=%d)\n",
          getpid());
  fprintf(stdout,
          "[HIAHExtension] HIAHExtensionHandler class initialized (PID=%d)\n",
          getpid());
  fflush(stdout);
  fflush(stderr);
}

- (instancetype)init {
  if (self = [super init]) {
    fprintf(stderr,
            "[HIAHExtension] HIAHExtensionHandler instance created (PID=%d)\n",
            getpid());
    fprintf(stdout,
            "[HIAHExtension] HIAHExtensionHandler instance created (PID=%d)\n",
            getpid());
    fflush(stdout);
    fflush(stderr);
  }
  return self;
}

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
  // Log to App Group shared directory so host app can read it
  NSFileManager *fm = [NSFileManager defaultManager];
  NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:
                            @"group.com.aspauldingcode.HIAHDesktop"];
  NSString *logPath = nil;
  if (groupURL) {
    logPath =
        [[groupURL.path stringByAppendingPathComponent:@"HIAHExtension.log"]
            stringByStandardizingPath];
  } else {
    // Fallback to temp directory
    logPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"HIAHExtension.log"];
  }

  FILE *logFile = fopen([logPath UTF8String], "a");
  if (logFile) {
    fprintf(logFile,
            "[HIAHExtension] ========================================\n");
    fprintf(logFile,
            "[HIAHExtension] beginRequestWithExtensionContext called\n");
    fprintf(logFile, "[HIAHExtension] PID: %d\n", getpid());
    fprintf(logFile, "[HIAHExtension] Log file: %s\n", [logPath UTF8String]);
    fprintf(logFile, "[HIAHExtension] Input items count: %lu\n",
            (unsigned long)context.inputItems.count);
    fflush(logFile);
  } else {
    // Try to create parent directory if it doesn't exist
    NSString *logDir = [logPath stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:logDir
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
    logFile = fopen([logPath UTF8String], "a");
    if (logFile) {
      fprintf(logFile,
              "[HIAHExtension] Log file created after creating directory\n");
      fflush(logFile);
    }
  }

  // Log to both stdout and stderr (stderr is more likely to be captured)
  fprintf(stderr, "[HIAHExtension] ========================================\n");
  fprintf(stderr, "[HIAHExtension] beginRequestWithExtensionContext called\n");
  fprintf(stderr, "[HIAHExtension] PID: %d\n", getpid());
  fprintf(stderr, "[HIAHExtension] Input items count: %lu\n",
          (unsigned long)context.inputItems.count);
  fprintf(stdout, "[HIAHExtension] ========================================\n");
  fprintf(stdout, "[HIAHExtension] beginRequestWithExtensionContext called\n");
  fprintf(stdout, "[HIAHExtension] PID: %d\n", getpid());
  fprintf(stdout, "[HIAHExtension] Input items count: %lu\n",
          (unsigned long)context.inputItems.count);
  fflush(stdout);
  fflush(stderr);

  HIAHLogInfo(GetExtensionLog, "Received spawn request from HIAHKernel");

  NSDictionary *spawnRequest = nil;

  if (context.inputItems.count > 0) {
    NSExtensionItem *item = context.inputItems.firstObject;
    spawnRequest = item.userInfo;

    if (spawnRequest) {
      if (logFile) {
        fprintf(logFile, "[HIAHExtension] Request keys: %s\n",
                [[spawnRequest.allKeys description] UTF8String]);
        fflush(logFile);
      }
      fprintf(stderr, "[HIAHExtension] Request keys: %s\n",
              [[spawnRequest.allKeys description] UTF8String]);
      fprintf(stdout, "[HIAHExtension] Request keys: %s\n",
              [[spawnRequest.allKeys description] UTF8String]);
      fflush(stdout);
      fflush(stderr);
      HIAHLogDebug(GetExtensionLog, "Request contains keys: %s",
                   [[spawnRequest.allKeys description] UTF8String]);
    } else {
      if (logFile) {
        fprintf(logFile, "[HIAHExtension] WARNING: item.userInfo is nil\n");
        fflush(logFile);
      }
      fprintf(stderr, "[HIAHExtension] WARNING: item.userInfo is nil\n");
      fprintf(stdout, "[HIAHExtension] WARNING: item.userInfo is nil\n");
      fflush(stdout);
      fflush(stderr);
    }
  } else {
    if (logFile) {
      fprintf(logFile, "[HIAHExtension] WARNING: No input items in context\n");
      fflush(logFile);
    }
    fprintf(stderr, "[HIAHExtension] WARNING: No input items in context\n");
    fprintf(stdout, "[HIAHExtension] WARNING: No input items in context\n");
    fflush(stdout);
    fflush(stderr);
  }

  if (!spawnRequest) {
    if (logFile) {
      fprintf(logFile, "[HIAHExtension] ERROR: No spawn request data in "
                       "extension context\n");
      fclose(logFile);
    }
    fprintf(
        stderr,
        "[HIAHExtension] ERROR: No spawn request data in extension context\n");
    fprintf(
        stdout,
        "[HIAHExtension] ERROR: No spawn request data in extension context\n");
    fflush(stdout);
    fflush(stderr);
    HIAHLogError(GetExtensionLog, "No spawn request data in extension context");
    return;
  }

  if (logFile) {
    fprintf(logFile,
            "[HIAHExtension] Dispatching to main queue for execution...\n");
    fflush(logFile);
  }
  fprintf(stderr,
          "[HIAHExtension] Dispatching to main queue for execution...\n");
  fprintf(stdout,
          "[HIAHExtension] Dispatching to main queue for execution...\n");
  fflush(stdout);
  fflush(stderr);

  // Execute immediately on current queue (extensions should already be on main
  // queue) But use async to ensure we're on the right queue
  dispatch_async(dispatch_get_main_queue(), ^{
    if (logFile) {
      fprintf(
          logFile,
          "[HIAHExtension] On main queue, executing guest application...\n");
      fflush(logFile);
    }
    fprintf(stderr,
            "[HIAHExtension] On main queue, executing guest application...\n");
    fprintf(stdout,
            "[HIAHExtension] On main queue, executing guest application...\n");
    fflush(stdout);
    fflush(stderr);

    @try {
      fprintf(stdout,
              "[HIAHExtension] About to call ExecuteGuestApplication with "
              "spawnRequest: %p\n",
              spawnRequest);
      fprintf(stderr,
              "[HIAHExtension] About to call ExecuteGuestApplication with "
              "spawnRequest: %p\n",
              spawnRequest);
      fflush(stdout);
      fflush(stderr);

      ExecuteGuestApplication(spawnRequest);

      fprintf(stdout,
              "[HIAHExtension] ExecuteGuestApplication returned (completed)\n");
      fprintf(stderr,
              "[HIAHExtension] ExecuteGuestApplication returned (completed)\n");
      fflush(stdout);
      fflush(stderr);

      if (logFile) {
        fprintf(logFile, "[HIAHExtension] ExecuteGuestApplication completed\n");
        fclose(logFile);
      }
    } @catch (NSException *exception) {
      if (logFile) {
        fprintf(logFile,
                "[HIAHExtension] FATAL: Exception in ExecuteGuestApplication: "
                "%s - %s\n",
                exception.name ? [exception.name UTF8String] : "(null)",
                exception.reason ? [exception.reason UTF8String] : "(null)");
        fclose(logFile);
      }
      fprintf(stderr,
              "[HIAHExtension] FATAL: Exception in ExecuteGuestApplication: %s "
              "- %s\n",
              exception.name ? [exception.name UTF8String] : "(null)",
              exception.reason ? [exception.reason UTF8String] : "(null)");
      fprintf(stdout,
              "[HIAHExtension] FATAL: Exception in ExecuteGuestApplication: %s "
              "- %s\n",
              exception.name ? [exception.name UTF8String] : "(null)",
              exception.reason ? [exception.reason UTF8String] : "(null)");
      fflush(stdout);
      fflush(stderr);
    }
  });
}

@end

// Force linkage by creating a reference to the class
// This ensures HIAHExtensionHandler is linked into the extension binary
__attribute__((used)) static void ForceLinkHIAHExtensionHandler(void) {
  // Reference the class to force linkage
  (void)gHIAHExtensionHandlerClass;
  (void)[HIAHExtensionHandler class];
}
