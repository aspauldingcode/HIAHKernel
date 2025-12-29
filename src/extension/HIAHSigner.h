#import <Foundation/Foundation.h>

@interface HIAHSigner : NSObject

/**
 * Resign the binary at the given path with ad-hoc signature or a specific
 * identity.
 * @param path Path to the executable.
 * @return YES on success, NO on failure.
 */
+ (BOOL)signBinaryAtPath:(NSString *)path;

@end
