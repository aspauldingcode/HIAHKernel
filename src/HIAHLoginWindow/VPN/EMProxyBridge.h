#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EMProxyBridge : NSObject

/**
 * Starts the em_proxy process on the specified address.
 * @param bindAddress The address to bind to (e.g., "127.0.0.1:65399").
 * @return 0 on success, non-zero on failure.
 */
+ (int)startVPNWithBindAddress:(NSString *)bindAddress;

/**
 * Stops the running em_proxy process.
 */
+ (void)stopVPN;

/**
 * Tests the VPN connection by attempting to connect to the proxy address.
 * @param timeout The timeout in milliseconds.
 * @return 0 on success (reachable), non-zero on failure.
 */
+ (int)testVPNWithTimeout:(NSInteger)timeout;

@end

NS_ASSUME_NONNULL_END
