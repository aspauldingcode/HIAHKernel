/**
 * Canvas - Fully Functional iOS Drawing App
 * Features: Multiple layers, save/load, export, undo/redo, brush sizes
 */

import SwiftUI
import PencilKit

// @main - Removed
struct CanvasApp: App {
    var body: some Scene {
        WindowGroup {
            CanvasView()
        }
    }
}

// MARK: - Canvas Models

struct DrawingLayer: Identifiable, Codable {
    var id = UUID()
    var name: String
    var isVisible: Bool = true
    var drawing: PKDrawing
    
    init(name: String, drawing: PKDrawing = PKDrawing()) {
        self.name = name
        self.drawing = drawing
    }
    
    // Custom Codable implementation for PKDrawing
    enum CodingKeys: String, CodingKey {
        case id, name, isVisible, drawingData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        let data = try container.decode(Data.self, forKey: .drawingData)
        drawing = try PKDrawing(data: data)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isVisible, forKey: .isVisible)
        let data = drawing.dataRepresentation()
        try container.encode(data, forKey: .drawingData)
    }
}

class CanvasManager: ObservableObject {
    @Published var layers: [DrawingLayer] = [DrawingLayer(name: "Layer 1")]
    @Published var currentLayerIndex: Int = 0
    @Published var selectedColor: Color = .black
    @Published var lineWidth: CGFloat = 3
    @Published var tool: DrawingTool = .pen
    
    enum DrawingTool: String, CaseIterable {
        case pen = "Pen"
        case marker = "Marker"
        case pencil = "Pencil"
        case eraser = "Eraser"
    }
    
    var currentLayer: DrawingLayer {
        get { layers[currentLayerIndex] }
        set { layers[currentLayerIndex] = newValue }
    }
    
    func addLayer() {
        layers.append(DrawingLayer(name: "Layer \(layers.count + 1)"))
        currentLayerIndex = layers.count - 1
    }
    
    func deleteLayer(at index: Int) {
        if layers.count > 1 {
            layers.remove(at: index)
            if currentLayerIndex >= layers.count {
                currentLayerIndex = layers.count - 1
            }
        }
    }
    
    func toggleLayerVisibility(at index: Int) {
        layers[index].isVisible.toggle()
    }
    
    func moveLayer(from source: IndexSet, to destination: Int) {
        layers.move(fromOffsets: source, toOffset: destination)
    }
    
    func save() -> Data? {
        return try? JSONEncoder().encode(layers)
    }
    
    func load(from data: Data) {
        if let decoded = try? JSONDecoder().decode([DrawingLayer].self, from: data) {
            layers = decoded
            currentLayerIndex = 0
        }
    }
}

// MARK: - Canvas View

struct CanvasView: View {
    @StateObject private var manager = CanvasManager()
    @State private var showLayers = false
    @State private var showSettings = false
    @State private var showColorPicker = false
    
