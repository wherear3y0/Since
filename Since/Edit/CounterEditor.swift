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
        _notifyMilestones = State(initialValue: counter?.notifyMilestones ?? false)
        _kind = State(initialValue: counter?.kind ?? .quit)
        _note = State(initialValue: counter?.note ?? "")
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

    /// Live preview of the counter: recolors smoothly when a color is picked.
    /// A new counter shows a sample pattern so the color has something to fill.
    private var preview: some View {
        let tint = color.color.onCard(tinted: tinted)
        let now = Date.now
        let daysAgo = { (n: Int) in Calendar.app.date(byAdding: .day, value: -n, to: now)! }
        let grid = counter == nil
            ? DayMath.heatmap(start: daysAgo(60), resets: [], now: now, weeks: 16)
            : DayMath.heatmap(start: startDate, resets: counter?.resetDates ?? [], now: now, weeks: 16)

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
            try? await Task.sleep(for: .milliseconds(200))
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
            savedEdits += 1
        } else {
            let nextOrder = (counters.map(\.sortOrder).max() ?? -1) + 1
            let newCounter = Counter(title: trimmedTitle, symbol: symbol, color: color, kind: kind,
                                     startDate: startDate, note: finalNote, sortOrder: nextOrder)
            newCounter.tinted = tinted
            newCounter.notifyMilestones = notifyMilestones
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
