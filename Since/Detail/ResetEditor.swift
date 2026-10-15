import SwiftUI

/// Sheet for adding a reset or a slip on a chosen (past) date, or changing an existing one.
struct ResetEditor: View {
    @Environment(\.dismiss) private var dismiss

    let counter: Counter
    let reset: Reset?
    /// Called on Save with the date, the note and whether it's a slip. For a new entry the caller inserts it;
    /// an existing one is already updated.
    let onSave: (Date, String?, Bool) -> Void

    @State private var date: Date
    @State private var note: String
    @State private var isSlip: Bool

    init(counter: Counter, reset: Reset?, onSave: @escaping (Date, String?, Bool) -> Void) {
        self.counter = counter
        self.reset = reset
        self.onSave = onSave
        _date = State(initialValue: reset?.date ?? .now)
        _note = State(initialValue: reset?.note ?? "")
        // A new entry on a "quit" counter is a slip unless a full reset is picked.
        _isSlip = State(initialValue: reset?.isSlip ?? (counter.kind == .quit))
    }

    private var title: String {
        guard counter.kind == .quit else {
            return reset == nil ? counter.kind.addTitle : counter.kind.editTitle
        }
        switch (reset == nil, isSlip) {
        case (true, true): return "Add Slip"
        case (true, false): return "Add Reset"
        case (false, true): return "Edit Slip"
        case (false, false): return "Edit Reset"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if counter.kind == .quit {
                    Section {
                        Picker("Kind", selection: $isSlip.animation()) {
                            Text("Slip").tag(true)
                            Text("Full Reset").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } footer: {
                        Text(isSlip
                             ? "The count starts again, but the days before stay on the heatmap, grayed out."
                             : "Starts over: the heatmap is cleared and the progress counts from this day.")
                            .contentTransition(.opacity)
                    }
                }
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
            .navigationTitle(title)
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
        let slip = counter.kind == .quit && isSlip
        if let reset {
            reset.date = date
            reset.note = finalNote
            reset.isSlip = slip
        }
        onSave(date, finalNote, slip)
        dismiss()
    }
}
