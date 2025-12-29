/**
 * LoginView.swift
 * HIAH LoginWindow - Apple ID Authentication UI
 *
 * Login interface styled like iOS/macOS login window.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import SwiftUI

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var appleID = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            // Background gradient (iOS/macOS style)
            LinearGradient(
                colors: [Color(white: 0.95), Color(white: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("HIAH Desktop")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("House in a House")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Login form
                VStack(spacing: 16) {
                    // Apple Account field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Account")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField("your-email@icloud.com", text: $appleID)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Sign in button
                    Button(action: signIn) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign In")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(isSignInEnabled ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!isSignInEnabled || isLoading)
                    
                    // Info text
                    VStack(spacing: 8) {
                        Text("Authentication enables:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            InfoRow(icon: "arrow.clockwise", text: "7-day auto-refresh of HIAH Desktop")
                            InfoRow(icon: "network", text: "JIT via SideStore VPN loopback")
                            InfoRow(icon: "checkmark.shield", text: "Bypass dyld signature validation")
                            InfoRow(icon: "app.badge", text: "Run unsigned .ipa apps (no re-signing)")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        
                        Text("Uses SideStore's VPN method (like LiveProcess)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.top, 4)
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Footer
                VStack(spacing: 4) {
                    Text("Powered by SideStore")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("AGPLv3 License")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
            }
        }
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private var isSignInEnabled: Bool {
        !appleID.isEmpty && !password.isEmpty && !isLoading
    }
    
    private func signIn() {
        isLoading = true
        
        Task {
            do {
                try await authManager.authenticate(appleID: appleID, password: password)
                // Success - AuthManager will update isAuthenticated
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

struct AuthenticatedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Signed In")
                .font(.system(size: 24, weight: .bold))
            
            Text("HIAH Desktop is ready to use")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Button("Launch HIAH Desktop") {
                // TODO: Transition to main desktop
                NotificationCenter.default.post(name: .init("LaunchHIAHDesktop"), object: nil)
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundColor(.blue)
            Text(text)
        }
    }
}

#Preview {
    LoginView()
}

