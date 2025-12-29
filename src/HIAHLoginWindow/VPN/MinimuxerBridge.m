#import "MinimuxerBridge.h"
#import "../../HIAHDesktop/HIAHLogging.h"

@implementation MinimuxerBridge

+ (void)startMuxer {
  HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Starting Minimuxer manager...");
  // Logic delegated to em-proxy process for now.
  // Use this bridge if we need more granular control over the muxer library
  // later.
  HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer",
            @"Minimuxer is managed by EMProxyBridge.");
}

+ (void)stopMuxer {
  HIAHLogEx(HIAH_LOG_INFO, @"Minimuxer", @"Stopping Minimuxer...");
}

@end
