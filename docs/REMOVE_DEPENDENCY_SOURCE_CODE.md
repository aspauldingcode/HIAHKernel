# Plan: Remove All Dependency Source Code from Repository

## Goal
Use Nix to build all dependencies and stage only build artifacts (headers + libraries). No dependency source code should be in the repository.

## Current State

### ✅ What's Already Good
- `dependencies/zsign.nix` - Nix package definition (build config, not source)
- `dependencies/build.nix`, `dependencies/common/`, `dependencies/platforms/` - Nix build infrastructure
- `dependencies/deps/` - Nix package definitions for bash, busybox, etc.

### ❌ What Needs to Be Removed (Dependency Source Code)
- `dependencies/libimobiledevice/` - Full source code (should be fetched by Nix)
- `dependencies/libimobiledevice-glue/` - Full source code (should be fetched by Nix)
- `dependencies/libplist/` - Full source code (should be fetched by Nix)
- `dependencies/libusbmuxd/` - Full source code (should be fetched by Nix)
- `Dependencies/` - Same as `dependencies/` (case-insensitive filesystem)

### ⚠️ What Needs to Be Created/Fixed
- `dependencies/sidestore/default.nix` - Missing Nix package definitions
- Template error in zsign archo.h (needs `<set>` include)

## Implementation Plan

### Phase 1: Fix Immediate Issues
1. ✅ Create `dependencies/sidestore/default.nix` (Nix package definitions)
2. ✅ Fix template error in zsign archo.h (add `#include <set>`)
3. ✅ Move ZSigner wrapper to `src/zsign/` (it's our code, not dependency source)

### Phase 2: Create Nix Packages for libimobiledevice Stack ✅ COMPLETED
Create Nix packages that fetch and build:
- ✅ `dependencies/libplist.nix` - Fetch from SideStore fork, build for iOS (COMPLETED)
- ✅ `dependencies/libimobiledevice-glue.nix` - Fetch from upstream, build for iOS (COMPLETED)
- ✅ `dependencies/libusbmuxd.nix` - Fetch from upstream, build for iOS (COMPLETED)
- ✅ `dependencies/libimobiledevice.nix` - Fetch from SideStore fork, build for iOS (COMPLETED)

These should:
- Fetch source from GitHub (not store in repo) ✅
- Build static libraries for iOS Simulator and iOS Device ✅
- Output only: `lib/` (libraries) and `include/` (headers) ✅
- No source code in output ✅

**Progress:**
1. ✅ Created `dependencies/libplist.nix` - Standalone package, fetches from GitHub, builds for iOS Simulator and Device
2. ✅ Created `dependencies/libimobiledevice-glue.nix` - Depends on libplist, fetches from upstream
3. ✅ Created `dependencies/libusbmuxd.nix` - Depends on libplist and libimobiledevice-glue
4. ✅ Created `dependencies/libimobiledevice.nix` - Depends on all three above, fetches from SideStore fork
5. ✅ Added all packages to flake.nix exports
6. ✅ Updated staging script in flake.nix to stage libimobiledevice stack (ready to use)

### Phase 3: Update Staging Script ✅ COMPLETED
Update `flake.nix` xcgen script to:
- ✅ Stage libimobiledevice libraries and headers from Nix builds
- ✅ Stage libplist libraries and headers from Nix builds
- ✅ Stage libusbmuxd libraries and headers from Nix builds
- ✅ Stage libimobiledevice-glue libraries and headers from Nix builds
- ✅ Only copy build artifacts, never source code

**Completed:** Staging script updated to use standalone packages and stage all libraries/headers to `dependencies/libimobiledevice/`

### Phase 4: Update project.yml ✅ COMPLETED
Change from compiling source files to linking against staged libraries:
- ✅ Removed `Dependencies/libimobiledevice/src` source compilation
- ✅ Removed `Dependencies/libplist/src` source compilation (kept libplist-compat.c - it's our code)
- ✅ Removed `Dependencies/libusbmuxd/src` source compilation
- ✅ Removed `Dependencies/libimobiledevice-glue/src` source compilation
- ✅ Added library linking: `-limobiledevice`, `-lplist`, `-lusbmuxd`, `-limobiledevice-glue`
- ✅ Updated header search paths to point to staged headers in `dependencies/libimobiledevice/include/`
- ✅ Updated library search paths for both iOS Simulator and iOS Device

### Phase 5: Remove Source Code Directories ⏳ READY
After Nix packages are working:
- ⏳ Remove `dependencies/libimobiledevice/` (source) - **READY** (packages built, project.yml updated)
- ⏳ Remove `dependencies/libimobiledevice-glue/` (source) - **READY**
- ⏳ Remove `dependencies/libplist/` (source) - **READY**
- ⏳ Remove `dependencies/libusbmuxd/` (source) - **READY**
- ✅ Keep only Nix package definitions (`.nix` files)

**Status:** All packages created, staging script updated, project.yml updated. Source directories can be removed once we verify the staged libraries work correctly.

### Phase 6: Update .gitignore ✅ COMPLETED
Ensure all staged build artifacts are ignored:
- ✅ Added `dependencies/libimobiledevice/lib/`
- ✅ Added `dependencies/libimobiledevice/lib-ios/`
- ✅ Added `dependencies/libimobiledevice/include/`
- ✅ Already had other dependency artifacts ignored

## Benefits
1. **Cleaner Repository**: No dependency source code cluttering the repo
2. **Reproducible Builds**: All dependencies built deterministically by Nix
3. **Easier Updates**: Update dependency versions by changing Nix package definitions
4. **Smaller Git History**: No dependency source code changes in history
5. **Single Source of Truth**: Nix is the only place dependency versions are defined

## Current Blockers
1. Missing `dependencies/sidestore/default.nix` - needs to be created
2. Template error in zsign archo.h - needs `#include <set>` fix
3. libimobiledevice stack still compiled from source in project.yml

## Next Steps
1. Create sidestore Nix package definitions (or find where they should be)
2. Fix zsign template error
3. Create Nix packages for libimobiledevice stack
4. Update staging and project.yml
5. Remove source code directories
