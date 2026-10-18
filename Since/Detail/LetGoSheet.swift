import SwiftUI
import SwiftData

/// When and why an owned thing left. It then goes to Past, with how long it was had.
struct LetGoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let counter: Counter

    @State private var date = Date.now
    @State private var reason: GoneReason?

    var body: some View {
        let tint = counter.color.color
        NavigationStack {
            Form {
                Section {
                    DatePicker("Gone Since", selection: $date, in: counter.startDate...Date.now,
                               displayedComponents: .date)
                } footer: {
                    Text("It was with you for \(counter.hadFor(until: date)).")
                        .contentTransition(.numericText())
                }

                Section("Why") {
                    Picker("Why", selection: $reason) {
                        Text("Not Saying").tag(GoneReason?.none)
                        ForEach(GoneReason.allCases) { reason in
                            Label(reason.title, systemImage: reason.symbol).tag(Optional(reason))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .tint(tint)
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .navigationTitle("Let Go")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Let Go", systemImage: "checkmark", role: .confirm) {
                        withAnimation(.smooth) { counter.letGo(on: date, reason: reason) }
                        saveChanges(context)
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: reason)
        }
        .presentationDetents([.large])
    }
}
