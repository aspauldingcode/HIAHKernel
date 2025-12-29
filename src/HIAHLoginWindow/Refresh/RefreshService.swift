/**
 * RefreshService.swift
 * HIAH LoginWindow - Auto-Refresh Service
 *
 * Handles automatic 7-day refresh of HIAH Desktop and installed apps.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import Foundation
import BackgroundTasks

class RefreshService: ObservableObject {
    static let shared = RefreshService()
    
    @Published var lastRefreshDate: Date?
    @Published var nextRefreshDate: Date?
    
    private let refreshTaskIdentifier = "com.aspauldingcode.HIAHDesktop.refresh"
    // Note: AuthenticationManager.shared is MainActor-isolated, access via MainActor.run
    @MainActor private var signingService: SigningService { SigningService.shared }
    
    private init() {
        registerBackgroundTasks()
        scheduleNextRefresh()
    }
    
    // MARK: - Background Tasks
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskIdentifier,
            using: nil
        ) { task in
            self.handleRefreshTask(task as! BGAppRefreshTask)
        }
        
        print("[Refresh] Background task registered")
    }
    
    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        
        // Schedule for 5 days from now (2 days before expiration)
        request.earliestBeginDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())
        
        do {
            try BGTaskScheduler.shared.submit(request)
            nextRefreshDate = request.earliestBeginDate
            print("[Refresh] Next refresh scheduled for: \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            print("[Refresh] Failed to schedule refresh: \(error)")
        }
    }
    
    private func handleRefreshTask(_ task: BGAppRefreshTask) {
        print("[Refresh] Background refresh task started")
        
        task.expirationHandler = {
            print("[Refresh] Background task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                try await performRefresh()
                task.setTaskCompleted(success: true)
                scheduleNextRefresh()
            } catch {
                print("[Refresh] Refresh failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    // MARK: - Refresh Logic
    
    func performRefresh() async throws {
        print("[Refresh] Starting refresh...")
        
        // Check if authenticated (MainActor-isolated)
        let isAuthenticated = await MainActor.run {
            AuthenticationManager.shared.isAuthenticated
        }
        
        guard isAuthenticated else {
            throw NSError(domain: "RefreshService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Check if refresh is needed (MainActor-isolated)
        let needsRefresh = await MainActor.run {
            AuthenticationManager.shared.needsRefresh()
        }
        
        guard needsRefresh else {
            print("[Refresh] Refresh not needed yet")
            return
        }
        
        // Re-sign HIAH Desktop
        try await signingService.signHIAHDesktop()
        
        // Update last refresh date
        await MainActor.run {
            lastRefreshDate = Date()
        }
        
        // Update certificate expiration (MainActor-isolated)
        await MainActor.run {
            AuthenticationManager.shared.certificateExpirationDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        }
        
        print("[Refresh] Refresh complete")
    }
    
    func manualRefresh() async throws {
        print("[Refresh] Manual refresh requested")
        try await performRefresh()
    }
    
    func daysUntilExpiration() async -> Int? {
        let expirationDate = await MainActor.run {
            AuthenticationManager.shared.certificateExpirationDate
        }
        
        guard let expirationDate = expirationDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
        return components.day
    }
}

