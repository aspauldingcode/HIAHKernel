#!/bin/bash
# Script to replace NSExtension code with dlopen implementation in HIAHKernel.m

set -e

FILE="src/HIAHKernel/Core/HIAHKernel.m"

# Create backup
cp "$FILE" "$FILE.backup"

# Use sed to delete lines 595-876 (NSExtension code)
sed -i '' '595,876d' "$FILE"

# Insert the new dlopen implementation at line 595
cat > /tmp/dlopen_impl.txt << 'EOF'

  // 2. Patch binary for dlopen if needed
  NSString *executablePath = path;
  
  // Check if binary needs patching (MH_EXECUTE → MH_BUNDLE)
  if ([HIAHMachOUtils isMHExecute:path]) {
    HIAHLogInfo(HIAHLogKernel, "Binary is MH_EXECUTE, patching for dlopen...");
    
    // Create a temporary copy for patching
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [[path lastPathComponent] stringByAppendingString:@".patched"]];
    
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:path
                                                  toPath:tempPath
                                                   error:&copyError]) {
      HIAHLogError(HIAHLogKernel, "Failed to copy binary for patching: %s",
                   [[copyError description] UTF8String]);
      if (completion) {
        completion(-1, copyError);
      }
      return;
    }
    
    // Patch the binary using JIT-less mode (LiveContainer approach)
    if (![HIAHMachOUtils patchBinaryForJITLessMode:tempPath]) {
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
    HIAHLogInfo(HIAHLogKernel, "Binary patched successfully: %s", [tempPath UTF8String]);
  }
  
  // 3. Load the binary via dlopen
  HIAHLogInfo(HIAHLogKernel, "Loading binary via dlopen: %s", [executablePath UTF8String]);
  
  void *handle = dlopen([executablePath UTF8String], RTLD_NOW | RTLD_GLOBAL);
  if (!handle) {
    const char *dlopen_error = dlerror();
    HIAHLogError(HIAHLogKernel, "dlopen failed: %s", dlopen_error ?: "(null)");
    
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
  
  HIAHLogInfo(HIAHLogKernel, "Spawned guest process via dlopen (Virtual PID: %d)", vproc.pid);
  
  // 5. Find and execute entry point
  // For command-line tools like ssh/waypipe, we need to find main()
  typedef int (*main_func_t)(int argc, char **argv, char **envp);
  main_func_t main_func = (main_func_t)dlsym(handle, "main");
  
  if (!main_func) {
    // Try _main (some binaries use this)
    main_func = (main_func_t)dlsym(handle, "_main");
  }
  
  if (main_func) {
    HIAHLogInfo(HIAHLogKernel, "Found entry point, executing in background thread...");
    
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
      HIAHLogInfo(HIAHLogKernel, "Calling main() with %d arguments", argc);
      int exitCode = main_func(argc, argv, envp);
      HIAHLogInfo(HIAHLogKernel, "main() returned with exit code: %d", exitCode);
      
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
    HIAHLogWarning(HIAHLogKernel, "No main() entry point found, binary loaded but not executed");
    
    // Still return success - the binary is loaded
    if (completion) {
      completion(vproc.pid, nil);
    }
  }
}
EOF

# Insert the new code at line 594 (after deletion, this is where line 595 was)
sed -i '' '594r /tmp/dlopen_impl.txt' "$FILE"

echo "✅ Successfully replaced NSExtension code with dlopen implementation"
echo "Backup saved to: $FILE.backup"
