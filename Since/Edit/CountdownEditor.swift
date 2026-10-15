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
        _style = State(initialValue: countdown?.style ?? .calendar)
        _notifyBefore = State(initialValue: countdown?.notifyBefore ?? false)
        _note = State(initialValue: countdown?.note ?? "")
        _isBirthday = State(initialValue: countdown?.isBirthday ?? false)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The day the preview counts down to, as it will be after saving.
    private var target: Date {
        rule.occurrence(rule.targetIndex(from: date, now: .now), from: date)
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
                    DatePicker(rule.repeats ? "Starts" : "Date", selection: $date.animation(.smooth),
                               displayedComponents: .date)
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
                } footer: {
                    Text(rule.repeats
                         ? "After each time, it counts down to the next one. For a birthday, the first day can be the day of birth."
                         : "Once the day has passed, you can count the days since it.")
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

                Section {
                    Toggle("Reminders", isOn: $notifyBefore)
                        .tint(color.color)
                } footer: {
                    Text("A notification a week before, the day before and on the day.")
                        .blurIn(isPreviewShown, delay: 0.26)
                }
                .sectionReveal(isPreviewShown, delay: 0.26)

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
            .sensoryFeedback(.selection, trigger: style)
            .sensoryFeedback(.selection, trigger: rule)
            .sensoryFeedback(.selection, trigger: date)
            .sensoryFeedback(.success, trigger: savedEdits)
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
                DaysLeftText(days: days, size: 22)
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
            try? await Task.sleep(for: .milliseconds(200))
            isPreviewShown = true
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

        if let countdown {
            countdown.title = trimmedTitle
            // A first day set by hand is taken as the real one, so a yearly day counts years from it.
            if countdown.date != date {
                countdown.countsYears = true
            }
            countdown.date = date
            countdown.rule = finalRule
            countdown.symbol = symbol
            countdown.color = color
            countdown.tinted = tinted
            countdown.style = style
            countdown.notifyBefore = notifyBefore
            countdown.note = finalNote
            countdown.isBirthday = isBirthday
            // Moved to a day still ahead, or made to repeat: it's upcoming again.
            if !countdown.hasPassed() {
                countdown.isArchived = false
            }
            savedEdits += 1
        } else {
            // New countdowns go on top.
            let newCountdown = Countdown(title: trimmedTitle, symbol: symbol, color: color, date: date,
                                         rule: finalRule, note: finalNote,
                                         sortOrder: Countdown.topOrders(1, above: countdowns)[0])
            newCountdown.tinted = tinted
            newCountdown.style = style
            newCountdown.notifyBefore = notifyBefore
            newCountdown.isBirthday = isBirthday
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
