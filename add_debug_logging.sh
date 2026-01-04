#!/bin/bash
set -e
FILE="src/HIAHKernel/Core/HIAHKernel.m"

# Backup
cp "$FILE" "$FILE.debug_backup"

# Remove lines 595-746
sed -i '' '595,746d' "$FILE"

# Create new content with debug prints
cat > /tmp/debug_impl.txt << 'EOF'

  // 2. Patch binary for dlopen if needed
  NSString *executablePath = path;
  NSLog(@"[HIAHKernel DEBUG] Starting spawn logic for: %@", path);
  printf("[HIAHKernel PRINTF] Starting spawn logic for: %s\n", [path UTF8String]); fflush(stdout);

  // Check if binary needs patching (MH_EXECUTE → MH_BUNDLE)
  BOOL isExecute = [HIAHMachOUtils isMHExecute:path];
  NSLog(@"[HIAHKernel DEBUG] isMHExecute check result: %d", isExecute);

  if (isExecute) {
    NSLog(@"[HIAHKernel DEBUG] Binary is MH_EXECUTE, patching for dlopen...");
    
    // Create a temporary copy for patching
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [[path lastPathComponent] stringByAppendingString:@".patched"]];
    
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:path
                                                  toPath:tempPath
                                                   error:&copyError]) {
      NSLog(@"[HIAHKernel DEBUG] Failed to copy binary: %@", copyError);
      HIAHLogError(HIAHLogKernel, "Failed to copy binary for patching: %s",
                   [[copyError description] UTF8String]);
      if (completion) {
        completion(-1, copyError);
      }
      return;
    }
    
    // Patch the binary using JIT-less mode (LiveContainer approach)
    if (![HIAHMachOUtils patchBinaryForJITLessMode:tempPath]) {
      NSLog(@"[HIAHKernel DEBUG] Failed to patch binary");
      HIAHLogError(HIAHLogKernel, "Failed to patch binary for dlopen");
      if (completion) {
        NSError *err = [NSError errorWithDomain:HIAHKernelErrorDomain
                                           code:HIAHKernelErrorSpawnFailed
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to patch binary"}];
        completion(-1, err);
      }
      return;
    }
    
    executablePath = tempPath;
    NSLog(@"[HIAHKernel DEBUG] Binary patched successfully: %@", tempPath);
  } else {
    NSLog(@"[HIAHKernel DEBUG] Binary does NOT need patching (already dylib/bundle)");
  }
  
  // 3. Load the binary via dlopen
  NSLog(@"[HIAHKernel DEBUG] About to dlopen: %@", executablePath);
  printf("[HIAHKernel PRINTF] Calling dlopen on: %s\n", [executablePath UTF8String]); fflush(stdout);
  
  void *handle = dlopen([executablePath UTF8String], RTLD_NOW | RTLD_GLOBAL);
  
  if (!handle) {
    const char *dlopen_error = dlerror();
    NSLog(@"[HIAHKernel DEBUG] dlopen FAILED: %s", dlopen_error);
    printf("[HIAHKernel PRINTF] dlopen FAILED: %s\n", dlopen_error); fflush(stdout);
    
    if (completion) {
      NSError *err = [NSError errorWithDomain:HIAHKernelErrorDomain
                                         code:HIAHKernelErrorSpawnFailed
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                       [NSString stringWithFormat:@"dlopen failed: %s", 
                                        dlopen_error ?: "(null)"]}];
      completion(-1, err);
    }
    return;
  }
  
  NSLog(@"[HIAHKernel DEBUG] dlopen SUCCESS, handle: %p", handle);
  printf("[HIAHKernel PRINTF] dlopen SUCCESS\n"); fflush(stdout);
  
  HIAHLogInfo(HIAHLogKernel, "Binary loaded successfully via dlopen");
  
  // 4. Create virtual process entry
  HIAHProcess *vproc = [HIAHProcess processWithPath:path
                                          arguments:arguments
                                        environment:environment];
  
  // Assign virtual PID
  [self.lock lock];
  vproc.pid = self.nextVirtualPid++;
  [self.lock unlock];
  
  // For dlopen-based execution, we don't have a separate physical PID
  // The code runs in our process
  vproc.physicalPid = getpid();
  
  [self registerProcess:vproc];
  
  NSLog(@"[HIAHKernel DEBUG] Registered virtual process PID: %d", vproc.pid);
  
  // 5. Find and execute entry point
  // For command-line tools like ssh/waypipe, we need to find main()
  typedef int (*main_func_t)(int argc, char **argv, char **envp);
  main_func_t main_func = (main_func_t)dlsym(handle, "main");
  
  if (!main_func) {
    // Try _main (some binaries use this)
    main_func = (main_func_t)dlsym(handle, "_main");
  }
  
  if (main_func) {
    NSLog(@"[HIAHKernel DEBUG] Found main() entry point, spawning thread...");
    printf("[HIAHKernel PRINTF] Executing main()\n"); fflush(stdout);
    
    // Execute main() in a background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      // Prepare argc/argv
      int argc = (int)(arguments.count + 1);
      char **argv = malloc(sizeof(char *) * (argc + 1));
      argv[0] = strdup([path UTF8String]);
      for (int i = 0; i < arguments.count; i++) {
        argv[i + 1] = strdup([arguments[i] UTF8String]);
      }
      argv[argc] = NULL;
      
      // Prepare envp
      NSMutableDictionary *fullEnv = environment ? [environment mutableCopy] : [NSMutableDictionary dictionary];
      fullEnv[@"HIAH_STDOUT_SOCKET"] = socketPath;
      if (self.controlSocketPath) {
        fullEnv[@"HIAH_KERNEL_SOCKET"] = self.controlSocketPath;
      }
      
      int envCount = (int)fullEnv.count;
      char **envp = malloc(sizeof(char *) * (envCount + 1));
      int envIdx = 0;
      for (NSString *key in fullEnv) {
        NSString *value = fullEnv[key];
        NSString *envStr = [NSString stringWithFormat:@"%@=%@", key, value];
        envp[envIdx++] = strdup([envStr UTF8String]);
      }
      envp[envCount] = NULL;
      
      // Call main()
      NSLog(@"[HIAHKernel DEBUG] Calling main() with %d args", argc);
      printf("[HIAHKernel PRINTF] Calling main() now...\n"); fflush(stdout);
      
      int exitCode = main_func(argc, argv, envp);
      
      NSLog(@"[HIAHKernel DEBUG] main() returned: %d", exitCode);
      printf("[HIAHKernel PRINTF] main() returned: %d\n", exitCode); fflush(stdout);
      
      // Clean up
      for (int i = 0; i < argc; i++) {
        free(argv[i]);
      }
      free(argv);
      for (int i = 0; i < envCount; i++) {
        free(envp[i]);
      }
      free(envp);
      
      // Mark process as exited
      [self handleExitForPID:vproc.pid exitCode:exitCode];
    });
    
    // Return success immediately (execution is async)
    if (completion) {
      completion(vproc.pid, nil);
    }
  } else {
    NSLog(@"[HIAHKernel DEBUG] No main() entry point found!");
    HIAHLogWarning(HIAHLogKernel, "No main() entry point found, binary loaded but not executed");
    
    // Still return success - the binary is loaded
    if (completion) {
      completion(vproc.pid, nil);
    }
  }
}
EOF

# Insert at line 594
sed -i '' '594r /tmp/debug_impl.txt' "$FILE"

echo "Replaced implementation with debug logging"
