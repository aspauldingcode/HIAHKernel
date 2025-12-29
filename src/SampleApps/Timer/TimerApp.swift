/**
 * Timer - Fully Functional iOS Timer & Stopwatch App
 * Features: Multiple timers, presets, lap tracking, sound alerts
 */

import SwiftUI
import AVFoundation

// @main - Removed
struct TimerApp: App {
    var body: some Scene {
        WindowGroup {
            TimerView()
        }
    }
}

// MARK: - Timer Models

enum TimerMode: String, CaseIterable {
    case stopwatch = "Stopwatch"
    case countdown = "Timer"
}

struct TimerPreset: Identifiable {
    let id = UUID()
    let name: String
    let duration: TimeInterval
    
    static let defaults: [TimerPreset] = [
        TimerPreset(name: "1 min", duration: 60),
        TimerPreset(name: "5 min", duration: 300),
        TimerPreset(name: "10 min", duration: 600),
        TimerPreset(name: "15 min", duration: 900),
        TimerPreset(name: "30 min", duration: 1800),
        TimerPreset(name: "1 hour", duration: 3600)
    ]
}

// MARK: - Timer Engine

class TimerEngine: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var isRunning = false
    @Published var laps: [Lap] = []
    @Published var mode: TimerMode = .stopwatch
    @Published var countdownTime: TimeInterval = 60
    @Published var presets: [TimerPreset] = TimerPreset.defaults
    
    private var timer: Timer?
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    private var audioPlayer: AVAudioPlayer?
    
    struct Lap: Identifiable {
        let id = UUID()
        let time: TimeInterval
        let lapNumber: Int
    }
    
    var displayTime: TimeInterval {
        if mode == .countdown {
            return max(0, countdownTime - elapsed)
        }
        return elapsed
    }
    
    var progress: CGFloat {
        if mode == .countdown {
            return countdownTime > 0 ? CGFloat(displayTime / countdownTime) : 0
        }
        // Stopwatch: cycle every 60 seconds
        return CGFloat(elapsed.truncatingRemainder(dividingBy: 60)) / 60
    }
    
    var progressColor: Color {
        if mode == .countdown {
            if displayTime <= 10 {
                return .red
            } else if displayTime <= 30 {
                return .orange
            }
        }
        return .green
    }
    
    func toggleTimer() {
        if isRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }
    
    private func startTimer() {
        if mode == .countdown && elapsed >= countdownTime {
            resetTimer()
        }
        
        startTime = Date()
        isRunning = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if let start = self.startTime {
                self.elapsed = self.pausedTime + Date().timeIntervalSince(start)
            }
            
            // Check countdown completion
            if self.mode == .countdown && self.displayTime <= 0 {
                self.completeTimer()
            }
        }
        
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    private func pauseTimer() {
        timer?.invalidate()
        timer = nil
        pausedTime = elapsed
        startTime = nil
        isRunning = false
    }
    
    private func completeTimer() {
        pauseTimer()
        playCompletionSound()
    }
    
    func resetTimer() {
        pauseTimer()
        elapsed = 0
        pausedTime = 0
        laps.removeAll()
    }
    
    func addLap() {
        let lapNumber = laps.count + 1
        laps.append(Lap(time: elapsed, lapNumber: lapNumber))
    }
    
    func setCountdownTime(_ time: TimeInterval) {
        if !isRunning {
            countdownTime = time
            resetTimer()
        }
    }
    
    private func playCompletionSound() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "caf") else {
            // Use system sound if custom sound not available
            AudioServicesPlaySystemSound(1054)
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            AudioServicesPlaySystemSound(1054)
        }
    }
}

// MARK: - Timer View

struct TimerView: View {
    @StateObject private var engine = TimerEngine()
    @State private var showingPresets = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Mode picker
                Picker("Mode", selection: $engine.mode) {
                    ForEach(TimerMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: engine.mode) { _ in
                    engine.resetTimer()
                }
                
                Spacer()
                
                // Timer display
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 12)
                        .frame(width: 280, height: 280)
                    
                    // Progress circle
                    Circle()
                        .trim(from: 0, to: engine.progress)
                        .stroke(engine.progressColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 280, height: 280)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: engine.progress)
                    
                    // Time display
                    VStack(spacing: 8) {
                        Text(formatTime(engine.displayTime))
                            .font(.system(size: 56, weight: .light, design: .monospaced))
                            .foregroundColor(.white)
                        
                        if engine.mode == .countdown {
                            Text("of \(formatTime(engine.countdownTime))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Countdown presets (only when not running)
                if engine.mode == .countdown && !engine.isRunning && engine.elapsed == 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(engine.presets) { preset in
                                Button(action: {
                                    engine.setCountdownTime(preset.duration)
                                }) {
                                    Text(preset.name)
                                        .font(.subheadline)
                                        .foregroundColor(engine.countdownTime == preset.duration ? .black : .orange)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(engine.countdownTime == preset.duration ? Color.orange : Color.orange.opacity(0.2))
                                        .cornerRadius(20)
                                }
                            }
                            
                            Button(action: { showingPresets = true }) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.orange)
                                    .font(.title2)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // Controls
                HStack(spacing: 40) {
                    // Reset/Lap button
                    Button(action: engine.isRunning ? engine.addLap : engine.resetTimer) {
                        VStack(spacing: 4) {
                            Image(systemName: engine.isRunning ? "stopwatch" : "arrow.counterclockwise")
                                .font(.title2)
                            Text(engine.isRunning ? "Lap" : "Reset")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Circle())
                    }
                    .disabled(engine.mode == .countdown && !engine.isRunning)
                    
                    // Start/Stop button
                    Button(action: engine.toggleTimer) {
                        VStack(spacing: 4) {
                            Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                                .font(.title)
                            Text(engine.isRunning ? "Pause" : "Start")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 90, height: 90)
                        .background(engine.isRunning ? Color.red : Color.green)
                        .clipShape(Circle())
                    }
                }
                
                // Laps (only in stopwatch mode)
                if engine.mode == .stopwatch && !engine.laps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Laps")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(Array(engine.laps.enumerated().reversed()), id: \.element.id) { index, lap in
                                    HStack {
                                        Text("Lap \(lap.lapNumber)")
                                            .foregroundColor(.gray)
                                        Spacer()
                                        Text(formatTime(lap.time))
                                            .foregroundColor(.white)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxHeight: 150)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showingPresets) {
            PresetEditorView(presets: $engine.presets)
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, milliseconds)
        }
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

struct PresetEditorView: View {
    @Binding var presets: [TimerPreset]
    @Environment(\.dismiss) var dismiss
    
    @State private var newPresetName = ""
    @State private var newPresetMinutes: Double = 5
    
    var body: some View {
        NavigationView {
            Form {
                Section("Existing Presets") {
                    ForEach(presets) { preset in
                        HStack {
                            Text(preset.name)
                            Spacer()
                            Text(formatTime(preset.duration))
                                .foregroundColor(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        presets.remove(atOffsets: indexSet)
                    }
                }
                
                Section("Add New Preset") {
                    TextField("Name", text: $newPresetName)
                    Stepper("Minutes: \(Int(newPresetMinutes))", value: $newPresetMinutes, in: 1...120)
                    
                    Button("Add Preset") {
                        if !newPresetName.isEmpty {
                            let duration = newPresetMinutes * 60
                            presets.append(TimerPreset(name: newPresetName, duration: duration))
                            newPresetName = ""
                            newPresetMinutes = 5
                        }
                    }
                    .disabled(newPresetName.isEmpty)
                }
            }
            .navigationTitle("Timer Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

import AudioToolbox
