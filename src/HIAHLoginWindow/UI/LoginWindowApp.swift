/**
 * LoginWindowApp.swift
 * HIAH LoginWindow - SideStore Integration
 *
 * Main entry point for HIAH LoginWindow.
 * Provides Apple ID authentication for HIAH Desktop.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import SwiftUI

// NOTE: This struct is NOT used as @main - HIAHDesktop has its own main entry point
// This file is kept for reference but LoginWindowApp is integrated into HIAHDesktop
struct LoginWindowApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                // Show success screen
                AuthenticatedView()
            } else {
                // Show login screen
                LoginView()
            }
        }
    }
}

