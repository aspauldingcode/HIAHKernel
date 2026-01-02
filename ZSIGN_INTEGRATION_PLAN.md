# ZSign Integration Plan - Complete Fix Guide

## Overview
ZSign is now added to the extension target, but there are a few missing pieces to make it fully functional. This document outlines the complete plan to fix everything.

## Current Status ✅
- [x] ZSign source files added to `HIAHProcessRunner` target in `project.yml`
- [x] C++ compilation enabled (C++17)
- [x] Include paths configured
- [x] `HIAHSigner.m` updated to use `ZSigner.adhocSignMachOAtPath`
- [x] Fallback to `codesign` ad-hoc signing if ZSign unavailable
- [x] ZSigner class loading fixed (direct import when HAS_ZSIGN defined)

## Missing Pieces & Fix Plan

### 1. OpenSSL Dependency (CRITICAL) ⚠️

**Problem:**
- ZSign includes OpenSSL headers (`<openssl/pem.h>`, `<openssl/cms.h>`, etc.)
- iOS doesn't have OpenSSL by default
- For **ad-hoc signing** (JIT-less mode), OpenSSL is NOT actually used:
  - `InitAdhoc()` just sets flags (no OpenSSL)
  - When `m_bAdhoc = true`, `GenerateCMS()` is skipped
  - Ad-hoc signing creates a simple blob: `{0xfa, 0xde, 0x0b, 0x01, ...}`

**Solution: Create OpenSSL Stub Headers (RECOMMENDED)**

Since ad-hoc signing doesn't use OpenSSL, we just need minimal header stubs for compilation.

**Steps:**
1. Create directory: `source0/ZSign/stubs/openssl/openssl/`
2. Create minimal header stubs (see below)
3. Add stub path to `HEADER_SEARCH_PATHS` in `project.yml` (FIRST, before system paths)

**Stub Headers Needed:**
- `openssl/pem.h`
- `openssl/cms.h`
- `openssl/err.h`
- `openssl/provider.h`
- `openssl/pkcs12.h`
- `openssl/conf.h`
- `openssl/x509.h`
- `openssl/x509v3.h`
- `openssl/bio.h`
- `openssl/ssl.h`
- `openssl/asn1.h`
- `openssl/ocsp.h`

Each stub just needs type definitions, not function implementations.

---

### 2. Test Compilation

**Steps:**
1. Regenerate Xcode project (if using Nix/XcodeGen)
2. Build `HIAHProcessRunner` target
3. If OpenSSL errors: Implement stub headers (Step 1)
4. Fix any other compilation errors

---

### 3. Test Runtime

**Steps:**
1. Build and run the app
2. Launch unsigned app (UTM SE)
3. Check logs for ZSign usage
4. Verify binary loads successfully
5. If fails, check fallback to codesign

---

## Quick Implementation Guide

### Step 1: Create OpenSSL Stubs

```bash
mkdir -p source0/ZSign/stubs/openssl/openssl
```

Create minimal stub files (just type definitions, no implementations).

### Step 2: Update project.yml

Add stub path FIRST in HEADER_SEARCH_PATHS:
```yaml
HEADER_SEARCH_PATHS:
  - $(SRCROOT)/source0/ZSign/stubs  # Add this FIRST
  - $(SRCROOT)/src
  - $(SRCROOT)/src/hooks
  - $(SRCROOT)/source0/ZSign
  - $(SRCROOT)/source0/ZSign/common
```

### Step 3: Build & Test

Build the extension and test with an unsigned app.

---

## Priority Order

1. **Handle OpenSSL** (stub headers) - Blocks compilation
2. **Test compilation** - Verify it builds
3. **Test runtime** - Verify it works
4. **Fix any issues** - Iterate based on results

---

## Expected Behavior

When working correctly:
- ZSign compiles without OpenSSL errors
- `ZSigner` class is available at runtime
- `adhocSignMachOAtPath` signs binaries successfully
- Unsigned apps launch via JIT-less mode
- Logs show: `✅ Binary signed successfully with ZSign (ad-hoc)`

