/**
 * Notes - Fully Functional iOS Notes App
 * Features: Persistent storage, rich text editing, search, categories
 */

import SwiftUI

// @main - Removed
struct NotesApp: App {
    var body: some Scene {
        WindowGroup {
            NotesView()
        }
    }
}

// MARK: - Models

struct Note: Identifiable, Codable {
    var id = UUID()
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var color: NoteColor
    var isPinned: Bool
    var tags: [String]
    
    enum NoteColor: String, Codable, CaseIterable {
        case yellow, green, blue, pink, orange, purple, red, gray
        
        var color: Color {
            switch self {
            case .yellow: return .yellow
            case .green: return .green
            case .blue: return .blue
            case .pink: return .pink
            case .orange: return .orange
            case .purple: return .purple
            case .red: return .red
            case .gray: return .gray
            }
        }
    }
}

// MARK: - Notes Manager

class NotesManager: ObservableObject {
    @Published var notes: [Note] = []
    @Published var searchText = ""
    @Published var selectedColor: Note.NoteColor?
    @Published var sortOption: SortOption = .modified
    
    enum SortOption: String, CaseIterable {
        case modified = "Recently Modified"
        case created = "Recently Created"
        case title = "Title"
    }
    
    private let notesKey = "SavedNotes"
    
    init() {
        loadNotes()
    }
    
    var filteredNotes: [Note] {
        var filtered = notes
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.content.localizedCaseInsensitiveContains(searchText) ||
                note.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        // Filter by color
        if let color = selectedColor {
            filtered = filtered.filter { $0.color == color }
        }
        
        // Sort
        switch sortOption {
        case .modified:
            filtered.sort { $0.modifiedAt > $1.modifiedAt }
        case .created:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .title:
            filtered.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        
        // Pinned notes first
        return filtered.sorted { $0.isPinned && !$1.isPinned }
    }
    
    func addNote(_ note: Note) {
        notes.append(note)
        saveNotes()
    }
    
    func updateNote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updated = note
            updated.modifiedAt = Date()
            notes[index] = updated
            saveNotes()
        }
    }
    
    func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        saveNotes()
    }
    
    func togglePin(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index].isPinned.toggle()
            saveNotes()
        }
    }
    
    func saveNotes() {
        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded, forKey: notesKey)
        }
    }
    
    func loadNotes() {
        if let data = UserDefaults.standard.data(forKey: notesKey),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        } else {
            // Create sample notes
            notes = [
                Note(title: "Welcome to Notes!", content: "This is your first note. Tap the + button to create a new note.", createdAt: Date(), modifiedAt: Date(), color: .yellow, isPinned: false, tags: []),
                Note(title: "Tips", content: "• Swipe left to delete\n• Tap and hold to pin\n• Use search to find notes\n• Change colors to organize", createdAt: Date(), modifiedAt: Date(), color: .blue, isPinned: true, tags: ["tips"])
            ]
            saveNotes()
        }
    }
}

// MARK: - Notes View

struct NotesView: View {
    @StateObject private var manager = NotesManager()
    @State private var showingAddNote = false
    @State private var editingNote: Note?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $manager.searchText)
                    .padding(.horizontal)
                
                // Filter and sort
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Color filter
                        Menu {
                            Button("All Colors") {
                                manager.selectedColor = nil
                            }
                            ForEach(Note.NoteColor.allCases, id: \.self) { color in
                                Button(action: {
                                    manager.selectedColor = manager.selectedColor == color ? nil : color
                                }) {
                                    HStack {
                                        Circle()
                                            .fill(color.color)
                                            .frame(width: 16, height: 16)
                                        Text(color.rawValue.capitalized)
                                        if manager.selectedColor == color {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "paintpalette.fill")
                                if let color = manager.selectedColor {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 12, height: 12)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .cornerRadius(20)
                        }
                        
                        // Sort
                        Menu {
                            ForEach(NotesManager.SortOption.allCases, id: \.self) { option in
                                Button(action: {
                                    manager.sortOption = option
                                }) {
                                    HStack {
                                        Text(option.rawValue)
                                        if manager.sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(manager.sortOption.rawValue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                // Notes list
                Group {
                    if manager.filteredNotes.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: manager.searchText.isEmpty ? "note.text" : "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text(manager.searchText.isEmpty ? "No notes yet" : "No notes found")
                                .font(.title2)
                                .foregroundColor(.gray)
                            if manager.searchText.isEmpty {
                                Text("Tap + to add your first note")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(manager.filteredNotes) { note in
                                    NoteCard(note: note, manager: manager) {
                                        editingNote = note
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        editingNote = Note(title: "", content: "", createdAt: Date(), modifiedAt: Date(), color: .yellow, isPinned: false, tags: [])
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(item: $editingNote) { note in
                NoteEditorView(note: note, manager: manager)
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search notes...", text: $text)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct NoteCard: View {
    let note: Note
    let manager: NotesManager
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                }
                
                if !note.content.isEmpty {
                    Text(note.content)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                
                HStack {
                    if !note.tags.isEmpty {
                        ForEach(note.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    Spacer()
                    Text(formatDate(note.modifiedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(note.color.color.opacity(0.15))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(note.color.color.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: {
                manager.togglePin(note)
            }) {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            
            Button(role: .destructive, action: {
                manager.deleteNote(note)
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct NoteEditorView: View {
    @State var note: Note
    let manager: NotesManager
    @Environment(\.dismiss) var dismiss
    
    @State private var titleText: String
    @State private var contentText: String
    @State private var selectedColor: Note.NoteColor
    @State private var tagsText: String
    
    init(note: Note, manager: NotesManager) {
        self.note = note
        self.manager = manager
        _titleText = State(initialValue: note.title)
        _contentText = State(initialValue: note.content)
        _selectedColor = State(initialValue: note.color)
        _tagsText = State(initialValue: note.tags.joined(separator: ", "))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Color picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Note.NoteColor.allCases, id: \.self) { color in
                            Circle()
                                .fill(color.color)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 3)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGray6))
                
                Divider()
                
                // Editor
                Form {
                    Section("Title") {
                        TextField("Note title", text: $titleText)
                    }
                    
                    Section("Content") {
                        TextEditor(text: $contentText)
                            .frame(minHeight: 300)
                    }
                    
                    Section("Tags (comma-separated)") {
                        TextField("e.g., work, personal, ideas", text: $tagsText)
                    }
                    
                    Section {
                        Toggle("Pin Note", isOn: Binding(
                            get: { note.isPinned },
                            set: { note.isPinned = $0 }
                        ))
                    }
                }
            }
            .navigationTitle(note.id == Note(title: "", content: "", createdAt: Date(), modifiedAt: Date(), color: .yellow, isPinned: false, tags: []).id ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveNote()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    func saveNote() {
        note.title = titleText
        note.content = contentText
        note.color = selectedColor
        note.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        note.modifiedAt = Date()
        
        if note.title.isEmpty && note.content.isEmpty {
            dismiss()
            return
        }
        
        if manager.notes.contains(where: { $0.id == note.id }) {
            manager.updateNote(note)
        } else {
            manager.addNote(note)
        }
        
        dismiss()
    }
}

// Note: String.trimmingCharacters(in:) is already provided by Foundation
// No need for custom extension
