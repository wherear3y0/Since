import SwiftUI
import SwiftData

/// Sheet for creating a countdown (`countdown == nil`) or editing an existing one.
struct CountdownEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Countdown.sortOrder) private var countdowns: [Countdown]

    let countdown: Countdown?
    let onDelete: () -> Void

    @State private var title: String
    @State private var date: Date
    @State private var rule: RepeatRule
    @State private var symbol: String
    @State private var color: CounterColor
    @State private var tinted: Bool
    @State private var style: CountdownStyle
    @State private var notifyBefore: Bool
    @State private var note: String
    @State private var isBirthday: Bool
    @State private var showsLiveActivity: Bool
    @State private var numberStyle: DurationStyle
    @State private var hasTime: Bool
    @State private var hasWindow: Bool
    @State private var windowEnd: Date
    /// The start of the wait shows up for editing only once its chip is turned on.
    @State private var editsWaitStart = false
    @State private var waitStart: Date
    @State private var liveActivityLead: Int
    @State private var place: PickedPlace?
    @State private var isPickingPlace = false
    @State private var isPickingSymbol = false
    @State private var savedEdits = 0
    @State private var isConfirmingDelete = false
    /// Turns true just after the sheet opens: the preview, then each section, come in from a blur.
    @State private var isPreviewShown = false
    @FocusState private var isTitleFocused: Bool

    init(countdown: Countdown? = nil, onDelete: @escaping () -> Void = {}) {
        self.countdown = countdown
        self.onDelete = onDelete
        // A new countdown starts a month out, so the preview has some days to show.
        _title = State(initialValue: countdown?.title ?? "")
        _date = State(initialValue: countdown?.date ?? Calendar.app.date(byAdding: .month, value: 1, to: .now)!)
        _rule = State(initialValue: countdown?.rule ?? .never)
        _symbol = State(initialValue: countdown?.symbol ?? "star.fill")
        _color = State(initialValue: countdown?.color ?? .cyan)
        _tinted = State(initialValue: countdown?.tinted ?? true)
        // A new one starts from the default number format in Settings.
        _numberStyle = State(initialValue: countdown?.numberStyle
                             ?? DurationStyle(rawValue: UserDefaults.standard.integer(forKey: "durationStyle")) ?? .days)
        _style = State(initialValue: countdown?.style ?? .calendar)
        _notifyBefore = State(initialValue: countdown?.notifyBefore ?? false)
        _note = State(initialValue: countdown?.note ?? "")
        _isBirthday = State(initialValue: countdown?.isBirthday ?? false)
        _showsLiveActivity = State(initialValue: countdown?.showsLiveActivity ?? false)
        _hasTime = State(initialValue: countdown?.hasTime ?? false)
        _hasWindow = State(initialValue: countdown?.windowEnd != nil)
        _windowEnd = State(initialValue: countdown?.windowEnd
                           ?? Calendar.app.date(byAdding: .day, value: 7, to: countdown?.date ?? .now)!)
        _waitStart = State(initialValue: countdown?.createdAt ?? .now)
        _liveActivityLead = State(initialValue: countdown?.liveActivityLead ?? 0)
        _place = State(initialValue: countdown?.pickedPlace)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The countdown as it will be after saving, for the preview's numbers. Never inserted.
    private var draft: Countdown {
        let draft = Countdown(title: trimmedTitle, symbol: symbol, color: color, date: date, rule: rule)
        draft.windowEnd = showsWindow ? windowEnd : nil
        return draft
    }

    /// The day the preview counts down to, as it will be after saving.
    private var target: Date {
        draft.target()
    }

    /// A window only for a day that doesn't repeat, and never for a birthday.
    private var showsWindow: Bool {
        hasWindow && !rule.repeats && !isBirthday
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
                    Picker("Style", selection: $style.animation(.smooth(duration: 0.45))) {
                        ForEach(CountdownStyle.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .sectionReveal(isPreviewShown, delay: 0.17, background: .clear)
                } footer: {
                    Text(style.explanation)
                        .contentTransition(.opacity)
                        .blurIn(isPreviewShown, delay: 0.17)
                }

                Section {
                    DatePicker(showsWindow ? "From" : (rule.repeats ? "Starts" : "Date"),
                               selection: $date.animation(.smooth), displayedComponents: .date)
                        .onChange(of: date) { old, new in
                            // The window moves along with its first day.
                            if showsWindow {
                                windowEnd = windowEnd.addingTimeInterval(new.timeIntervalSince(old))
                            }
                        }
                    if showsWindow {
                        DatePicker("To", selection: $windowEnd.animation(.smooth),
                                   in: Calendar.app.startOfDay(for: date)..., displayedComponents: .date)
                            .transition(.blurReplace)
                    }
                    NavigationLink {
                        RepeatPicker(rule: $rule.animation(.smooth), start: date, tint: color.color)
                    } label: {
                        LabeledContent("Repeat", value: rule.summary())
                    }
                    if rule.repeats {
                        NavigationLink {
                            EndRepeatPicker(end: $rule.end, start: date, tint: color.color)
                        } label: {
                            LabeledContent("End Repeat",
                                           value: rule.end?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
                        }
                        .transition(.blurReplace)
                    }
                    optionChips
                    optionRows
                } footer: {
                    Text(dateFooter)
                        .contentTransition(.opacity)
                        .blurIn(isPreviewShown, delay: 0.2)
                }
                .sectionReveal(isPreviewShown, delay: 0.2)

                Section {
                    Toggle(isOn: $isBirthday.animation(.smooth)) {
                        Label {
                            Text("Birthday")
                        } icon: {
                            Image(systemName: "birthday.cake.fill")
                                .foregroundStyle(color.color)
                        }
                    }
                    .tint(color.color)
                    .onChange(of: isBirthday) { _, isOn in
                        // A birthday comes round every year.
                        if isOn && !rule.repeats {
                            withAnimation(.smooth) { rule = RepeatRule(frequency: .yearly) }
                        }
                    }
                } footer: {
                    Text("Birthdays get a section of their own on the Until tab, soonest first.")
                        .blurIn(isPreviewShown, delay: 0.23)
                }
                .sectionReveal(isPreviewShown, delay: 0.23)

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                .sectionReveal(isPreviewShown, delay: 0.32)

                if countdown != nil {
                    Section {
                        Button("Delete Countdown", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                        .confirmationDialog("Delete “\(countdown?.title ?? "")”?", isPresented: $isConfirmingDelete,
                                            titleVisibility: .visible) {
                            Button("Delete Countdown", role: .destructive) {
                                delete()
                            }
                        }
                    }
                    .sectionReveal(isPreviewShown, delay: 0.38)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle(countdown == nil ? "New Countdown" : "Edit Countdown")
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
            .sensoryFeedback(.selection, trigger: tinted)
            .sensoryFeedback(.selection, trigger: numberStyle)
            .sensoryFeedback(.selection, trigger: style)
            .sensoryFeedback(.selection, trigger: rule)
            .sensoryFeedback(.selection, trigger: date)
            .sensoryFeedback(.selection, trigger: [hasTime, hasWindow, editsWaitStart, notifyBefore, showsLiveActivity,
                                                   place != nil])
            .sensoryFeedback(.success, trigger: savedEdits)
            .sheet(isPresented: $isPickingPlace) {
                PlacePicker(calendarLocation: countdown?.calendarLocation, current: place, tint: color.color) { picked in
                    withAnimation(.smooth) { place = picked }
                }
            }
            .sheet(isPresented: $isPickingSymbol) {
                SymbolPicker(selection: $symbol, tint: color.color)
            }
            .onAppear {
                if countdown == nil {
                    isTitleFocused = true
                }
            }
        }
    }

    /// Days of the wait already behind, as they'll be after saving. A new one-off countdown hasn't
    /// started waiting yet, so the preview shows it halfway, to have something to fill.
    private var previewWaited: Int {
        let days = DayMath.daysUntil(target, from: .now)
        let index = rule.targetIndex(from: date, now: .now)
        if index > 0 {
            return DayMath.days(from: rule.occurrence(index - 1, from: date), to: .now)
        }
        if let before = rule.timeBefore(date), before <= .now {
            return DayMath.days(from: before, to: .now)
        }
        if let countdown {
            return DayMath.days(from: countdown.createdAt, to: .now)
        }
        return max(1, days / 2)
    }

    /// Live preview: the days to go and the wait in the chosen style, recolored as a color is picked.
    private var preview: some View {
        let tint = color.color.onCard(tinted: tinted)
        let days = DayMath.daysUntil(target, from: .now)
        let waited = previewWaited
        let progress = days > 0 ? Double(waited) / Double(waited + days) : 1

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .contentTransition(.symbolEffect(.replace))
                    Text(trimmedTitle.isEmpty ? "Title" : trimmedTitle)
                        .lineLimit(1)
                }
                .font(.headline)
                .foregroundStyle(tint)
                Spacer()
                DaysLeftText(days: days, size: 22, isApproximate: draft.isApproximate())
            }

            Group {
                switch style {
                case .calendar:
                    HStack(spacing: 16) {
                        ForEach(Calendar.app.monthsShown(now: .now, target: target), id: \.self) { month in
                            MonthGrid(month: month, target: target, tint: tint, showsTitle: true)
                        }
                    }
                    .frame(height: 150)
                case .fill:
                    CountdownFillFooter(waited: waited, daysLeft: days, progress: progress)
                        .padding(.top, 90)
                case .timeline:
                    CountdownTimeline(start: Calendar.app.date(byAdding: .day, value: -waited, to: .now)!,
                                      target: target, waited: waited, daysLeft: days, tint: tint)
                        .padding(.vertical, 22)
                }
            }
            .id(style)
            .transition(.blurReplace)
        }
        .padding(16)
        .background {
            if style == .fill {
                FillLevel(level: progress, tint: tint)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .counterCardBackground(tint: tint, tinted: tinted, glowOpacity: 0.35, glowRadius: 22)
        .editorPreview(isShown: isPreviewShown)
        // Started once the sheet is on screen; changed earlier, the animation finishes before anyone sees it.
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            isPreviewShown = true
        }
    }

    // MARK: - Extras

    private var dateFooter: String {
        if showsWindow {
            return "It comes any day from the first date to the second. Until then the days are about right: "
                + "they count to the middle."
        }
        return rule.repeats
            ? "After each time, it counts down to the next one. For a birthday, the first day can be the day of birth."
            : "Once the day has passed, you can count the days since it."
    }

    /// Extras for the day, off until tapped, like the buttons under a new reminder.
    private var optionChips: some View {
        HStack(spacing: 12) {
            if !isBirthday {
                OptionChip(title: "Time", symbol: "clock", isOn: hasTime, tint: color.color) {
                    withAnimation(.smooth) { setTime(!hasTime) }
                }
            }
            if !rule.repeats && !isBirthday {
                OptionChip(title: "Window", symbol: "arrow.left.and.right", isOn: hasWindow, tint: color.color) {
                    withAnimation(.smooth) {
                        hasWindow.toggle()
                        // A window has no time: it's any day in it. It starts a week long.
                        if hasWindow {
                            hasTime = false
                            if windowEnd <= date {
                                windowEnd = Calendar.app.date(byAdding: .day, value: 7, to: date)!
                            }
                        }
                    }
                }
            }
            if !rule.repeats {
                OptionChip(title: "Waiting Since", symbol: "hourglass.bottomhalf.filled", isOn: editsWaitStart,
                           tint: color.color) {
                    withAnimation(.smooth) {
                        editsWaitStart.toggle()
                        if !editsWaitStart {
                            waitStart = countdown?.createdAt ?? .now
                        }
                    }
                }
            }
            OptionChip(title: "Place", symbol: "mappin.and.ellipse", isOn: place != nil, tint: color.color) {
                if place == nil {
                    isPickingPlace = true
                } else {
                    withAnimation(.smooth) { place = nil }
                }
            }
            OptionChip(title: "Reminders", symbol: "bell", isOn: notifyBefore, tint: color.color) {
                withAnimation(.smooth) { notifyBefore.toggle() }
            }
            OptionChip(title: "Live Activity", symbol: "platter.filled.bottom.iphone", isOn: showsLiveActivity,
                       tint: color.color) {
                withAnimation(.smooth) { showsLiveActivity.toggle() }
            }
        }
        .padding(.vertical, 4)
    }

    /// The settings of the chips that are on.
    @ViewBuilder
    private var optionRows: some View {
        if hasTime && !isBirthday {
            DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                .transition(.blurReplace)
        }
        if editsWaitStart && !rule.repeats {
            DatePicker("Waiting Since", selection: $waitStart.animation(.smooth), in: ...Date.now,
                       displayedComponents: .date)
                .transition(.blurReplace)
        }
        if let place {
            Button {
                isPickingPlace = true
            } label: {
                LabeledContent {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        if let address = place.address {
                            Text(address)
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .transition(.blurReplace)
        }
        if notifyBefore {
            LabeledContent("Reminders", value: "A week before, the day before, on the day")
                .transition(.blurReplace)
        }
        if showsLiveActivity {
            Picker("Live Activity", selection: $liveActivityLead) {
                Text("On the Day").tag(0)
                Text("1 Day Before").tag(1)
                Text("3 Days Before").tag(3)
                Text("A Week Before").tag(7)
            }
            .transition(.blurReplace)
        }
    }

    /// Turning the time on starts it at the next full hour.
    private func setTime(_ isOn: Bool) {
        hasTime = isOn
        guard isOn else { return }
        hasWindow = false
        if countdown?.hasTime != true {
            let hour = (Calendar.app.component(.hour, from: .now) + 1) % 24
            date = Calendar.app.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        }
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = trimmedNote.isEmpty ? nil : trimmedNote
        // An end before the (moved) first day would stop the repeat before it starts.
        var finalRule = rule
        if let end = finalRule.end, end < date {
            finalRule.end = date
        }
        let finalWindowEnd = showsWindow ? max(windowEnd, date) : nil
        let finalHasTime = hasTime && !isBirthday && finalWindowEnd == nil
        // A time is to the minute.
        let time = Calendar.app.dateComponents([.hour, .minute], from: date)
        let finalDate = finalHasTime
            ? Calendar.app.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: date) ?? date
            : date

        if let countdown {
            countdown.title = trimmedTitle
            // A first day set by hand is taken as the real one, so a yearly day counts years from it.
            if countdown.date != finalDate {
                countdown.countsYears = true
            }
            countdown.date = finalDate
            countdown.hasTime = finalHasTime
            countdown.windowEnd = finalWindowEnd
            if editsWaitStart {
                countdown.createdAt = waitStart
            }
            countdown.rule = finalRule
            countdown.symbol = symbol
            countdown.color = color
            countdown.tinted = tinted
            countdown.style = style
            countdown.notifyBefore = notifyBefore
            countdown.note = finalNote
            countdown.isBirthday = isBirthday
            countdown.numberStyle = numberStyle
            if showsLiveActivity && (!countdown.showsLiveActivity || countdown.liveActivityLead != liveActivityLead) {
                LiveActivities.allowRestart(of: countdown.id)
            }
            countdown.showsLiveActivity = showsLiveActivity
            countdown.liveActivityLead = liveActivityLead
            if place != countdown.pickedPlace {
                countdown.setPlace(place)
            }
            // Moved to a day still ahead, or made to repeat: it's upcoming again.
            if !countdown.hasPassed() {
                countdown.isArchived = false
            }
            savedEdits += 1
        } else {
            // New countdowns go on top.
            let newCountdown = Countdown(title: trimmedTitle, symbol: symbol, color: color, date: finalDate,
                                         rule: finalRule, note: finalNote,
                                         sortOrder: Countdown.topOrders(1, above: countdowns)[0])
            newCountdown.tinted = tinted
            newCountdown.style = style
            newCountdown.notifyBefore = notifyBefore
            newCountdown.isBirthday = isBirthday
            newCountdown.showsLiveActivity = showsLiveActivity
            newCountdown.numberStyle = numberStyle
            newCountdown.hasTime = finalHasTime
            newCountdown.windowEnd = finalWindowEnd
            newCountdown.liveActivityLead = liveActivityLead
            newCountdown.setPlace(place)
            if editsWaitStart {
                newCountdown.createdAt = waitStart
            }
            context.insert(newCountdown)
        }
        saveChanges(context)
        if notifyBefore {
            Task {
                _ = await Milestones.requestPermission()
                refreshMirrors(context)
            }
        }
        dismiss()
    }

    private func delete() {
        guard let countdown else { return }
        context.delete(countdown)
        saveChanges(context)
        dismiss()
        onDelete()
    }
}

#Preview("New", traits: .sampleData) {
    CountdownEditor()
}
