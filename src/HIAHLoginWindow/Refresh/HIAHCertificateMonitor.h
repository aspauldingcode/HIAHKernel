#import <Foundation/Foundation.h>

@interface HIAHCertificateMonitor : NSObject

+ (instancetype)sharedMonitor;
- (void)startMonitoring;
- (void)stopMonitoring;

@end
