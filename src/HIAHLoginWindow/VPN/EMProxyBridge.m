#import "EMProxyBridge.h"
#import "../../HIAHDesktop/HIAHLogging.h"
#import <spawn.h>
#import <sys/wait.h>

static pid_t gEMProxyPID = 0;

@implementation EMProxyBridge

+ (int)startVPNWithBindAddress:(NSString *)bindAddress {
  if (gEMProxyPID > 0) {
    [self stopVPN];
  }

  NSString *proxyPath = [[NSBundle mainBundle] pathForResource:@"em-proxy"
                                                        ofType:nil];
  // Also check bin/em-proxy (where we bundled it)
  if (!proxyPath) {
    proxyPath = [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"bin/em-proxy"];
  }

  if (![[NSFileManager defaultManager] fileExistsAtPath:proxyPath]) {
    HIAHLogEx(HIAH_LOG_ERROR, @"VPN", @"em-proxy binary not found at: %@",
              proxyPath);
    return -1;
  }

  // Arguments: em-proxy -l <bindAddress>
  const char *path = [proxyPath fileSystemRepresentation];
  const char *args[] = {path, "-l", [bindAddress UTF8String], NULL};

  // Environment
  char *const envp[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL};

  HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Starting em-proxy: %s -l %@", path,
            bindAddress);

  int status =
      posix_spawn(&gEMProxyPID, path, NULL, NULL, (char *const *)args, envp);

  if (status != 0) {
    HIAHLogEx(HIAH_LOG_ERROR, @"VPN", @"Failed to spawn em-proxy: %d", status);
    gEMProxyPID = 0;
    return status;
  }

  HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"em-proxy started with PID: %d",
            gEMProxyPID);
  return 0;
}

+ (void)stopVPN {
  if (gEMProxyPID > 0) {
    HIAHLogEx(HIAH_LOG_INFO, @"VPN", @"Stopping em-proxy (PID: %d)",
              gEMProxyPID);
    kill(gEMProxyPID, SIGTERM);
    int stat_loc;
    waitpid(gEMProxyPID, &stat_loc, 0);
    gEMProxyPID = 0;
  }
}

+ (int)testVPNWithTimeout:(NSInteger)timeout {
  // Simple TCP connect check to the bind address could go here
  // For now, checks if process is running
  if (gEMProxyPID <= 0)
    return -1;

  // Check if process is still alive
  if (kill(gEMProxyPID, 0) == 0) {
    return 0;
  }

  return -1;
}

@end