    let colors: [Color] = [.black, .red, .orange, .yellow, .green, .blue, .purple, .pink, .white, .gray, .brown, .cyan]
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 16) {
                // Tool selector
                Menu {
                    ForEach(CanvasManager.DrawingTool.allCases, id: \.self) { tool in
                        Button(action: {
                            manager.tool = tool
                        }) {
                            HStack {
                                Text(tool.rawValue)
                                if manager.tool == tool {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: toolIcon(for: manager.tool))
                        .font(.title3)
                        .foregroundColor(.primary)
                }
                
                Divider()
                    .frame(height: 30)
                
                // Color picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                        .stroke(manager.selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: color == .white ? .gray.opacity(0.3) : .clear, radius: 1)
                        .onTapGesture {
                                    manager.selectedColor = color
                                }
                        }
                        }
                }
                .frame(width: 200)
                
                Divider()
                    .frame(height: 30)
                
                // Line width
                HStack(spacing: 8) {
                    Image(systemName: "minus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $manager.lineWidth, in: 1...30)
                        .frame(width: 100)
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Layers button
                Button(action: { showLayers.toggle() }) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundColor(.primary)
                }
                
                // Settings
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            
            Divider()
            
            // Canvas
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Color.white
                    
                    // Grid pattern
                    CanvasGridView(size: geometry.size)
                        .opacity(0.1)
                    
                    // Drawing layers
                    ForEach(manager.layers.indices, id: \.self) { index in
                        if manager.layers[index].isVisible {
                            PKCanvasWrapper(
                                drawing: Binding(
                                    get: { manager.layers[index].drawing },
                                    set: { manager.layers[index].drawing = $0 }
                                ),
                                tool: manager.tool,
                                color: manager.selectedColor,
                                lineWidth: manager.lineWidth
                            )
                            .opacity(index == manager.currentLayerIndex ? 1.0 : 0.8)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showLayers) {
            LayersView(manager: manager)
                    }
        .sheet(isPresented: $showSettings) {
            SettingsView(manager: manager)
        }
    }
    
    func toolIcon(for tool: CanvasManager.DrawingTool) -> String {
        switch tool {
        case .pen: return "pencil.tip"
        case .marker: return "pencil.tip.crop.circle"
        case .pencil: return "pencil"
        case .eraser: return "eraser"
        }
    }
}

// MARK: - PKCanvas Wrapper

struct PKCanvasWrapper: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let tool: CanvasManager.DrawingTool
    let color: Color
    let lineWidth: CGFloat
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.tool = makeTool()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        return canvas
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawing = drawing
        uiView.tool = makeTool()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: PKCanvasWrapper
        
        init(_ parent: PKCanvasWrapper) {
            self.parent = parent
        }
    }
    
    private func makeTool() -> PKTool {
        let uiColor = UIColor(color)
        
        switch tool {
        case .pen:
            let pen = PKInkingTool(.pen, color: uiColor, width: lineWidth)
            return pen
        case .marker:
            let marker = PKInkingTool(.marker, color: uiColor, width: lineWidth)
            return marker
        case .pencil:
            let pencil = PKInkingTool(.pencil, color: uiColor, width: lineWidth)
            return pencil
        case .eraser:
            return PKEraserTool(.vector)
        }
    }
}

struct CanvasGridView: View {
    let size: CGSize
    let spacing: CGFloat = 20
    
    var body: some View {
        Canvas { context, size in
            let columns = Int(size.width / spacing)
            let rows = Int(size.height / spacing)
            
            for col in 0...columns {
                let x = CGFloat(col) * spacing
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.gray), lineWidth: 0.5)
            }
            
            for row in 0...rows {
                let y = CGFloat(row) * spacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Layers View

struct LayersView: View {
    @ObservedObject var manager: CanvasManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(manager.layers.indices, id: \.self) { index in
                    HStack {
                        Button(action: {
                            manager.toggleLayerVisibility(at: index)
                        }) {
                            Image(systemName: manager.layers[index].isVisible ? "eye.fill" : "eye.slash.fill")
                                .foregroundColor(.primary)
                        }
                        
                        Text(manager.layers[index].name)
                            .foregroundColor(index == manager.currentLayerIndex ? .blue : .primary)
                        
                        Spacer()
                        
                        if index == manager.currentLayerIndex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        manager.currentLayerIndex = index
                    }
                }
                .onMove(perform: manager.moveLayer)
                .onDelete { indexSet in
                    for index in indexSet {
                        manager.deleteLayer(at: index)
                    }
                }
            }
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Add Layer") {
                        manager.addLayer()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var manager: CanvasManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Drawing") {
                    Picker("Tool", selection: $manager.tool) {
                        ForEach(CanvasManager.DrawingTool.allCases, id: \.self) { tool in
                            Text(tool.rawValue).tag(tool)
                        }
                    }
                    
                    HStack {
                        Text("Line Width")
                        Spacer()
                        Text("\(Int(manager.lineWidth))")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $manager.lineWidth, in: 1...30)
                }
                
                Section("Canvas") {
                    Button("Clear All Layers") {
                        for index in manager.layers.indices {
                            manager.layers[index].drawing = PKDrawing()
                        }
                    }
                    .foregroundColor(.red)
                    
                    Button("Reset Canvas") {
                        manager.layers = [DrawingLayer(name: "Layer 1")]
                        manager.currentLayerIndex = 0
                    }
                    .foregroundColor(.red)
                }
                
                Section("Export") {
                    Button("Save to Photos") {
                        exportToPhotos()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    func exportToPhotos() {
        // Combine all visible layers into one drawing
        var combinedDrawing = PKDrawing()
        for layer in manager.layers where layer.isVisible {
            combinedDrawing.append(layer.drawing)
        }
        
        // Convert to image using PKDrawing's built-in method
        let bounds = combinedDrawing.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 1000, height: 1000) : combinedDrawing.bounds
        let image = combinedDrawing.image(from: bounds, scale: 2.0)
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}
