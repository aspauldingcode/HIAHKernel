/**
 * HIAHLoginWindow-Bridging-Header.h
 * HIAH LoginWindow - Objective-C to Swift Bridge
 *
 * Bridges C libraries from SideStore to Swift.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

#ifndef HIAHLoginWindow_Bridging_Header_h
#define HIAHLoginWindow_Bridging_Header_h

// EM Proxy (VPN)
#import "EMProxyBridge.h"

// AltSign
#import <AltSign/AltSign.h>

// Roxas
#import <Roxas/Roxas.h>

// Minimuxer (Device communication) - Rust library via swift-bridge
#import "SwiftBridgeCore.h"
#import "minimuxer.h"

// HIAH VPN and JIT (LocalDevVPN-based - official SideStore VPN)
#import "VPN/HIAHVPNManager.h"
#import "VPN/HIAHVPNStateMachine.h"
#import "VPN/LocalDevVPN/HIAHLocalDevVPNManager.h"
#import "JIT/HIAHJITManager.h"
#import "JIT/HIAHJITEnablerHelper.h"
#import "Signing/HIAHSignatureBypass.h"
#import "Signing/HIAHBypassCoordinator.h"

#endif /* HIAHLoginWindow_Bridging_Header_h */

