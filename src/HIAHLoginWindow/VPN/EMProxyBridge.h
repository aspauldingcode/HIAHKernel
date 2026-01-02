/**
 * EMProxyBridge.h
 * HIAH LoginWindow - EM Proxy Bridge
 *
 * Bridge to em_proxy Rust library for VPN loopback functionality.
 * em_proxy creates a UDP socket that LocalDevVPN connects to, enabling
 * JIT via the debugger attachment flow.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridge to em_proxy library for VPN loopback
@interface EMProxyBridge : NSObject

/// Whether em_proxy is currently running
@property (class, nonatomic, readonly) BOOL isRunning;

/**
 * Starts the em_proxy loopback server.
 * This creates a UDP socket on 127.0.0.1:65399 that LocalDevVPN connects to.
 * @param bindAddress The address to bind to (e.g., "127.0.0.1:65399").
 * @return 0 on success, non-zero on failure (handle is returned internally).
 */
+ (int)startVPNWithBindAddress:(NSString *)bindAddress;

/**
 * Stops the running em_proxy server.
 */
+ (void)stopVPN;

/**
 * Tests if LocalDevVPN is ready to receive connections.
 * This blocks until LocalDevVPN is ready or timeout expires.
 * @param timeout The timeout in milliseconds.
 * @return 0 on success (LocalDevVPN ready), -1 on timeout/failure.
 */
+ (int)testVPNWithTimeout:(NSInteger)timeout;

@end

NS_ASSUME_NONNULL_END
