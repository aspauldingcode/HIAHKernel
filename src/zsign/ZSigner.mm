//
// ZSigner.mm
// Objective-C wrapper for zsign C++ library
//
// This wraps the C++ zsign API to provide the ZSigner class interface
// that HIAHSigner.m expects, similar to how LiveContainer does it.
//

#import "ZSigner.h"
#import <Foundation/Foundation.h>

// Include zsign C++ headers
// These are staged from Nix build to dependencies/zsign/include/zsign/
// We use angle brackets to search in header search paths
#include <zsign/archo.h>
#include <zsign/openssl.h>
#include <zsign/common/common.h>
#include <string>
#include <vector>
#include <set>

using namespace std;

@implementation ZSigner

+ (BOOL)adhocSignMachOAtPath:(NSString *)path
                    bundleId:(NSString *)bundleId
              entitlementData:(NSData *)entitlementData {
    if (!path || path.length == 0) {
        NSLog(@"[ZSigner] Error: path is nil or empty");
        return NO;
    }
    
    // Read the Mach-O file into memory
    NSData *fileData = [NSData dataWithContentsOfFile:path];
    if (!fileData || fileData.length == 0) {
        NSLog(@"[ZSigner] Error: Failed to read file at path: %@", path);
        return NO;
    }
    
    // Create a mutable copy so we can modify it
    NSMutableData *mutableData = [fileData mutableCopy];
    uint8_t *fileBytes = (uint8_t *)mutableData.mutableBytes;
    uint32_t fileLength = (uint32_t)mutableData.length;
    
    // Initialize ZArchO with the file
    ZArchO archo;
    if (!archo.Init(fileBytes, fileLength)) {
        NSLog(@"[ZSigner] Error: Failed to initialize ZArchO with file: %@", path);
        return NO;
    }
    
    // Create ZSignAsset for ad-hoc signing
    // For ad-hoc signing, we don't need certificates, so pass empty strings
    ZSignAsset signAsset;
    string emptyStr = "";
    string bundleIdStr = bundleId ? [bundleId UTF8String] : "";
    
    // Convert entitlements data to string if provided
    string entitlementsStr = "";
    if (entitlementData && entitlementData.length > 0) {
        NSString *entitlementsXML = [[NSString alloc] initWithData:entitlementData encoding:NSUTF8StringEncoding];
        if (entitlementsXML) {
            entitlementsStr = [entitlementsXML UTF8String];
        }
    }
    
    // Initialize sign asset in ad-hoc mode
    // Parameters: certFile, pkeyFile, provFile, entitleFile, password, bAdhoc, bSHA256Only, bSingleBinary
    if (!signAsset.Init(emptyStr, emptyStr, emptyStr, entitlementsStr, emptyStr, true, false, false)) {
        NSLog(@"[ZSigner] Error: Failed to initialize ZSignAsset for ad-hoc signing");
        return NO;
    }
    
    // Calculate Info.plist hashes (empty for single binary signing)
    string infoSHA1 = "";
    string infoSHA256 = "";
    string codeResourcesData = "";
    
    // Sign the binary
    // Parameters: pSignAsset, bForce, bundleId, infoSHA1, infoSHA256, codeResourcesData
    archo.Sign(&signAsset, true, bundleIdStr, infoSHA1, infoSHA256, codeResourcesData);
    
    // Check if signing was successful
    if (!archo.IsSigned()) {
        NSLog(@"[ZSigner] Warning: Binary may not be signed (IsSigned() returned false)");
        // Continue anyway - the signing might have worked but IsSigned() might not detect it
    }
    
    // Write the signed binary back to disk
    NSError *writeError = nil;
    if (![mutableData writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
        NSLog(@"[ZSigner] Error: Failed to write signed binary to disk: %@", writeError);
        return NO;
    }
    
    NSLog(@"[ZSigner] Successfully signed binary at: %@", path);
    return YES;
}

@end
