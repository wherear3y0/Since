import PhotosUI
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
    @State private var habit: Habit
    @State private var unitName: String
    @State private var unitsPerDayText: String
    @State private var priceText: String
    @State private var unitsPerPriceText: String
    @State private var minutesPerUnitText: String
    @State private var showsHealth: Bool
    /// Slips not in the history, edited as part of the total.
    @State private var extraSlips: Int
    @State private var numberStyle: DurationStyle
    // An owned thing's picture, and reading one off a screenshot of its order or receipt.
    @State private var photoData: Data?
    @State private var screenshotItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var scanNote: String?
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
        _photoData = State(initialValue: counter?.photoData)
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
        _habit = State(initialValue: counter?.habit ?? .other)
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

                if kind == .owned {
                    ownedSection
                        .sectionReveal(isPreviewShown, delay: 0.23)
                }

                Section {
                    DatePicker(kind == .owned ? "Got It" : "Started", selection: $startDate, in: ...latestStartDate,
                               displayedComponents: .date)
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
            .navigationTitle(kind == .owned ? (counter == nil ? "New Thing" : "Edit Thing")
                                            : (counter == nil ? "New Counter" : "Edit Counter"))
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
            .sensoryFeedback(.selection, trigger: habit)
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

    /// An owned thing's picture, and its name, the day it was got and a picture read off a screenshot.
    private var ownedSection: some View {
        Section {
            ScreenshotFillRow(selection: $screenshotItem, isScanning: isScanning,
                              note: scanNote ?? "Pick a screenshot of the order or receipt: the name, the day you got it and a photo fill in from it.",
                              tint: color.color)
            ItemPhotoRow(title: "Photo", photoData: $photoData, symbol: symbol, tint: color.color)
        }
        .onChange(of: screenshotItem) { _, item in
            guard let item else { return }
            Task { await scan(item) }
        }
    }

    /// Fills in what can be read off a screenshot, keeping what's already been typed.
    private func scan(_ item: PhotosPickerItem) async {
        isScanning = true
        defer {
            isScanning = false
            screenshotItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let result = await ParcelScanner.scan(image)
        var found: [String] = []
        withAnimation(.smooth) {
            if let name = result.draft.title {
                if trimmedTitle.isEmpty {
                    title = name
                }
                found.append("name")
            }
            if let got = result.draft.got {
                startDate = min(got, latestStartDate)
                found.append("the day you got it")
            }
            if let photo = result.photo {
                if photoData == nil {
                    photoData = photo
                }
                found.append("photo")
            }
            scanNote = found.isEmpty
                ? "Nothing could be read off that picture."
                : "Filled in from the screenshot: \(found.joined(separator: ", "))."
        }
        savedEdits += found.isEmpty ? 0 : 1
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
    /// The habit sets the questions: a pack price and how many are in a pack for smoking, a price per cup for coffee.
    private var savingsSection: some View {
        let typed = unitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let one = habit.unit?.one ?? (typed.isEmpty ? "unit" : typed)
        let many = habit.unit?.many ?? (typed.isEmpty ? "units" : typed)
        return Section {
            Picker(selection: $habit.animation(.smooth)) {
                ForEach(Habit.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            } label: {
                Label {
                    Text("Habit")
                } icon: {
                    Image(systemName: habit.symbol)
                        .foregroundStyle(color.color)
                }
            }
            .onChange(of: habit) { _, newHabit in
                applyDefaults(of: newHabit)
            }
            if habit == .other {
                LabeledContent("What") {
                    TextField("units", text: $unitName)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
            }
            LabeledContent("\(many.capitalized) a day") {
                numberField("0", text: $unitsPerDayText)
            }
            if let pack = habit.pack {
                LabeledContent("\(pack.name.capitalized) price") {
                    priceField
                }
                LabeledContent("\(many.capitalized) in a \(pack.name)") {
                    numberField("\(pack.size)", text: $unitsPerPriceText, keyboard: .numberPad)
                }
            } else if habit == .other {
                LabeledContent("Price") {
                    priceField
                }
                LabeledContent("Price is for") {
                    HStack(spacing: 4) {
                        numberField("1", text: $unitsPerPriceText, keyboard: .numberPad)
                        Text(many)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                LabeledContent("Price per \(one)") {
                    priceField
                }
            }
            LabeledContent("Minutes each") {
                numberField("0", text: $minutesPerUnitText)
            }
            if habit.hasHealthSteps {
                Toggle("Health Recovery", isOn: $showsHealth)
                    .tint(color.color)
            }
        } header: {
            Text("Savings")
        } footer: {
            Text(habit.pack != nil
                 ? "\(many.capitalized) a day, the price of a \(habit.pack!.name) and how many are in it. "
                     + "Since shows the money, time and \(many) saved since the last full reset, less the ones had in slips"
                     + (habit.hasHealthSteps ? ", and how the body recovers." : ".")
                 : "What it cost a day. Since shows the money, time and \(many) saved since the last full reset, "
                     + "less what was had in slips.")
                .contentTransition(.opacity)
        }
    }

    private var priceField: some View {
        HStack(spacing: 4) {
            numberField("0", text: $priceText)
            Text(Locale.current.currencySymbol ?? Savings.currencyCode)
                .foregroundStyle(.secondary)
        }
    }

    /// A habit picked in the editor fills in what fits it: the pack size, a starting time per unit, the health
    /// steps, and its icon when the counter still has the default one.
    private func applyDefaults(of newHabit: Habit) {
        if let pack = newHabit.pack {
            if Self.number(from: unitsPerPriceText) <= 1 {
                unitsPerPriceText = "\(pack.size)"
            }
        } else if newHabit != .other {
            // Priced per cup or drink.
            unitsPerPriceText = ""
        }
        if Self.number(from: minutesPerUnitText) == 0, newHabit.defaultMinutes > 0 {
            minutesPerUnitText = Self.text(for: newHabit.defaultMinutes)
        }
        showsHealth = newHabit.hasHealthSteps
        if symbol == "star.fill" && newHabit != .other {
            symbol = newHabit.symbol
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
        // A new "last time" counter shows a few sample days it was done; an owned thing, the days since it was got.
        let grid = counter == nil && kind != .owned
            ? DayMath.heatmap(start: daysAgo(60), resets: kind == .lastTime ? [45, 31, 17, 6].map(daysAgo) : [],
                              logsEvents: kind == .lastTime, now: now, weeks: 16)
            : DayMath.heatmap(start: startDate, resets: counter?.resetDates ?? [], slips: counter?.slipDates ?? [],
                              logsEvents: kind == .lastTime, now: now, weeks: 16)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                if kind == .owned && photoData != nil {
                    ItemPhoto(data: photoData, symbol: symbol, tint: tint, side: 22)
                } else {
                    Image(systemName: symbol)
                        .contentTransition(.symbolEffect(.replace))
                }
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
            counter.photoData = kind == .owned ? photoData : counter.photoData
            applySavings(to: counter)
            savedEdits += 1
        } else {
            let nextOrder = (counters.map(\.sortOrder).max() ?? -1) + 1
            let newCounter = Counter(title: trimmedTitle, symbol: symbol, color: color, kind: kind,
                                     startDate: startDate, note: finalNote, sortOrder: nextOrder)
            newCounter.tinted = tinted
            newCounter.notifyMilestones = notifyMilestones
            newCounter.numberStyle = numberStyle
            newCounter.photoData = kind == .owned ? photoData : nil
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
        counter.habit = habit
        counter.unitName = habit == .other ? unitName.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        counter.unitsPerDay = max(0, Self.number(from: unitsPerDayText))
        counter.price = max(0, Self.number(from: priceText))
        // A pack left empty is the habit's usual pack; a habit priced per unit is always one.
        let typedPerPrice = Self.number(from: unitsPerPriceText)
        let perPrice: Double = if let pack = habit.pack {
            typedPerPrice > 0 ? typedPerPrice : Double(pack.size)
        } else if habit == .other {
            typedPerPrice
        } else {
            1
        }
        counter.unitsPerPrice = Int(min(10_000, max(1, perPrice)).rounded())
        counter.minutesPerUnit = max(0, Self.number(from: minutesPerUnitText))
        counter.showsHealth = showsHealth && habit.hasHealthSteps
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
