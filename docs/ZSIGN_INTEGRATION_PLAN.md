# ZSign Integration Plan - Complete Fix Guide

## Overview
ZSign is now added to the extension target, but there are a few missing pieces to make it fully functional. This document outlines the complete plan to fix everything.

## Current Status ✅
- [x] ZSign source files added to `HIAHProcessRunner` target in `project.yml`
- [x] C++ compilation enabled (C++17)
- [x] Include paths configured
- [x] `HIAHSigner.m` updated to use `ZSigner.adhocSignMachOAtPath`
- [x] Fallback to `codesign` ad-hoc signing if ZSign unavailable

## Missing Pieces & Fix Plan

### 1. OpenSSL Dependency (CRITICAL) ⚠️

**Problem:**
- ZSign includes OpenSSL headers (`<openssl/pem.h>`, `<openssl/cms.h>`, etc.)
- iOS doesn't have OpenSSL by default
- For **ad-hoc signing** (JIT-less mode), OpenSSL is NOT actually used:
  - `InitAdhoc()` just sets flags (no OpenSSL)
  - When `m_bAdhoc = true`, `GenerateCMS()` is skipped
  - Ad-hoc signing creates a simple blob: `{0xfa, 0xde, 0x0b, 0x01, ...}`

**Solution Options:**

#### Option A: Stub OpenSSL Headers (RECOMMENDED for ad-hoc only)
Create minimal OpenSSL header stubs that provide just the types/definitions needed for compilation, but don't require the library.

**Steps:**
1. Create `source0/ZSign/stubs/openssl/` directory
2. Create minimal header stubs:
   - `openssl/pem.h` - minimal types
   - `openssl/cms.h` - minimal types  
   - `openssl/err.h` - minimal error codes
   - `openssl/provider.h` - minimal types
   - `openssl/pkcs12.h` - minimal types
   - `openssl/conf.h` - minimal types
   - `openssl/x509.h` - minimal types
   - `openssl/x509v3.h` - minimal types
   - `openssl/bio.h` - minimal types
   - `openssl/ssl.h` - minimal types
   - `openssl/asn1.h` - minimal types
   - `openssl/ocsp.h` - minimal types
