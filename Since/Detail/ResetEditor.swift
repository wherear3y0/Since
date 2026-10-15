import SwiftUI

/// Sheet for adding a reset on a chosen (past) date, or changing an existing reset.
struct ResetEditor: View {
    @Environment(\.dismiss) private var dismiss

    let counter: Counter
    let reset: Reset?
    /// Called on Save. For a new reset the caller inserts it; for an existing one it's already updated.
    let onSave: (Date, String?) -> Void

    @State private var date: Date
    @State private var note: String

    init(counter: Counter, reset: Reset?, onSave: @escaping (Date, String?) -> Void) {
        self.counter = counter
        self.reset = reset
        self.onSave = onSave
        _date = State(initialValue: reset?.date ?? .now)
        _note = State(initialValue: reset?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: counter.startDate...Date.now, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(counter.color.color)
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(reset == nil ? counter.kind.addTitle : counter.kind.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = trimmed.isEmpty ? nil : trimmed
        if let reset {
            reset.date = date
            reset.note = finalNote
        }
        onSave(date, finalNote)
        dismiss()
    }
}
