import SwiftUI

/// Sheet for adding a reset or a slip on a chosen (past) date, or changing an existing one.
struct ResetEditor: View {
    @Environment(\.dismiss) private var dismiss

    /// What the sheet saves.
    struct Entry {
        var date: Date
        var note: String?
        var isSlip: Bool
        /// For a slip: how many were had.
        var amount: Int
    }

    let counter: Counter
    let reset: Reset?
    /// Called on Save. For a new entry the caller inserts it; an existing one is already updated.
    let onSave: (Entry) -> Void
    /// For an existing entry: deletes it. Without it there's no Delete button.
    let onDelete: (() -> Void)?

    @State private var date: Date
    @State private var note: String
    @State private var isSlip: Bool
    @State private var amount: Int
    @State private var isConfirmingDelete = false

    init(counter: Counter, reset: Reset?, onSave: @escaping (Entry) -> Void, onDelete: (() -> Void)? = nil) {
        self.counter = counter
        self.reset = reset
        self.onSave = onSave
        self.onDelete = onDelete
        _date = State(initialValue: reset?.date ?? .now)
        _note = State(initialValue: reset?.note ?? "")
        // A new entry on a "quit" counter is a slip unless a full reset is picked.
        _isSlip = State(initialValue: reset?.isSlip ?? (counter.kind == .quit))
        _amount = State(initialValue: max(1, reset?.amount ?? 1))
    }

    /// "3 cigarettes", or just "3".
    private var amountText: String {
        counter.amountText(amount)
    }

    private var deleteTitle: String {
        guard counter.kind == .quit else { return "Delete Entry" }
        return isSlip ? "Delete Slip" : "Delete Reset"
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

    /// The chosen day already has another entry (or, on a "last time" counter, is its first day,
    /// which counts as a time it was done), so saving would change nothing.
    private var isDayTaken: Bool {
        let calendar = Calendar.app
        if counter.kind == .lastTime && calendar.isDate(date, inSameDayAs: counter.startDate) {
            return true
        }
        return counter.resets.contains { $0 !== reset && calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Why the day can't be saved.
    private var dayTakenText: String {
        guard counter.kind == .quit else { return "This day is already logged." }
        let calendar = Calendar.app
        let other = counter.resets.first { $0 !== reset && calendar.isDate($0.date, inSameDayAs: date) }
        return other?.isSlip == true && isSlip
            ? "This day already has a slip. Edit that one to change how many."
            : "This day already has a slip or a reset."
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
                    if isSlip {
                        Section {
                            Stepper(value: $amount, in: 1...99) {
                                LabeledContent("How Many", value: amountText)
                            }
                            .tint(counter.color.color)
                        } footer: {
                            if counter.tracksSavings {
                                Text("Taken off what’s been saved.")
                            }
                        }
                        .transition(.blurReplace)
                    }
                }
                Section {
                    DatePicker("Date", selection: $date, in: counter.startDate...Date.now, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(counter.color.color)
                } footer: {
                    if isDayTaken {
                        Text(dayTakenText)
                    }
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                if reset != nil, let onDelete {
                    Section {
                        Button(deleteTitle, role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                        .confirmationDialog("\(deleteTitle)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                            Button(deleteTitle, role: .destructive) {
                                dismiss()
                                onDelete()
                            }
                        }
                    }
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
                    .disabled(isDayTaken)
                }
            }
        }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = trimmed.isEmpty ? nil : trimmed
        let slip = counter.kind == .quit && isSlip
        let finalAmount = slip ? max(1, amount) : 1
        if let reset {
            reset.date = date
            reset.note = finalNote
            reset.isSlip = slip
            reset.amount = finalAmount
        }
        onSave(Entry(date: date, note: finalNote, isSlip: slip, amount: finalAmount))
        dismiss()
    }
}
