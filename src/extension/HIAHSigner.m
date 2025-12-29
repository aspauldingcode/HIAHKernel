#import "HIAHSigner.h"
#import "../HIAHDesktop/HIAHLogging.h"
#import "../HIAHDesktop/HIAHMachOUtils.h"

@implementation HIAHSigner

+ (BOOL)signBinaryAtPath:(NSString *)path {
  // In extension context, we might not have `ldid`.
  // However, we can use HIAHMachOUtils to "remove" signature which often allows
  // running if dyld bypass is active. Or we can invoke `ldid -S` if bundled.

  HIAHLogEx(HIAH_LOG_INFO, @"Signer", @"Requesting signature update for: %@",
            path.lastPathComponent);

  // Step 1: Remove existing signature to ensure clean slate
  BOOL removed = [HIAHMachOUtils removeCodeSignature:path];
  if (removed) {
    HIAHLogEx(HIAH_LOG_INFO, @"Signer", @"Removed existing code signature");
  }

  // Step 2: Ad-hoc sign (Placeholder)
  // Real implementation would invoke: ldid -S <path>
  // For now, we assume dyld bypass handles unsigned binaries
  HIAHLogEx(HIAH_LOG_INFO, @"Signer",
            @"Ad-hoc signing simulated (Relies on Dyld Bypass)");

  return YES;
}

@end
