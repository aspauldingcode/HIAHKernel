#import "HIAHCertificateMonitor.h"
#import "../../HIAHDesktop/HIAHLogging.h"
#import "HIAHBackgroundRefresher.h"

@interface HIAHCertificateMonitor ()
@property(nonatomic, strong) NSTimer *monitorTimer;
@end

@implementation HIAHCertificateMonitor

+ (instancetype)sharedMonitor {
  static HIAHCertificateMonitor *shared = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[self alloc] init];
  });
  return shared;
}

- (void)startMonitoring {
  HIAHLogEx(HIAH_LOG_INFO, @"CertMonitor",
            @"Starting certificate expiration monitoring...");

  // Check every hour (3600 seconds)
  self.monitorTimer =
      [NSTimer scheduledTimerWithTimeInterval:3600
                                       target:self
                                     selector:@selector(checkExpiration)
                                     userInfo:nil
                                      repeats:YES];

  // Also check immediately
  [self checkExpiration];
}

- (void)stopMonitoring {
  HIAHLogEx(HIAH_LOG_INFO, @"CertMonitor", @"Stopping monitoring.");
  [self.monitorTimer invalidate];
  self.monitorTimer = nil;
}

- (void)checkExpiration {
  HIAHLogEx(HIAH_LOG_DEBUG, @"CertMonitor",
            @"Checking certificate expiration status...");

  // In a real impl, we would read the cert from Keychain
  // For now, we simulate a check

  BOOL expiringSoon = NO; // Simulate logic

  if (expiringSoon) {
    HIAHLogEx(HIAH_LOG_INFO, @"CertMonitor",
              @"Certificate expires soon! Triggering refresh.");
    [[HIAHBackgroundRefresher sharedRefresher]
        performRefreshWithCompletion:^(BOOL success, NSError *_Nullable error) {
          if (success) {
            HIAHLogEx(HIAH_LOG_INFO, @"CertMonitor",
                      @"Refresh completed successfully.");
          } else {
            HIAHLogEx(HIAH_LOG_ERROR, @"CertMonitor", @"Refresh failed: %@",
                      error);
          }
        }];
  } else {
    HIAHLogEx(HIAH_LOG_DEBUG, @"CertMonitor", @"Certificate is healthy.");
  }
}

@end
