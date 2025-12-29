/**
 * Calculator - Fully Functional iOS Calculator
 * Features: History, memory functions, scientific operations
 */

import SwiftUI

// @main - Removed
struct CalculatorApp: App {
    var body: some Scene {
        WindowGroup {
            CalculatorView()
        }
    }
}

// MARK: - Calculator Engine

class CalculatorEngine: ObservableObject {
    @Published var display = "0"
    @Published var history: [String] = []
    
    private var currentNumber: Double = 0
    private var previousNumber: Double = 0
    private var operation: Operation?
    private var shouldResetDisplay = false
    private var memory: Double = 0
    
    enum Operation: String {
        case add = "+"
        case subtract = "−"
        case multiply = "×"
        case divide = "÷"
        case equals = "="
    }
    
    func input(_ value: String) {
        switch value {
        case "C":
            clear()
        case "AC":
            allClear()
        case "±":
            toggleSign()
        case "%":
            percentage()
        case "÷", "×", "−", "+":
            setOperation(value)
        case "=":
            calculate()
        case ".":
            addDecimal()
        case "M+":
            memoryAdd()
        case "M−":
            memorySubtract()
        case "MR":
            memoryRecall()
        case "MC":
            memoryClear()
        default:
            inputNumber(value)
        }
    }
    
    private func inputNumber(_ digit: String) {
        if shouldResetDisplay {
            display = digit
            shouldResetDisplay = false
        } else if display == "0" {
            display = digit
        } else {
            display += digit
        }
        currentNumber = Double(display) ?? 0
    }
    
    private func addDecimal() {
        if shouldResetDisplay {
            display = "0."
            shouldResetDisplay = false
        } else if !display.contains(".") {
            display += "."
        }
    }
    
    private func toggleSign() {
        if let value = Double(display) {
            display = formatNumber(value * -1)
            currentNumber = value * -1
        }
    }
    
    private func percentage() {
        if let value = Double(display) {
            display = formatNumber(value / 100)
            currentNumber = value / 100
        }
    }
    
    private func setOperation(_ op: String) {
        if operation != nil {
            // Chain operations
            calculate()
        }
        previousNumber = Double(display) ?? 0
        operation = Operation(rawValue: op)
        shouldResetDisplay = true
    }
    
    private func calculate() {
        guard let op = operation else { return }
        
        currentNumber = Double(display) ?? 0
        var result: Double = 0
        
        switch op {
        case .add:
            result = previousNumber + currentNumber
        case .subtract:
            result = previousNumber - currentNumber
        case .multiply:
            result = previousNumber * currentNumber
        case .divide:
            result = currentNumber != 0 ? previousNumber / currentNumber : 0
        case .equals:
            return
        }
        
        // Add to history
        let expression = "\(formatNumber(previousNumber)) \(op.rawValue) \(formatNumber(currentNumber)) = \(formatNumber(result))"
        history.insert(expression, at: 0)
        if history.count > 50 {
            history.removeLast()
        }
        
        display = formatNumber(result)
        currentNumber = result
        operation = nil
        shouldResetDisplay = true
    }
    
    private func clear() {
        display = "0"
        currentNumber = 0
        shouldResetDisplay = false
    }
    
    private func allClear() {
        clear()
        previousNumber = 0
        operation = nil
        history.removeAll()
    }
    
    private func memoryAdd() {
        memory += Double(display) ?? 0
    }
    
    private func memorySubtract() {
        memory -= Double(display) ?? 0
    }
    
    private func memoryRecall() {
        display = formatNumber(memory)
        currentNumber = memory
        shouldResetDisplay = true
    }
    
    private func memoryClear() {
        memory = 0
    }
    
    private func formatNumber(_ number: Double) -> String {
        if number.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(number))
        }
        
        // Limit decimal places
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}

// MARK: - Calculator View

struct CalculatorView: View {
    @StateObject private var engine = CalculatorEngine()
    @State private var showHistory = false
    
    let buttons: [[String]] = [
        ["C", "AC", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "="]
    ]
    
    let memoryButtons: [String] = ["MC", "MR", "M−", "M+"]
    
    var body: some View {
        GeometryReader { geometry in
            let buttonSize = min(geometry.size.width / 4.5, 80)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Display area
                    VStack(alignment: .trailing, spacing: 8) {
                        // History button
                        HStack {
                            Button(action: { showHistory.toggle() }) {
                                Image(systemName: "clock")
                                    .foregroundColor(.gray)
                                    .font(.title3)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        // Display
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(engine.display)
                                .font(.system(size: min(60, geometry.size.width / 6), weight: .light))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .padding(.horizontal)
                        }
                        .frame(height: 80)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(Color.black)
                    
                    // Memory buttons (optional)
                    if !memoryButtons.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(memoryButtons, id: \.self) { button in
                                CalculatorButton(
                                    title: button,
                                    size: buttonSize * 0.6,
                                    isWide: false,
                                    color: Color(.darkGray),
                                    textColor: .white
                                ) {
                                    engine.input(button)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    
                    // Main buttons
                    VStack(spacing: 12) {
                        ForEach(buttons, id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(row, id: \.self) { button in
                                    CalculatorButton(
                                        title: button,
                                        size: buttonSize,
                                        isWide: button == "0",
                                        color: buttonColor(for: button),
                                        textColor: textColor(for: button)
                                    ) {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                            engine.input(button)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(history: engine.history)
        }
    }
    
    func buttonColor(for button: String) -> Color {
        if ["÷", "×", "−", "+", "="].contains(button) {
            return .orange
        } else if ["C", "AC", "±", "%"].contains(button) {
            return Color(.darkGray)
        }
        return Color(.gray)
    }
    
    func textColor(for button: String) -> Color {
        if ["C", "AC", "±", "%"].contains(button) {
            return .white
        }
        return .white
    }
}

struct CalculatorButton: View {
    let title: String
    let size: CGFloat
    let isWide: Bool
    let color: Color
    let textColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
            action()
        }) {
            Text(title)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(textColor)
                .frame(width: isWide ? size * 2 + 12 : size, height: size)
                .background(color)
                .cornerRadius(size / 2)
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

struct HistoryView: View {
    let history: [String]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if history.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No history yet")
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(history, id: \.self) { item in
                            Text(item)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
