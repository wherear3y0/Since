import AppIntents
import SwiftUI
import SwiftData

struct CounterDetailView: View {
    @Environment(\.modelContext) private var context

    let counter: Counter
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var isAddingReset = false
    @State private var editingReset: Reset?
    @State private var undoableReset: Reset?
    /// The toast's Undo takes one off today's slip instead of removing the entry.
    @State private var undoTakesOne = false
    /// Today's slip's time before one was added, which Undo puts back.
    @State private var undoPreviousDate: Date?
    /// Restarts the toast's timer on every new action, even one on the same slip.
    @State private var toastTick = 0
    /// The heatmap wave plays once per opening, not again when the card scrolls back into view.
    @State private var heatmapRevealed = false
    /// The streak chart starts folded into its summary.
    @State private var isChartExpanded = false
    /// Turns true when the page opens; the blocks under the heatmap then blur in one after another.
    @State private var contentShown = false

    var body: some View {
        let tint = counter.color.color
        let kind = counter.kind
        let streaks = counter.streaks()

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeatmapCard(counter: counter, animated: !heatmapRevealed)
                    .onAppear { heatmapRevealed = true }
                    .detailCard {
                        if counter.tinted {
                            Color.cardBackground
                            tint.opacity(0.16)
                        } else {
                            SoftColorFill(tint: tint.onCard(tinted: false))
                        }
                    }

                if kind == .quit {
                    ProgressCard(counter: counter)
                        .detailCard()
                        .blurIn(contentShown, delay: 0.06)
                    if counter.tracksSavings {
                        SavingsCard(counter: counter)
                            .detailCard()
                            .blurIn(contentShown, delay: 0.08)
                    }
                    if counter.showsHealth {
                        HealthCard(counter: counter)
                            .detailCard()
                            .blurIn(contentShown, delay: 0.09)
                    }
                }

                StreakSummary(streaks: streaks, kind: kind, tint: tint, isExpanded: $isChartExpanded)
                    .detailCard()
                    .blurIn(contentShown, delay: 0.1)

                StreakTimelineCard(counter: counter)
                    .detailCard()
                    .blurIn(contentShown, delay: 0.17)

                WeekdaysCard(counter: counter)
                    .detailCard()
                    .blurIn(contentShown, delay: 0.24)

                Group {
                    sectionHeader("Summary")
                    summary(streaks: streaks)
                        .detailCard(vertical: 4)
                }
                .blurIn(contentShown, delay: 0.31)

                Group {
                    sectionHeader("History")
                    history(streaks: streaks, tint: tint)
                }
                .blurIn(contentShown, delay: 0.38)

                if let note = counter.note {
                    sectionHeader("Note")
                    Text(note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .detailCard()
                }

                let resetToday = counter.isDoneToday()
                let slipToday = counter.slipToday()
                let canSlip = counter.canSlipToday()
                VStack(alignment: .leading, spacing: 8) {
                    if kind == .quit {
                        // A slip is a quick tap (another tap the same day adds one more);
                        // starting over takes a press and hold.
                        Button {
                            logSlip()
                        } label: {
                            Text(slipToday.map { "One More Today · \(max(1, $0.amount))" } ?? "Log a Slip")
                                .contentTransition(.numericText())
                                .foregroundStyle(canSlip ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Color.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSlip)
                        .accessibilityHint(slipToday == nil ? "Starts the count again, but keeps the days so far"
                                                            : "Adds one more to today's slip")
                    }
                    // Logging a "last time" event is a good thing, so it isn't red.
                    HoldToResetButton(title: kind.resetAction, color: kind == .quit ? .red : tint) {
                        addReset(on: .now, note: nil)
                    }
                    .disabled(resetToday)
                    .frame(minHeight: 52)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                    Text(slipToday != nil
                         ? "Tap again for each one more today. Press and hold Reset Counter on another day to start over."
                         : (resetToday ? kind.doneToday : kind.holdHint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(counter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: counter.symbol)
                        .foregroundStyle(tint)
                    Text(counter.title)
                }
                .font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button(kind.addTitle, systemImage: "plus") {
                    isAddingReset = true
                }
            }
        }
        // One more on today's slip (or Undo taking it off) changes no date, so it gets its own tap.
        .sensoryFeedback(.success, trigger: toastTick)
        .sensoryFeedback(trigger: counter.resetDates) { old, new in
            if new.count > old.count { return .success }
            if new.count < old.count { return .impact(weight: .light) }
            return .selection
        }
        .overlay(alignment: .bottom) {
            if let reset = undoableReset {
                UndoToast(text: reset.isSlip ? (undoTakesOne ? "Slips today: \(reset.amount)" : "Slip logged") : kind.toast,
                          tint: tint) {
                    undo(reset)
                }
                .transition(.blurRise)
            }
        }
        .onAppear { contentShown = true }
        // Siri knows this is the counter on screen: "how long is this", "reset this".
        .userActivity("me.wherar3y0.since.counter") { activity in
            activity.title = counter.title
            activity.appEntityIdentifier = EntityIdentifier(for: CounterEntity.self, identifier: counter.id)
        }
        .task(id: toastTick) {
            guard undoableReset != nil else { return }
            // Cancelled when a newer toast replaces this one: then it must not clear that one.
            guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
            withAnimation { undoableReset = nil }
        }
        .sheet(isPresented: $isEditing) {
            CounterEditor(counter: counter, onDelete: onDelete)
        }
        .sheet(isPresented: $isAddingReset) {
            ResetEditor(counter: counter, reset: nil) { entry in
                addReset(on: entry.date, note: entry.note, isSlip: entry.isSlip, amount: entry.amount)
            }
        }
        .sheet(item: $editingReset) { reset in
            ResetEditor(counter: counter, reset: reset) { _ in
                saveChanges(context)
            } onDelete: {
                delete(reset)
            }
        }
    }

    // MARK: - Sections

    /// A small non-scrolling List, because swipe actions only exist in List.
    /// Rows have a fixed height so the list can be sized to fit them exactly.
    private func history(streaks: [Streak], tint: Color) -> some View {
        // How long the streak lasted that each reset ended.
        let lengthByEnd = Dictionary(streaks.filter { !$0.isCurrent }.map { ($0.end, $0.days) },
                                     uniquingKeysWith: { first, _ in first })
        let resets = counter.resets.sorted { $0.date > $1.date }
        let rowHeight: CGFloat = 56

        return List {
            ForEach(resets) { reset in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(reset.date.formatted(date: .abbreviated, time: .omitted))
                            if reset.isSlip {
                                Text(reset.amount > 1 ? "Slip ×\(reset.amount)" : "Slip")
                                    .font(.caption.bold())
                                    .foregroundStyle(tint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(tint.opacity(0.2), in: Capsule())
                            }
                        }
                        if let note = reset.note {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if let length = lengthByEnd[reset.date] {
                        Text("\(length) \(length == 1 ? "day" : "days")")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: rowHeight)
                .historyRow()
                // The same actions as the swipe, for anyone who doesn't know to swipe.
                .contextMenu {
                    Button("Edit", systemImage: "pencil") {
                        editingReset = reset
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(reset)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(reset)
                    }
                    Button("Edit", systemImage: "calendar") {
                        editingReset = reset
                    }
                    .tint(tint)
                }
            }

            HStack {
                Text("Started")
                Spacer()
                Text(counter.startDate.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            .frame(height: rowHeight)
            .historyRow()
            .listRowSeparator(.hidden, edges: .bottom)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, rowHeight)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .frame(height: CGFloat(resets.count + 1) * rowHeight)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func summary(streaks: [Streak]) -> some View {
        let kind = counter.kind
        let days = { (n: Int) in "\(n) \(n == 1 ? "day" : "days")" }
        let average = Int(kind.average(of: streaks).rounded())
        // `<=` picks the latest of equally long streaks.
        let best = streaks.max { $0.days <= $1.days }
        let tracked = DayMath.days(from: counter.startDate, to: .now) + 1
        let clean = DayMath.cleanRuns(start: counter.startDate, resets: counter.resetDates, now: .now)
            .map { DayMath.days(from: $0.lowerBound, to: $0.upperBound) + 1 }
            .reduce(0, +)

        var rows: [SummaryRow] = [
            SummaryRow(symbol: kind == .quit ? "flame" : "hourglass", title: "Current \(kind.period)", value: days(counter.days())),
        ]
        if let best {
            rows.append(SummaryRow(symbol: "trophy", title: kind.longest,
                                   subtitle: best.isCurrent
                                       ? "Since \(best.start.formatted(date: .abbreviated, time: .omitted))"
                                       : "\(best.start.formatted(.dateTime.month(.abbreviated).day())) – \(best.end.formatted(date: .abbreviated, time: .omitted))",
                                   value: days(best.days)))
        }
        rows.append(SummaryRow(symbol: "divide.circle", title: "Average \(kind.period)", value: days(average)))
        if kind == .quit {
            rows.append(SummaryRow(symbol: "arrow.uturn.backward", title: "Slips",
                                   subtitle: counter.extraSlips > 0 ? "\(counter.extraSlips) added by hand" : nil,
                                   value: "\(counter.totalSlips)"))
            if !counter.slipDates.isEmpty && (counter.slippedAmount != counter.slipDates.count || !counter.unitWord(2).isEmpty) {
                rows.append(SummaryRow(symbol: "smoke", title: "Had in slips", value: counter.amountText(counter.slippedAmount)))
            }
            rows.append(SummaryRow(symbol: "arrow.counterclockwise", title: "Full resets",
                                   value: "\(counter.fullResetDates.count)"))
        } else {
            rows.append(SummaryRow(symbol: "arrow.counterclockwise", title: kind.totalResets,
                                   value: "\(counter.resets.count)"))
        }
        rows.append(SummaryRow(symbol: "calendar", title: "Days tracked", value: "\(tracked)"))
        if kind == .quit {
            rows.append(SummaryRow(symbol: "checkmark.seal", title: "Clean days",
                                   value: "\(clean) (\(Int((Double(clean) / Double(max(tracked, 1)) * 100).rounded()))%)"))
        }
        rows.append(SummaryRow(symbol: "flag.checkered", title: "Started",
                               subtitle: counter.startDate.formatted(date: .long, time: .omitted),
                               value: counter.startDate.relativeDayDescription))
        if let lastReset = counter.resetDates.last {
            rows.append(SummaryRow(symbol: "clock.arrow.circlepath", title: kind.lastReset,
                                   subtitle: lastReset.formatted(date: .long, time: .omitted),
                                   value: lastReset.relativeDayDescription))
        }

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().padding(.leading, 42)
                }
                row
                    .frame(minHeight: 44)
                    .padding(.vertical, 8)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }

    // MARK: - Actions

    private func addReset(on date: Date, note: String?, isSlip: Bool = false, amount: Int = 1) {
        let reset = Reset(date: date, note: note, isSlip: isSlip, amount: amount)
        withAnimation {
            counter.resets.append(reset)
            undoableReset = reset
            undoTakesOne = false
            undoPreviousDate = nil
            toastTick += 1
        }
        saveChanges(context)
    }

    private func logSlip() {
        withAnimation {
            let logged = counter.logSlip()
            undoableReset = logged.slip
            undoTakesOne = logged.addedToToday
            undoPreviousDate = logged.previousDate
            toastTick += 1
        }
        saveChanges(context)
    }

    private func undo(_ reset: Reset) {
        if undoTakesOne && reset.amount > 1 {
            withAnimation {
                undoableReset = nil
                reset.amount -= 1
                if let undoPreviousDate {
                    reset.date = undoPreviousDate
                }
            }
            saveChanges(context)
        } else {
            withAnimation { undoableReset = nil }
            delete(reset)
        }
    }

    private func delete(_ reset: Reset) {
        withAnimation {
            if undoableReset === reset {
                undoableReset = nil
                undoTakesOne = false
            }
            counter.resets.removeAll { $0 === reset }
            context.delete(reset)
        }
        saveChanges(context)
    }
}

extension View {
    fileprivate func historyRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.cardBackground)
            .listRowSeparatorTint(Color.primary.opacity(0.15))
    }

    /// A rounded card on the detail screen. The background defaults to the plain card color.
    func detailCard<Background: View>(vertical: CGFloat = 12, @ViewBuilder background: () -> Background) -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { ZStack { background() } }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    func detailCard(vertical: CGFloat = 12) -> some View {
        detailCard(vertical: vertical) { Color.cardBackground }
    }
}

/// Floating glass toast shown for a few seconds after a reset. The whole toast is the Undo button,
/// so it gets the system's interactive glass: it swells and lights up under the finger.
struct UndoToast: View {
    let text: String
    let tint: Color
    let onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            HStack(spacing: 14) {
                Label(text, systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.primary)
                Text("Undo")
                    .bold()
                    .foregroundStyle(tint)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("\(text). Undo")
        .padding(.bottom, 8)
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query(sort: \Counter.sortOrder) var counters: [Counter]
    NavigationStack {
        if let counter = counters.first {
            CounterDetailView(counter: counter, onDelete: {})
        }
    }
}
