import AppIntents
import SwiftUI
import SwiftData
import Contacts

/// The Until tab: countdowns to the days ahead, and below them the ones kept in Past.
struct UntilView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Countdown.sortOrder) private var countdowns: [Countdown]

    /// A countdown to open, set by a link from a widget or a notification.
    @Binding var opened: UUID?
    /// Each time the tab comes on screen, the cards blur in as a wave.
    let arrival: TabArrival
    /// Called once a countdown has become a counter, to show it on the Since tab.
    let onCountedSince: () -> Void

    @State private var path: [UUID] = []
    @State private var dragged: Countdown?
    @State private var isAdding = false
    @State private var isPickingContacts = false
    @State private var isImportingCalendar = false
    @State private var isShowingSettings = false
    // Context menu and card actions.
    @State private var editing: Countdown?
    @State private var deleting: Countdown?
    @State private var converting: Countdown?
    /// Just moved to Past; the toast can still take it back.
    @State private var archivedRecently: Countdown?
    @State private var reorderTick = 0
    /// Ties each card to its detail screen for the zoom transition.
    @Namespace private var zoom
    /// The arrival whose wave has played; cards are hidden until it matches the current one.
    @State private var revealed: UUID?
    /// A just-created countdown stays hidden until the editor sheet is gone, then blurs in at its place.
    @State private var unrevealed: Set<UUID> = []

    private var upcoming: [Countdown] {
        countdowns.filter { !$0.isArchived }
    }

    /// Kept after their day, latest first.
    private var past: [Countdown] {
        countdowns.filter(\.isArchived).sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        CardGridLayout {
                            ForEach(upcoming) { countdown in
                                card(for: countdown, in: upcoming)
                                    .cardSize(countdown.size)
                            }
                        }
                        if !past.isEmpty {
                            Text("Past")
                                .font(.title3.bold())
                                .padding(.leading, 4)
                                .padding(.top, 16)
                                .waveIn(cardsShown, delay: arrival.delay(for: CardSlot(row: pastFirstRow - 1, column: 0)),
                                        from: arrival.edge)
                            CardGridLayout {
                                ForEach(past) { countdown in
                                    card(for: countdown, in: past, firstRow: pastFirstRow)
                                        .cardSize(countdown.size)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .background(Color.pageBackground)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .onChange(of: countdowns.map(\.id)) { old, new in
                    revealAdded(Set(new).subtracting(old), order: new, scroller: scroller)
                }
            }
            .overlay {
                if countdowns.isEmpty {
                    ContentUnavailableView("No Countdowns", systemImage: "hourglass",
                                           description: Text("Tap + to count down to a day, or to add birthdays and events."))
                }
            }
            .navigationTitle("Until")
            .task(id: arrival.id) {
                // On the next frame, once the hidden cards are on screen, so the wave plays from its start.
                await Task.yield()
                revealed = arrival.id
            }
            .onChange(of: opened, initial: true) {
                guard let id = opened else { return }
                isAdding = false
                isShowingSettings = false
                path = [id]
                opened = nil
            }
            .sensoryFeedback(.selection, trigger: reorderTick)
            .sensoryFeedback(.selection, trigger: countdowns.map(\.sizeRaw))
            .sensoryFeedback(.selection, trigger: countdowns.map(\.styleRaw))
            .sensoryFeedback(.impact(weight: .light), trigger: countdowns.map(\.isArchived))
            .sensoryFeedback(trigger: countdowns.count) { old, new in
                new > old ? .success : .impact(weight: .medium)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Add", systemImage: "plus") {
                        Button("New Countdown", systemImage: "hourglass") {
                            isAdding = true
                        }
                        Button("Birthdays…", systemImage: "birthday.cake") {
                            isPickingContacts = true
                        }
                        Button("Calendar Events…", systemImage: "calendar") {
                            isImportingCalendar = true
                        }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let countdown = countdowns.first(where: { $0.id == id }) {
                    CountdownDetailView(countdown: countdown) {
                        path.removeAll()
                    } onCountedSince: {
                        path.removeAll()
                        onCountedSince()
                    }
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
            }
            .sheet(isPresented: $isAdding) {
                CountdownEditor()
            }
            .sheet(isPresented: $isImportingCalendar) {
                CalendarImportView()
            }
            .background {
                ContactBirthdayPicker(isPresented: $isPickingContacts) { contacts in
                    addBirthdays(of: contacts)
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(item: $editing) { countdown in
                CountdownEditor(countdown: countdown)
            }
            .alert("Delete “\(deleting?.title ?? "")”?",
                   isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete", role: .destructive) {
                    if let countdown = deleting {
                        withAnimation { context.delete(countdown) }
                        saveChanges(context)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The countdown will be deleted.")
            }
            .countSinceAlert($converting, onDone: onCountedSince)
            .overlay(alignment: .bottom) {
                if let countdown = archivedRecently {
                    UndoToast(text: "Moved to Past", tint: countdown.color.color) {
                        setArchived(false, countdown)
                    }
                    .transition(.blurRise)
                }
            }
            .task(id: archivedRecently?.id) {
                guard archivedRecently != nil else { return }
                try? await Task.sleep(for: .seconds(5))
                withAnimation { archivedRecently = nil }
            }
        }
    }

    private var cardsShown: Bool {
        revealed == arrival.id
    }

    /// The Past grid's rows come after the upcoming ones and the heading between them.
    private var pastFirstRow: Int {
        (CardGridLayout.slots(for: upcoming.map(\.size)).last?.row ?? -1) + 2
    }

    private func card(for countdown: Countdown, in items: [Countdown], firstRow: Int = 0) -> some View {
        let index = items.firstIndex(of: countdown) ?? 0
        let slot = CardGridLayout.slots(for: items.map(\.size), firstRow: firstRow)[index]
        // A just-added countdown blurs in on its own, without the wave.
        let isNew = !unrevealed.isEmpty
        return CountdownCard(countdown: countdown) {
            path.append(countdown.id)
        } onCountSince: {
            converting = countdown
        } onArchive: {
            setArchived(true, countdown)
        }
        .waveIn(cardsShown && !unrevealed.contains(countdown.id),
                delay: isNew ? 0 : arrival.delay(for: slot), from: isNew ? nil : arrival.edge)
        .id(countdown.id)
        // Lets Siri tell which countdown "this one" is.
        .appEntityIdentifier(EntityIdentifier(for: CountdownEntity.self, identifier: countdown.id))
        .matchedTransitionSource(id: countdown.id, in: zoom) { source in
            source
                .background(.clear)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        // Outside the transition source: it clips to the card, which cut off the edge of a card swelling under a finger.
        .pressEffect(in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                     glow: countdown.color.color.mix(with: .white, by: 0.5))
        .contextMenu {
            menu(for: countdown)
        } preview: {
            CountdownMenuPreview(countdown: countdown)
        }
        .onDrag {
            dragged = countdown
            return NSItemProvider(object: countdown.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: ReorderDropDelegate(target: countdown, items: items, dragged: $dragged,
                                                           onMove: { reorderTick += 1 }) {
            saveChanges(context)
        })
    }

    /// A just-created countdown stays hidden while the editor sheet slides away, then the grid scrolls to it
    /// and it blurs in at its place.
    private func revealAdded(_ added: Set<UUID>, order: [UUID], scroller: ScrollViewProxy) {
        guard cardsShown, !added.isEmpty else { return }
        unrevealed = added
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if let last = order.last(where: added.contains) {
                withAnimation(.smooth) { scroller.scrollTo(last, anchor: .center) }
            }
            try? await Task.sleep(for: .milliseconds(250))
            unrevealed = []
        }
    }
}

extension UntilView {
    /// Long-press menu, laid out like the one on the Since tab.
    @ViewBuilder
    private func menu(for countdown: Countdown) -> some View {
        ControlGroup {
            Button("Edit", systemImage: "pencil") {
                editing = countdown
            }
            Button(countdown.tinted ? "Plain" : "Tinted",
                   systemImage: countdown.tinted ? "square.dashed" : "squareshape.on.pattern.diagonalline") {
                withAnimation { countdown.tinted.toggle() }
                saveChanges(context)
            }
            Button(countdown.notifyBefore ? "Mute" : "Remind",
                   systemImage: countdown.notifyBefore ? "bell.slash" : "bell") {
                countdown.notifyBefore.toggle()
                saveChanges(context)
                if countdown.notifyBefore {
                    Task {
                        _ = await Milestones.requestPermission()
                        refreshMirrors(context)
                    }
                }
            }
        }

        SizeMenu(current: countdown.size) { size in
            setSize(size, of: countdown)
        }
        // Buttons rather than a Picker, for the same reason as the size menu.
        Menu {
            ForEach(CountdownStyle.allCases) { style in
                Button {
                    setStyle(style, of: countdown)
                } label: {
                    if countdown.style == style {
                        Label(style.title, systemImage: "checkmark")
                    } else {
                        Text(style.title)
                    }
                }
            }
        } label: {
            Label("Style", systemImage: countdown.style.symbol)
        }

        Section {
            Button("Open", systemImage: "arrow.up.forward") {
                path.append(countdown.id)
            }
            if countdown.hasPassed() {
                Button("Count Since…", systemImage: "arrow.counterclockwise") {
                    converting = countdown
                }
                if countdown.isArchived {
                    Button("Move Out of Past", systemImage: "tray.and.arrow.up") {
                        setArchived(false, countdown)
                    }
                } else {
                    Button("Move to Past", systemImage: "archivebox") {
                        setArchived(true, countdown)
                    }
                }
            }
        }

        Section {
            Button("Delete Countdown", systemImage: "trash", role: .destructive) {
                deleting = countdown
            }
        }
    }

    private func setSize(_ size: CardSize, of countdown: Countdown) {
        let id = countdown.id
        // The menu closes first, then the grid reflows around the card's new size.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard let target = countdowns.first(where: { $0.id == id }) else { return }
            withAnimation(.smooth(duration: 0.45)) { target.size = size }
            saveChanges(context)
        }
    }

    /// A yearly countdown per person, each in its own color; people already counted down to are skipped.
    private func addBirthdays(of contacts: [CNContact]) {
        let colors: [CounterColor] = [.pink, .purple, .orange, .cyan, .yellow, .mint, .red, .blue, .lime, .green]
        var order = (countdowns.map(\.sortOrder).max() ?? -1) + 1
        for contact in contacts {
            guard let countdown = Countdown.birthday(of: contact, color: colors[order % colors.count], sortOrder: order),
                  !countdowns.contains(where: { $0.title == countdown.title && $0.rule.frequency == .yearly })
            else { continue }
            context.insert(countdown)
            order += 1
        }
        saveChanges(context)
    }

    private func setStyle(_ style: CountdownStyle, of countdown: Countdown) {
        let id = countdown.id
        // The menu closes first, then the card changes through a blur.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard let target = countdowns.first(where: { $0.id == id }) else { return }
            withAnimation(.smooth(duration: 0.45)) { target.style = style }
            saveChanges(context)
        }
    }

    private func setArchived(_ isArchived: Bool, _ countdown: Countdown) {
        withAnimation(.smooth(duration: 0.45)) {
            countdown.isArchived = isArchived
            archivedRecently = isArchived ? countdown : nil
        }
        saveChanges(context)
    }
}

/// Asks how a countdown whose day has passed should count from now on,
/// then turns it into a counter on the Since tab that starts on that day.
private struct CountSinceAlert: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var countdown: Countdown?
    let onDone: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Count days since “\(countdown?.title ?? "")”?",
                   isPresented: Binding(get: { countdown != nil }, set: { if !$0 { countdown = nil } })) {
                Button(CounterKind.quit.title) { convert(to: .quit) }
                Button(CounterKind.lastTime.title) { convert(to: .lastTime) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It becomes a counter on the Since tab, starting \(countdown?.target().sinceFormat ?? ""). "
                     + "Quit counts days without something; Last Time counts days since you last did it.")
            }
    }

    private func convert(to kind: CounterKind) {
        guard let countdown else { return }
        let counters = (try? context.fetch(FetchDescriptor<Counter>())) ?? []
        let counter = Counter(title: countdown.title, symbol: countdown.symbol, color: countdown.color, kind: kind,
                              startDate: countdown.target(), note: countdown.note,
                              sortOrder: (counters.map(\.sortOrder).max() ?? -1) + 1)
        counter.tinted = countdown.tinted
        counter.size = countdown.size
        context.insert(counter)
        context.delete(countdown)
        saveChanges(context)
        self.countdown = nil
        onDone()
    }
}

extension View {
    /// Shows the "count days since" question while `countdown` is set.
    func countSinceAlert(_ countdown: Binding<Countdown?>, onDone: @escaping () -> Void) -> some View {
        modifier(CountSinceAlert(countdown: countdown, onDone: onDone))
    }
}

#Preview(traits: .sampleData) {
    UntilView(opened: .constant(nil), arrival: TabArrival(), onCountedSince: {})
}
