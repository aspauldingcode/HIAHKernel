# HIAH Desktop: Architecture and Roadmap

## Current State

HIAH Desktop is a virtual iOS desktop environment with process spawning capabilities. Recent refactoring has transformed it from a prototype into a clean, maintainable codebase.

### Refactoring Summary

**Key Improvements:**
- Centralized logging system (HIAHLogging)
- Removed emoji-heavy debugging
- Structured log levels (Debug/Info/Error)
- Consistent naming conventions
- Reduced verbosity by ~40%
- Professional code structure

**Components:**
- **HIAHKernel**: Virtual process management
- **HIAHProcessRunner**: Extension-based app execution
- **HIAHDesktop**: Window manager and UI
- **HIAHInstaller**: .ipa file extraction and installation
- **HIAHWindowServer**: Multi-window management
- **HIAHFilesystem**: Virtual Unix filesystem

## Future: SideStore Integration

### Vision

Transform HIAH Desktop into a fully self-contained iOS desktop environment with integrated SideStore functionality, eliminating the need for external sideloading tools.

### Architecture

```
HIAH Desktop (Main App)
├── HIAH LoginWindow (SideStore Core)
│   ├── Apple Account Authentication
│   ├── Certificate Management
│   ├── App Signing (AltSign)
│   └── Self-Refresh (7-day renewal)
├── HIAH ProcessRunner (LiveProcess-style)
│   ├── VPN Loopback (EM Proxy)
│   ├── JIT Enablement
│   └── App Execution
└── HIAH Desktop Environment
    ├── Window Manager
    ├── App Launcher
    └── Virtual Filesystem
```

### Components to Integrate

**1. EM Proxy (VPN Loopback)**
- Source: `source2/SideStore/em_proxy/`
- Language: Rust
- Purpose: VPN tunnel for untethered installation

**2. Minimuxer (Lockdown Muxer)**
- Source: `source2/SideStore/minimuxer/`
- Language: Rust
- Purpose: On-device usbmuxd protocol

**3. AltSign (Code Signing)**
- Source: `source2/SideStore/AltSign/`
- Language: Objective-C/Swift
- Purpose: App signing with personal certificate

**4. Roxas (Utility Framework)**
- Source: `source2/Dependencies/Roxas/`
- Language: Objective-C/Swift
- Purpose: Common utilities

**5. SideStore Core**
- Source: `source2/AltStore/`, `source2/SideStore/`
- Language: Swift
- Purpose: Apple ID auth, certificate management

## Implementation Roadmap

### Phase 1: Dependencies (Week 1)
Build all SideStore dependencies with Nix:
- Rust components (em_proxy, minimuxer)
- Roxas framework
- AltSign framework
- libimobiledevice dependencies

### Phase 2: HIAH LoginWindow (Week 2-3)
Create login UI with SideStore authentication:
- Apple Account login interface
- Certificate download and storage
- Keychain integration
- Session management

### Phase 3: VPN Integration (Week 4)
Integrate EM Proxy for untethered operation:
- VPN tunnel setup
- Loopback routing
- Minimuxer protocol
- LocalDevVPN entitlement

### Phase 4: Enhanced ProcessRunner (Week 5)
LiveProcess-style execution:
- App signing before loading
- JIT enablement via VPN
- Certificate communication

### Phase 5: Self-Refresh System (Week 6)
Keep HIAH Desktop alive:
- Monitor certificate expiration
- Auto-resign every 7 days
- Background refresh
- User notifications

### Phase 6: Polish (Week 7)
- UI/UX improvements
- Error handling
- Documentation
- Testing

**Total Time: 7 weeks**

## Technical Flow

### VPN Loopback
```
HIAH Desktop → Start VPN (EM Proxy)
             → Creates loopback tunnel
             → Routes requests through VPN
             → Minimuxer handles lockdown
             → iOS thinks requests from computer
             → Allows installation & JIT!
```

### Certificate Management
```
User Login → Download Cert → Store in Keychain
          → Create Profile → Sign HIAH Desktop
          → Sign .ipa apps → Enable JIT
          → Apps run with JIT!
```

## Licensing

### AGPLv3 Compliance

SideStore components require AGPLv3. Strategy:

**Dual License Approach:**
- HIAH Desktop Core: MIT
- HIAH LoginWindow: AGPLv3 (SideStore integration)

This isolates AGPLv3 requirements to the LoginWindow component.

## File Structure

```
HIAHDesktop/
├── src/
│   ├── HIAHLoginWindow/        # AGPLv3
│   │   ├── Auth/
│   │   ├── Signing/
│   │   ├── VPN/
│   │   └── Refresh/
│   ├── HIAHDesktop/            # MIT
│   ├── HIAHProcessRunner/      # MIT
│   └── ...
├── dependencies/sidestore/
│   ├── em-proxy.nix
│   ├── minimuxer.nix
│   ├── roxas.nix
│   └── altsign.nix
└── LICENSE.AGPLv3
```

## Resources

- **SideStore**: https://github.com/SideStore/SideStore
- **EM Proxy**: https://github.com/jkcoxson/em_proxy
- **Minimuxer**: https://github.com/jkcoxson/minimuxer
- **Jitterbug**: https://github.com/osy/Jitterbug
- **LocalDevVPN**: https://github.com/jkcoxson/LocalDevVPN

## Success Criteria

- User installs HIAH Desktop once
- User logs in with Apple ID
- HIAH Desktop auto-refreshes itself
- User can install .ipa files
- Apps run with JIT enabled
- No external tools needed
- Works on non-jailbroken devices

---

**Current Phase**: Planning  
**Next Milestone**: Phase 1 (Dependencies)  
**Status**: Ready to begin implementation

