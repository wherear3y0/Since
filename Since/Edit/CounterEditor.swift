import SwiftUI
import SwiftData

/// Sheet for creating a counter (`counter == nil`) or editing an existing one.
struct CounterEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Counter.sortOrder) private var counters: [Counter]

    let counter: Counter?
    let onDelete: () -> Void

    @State private var title: String
    @State private var startDate: Date
    @State private var symbol: String
    @State private var color: CounterColor
    @State private var tinted: Bool
    @State private var notifyMilestones: Bool
    @State private var kind: CounterKind
    @State private var note: String
    // Savings, for "quit" counters. The numbers are kept as typed and read on Save: a number field only
    // takes its value when editing ends, and a number pad has no key to end it before Save is tapped.
    @State private var unitName: String
    @State private var unitsPerDayText: String
    @State private var priceText: String
    @State private var unitsPerPriceText: String
    @State private var minutesPerUnitText: String
    @State private var showsHealth: Bool
    /// Slips not in the history, edited as part of the total.
    @State private var extraSlips: Int
    @State private var numberStyle: DurationStyle
    @State private var isPickingSymbol = false
    @State private var savedEdits = 0
    @State private var isConfirmingDelete = false
    /// Turns true just after the sheet opens: the preview, then each section, come in from a blur.
    @State private var isPreviewShown = false
    /// The sample wave in a new counter's preview plays only on the first appearance.
    @State private var didAppear = false
    @FocusState private var isTitleFocused: Bool

    init(counter: Counter? = nil, onDelete: @escaping () -> Void = {}) {
        self.counter = counter
        self.onDelete = onDelete
        _title = State(initialValue: counter?.title ?? "")
        _startDate = State(initialValue: counter?.startDate ?? .now)
        _symbol = State(initialValue: counter?.symbol ?? "star.fill")
        _color = State(initialValue: counter?.color ?? .blue)
        _tinted = State(initialValue: counter?.tinted ?? true)
        // A new one starts from the default number format in Settings.
        _numberStyle = State(initialValue: counter?.numberStyle
                             ?? DurationStyle(rawValue: UserDefaults.standard.integer(forKey: "durationStyle")) ?? .days)
        _notifyMilestones = State(initialValue: counter?.notifyMilestones ?? false)
        _kind = State(initialValue: counter?.kind ?? .quit)
        _note = State(initialValue: counter?.note ?? "")
        _unitName = State(initialValue: counter?.unitName ?? "")
        _unitsPerDayText = State(initialValue: Self.text(for: counter?.unitsPerDay ?? 0))
        _priceText = State(initialValue: Self.text(for: counter?.price ?? 0))
        _unitsPerPriceText = State(initialValue: Self.text(for: Double(counter?.unitsPerPrice ?? 0)))
        _minutesPerUnitText = State(initialValue: Self.text(for: counter?.minutesPerUnit ?? 0))
        _showsHealth = State(initialValue: counter?.showsHealth ?? false)
        _extraSlips = State(initialValue: max(0, counter?.extraSlips ?? 0))
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The start can't be in the future or after the first reset.
    private var latestStartDate: Date {
        min(.now, counter?.resetDates.first ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                // The preview lives in a section header, where its glow isn't clipped by a cell.
                Section {
                    EditorTitleRow(title: $title, symbol: symbol, color: color.color, isFocused: $isTitleFocused) {
                        isPickingSymbol = true
                    }
                    .listRowInsets(EdgeInsets())
                        .sectionReveal(isPreviewShown, delay: 0.08, background: .clear)
                } header: {
                    preview
                        .textCase(nil)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }

                Section {
                    ColorRow(color: $color)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    Toggle(isOn: $tinted.animation(.easeInOut(duration: 0.45))) {
                        Label {
                            Text("Tinted Background")
                        } icon: {
                            Image(systemName: "squareshape.on.pattern.diagonalline")
                                .foregroundStyle(color.color)
                        }
                    }
                    .tint(color.color)
                    Picker(selection: $numberStyle) {
                        Text("127 days").tag(DurationStyle.days)
                        Text("18w 1d").tag(DurationStyle.weeks)
                        Text("4m 5d").tag(DurationStyle.months)
                    } label: {
                        Label {
                            Text("Number Format")
                        } icon: {
                            Image(systemName: "number")
                                .foregroundStyle(color.color)
                        }
                    }
                }
                .sectionReveal(isPreviewShown, delay: 0.14)

                Section {
                    Picker("Type", selection: $kind.animation()) {
                        ForEach(CounterKind.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .sectionReveal(isPreviewShown, delay: 0.2, background: .clear)
                } footer: {
                    Text(kind.explanation)
                        .contentTransition(.opacity)
                        .blurIn(isPreviewShown, delay: 0.2)
                }

                Section {
                    DatePicker("Started", selection: $startDate, in: ...latestStartDate, displayedComponents: .date)
                    Toggle("Milestone Reminders", isOn: $notifyMilestones)
                        .tint(color.color)
                } footer: {
                    Text("A notification at half a year and on every anniversary.")
                        .blurIn(isPreviewShown, delay: 0.26)
                }
                .sectionReveal(isPreviewShown, delay: 0.26)

                if kind == .quit {
                    slipsSection
                        .sectionReveal(isPreviewShown, delay: 0.28)
                    savingsSection
                        .sectionReveal(isPreviewShown, delay: 0.29)
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                .sectionReveal(isPreviewShown, delay: 0.32)

                if counter != nil {
                    Section {
                        Button("Delete Counter", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                        .confirmationDialog("Delete “\(counter?.title ?? "")”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                            Button("Delete Counter", role: .destructive) {
                                delete()
                            }
                        } message: {
                            Text("The counter and its whole reset history will be deleted.")
                        }
                    }
                    .sectionReveal(isPreviewShown, delay: 0.38)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle(counter == nil ? "New Counter" : "Edit Counter")
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
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .sensoryFeedback(.selection, trigger: color)
            .sensoryFeedback(.selection, trigger: symbol)
            .sensoryFeedback(.selection, trigger: kind)
            .sensoryFeedback(.selection, trigger: tinted)
            .sensoryFeedback(.selection, trigger: numberStyle)
            .sensoryFeedback(.success, trigger: savedEdits)
            .sheet(isPresented: $isPickingSymbol) {
                SymbolPicker(selection: $symbol, tint: color.color)
            }
            .onAppear {
                didAppear = true
                if counter == nil {
                    isTitleFocused = true
                }
            }
        }
    }

    /// The total number of slips, for slips that aren't in the history: from before tracking, or never logged.
    /// It can't go below the logged ones; those are deleted from the history.
    private var slipsSection: some View {
        let logged = counter?.slipDates.count ?? 0
        let total = Binding {
            logged + extraSlips
        } set: { newTotal in
            extraSlips = max(0, newTotal - logged)
        }
        return Section {
            Stepper(value: total, in: logged...9999) {
                LabeledContent("Total Slips", value: "\(logged + extraSlips)")
            }
        } footer: {
            Text(logged > 0
                 ? "\(logged) in the history. Raise it for slips you didn’t log, like ones from before you started tracking. To lower it, delete slips from the history."
                 : "For slips you had before you started tracking, if you want them counted.")
        }
    }

    /// What the habit cost, so the counter can show what's been saved. Shown for "quit" counters.
    private var savingsSection: some View {
        let unit = unitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let units = unit.isEmpty ? "units" : unit
        return Section {
            LabeledContent("What") {
                TextField("cigarettes", text: $unitName)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            LabeledContent("A day") {
                numberField("0", text: $unitsPerDayText)
            }
            LabeledContent("Price") {
                HStack(spacing: 4) {
                    numberField("0", text: $priceText)
                    Text(Locale.current.currencySymbol ?? Savings.currencyCode)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Price is for") {
                HStack(spacing: 4) {
                    numberField("1", text: $unitsPerPriceText, keyboard: .numberPad)
                    Text(units)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Minutes each") {
                numberField("0", text: $minutesPerUnitText)
            }
            Toggle("Health Recovery", isOn: $showsHealth)
                .tint(color.color)
            Button("Fill In for Smoking", systemImage: "lungs") {
                withAnimation {
                    unitName = "cigarettes"
                    unitsPerPriceText = "20"
                    if Self.number(from: minutesPerUnitText) == 0 {
                        minutesPerUnitText = "5"
                    }
                    showsHealth = true
                }
            }
            .tint(color.color)
        } header: {
            Text("Savings")
        } footer: {
            Text("For smoking: cigarettes a day, the price of a pack and how many are in it. "
                 + "Since then shows the money, time and cigarettes saved since the last full reset, "
                 + "less the ones had in slips, and how the body recovers.")
        }
    }

    private func numberField(_ placeholder: String, text: Binding<String>,
                             keyboard: UIKeyboardType = .decimalPad) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.trailing)
    }

    /// A number as it's shown for editing: empty for 0, no grouping, decimals only when there are some.
    private static func text(for value: Double) -> String {
        value == 0 ? "" : value.formatted(.number.grouping(.never))
    }

    /// A number typed in the region's format ("9,50") or with a point ("9.50"); 0 when it isn't one.
    private static func number(from text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let value = try? Double(trimmed, format: .number) {
            return value
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Live preview of the counter: recolors smoothly when a color is picked.
    /// A new counter shows a sample pattern so the color has something to fill.
    private var preview: some View {
        let tint = color.color.onCard(tinted: tinted)
        let now = Date.now
        let daysAgo = { (n: Int) in Calendar.app.date(byAdding: .day, value: -n, to: now)! }
        // A new "last time" counter shows a few sample days it was done.
        let grid = counter == nil
            ? DayMath.heatmap(start: daysAgo(60), resets: kind == .lastTime ? [45, 31, 17, 6].map(daysAgo) : [],
                              logsEvents: kind == .lastTime, now: now, weeks: 16)
            : DayMath.heatmap(start: startDate, resets: counter?.resetDates ?? [], slips: counter?.slipDates ?? [],
                              logsEvents: kind == .lastTime, now: now, weeks: 16)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .contentTransition(.symbolEffect(.replace))
                Text(trimmedTitle.isEmpty ? "Title" : trimmedTitle)
                    .lineLimit(1)
            }
            .font(.headline)
            .foregroundStyle(tint)

            HeatmapView(days: grid, tint: tint, showsWeekdays: true,
                        animated: counter == nil && !didAppear, startDelay: 0.35)
        }
        .padding(16)
        .counterCardBackground(tint: tint, tinted: tinted, glowOpacity: 0.35, glowRadius: 22)
        .editorPreview(isShown: isPreviewShown)
        // Started once the sheet is on screen; changed earlier, the animation finishes before anyone sees it.
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            isPreviewShown = true
        }
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = trimmedNote.isEmpty ? nil : trimmedNote

        if let counter {
            counter.title = trimmedTitle
            counter.startDate = startDate
            counter.symbol = symbol
            counter.color = color
            counter.tinted = tinted
            counter.notifyMilestones = notifyMilestones
            counter.kind = kind
            counter.note = finalNote
            counter.numberStyle = numberStyle
            applySavings(to: counter)
            savedEdits += 1
        } else {
            let nextOrder = (counters.map(\.sortOrder).max() ?? -1) + 1
            let newCounter = Counter(title: trimmedTitle, symbol: symbol, color: color, kind: kind,
                                     startDate: startDate, note: finalNote, sortOrder: nextOrder)
            newCounter.tinted = tinted
            newCounter.notifyMilestones = notifyMilestones
            newCounter.numberStyle = numberStyle
            applySavings(to: newCounter)
            context.insert(newCounter)
        }
        saveChanges(context)
        if notifyMilestones {
            Task {
                _ = await Milestones.requestPermission()
                refreshMirrors(context)
            }
        }
        dismiss()
    }

    /// Savings only mean something for "quit" counters; a "last time" counter keeps whatever it had.
    private func applySavings(to counter: Counter) {
        guard kind == .quit else { return }
        counter.unitName = unitName.trimmingCharacters(in: .whitespacesAndNewlines)
        counter.unitsPerDay = max(0, Self.number(from: unitsPerDayText))
        counter.price = max(0, Self.number(from: priceText))
        counter.unitsPerPrice = Int(min(10_000, max(1, Self.number(from: unitsPerPriceText))).rounded())
        counter.minutesPerUnit = max(0, Self.number(from: minutesPerUnitText))
        counter.showsHealth = showsHealth
        counter.extraSlips = max(0, extraSlips)
    }

    private func delete() {
        guard let counter else { return }
        context.delete(counter)
        saveChanges(context)
        dismiss()
        onDelete()
    }
}

#Preview("New", traits: .sampleData) {
    CounterEditor()
}

#Preview("Edit", traits: .sampleData) {
    @Previewable @Query(sort: \Counter.sortOrder) var counters: [Counter]
    if let counter = counters.first {
        CounterEditor(counter: counter)
    }
}
