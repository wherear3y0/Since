import SwiftUI

/// Repeat choices, like an event's in Calendar: the common ones, then Custom. Picking one goes back.
struct RepeatPicker: View {
    @Binding var rule: RepeatRule
    let start: Date
    let tint: Color

    @Environment(\.dismiss) private var dismiss
    @State private var isShown = false

    var body: some View {
        Form {
            Section {
                ForEach(RepeatRule.presets, id: \.title) { preset in
                    CheckButton(title: preset.title, isChecked: rule.withoutEnd == preset.rule, tint: tint) {
                        var chosen = preset.rule
                        // The end date stays when switching between repeats.
                        chosen.end = chosen.repeats ? rule.end : nil
                        rule = chosen
                        dismiss()
                    }
                }
            }
            .sectionReveal(isShown, delay: 0.04)

            Section {
                NavigationLink {
                    CustomRepeatView(rule: $rule, start: start, tint: tint)
                } label: {
                    HStack {
                        Text("Custom")
                        Spacer()
                        if !rule.isPreset {
                            Text(rule.summary())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(tint)
                        }
                    }
                }
            }
            .sectionReveal(isShown, delay: 0.1)
        }
        .scrollContentBackground(.hidden)
        .background(Color.pageBackground)
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            isShown = true
        }
    }
}

/// Every N days, weeks (on chosen weekdays), months or years.
struct CustomRepeatView: View {
    @Binding var rule: RepeatRule
    let start: Date
    let tint: Color

    @State private var isShown = false

    private var calendar: Calendar { .app }

    /// The first day's weekday, which a weekly rule falls on when no weekdays are chosen.
    private var startWeekday: Int {
        calendar.component(.weekday, from: start)
    }

    private var chosenWeekdays: Set<Int> {
        rule.weekdays.isEmpty ? [startWeekday] : rule.weekdays
    }

    var body: some View {
        Form {
            Section {
                Picker("Frequency", selection: frequency) {
                    ForEach(RepeatFrequency.allCases.filter { $0 != .never }) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                Stepper(value: $rule.interval.animation(.snappy), in: 1...99) {
                    LabeledContent("Every") {
                        Text("\(rule.interval) \(rule.frequency.unit(rule.interval))")
                            .contentTransition(.numericText(value: Double(rule.interval)))
                    }
                }
            } footer: {
                Text(description)
                    .contentTransition(.opacity)
            }
            .sectionReveal(isShown, delay: 0.04)

            if rule.frequency == .weekly {
                Section("On") {
                    ForEach(weekdaysInOrder, id: \.self) { weekday in
                        CheckButton(title: calendar.weekdaySymbols[weekday - 1],
                                    isChecked: chosenWeekdays.contains(weekday), tint: tint) {
                            toggle(weekday)
                        }
                    }
                }
                .sectionReveal(isShown, delay: 0.1)
                .transition(.blurReplace)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.pageBackground)
        .navigationTitle("Custom")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: rule)
        .onAppear {
            // Custom starts from every day, like in Calendar.
            if !rule.repeats {
                rule = RepeatRule(frequency: .daily)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            isShown = true
        }
    }

    /// Weekdays only apply to weekly rules; switching away drops them.
    private var frequency: Binding<RepeatFrequency> {
        Binding {
            rule.frequency
        } set: { frequency in
            withAnimation(.smooth) {
                rule.frequency = frequency
                if frequency != .weekly {
                    rule.weekdays = []
                }
            }
        }
    }

    private var weekdaysInOrder: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// The last chosen weekday can't be turned off. Just the first day's weekday is stored as none,
    /// so the rule still reads as "Every Week".
    private func toggle(_ weekday: Int) {
        var chosen = chosenWeekdays
        if chosen.contains(weekday) {
            guard chosen.count > 1 else { return }
            chosen.remove(weekday)
        } else {
            chosen.insert(weekday)
        }
        rule.weekdays = chosen == [startWeekday] ? [] : chosen
    }

    /// "Counts down to a day every 2 weeks on Monday and Wednesday."
    private var description: String {
        let interval = rule.interval
        let every = interval == 1 ? "every \(rule.frequency.unit(1))" : "every \(interval) \(rule.frequency.unit(interval))"
        let day = calendar.component(.day, from: start)
        switch rule.frequency {
        case .never, .daily:
            return "Counts down to a day \(every)."
        case .weekly:
            let names = chosenWeekdays
                .sorted { weekdaysInOrder.firstIndex(of: $0)! < weekdaysInOrder.firstIndex(of: $1)! }
                .map { calendar.weekdaySymbols[$0 - 1] }
            return "Counts down to a day \(every) on \(names.formatted(.list(type: .and)))."
        case .monthly:
            let shorter = day > 28 ? ", or the last day of shorter months" : ""
            return "Counts down to a day \(every) on the \(day.ordinal)\(shorter)."
        case .yearly:
            return "Counts down to a day \(every) on \(start.formatted(.dateTime.month(.wide).day()))."
        }
    }
}

/// When a repeat stops: never, or on a chosen day.
struct EndRepeatPicker: View {
    @Binding var end: Date?
    let start: Date
    let tint: Color

    @State private var isShown = false

    var body: some View {
        Form {
            Section {
                CheckButton(title: "Never", isChecked: end == nil, tint: tint) {
                    withAnimation(.smooth) { end = nil }
                }
                CheckButton(title: "On Date", isChecked: end != nil, tint: tint) {
                    withAnimation(.smooth) {
                        end = end ?? Calendar.app.date(byAdding: .year, value: 1, to: max(start, .now))
                    }
                }
                if end != nil {
                    DatePicker("End Date", selection: Binding { end ?? start } set: { end = $0 },
                               in: start..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(tint)
                        .transition(.blurReplace)
                }
            } footer: {
                Text(end == nil
                     ? "It keeps repeating."
                     : "After the last time on or before this day, you can count the days since it.")
                    .contentTransition(.opacity)
            }
            .sectionReveal(isShown, delay: 0.04)
        }
        .scrollContentBackground(.hidden)
        .background(Color.pageBackground)
        .navigationTitle("End Repeat")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: end)
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            isShown = true
        }
    }
}

/// A row in plain text with a checkmark in the tint color when chosen, like Calendar's choices.
private struct CheckButton: View {
    let title: String
    let isChecked: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
                    .opacity(isChecked ? 1 : 0)
                    .scaleEffect(isChecked ? 1 : 0.5)
                    .animation(.snappy, value: isChecked)
            }
            .contentShape(Rectangle())
        }
        .tint(.primary)
    }
}

extension Int {
    /// "1st", "22nd", "31st", in English like the rest of the app.
    var ordinal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale(identifier: "en")
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

#Preview {
    @Previewable @State var rule = RepeatRule(frequency: .weekly, interval: 2, weekdays: [2, 4])
    NavigationStack {
        RepeatPicker(rule: $rule, start: .now, tint: .cyan)
    }
}
