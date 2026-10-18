import SwiftUI
import SwiftData

/// Moves a one-off countdown to a later day (or window), keeping the day it was set for in its history.
struct PostponeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let countdown: Countdown

    @State private var date: Date
    @State private var hasWindow: Bool
    @State private var windowEnd: Date

    init(countdown: Countdown) {
        self.countdown = countdown
        let calendar = Calendar.app
        // A week after the day it was set for, or after today if that's already gone, at the same time.
        let base = max(calendar.startOfDay(for: countdown.date), calendar.startOfDay(for: .now))
        let time = calendar.dateComponents([.hour, .minute], from: countdown.date)
        let day = calendar.date(byAdding: .day, value: 7, to: base)!
        let start = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
        let length = countdown.window().map { DayMath.days(from: $0.lowerBound, to: $0.upperBound) } ?? 7
        _date = State(initialValue: start)
        _hasWindow = State(initialValue: countdown.windowEnd != nil)
        _windowEnd = State(initialValue: calendar.date(byAdding: .day, value: length, to: start)!)
    }

    var body: some View {
        let tint = countdown.color.color

        NavigationStack {
            Form {
                Section {
                    DatePicker(hasWindow ? "From" : "New Date", selection: $date.animation(.smooth),
                               in: Calendar.app.startOfDay(for: .now)...,
                               displayedComponents: countdown.hasTime && !hasWindow ? [.date, .hourAndMinute] : .date)
                    if hasWindow {
                        DatePicker("To", selection: $windowEnd, in: Calendar.app.startOfDay(for: date)...,
                                   displayedComponents: .date)
                            .transition(.blurReplace)
                    }
                    Toggle("Window", isOn: $hasWindow.animation(.smooth))
                        .tint(tint)
                } footer: {
                    Text(previous)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .navigationTitle("Postpone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Postpone", systemImage: "checkmark", role: .confirm) {
                        withAnimation(.smooth(duration: 0.45)) {
                            countdown.postpone(to: date, windowEnd: hasWindow ? max(windowEnd, date) : nil)
                        }
                        saveChanges(context)
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: date)
        }
        .presentationDetents([.medium])
    }

    /// The day (or window) it's moving from, which stays in its history.
    private var previous: String {
        let was = countdown.window()?.rangeFormat ?? countdown.date.formatted(date: .abbreviated, time: .omitted)
        return "Set for \(was) until now. It stays in the history on the countdown's page."
    }
}