3. Add stub include path to `HEADER_SEARCH_PATHS` before system paths
4. Ensure stubs only define types, not functions (since ad-hoc signing doesn't call them)

#### Option B: Link Against OpenSSL Static Library
If you have OpenSSL compiled for iOS, link it statically.

**Steps:**
1. Add OpenSSL static library to project
2. Add to `OTHER_LDFLAGS`: `-lssl -lcrypto`
3. Add library search path if needed

#### Option C: Conditional Compilation
Modify ZSign to conditionally compile OpenSSL-dependent code only when needed.

**Steps:**
1. Add `#define ZSIGN_ADHOC_ONLY 1` preprocessor flag
2. Wrap OpenSSL includes in `#ifndef ZSIGN_ADHOC_ONLY`
3. Stub out `GenerateCMS` for ad-hoc mode

**Recommendation:** Start with **Option A** (stub headers) - it's the cleanest for ad-hoc signing only.

---

### 2. Fix ZSigner Class Loading

**Problem:**
Current code uses `NSClassFromString(@"ZSigner")` which may not work if ZSign isn't linked properly.

**Fix:**
```objc
// In HIAHSigner.m, replace the class loading logic:
Class zSignerClass = nil;

#if HAS_ZSIGN
// Direct import - class should be available at link time
zSignerClass = [ZSigner class];
#else
// Fallback to runtime lookup
zSignerClass = NSClassFromString(@"ZSigner");
#endif

if (!zSignerClass) {
  HIAHLogEx(HIAH_LOG_WARNING, @"Signer", @"ZSigner class not found");
  // Fall through to codesign fallback
}
```

**Steps:**
1. Update `HIAHSigner.m` to use direct class reference when `HAS_ZSIGN` is defined
2. Remove redundant `NSClassFromString` calls

---

### 3. Verify Binary Patching Order

**Problem:**
ZSign expects the binary to be in a certain state. We patch it first (MH_BUNDLE + __PAGEZERO), then sign.

**Current Flow (in `HIAHProcessRunner.m`):**
1. Patch binary: `patchBinaryToDylib` + `patchPageZero`
2. Remove signature: `removeCodeSignature`
3. Sign: `HIAHSigner.signBinaryAtPath`

**Verify:**
- [ ] Binary is patched BEFORE signing
- [ ] Signature is removed BEFORE signing
- [ ] ZSign receives the patched, unsigned binary

**Steps:**
1. Check `HIAHProcessRunner.m` `continueBinaryLoadingWithBypass` function
2. Ensure order is: Patch → Remove Signature → Sign
3. Add logging to confirm order

---

### 4. Test Compilation

**Steps:**
1. **Regenerate Xcode project:**
   ```bash
   # If using Nix:
   nix develop
   # Or manually run XcodeGen if installed
   ```

2. **Build the extension target:**
   - Open Xcode
   - Select `HIAHProcessRunner` target
   - Build (Cmd+B)
   - Check for errors

3. **Expected Errors (if OpenSSL not handled):**
   - `'openssl/pem.h' file not found`
   - `'openssl/cms.h' file not found`
   - Similar for other OpenSSL headers

4. **If OpenSSL errors occur:**
   - Implement Option A (stub headers) from section 1
   - Or implement Option C (conditional compilation)

---

### 5. Test Runtime Behavior

**Steps:**
1. **Build and run the app**
2. **Launch an unsigned app (e.g., UTM SE)**
3. **Check logs for:**
   ```
   [Signer] Trying ZSign for programmatic signing (like LiveContainer)...
   [Signer] ✅ ZSigner class found - using ZSign for signing
   [Signer] ✅ Binary signed successfully with ZSign (ad-hoc)
   ```
4. **If ZSign fails, should fall back to:**
   ```
   [Signer] Attempting ad-hoc signing with codesign as fallback...
   [Signer] ✅ Binary ad-hoc signed successfully with codesign
   ```

5. **Verify binary loads:**
   - Check extension logs: `HIAHExtension.log`
   - Should see: `dlopen` succeeds (no "code signature invalid" error)
   - App should launch successfully

---

### 6. Handle Edge Cases

#### 6.1 Bundle ID Detection
**Current:** Uses default `com.aspauldingcode.HIAHDesktop.guest` if Info.plist not found

**Improvement:**
- Extract bundle ID from binary's embedded Info.plist
- Or use executable name as fallback
- Log the bundle ID used

#### 6.2 Entitlements
**Current:** Creates minimal entitlements

**Verify:**
- Entitlements are properly serialized to XML plist format
- ZSign accepts the entitlement data
- Entitlements match what the app needs

#### 6.3 Error Handling
**Current:** Falls back to codesign if ZSign fails

**Improvement:**
- Log specific ZSign error if available
- Provide more diagnostic information
- Consider retrying with different parameters

---

## Implementation Priority

### Phase 1: Get It Compiling (HIGH PRIORITY)
1. ✅ Add ZSign files to project.yml (DONE)
2. ⚠️ **Handle OpenSSL dependency** (Option A - stub headers)
3. Fix ZSigner class loading
4. Test compilation

### Phase 2: Get It Working (MEDIUM PRIORITY)
5. Verify binary patching order
6. Test runtime behavior
7. Fix any runtime issues

### Phase 3: Polish (LOW PRIORITY)
8. Improve bundle ID detection
9. Enhance error handling
10. Add more logging

---

## Quick Start: Handle OpenSSL (Option A - Stub Headers)

### Step 1: Create Stub Directory
```bash
mkdir -p source0/ZSign/stubs/openssl
```

### Step 2: Create Minimal Headers
Create these files with minimal type definitions:

**`source0/ZSign/stubs/openssl/openssl/pem.h`:**
```c
#ifndef OPENSSL_PEM_H
#define OPENSSL_PEM_H

// Minimal stubs for ad-hoc signing (doesn't use OpenSSL)
typedef void* EVP_PKEY;
typedef void* X509;
typedef void* BIO;

#endif
```

**`source0/ZSign/stubs/openssl/openssl/cms.h`:**
```c
#ifndef OPENSSL_CMS_H
#define OPENSSL_CMS_H

typedef void* CMS_ContentInfo;

#endif
```

**Repeat for:** `err.h`, `provider.h`, `pkcs12.h`, `conf.h`, `x509.h`, `x509v3.h`, `bio.h`, `ssl.h`, `asn1.h`, `ocsp.h`

### Step 3: Update project.yml
Add stub include path **BEFORE** system paths:
```yaml
HEADER_SEARCH_PATHS:
  - $(SRCROOT)/source0/ZSign/stubs  # Add this FIRST
  - $(SRCROOT)/src
  - $(SRCROOT)/src/hooks
  - $(SRCROOT)/source0/ZSign
  - $(SRCROOT)/source0/ZSign/common
```

### Step 4: Test Compilation
Build and verify no OpenSSL errors.

---

## Alternative: Use System Security Framework

If OpenSSL stubs are too complex, we could modify ZSign to use iOS's Security framework instead of OpenSSL for ad-hoc signing. However, this requires more code changes.

---

## Testing Checklist

- [ ] Project compiles without errors
- [ ] Extension builds successfully
- [ ] ZSigner class is available at runtime
- [ ] `adhocSignMachOAtPath` can be called
- [ ] Binary is signed successfully (check with `codesign -dv`)
- [ ] Signed binary can be `dlopen`'d
- [ ] Unsigned apps (UTM SE) launch successfully
- [ ] Logs show ZSign being used (not codesign fallback)

---

## Troubleshooting

### "ZSigner class not found"
- Check that ZSign files are in the extension target
- Verify `HAS_ZSIGN` is defined
- Check linking - ensure ZSign symbols are exported

### "OpenSSL headers not found"
- Implement Option A (stub headers)
- Or add OpenSSL library/include paths

### "Binary still fails to load after signing"
- Check binary is patched (MH_BUNDLE + __PAGEZERO)
- Verify signature was removed before signing
- Check entitlements are correct
- Verify JIT is enabled OR JIT-less mode is working

### "dlopen: code signature invalid"
- ZSign may not have worked - check logs
- Verify fallback to codesign occurred
- Check that binary patching happened
- Ensure signature removal happened

---

## Next Steps (In Order)

1. **Try building first** - see what errors you get
2. **If OpenSSL errors:** Implement stub headers (Option A)
3. **Fix ZSigner class loading** - use direct import
4. **Test compilation** - ensure it builds
5. **Test runtime** - launch an unsigned app
6. **Verify signing** - check logs and binary signature
7. **Fix any issues** - iterate based on results

---

## Summary

The main missing piece is **OpenSSL dependency handling**. Since ad-hoc signing doesn't actually use OpenSSL, the cleanest solution is to create minimal stub headers that satisfy the compiler without requiring the OpenSSL library.

Once OpenSSL is handled, ZSign should work exactly like LiveContainer uses it - programmatic signing without needing `ldid` or `codesign` external tools.
