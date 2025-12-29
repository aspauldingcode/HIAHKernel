/**
 * HIAH Terminal - Minimal SwiftUI Terminal for HIAH Desktop
 * Uses HIAH Kernel to spawn processes and access virtual filesystem
 */

import SwiftUI

// @main - Removed because multiple @main types exist in the module
struct TerminalApp: App {
    var body: some Scene {
        WindowGroup {
            TerminalView()
        }
    }
}

struct TerminalView: View {
    @StateObject private var terminal = TerminalViewModel()
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(terminal.outputLines) { line in
                            Text(line.text)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(line.color)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                        
                        // Input prompt
                        HStack(alignment: .bottom, spacing: 4) {
                            Text(terminal.prompt)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                            
                            TextField("", text: $terminal.currentInput, axis: .vertical)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                                .focused($isInputFocused)
                                .lineLimit(nil)
                                .onSubmit {
                                    terminal.executeCommand()
                                }
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black)
                .onChange(of: terminal.outputLines.count) { _ in
                    if let lastLine = terminal.outputLines.last {
                        withAnimation {
                            proxy.scrollTo(lastLine.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.black)
        .onAppear {
            isInputFocused = true
            terminal.startup()
        }
    }
}

class TerminalViewModel: ObservableObject {
    @Published var outputLines: [TerminalLine] = []
    @Published var currentInput: String = ""
    @Published var prompt: String = "$ "
    
    private var currentDirectory: String = "~"
    private var environment: [String: String] = [:]
    
    init() {
        setupEnvironment()
    }
    
    private func setupEnvironment() {
        // Set up virtual filesystem paths
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        environment["HOME"] = "\(docsPath)/home"
        environment["PATH"] = "\(docsPath)/bin:\(docsPath)/usr/bin:\(docsPath)/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PWD"] = docsPath
        environment["SHELL"] = "\(docsPath)/bin/bash"
        currentDirectory = docsPath
        updatePrompt()
    }
    
    private func updatePrompt() {
        let dirName = (currentDirectory as NSString).lastPathComponent
        prompt = dirName == "Documents" ? "$ " : "\(dirName)$ "
    }
    
    func startup() {
        addOutput("HIAH Terminal v1.0", color: .cyan)
        addOutput("Accessing virtual filesystem via HIAH Kernel...", color: .gray)
        addOutput("", color: .white)
        
        // Try to run pfetch if available
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.executeCommand("pfetch", addToHistory: false)
        }
    }
    
    func executeCommand() {
        let command = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            addOutput("", color: .white)
            return
        }
        
        addOutput("\(prompt)\(command)", color: .white)
        currentInput = ""
        
        // Handle built-in commands
        if handleBuiltin(command) {
            return
        }
        
        // Execute via HIAH Kernel
        executeCommand(command, addToHistory: true)
    }
    
    func executeCommand(_ command: String, addToHistory: Bool = true) {
        let parts = command.components(separatedBy: .whitespaces)
        guard let executable = parts.first else { return }
        
        let args = Array(parts.dropFirst())
        
        // Use HIAH Kernel to spawn process
        HIAHKernelBridge.shared.spawnProcess(
            executable: executable,
            arguments: args,
            environment: environment,
            workingDirectory: currentDirectory
        ) { [weak self] output, error, exitCodeNumber in
            DispatchQueue.main.async {
                if let error = error {
                    self?.addOutput("Error: \(error)", color: .red)
                } else if let output = output, !output.isEmpty {
                    self?.addOutput(output, color: .white)
                }
                
                if let exitCode = exitCodeNumber?.intValue {
                    // Command completed
                    if exitCode != 0 {
                        self?.addOutput("Process exited with code \(exitCode)", color: .yellow)
                    }
                }
            }
        }
    }
    
    private func handleBuiltin(_ command: String) -> Bool {
        let parts = command.components(separatedBy: .whitespaces)
        let cmd = parts.first?.lowercased() ?? ""
        let args = Array(parts.dropFirst())
        
        switch cmd {
        case "cd":
            changeDirectory(args.first ?? "~")
            return true
        case "pwd":
            addOutput(currentDirectory, color: .white)
            return true
        case "clear", "cls":
            outputLines.removeAll()
            return true
        case "exit":
            // Could close terminal window here
            addOutput("Use window controls to close terminal", color: .yellow)
            return true
        case "help":
            addOutput("Built-in commands: cd, pwd, clear, exit, help", color: .cyan)
            addOutput("Use HIAH Kernel to run: bash, pfetch, neovim, and other binaries", color: .cyan)
            return true
        default:
            return false
        }
    }
    
    private func changeDirectory(_ path: String) {
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        var newPath: String
        
        if path == "~" || path.isEmpty {
            newPath = "\(docsPath)/home"
        } else if path.hasPrefix("/") {
            // Absolute path - resolve virtual filesystem
            newPath = resolveVirtualPath(path)
        } else {
            // Relative path
            newPath = (currentDirectory as NSString).appendingPathComponent(path)
        }
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: newPath, isDirectory: &isDir) && isDir.boolValue {
            currentDirectory = newPath
            environment["PWD"] = newPath
            updatePrompt()
        } else {
            addOutput("cd: no such file or directory: \(path)", color: .red)
        }
    }
    
    private func resolveVirtualPath(_ path: String) -> String {
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        
        // Remove leading slash and append to Documents
        if path == "/" {
            return docsPath
        }
        
        let relativePath = String(path.dropFirst())
        return (docsPath as NSString).appendingPathComponent(relativePath)
    }
    
    private func addOutput(_ text: String, color: Color = .white) {
        let line = TerminalLine(text: text, color: color)
        outputLines.append(line)
        
        // Limit output lines to prevent memory issues
        if outputLines.count > 1000 {
            outputLines.removeFirst(100)
        }
    }
}

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}

// Bridge to HIAH Kernel (Objective-C)
@objc class HIAHKernelBridge: NSObject {
    static let shared = HIAHKernelBridge()
    
    @objc func spawnProcess(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String,
        completion: @escaping (String?, String?, NSNumber?) -> Void
    ) {
        // Import HIAHKernel and spawn process
        // This will be implemented to call HIAHKernel's spawn method
        DispatchQueue.global(qos: .userInitiated).async {
            // For now, simulate process execution
            // TODO: Integrate with actual HIAHKernel
            
            // Try to find executable in virtual filesystem
            let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
            let possiblePaths = [
                "\(docsPath)/bin/\(executable)",
                "\(docsPath)/usr/bin/\(executable)",
                "\(docsPath)/usr/local/bin/\(executable)",
                executable  // Try direct path
            ]
            
            var foundPath: String?
            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    foundPath = path
                    break
                }
            }
            
            if foundPath != nil {
                // Execute via HIAHKernel
                // TODO: Call actual HIAHKernel spawn method
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    completion("Command executed: \(executable)", nil, 0)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil, "Command not found: \(executable)", nil)
                }
            }
        }
    }
}

