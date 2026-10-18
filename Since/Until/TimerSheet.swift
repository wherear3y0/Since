import SwiftUI
import SwiftData

/// A quick timer: pick how long, and it counts down at the top of the Until tab and on the Lock Screen,
/// then goes away.
struct TimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Countdown.sortOrder) private var countdowns: [Countdown]

    @State private var name = ""
    @State private var hours = 0
    @State private var minutes = 10

    private let presets: [(title: String, minutes: Int)] = [
        ("15 min", 15), ("30 min", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Timer", text: $name)
                        .submitLabel(.done)
                }

                Section("Start") {
                    // Tapping one starts it right away.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(presets, id: \.minutes) { preset in
                            Button(preset.title) {
                                start(minutes: preset.minutes)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Or Choose") {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: $hours) {
                            ForEach(0..<24) { Text("\($0) h").tag($0) }
                        }
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0..<60) { Text("\($0) min").tag($0) }
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)
                    Button("Start Timer", systemImage: "timer") {
                        start(minutes: hours * 60 + minutes)
                    }
                    .disabled(hours == 0 && minutes == 0)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: hours * 60 + minutes)
        }
    }

    private func start(minutes: Int) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date.now
        let timer = Countdown(title: title.isEmpty ? "Timer" : title, symbol: "timer", color: .orange,
                              date: now.addingTimeInterval(Double(minutes) * 60),
                              sortOrder: Countdown.topOrders(1, above: countdowns)[0])
        timer.isTimer = true
        timer.createdAt = now
        timer.showsLiveActivity = true
        context.insert(timer)
        saveChanges(context)
        // It says when it's up, so it needs notifications.
        Task {
            _ = await Milestones.requestPermission()
            refreshMirrors(context)
        }
        dismiss()
    }
}
