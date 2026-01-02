#import "HIAHSigner.h"
#import "../HIAHDesktop/HIAHLogging.h"
#import "../HIAHDesktop/HIAHMachOUtils.h"
#import <Security/Security.h>
#import <spawn.h>
#import <sys/wait.h>

// ZSign for programmatic signing (like LiveContainer)
// ZSign is compiled via Nix and wrapped in ZSigner Objective-C class
#if __has_include("../../zsign/ZSigner.h")
#import "../../zsign/ZSigner.h"
#define HAS_ZSIGN 1
#elif __has_include("../../../zsign/ZSigner.h")
#import "../../../zsign/ZSigner.h"
#define HAS_ZSIGN 1
#elif __has_include("zsign/ZSigner.h")
#import "zsign/ZSigner.h"
#define HAS_ZSIGN 1
#else
// ZSign should be available since it's in project.yml, but if not, we'll use runtime class loading
#define HAS_ZSIGN 0
#endif

@implementation HIAHSigner

+ (BOOL)signBinaryAtPath:(NSString *)path {
  HIAHLogEx(HIAH_LOG_INFO, @"Signer", @"Signing binary: %@", path.lastPathComponent);

  // Try to get certificate from HIAHCertificateManager (Swift class)
  Class certManagerClass = NSClassFromString(@"HIAHCertificateManager");
  if (!certManagerClass) {
    HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"HIAHCertificateManager class not found - cannot sign binary");
    return NO;
  }
  
  SEL sharedSel = NSSelectorFromString(@"shared");
  id certManager = nil;
  if ([certManagerClass respondsToSelector:sharedSel]) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    certManager = [certManagerClass performSelector:sharedSel];
    #pragma clang diagnostic pop
  }
  
  if (!certManager) {
    HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"Failed to get HIAHCertificateManager instance");
    return NO;
  }
  
  // Check if certificate is available
  SEL hasCertSel = NSSelectorFromString(@"hasCertificate");
  BOOL hasCert = NO;
  if ([certManager respondsToSelector:hasCertSel]) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSMethodSignature *sig = [certManager methodSignatureForSelector:hasCertSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:certManager];
    [inv setSelector:hasCertSel];
    [inv invoke];
    [inv getReturnValue:&hasCert];
    #pragma clang diagnostic pop
  }
  
  if (!hasCert) {
    HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"No certificate available - cannot sign binary");
    HIAHLogEx(HIAH_LOG_INFO, @"Signer", @"Please sign in to HIAH LoginWindow to get a certificate from SideStore");
    return NO;
  }
  
  // Get certificate property
  SEL certSel = NSSelectorFromString(@"certificate");
  id certificate = nil;
  if ([certManager respondsToSelector:certSel]) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSMethodSignature *sig = [certManager methodSignatureForSelector:certSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:certManager];
    [inv setSelector:certSel];
    [inv invoke];
    [inv getReturnValue:&certificate];
    #pragma clang diagnostic pop
  }
  
  if (!certificate) {
    HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"Certificate is nil");
    return NO;
  }
  
  // Get P12 data and password from certificate
  SEL p12DataSel = NSSelectorFromString(@"p12Data");
  NSData *p12Data = nil;
  if ([certificate respondsToSelector:p12DataSel]) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSMethodSignature *sig = [certificate methodSignatureForSelector:p12DataSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:certificate];
    [inv setSelector:p12DataSel];
    [inv invoke];
    [inv getReturnValue:&p12Data];
    #pragma clang diagnostic pop
  }
  
  if (!p12Data) {
    HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"Certificate has no P12 data");
    return NO;
  }
  
  // Get machine identifier (password for P12)
  SEL machineIdSel = NSSelectorFromString(@"machineIdentifier");
  NSString *password = nil;
  if ([certificate respondsToSelector:machineIdSel]) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSMethodSignature *sig = [certificate methodSignatureForSelector:machineIdSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:certificate];
    [inv setSelector:machineIdSel];
    [inv invoke];
    [inv getReturnValue:&password];
    #pragma clang diagnostic pop
  }
  
  // Import P12 into keychain
  NSDictionary *options = @{
    (__bridge id)kSecImportExportPassphrase: password ?: @""
  };
  
  CFArrayRef items = NULL;
  OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)options, &items);
  
  if (status != errSecSuccess || !items || CFArrayGetCount(items) == 0) {
    HIAHLogEx(HIAH_LOG_ERROR, @"Signer", @"Failed to import P12 certificate: %d", (int)status);
    return NO;
  }
  
  CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
  SecIdentityRef identity = (SecIdentityRef)CFDictionaryGetValue(identityDict, kSecImportItemIdentity);
  
  if (!identity) {
    HIAHLogEx(HIAH_LOG_ERROR, @"Signer", @"Failed to get identity from P12");
    CFRelease(items);
    return NO;
  }
  
  // CRITICAL: Use ZSign for programmatic signing (like LiveContainer)
  // ZSign's adhocSignMachOAtPath can sign a single binary without needing ldid/codesign
  // This is how LiveContainer solves the signing problem in JIT-less mode
  // 
  // LiveContainer uses ZSign's adhocSignMachOAtPath which:
  // 1. Patches the binary (MH_BUNDLE + __PAGEZERO) - we do this separately
  // 2. Signs it with ad-hoc signature (no certificate needed)
  // 3. Works entirely programmatically using Security framework APIs
  
  // Try ZSign first (programmatic signing, no external tools needed)
  // ZSign is compiled into the extension, so we can use it directly
  HIAHLogEx(HIAH_LOG_INFO, @"Signer", @"Trying ZSign for programmatic signing (like LiveContainer)...");
  
  Class zSignerClass = nil;
  
  #if HAS_ZSIGN
  // Direct class reference - ZSign is compiled into extension
  zSignerClass = [ZSigner class];
  #else
  // Fallback to runtime lookup (shouldn't happen if ZSign is in project.yml)
  zSignerClass = NSClassFromString(@"ZSigner");
  #endif
  
  if (zSignerClass) {
    HIAHLogEx(HIAH_LOG_INFO, @"Signer", @"✅ ZSigner class found - using ZSign for signing");
    // Get bundle ID from the binary's Info.plist (if available)
    // For now, use a default bundle ID
    NSString *bundleId = @"com.aspauldingcode.HIAHDesktop.guest";
    
    // Try to find Info.plist in the same directory or parent .app bundle
    NSString *appBundlePath = [path stringByDeletingLastPathComponent];
    if ([appBundlePath hasSuffix:@".app"]) {
      NSString *infoPlistPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
      NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
      if (infoPlist[@"CFBundleIdentifier"]) {
        bundleId = infoPlist[@"CFBundleIdentifier"];
      }
    }
    
    // Create minimal entitlements (required by ZSign)
    NSDictionary *entitlements = @{
      @"get-task-allow": @YES,
      @"com.apple.security.cs.allow-jit": @YES,
      @"com.apple.security.cs.allow-unsigned-executable-memory": @YES,
      @"com.apple.security.cs.disable-library-validation": @YES
    };
    
    NSError *entitlementsError = nil;
    NSData *entitlementData = [NSPropertyListSerialization dataWithPropertyList:entitlements
                                                                          format:NSPropertyListXMLFormat_v1_0
                                                                         options:0
                                                                           error:&entitlementsError];
    
    if (!entitlementData) {
      HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"Failed to create entitlements data: %@", entitlementsError);
      // Continue anyway - ZSign might work without entitlements
      entitlementData = [NSData data];
    }
    
    // Use ZSign's adhocSignMachOAtPath (ad-hoc signing)
    // This is what LiveContainer uses for JIT-less mode
    SEL adhocSignSel = NSSelectorFromString(@"adhocSignMachOAtPath:bundleId:entitlementData:");
    if ([zSignerClass respondsToSelector:adhocSignSel]) {
      #pragma clang diagnostic push
      #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      NSMethodSignature *sig = [zSignerClass methodSignatureForSelector:adhocSignSel];
      NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
      [inv setTarget:zSignerClass];
      [inv setSelector:adhocSignSel];
      [inv setArgument:&path atIndex:2];
      [inv setArgument:&bundleId atIndex:3];
      [inv setArgument:&entitlementData atIndex:4];
      [inv invoke];
      
      BOOL success = NO;
      [inv getReturnValue:&success];
      #pragma clang diagnostic pop
      
      if (success) {
        HIAHLogEx(HIAH_LOG_INFO, @"Signer", @"✅ Binary signed successfully with ZSign (ad-hoc)");
        CFRelease(items);
        return YES;
      } else {
        HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"ZSign ad-hoc signing failed");
      }
    } else {
      HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"ZSigner does not respond to adhocSignMachOAtPath:selector");
    }
  } else {
    HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"ZSigner class not found - ZSign not available");
  }
  
  // Fallback: Try ad-hoc signing using codesign with "-" identity
  // This creates an ad-hoc signature which is better than no signature at all
  HIAHLogEx(HIAH_LOG_INFO, @"Signer", @"Attempting ad-hoc signing with codesign as fallback...");
  
  NSString *codesignPath = @"/usr/bin/codesign";
  if ([[NSFileManager defaultManager] fileExistsAtPath:codesignPath]) {
    const char *codesignPathC = [codesignPath UTF8String];
    const char *pathC = [path UTF8String];
    
    char *argv[] = {
      (char *)codesignPathC,
      "--force",
      "--sign",
      "-",  // Ad-hoc signing identity
      (char *)pathC,
      NULL
    };
    
    pid_t pid;
    int status_code;
    int result = posix_spawn(&pid, codesignPathC, NULL, NULL, argv, NULL);
    
    if (result == 0) {
      waitpid(pid, &status_code, 0);
      
      if (WIFEXITED(status_code) && WEXITSTATUS(status_code) == 0) {
        HIAHLogEx(HIAH_LOG_INFO, @"Signer", @"✅ Binary ad-hoc signed successfully with codesign");
        CFRelease(items);
        return YES;
      } else {
        HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"Ad-hoc codesign failed with exit status: %d", WEXITSTATUS(status_code));
      }
    } else {
      HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"Failed to spawn codesign for ad-hoc signing: %s", strerror(result));
    }
  } else {
    HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"codesign not available for ad-hoc signing");
  }
  
  // If all signing attempts failed, the binary will be unsigned
  // This will only work if JIT is enabled and dyld bypass is active
  HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"⚠️ All signing attempts failed - binary will be unsigned");
  HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"⚠️ This will only work if JIT is enabled and dyld bypass is active");
  
  CFRelease(items);
  
  return NO; // Return NO to indicate signing failed
}

@end
