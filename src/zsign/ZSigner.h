//
// ZSigner.h
// Objective-C wrapper for zsign C++ library
//
// This provides the ZSigner class that HIAHSigner.m expects,
// similar to how LiveContainer integrates zsign.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZSigner : NSObject

/// Ad-hoc sign a Mach-O binary at the given path
/// This is the method that HIAHSigner.m calls, matching LiveContainer's API
/// @param path Path to the Mach-O binary to sign
/// @param bundleId Bundle identifier for the binary
/// @param entitlementData Entitlements as XML plist data
/// @return YES if signing succeeded, NO otherwise
+ (BOOL)adhocSignMachOAtPath:(NSString *)path
                    bundleId:(NSString *)bundleId
              entitlementData:(NSData *)entitlementData;

@end

NS_ASSUME_NONNULL_END
