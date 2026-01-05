# HIAHLoginWindow

Apple ID authentication and certificate management.

**License: AGPLv3** (due to AltSign integration patterns)

## Overview

HIAHLoginWindow provides:
- Apple ID login with 2FA
- Development certificate management
- Anisette data generation
- App signing coordination
- JIT enablement via minimuxer

## Features

### Authentication
- Apple ID username/password
- Two-factor authentication
- Session persistence
- Secure credential storage

### Certificate Management
- Fetch development certificates
- 7-day expiration tracking
- Automatic refresh
- Certificate caching

### App Signing
- Ad-hoc signing via ZSign
- Certificate-based signing
- Entitlements injection
- Provisioning profiles

### JIT Enablement
- em_proxy VPN loopback
- minimuxer debugserver connection
- CS_DEBUGGED flag setting

## Usage

```swift
// Login
let accountManager = HIAHAccountManager.shared
try await accountManager.login(username: "user@example.com", 
                               password: "password")

// Handle 2FA if needed
if accountManager.requires2FA {
    try await accountManager.verify2FA(code: "123456")
}

// Get certificate
let certManager = HIAHCertificateManager.shared
let cert = try await certManager.fetchCertificate()

// Sign app
let signer = SigningService.shared
try await signer.signApp(at: appURL, certificate: cert)

// Enable JIT
let minimuxer = HIAHMinimuxer.shared
try await minimuxer.enableJIT(for: pid)
```

## Components

| Component | Purpose |
|-----------|---------|
| `HIAHAccountManager` | Apple ID authentication |
| `HIAHCertificateManager` | Certificate handling |
| `SigningService` | App signing coordination |
| `HIAHMinimuxer` | JIT enablement |
| `HIAHVPNManager` | em_proxy coordination |

## Files

```
src/HIAHLoginWindow/
├── Auth/
│   └── HIAHAccountManager.swift
├── Signing/
│   ├── HIAHCertificateManager.swift
│   └── SigningService.swift
├── JIT/
│   └── HIAHMinimuxer.swift
└── VPN/
    ├── HIAHVPNManager.swift
    ├── EMProxyBridge.h
    └── MinimuxerBridge.h
```

## Why AGPLv3?

HIAHLoginWindow implements patterns from AltSign/SideStore for Apple authentication. While our Rust implementations (em_proxy, minimuxer) are clean-room MIT, the Swift auth code follows AGPLv3-licensed patterns.

**Implications:**
- If you distribute HIAHLoginWindow, you must provide source
- The rest of HIAH (kernel, extension) remains MIT
- You can use the MIT parts without AGPLv3 obligations

## Without HIAHLoginWindow

For MIT-only builds, omit HIAHLoginWindow:
- Manually sign apps before installing
- No Apple ID integration
- No automatic JIT (manual debugger attach)

Set `HIAH_MINIMAL_BUILD=1` to exclude.
