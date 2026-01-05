# HIAH Architecture

## Overview

HIAH (House in a House) enables multi-process execution on jailed iOS by combining:
- Virtual process management
- NSExtension-based isolation
- POSIX syscall interception
- Optional JIT enablement for unsigned code

```
┌─────────────────────────────────────────────────────────────┐
│                     HIAHDesktop (Host App)                  │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ HIAHKernel  │  │HIAHLoginWindow│  │   HIAHTop        │  │
│  │ (MIT)       │  │ (AGPLv3)     │  │   (Process Mon)  │  │
│  └──────┬──────┘  └──────┬───────┘  └───────────────────┘  │
│         │                │                                  │
│         │    ┌───────────┴───────────┐                     │
│         │    │   Auth & Signing      │                     │
│         │    │   - Apple ID login    │                     │
│         │    │   - Certificate mgmt  │                     │
│         │    │   - ZSign (ad-hoc)    │                     │
│         │    └───────────────────────┘                     │
└─────────┼───────────────────────────────────────────────────┘
          │
          │ Unix Socket IPC
          ▼
┌─────────────────────────────────────────────────────────────┐
│              HIAHProcessRunner (NSExtension)                │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │  DYLD Bypass    │  │  Guest Process  │                  │
│  │  (JIT enabled)  │  │  (dlopen'd)     │                  │
│  └─────────────────┘  └─────────────────┘                  │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Virtual Filesystem                      │   │
│  │  /Applications, /var/mobile, /tmp (sandboxed)       │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Components

### HIAHKernel (Core Library)

The heart of HIAH. Manages virtual processes.

**Key Classes:**
- `HIAHKernel` - Singleton for process management
- `HIAHProcess` - Process representation
- `HIAHGuestHooks` - POSIX syscall interception

**Features:**
- Process table management
- IPC via Unix sockets
- Extension lifecycle coordination
- Output capture and routing

### HIAHProcessRunner (Extension)

NSExtension that actually runs guest code.

**Flow:**
1. Receives spawn request from kernel
2. Patches Mach-O binary (MH_EXECUTE → MH_BUNDLE)
3. If JIT enabled: activates DYLD bypass
4. If no JIT: re-signs with ZSign
5. `dlopen()` the patched binary
6. Routes output back to kernel

### HIAHLoginWindow (Auth/Signing)

Apple ID authentication and certificate management.

**Built-in SideStore Features:**
- Apple ID login with 2FA
- Anisette data generation
- Development certificate fetching
- 7-day certificate refresh

**Built-in LiveContainer Features:**
- App installation to virtual /Applications
- On-demand signing
- JIT enablement via minimuxer

### DYLD Bypass

When JIT is enabled (CS_DEBUGGED flag set), patches dyld to skip signature validation:
- Hooks `mmap()` and `fcntl()` 
- Allows loading unsigned/modified binaries
- Only activates when JIT is confirmed

### JIT Enablement

Two components work together:

1. **em_proxy** (Rust) - UDP loopback for LocalDevVPN
2. **minimuxer** (Rust) - Connects to debugserver via lockdown

**Flow:**
```
LocalDevVPN → em_proxy → minimuxer → debugserver → CS_DEBUGGED
```

### Virtual Filesystem

Sandboxed filesystem for guest apps:
- `/Applications` - Installed guest apps
- `/var/mobile` - User data
- `/tmp` - Temporary files

Stored in App Group container, accessible by both host and extension.

## Data Flow

### Process Spawn

```
1. Host calls [kernel spawnVirtualProcessWithPath:]
2. Kernel creates HIAHProcess, assigns virtual PID
3. Kernel writes request to control socket
4. Extension receives request
5. Extension patches binary, signs if needed
6. Extension dlopen's binary
7. Extension routes stdout/stderr to kernel
8. Kernel invokes onOutput callback
```

### JIT Enablement

```
1. User taps "Enable JIT" in HIAHDesktop
2. HIAHLoginWindow starts em_proxy
3. User connects LocalDevVPN (App Store app)
4. minimuxer connects through em_proxy
5. minimuxer sends debug_attach to lockdownd
6. iOS sets CS_DEBUGGED on extension process
7. DYLD bypass activates
8. Unsigned code can now load
```

## Build Configurations

### MINIMAL Build (MIT only)
- HIAHKernel core
- ProcessRunner extension
- No auth/signing (requires manual signing)

### FULL Build (includes AGPLv3)
- Everything in MINIMAL
- HIAHLoginWindow (auth/signing)
- em_proxy + minimuxer (JIT)
- ZSign integration

Controlled by `HIAH_MINIMAL_BUILD` preprocessor flag.

## License Boundaries

```
MIT License:
├── src/HIAHKernel/
├── src/extension/
└── src/HIAHTop/

AGPLv3 License:
└── src/HIAHLoginWindow/
    (Due to AltSign/Roxas integration patterns)
```

## Security Model

- Guest apps run in NSExtension sandbox
- No direct kernel access
- File access limited to App Group container
- Network access subject to iOS restrictions
- JIT requires explicit user action (LocalDevVPN)

## Platform Requirements

- iOS 14.0+
- App Groups entitlement
- For JIT: LocalDevVPN from App Store
