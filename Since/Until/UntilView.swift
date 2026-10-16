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
    /// Goes up with every link the app opens: the tab's sheets close then.
    var linkTick = 0
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
    /// Just moved to Past; the toast can still take it back. Kept by id, so a countdown deleted meanwhile
    /// just drops out of the query instead of being touched after it's gone.
    @State private var archivedRecentlyID: UUID?
    /// The toast is for a countdown just marked done rather than moved to Past.
    @State private var toastIsDone = false
    @State private var reorderTick = 0
    /// Ties each card to its detail screen for the zoom transition.
    @Namespace private var zoom
    /// The arrival whose wave has played; cards are hidden until it matches the current one.
    @State private var revealed: UUID?
    /// A just-created countdown stays hidden until the editor sheet is gone, then blurs in at its place.
    @State private var unrevealed: Set<UUID> = []
    /// Cards changing size, their content faded out meanwhile.
    @State private var reshaping: Set<UUID> = []
    /// Sections folded under their heading, remembered between launches. A @State, since stored changes
    /// don't animate; it's written back on every change.
    @State private var collapsed = Set(UserDefaults.standard.stringArray(forKey: "collapsedUntilSections") ?? [])
    /// Contacts just picked, waiting for the choice of how their birthdays are shown.
    @State private var pickedContacts: [CNContact] = []

    /// A group of cards under its own heading.
    private struct CardSection: Identifiable {
        let id: String
        /// Nil for the events when they're the only cards ahead: no heading is needed then.
        let title: String?
        let items: [Countdown]
        /// Cards can be dragged into a new order; birthdays and Past keep an order of their own.
        let reorders: Bool
    }

    /// Pinned first, then the other days ahead, then birthdays (soonest first), then the ones kept in Past.
    private var sections: [CardSection] {
        let upcoming = countdowns.filter { !$0.isArchived }
        let pinned = upcoming.filter(\.isPinned)
        let events = upcoming.filter { !$0.isPinned && !$0.isBirthday }
        let birthdays = upcoming.filter { !$0.isPinned && $0.isBirthday }
            .sorted { $0.daysLeft() < $1.daysLeft() }
        // Kept after their day, latest first.
        let past = countdowns.filter(\.isArchived).sorted { $0.target() > $1.target() }
        let needsHeadings = !pinned.isEmpty || !birthdays.isEmpty
        return [
            CardSection(id: "pinned", title: "Pinned", items: pinned, reorders: true),
            CardSection(id: "events", title: needsHeadings ? "Events" : nil, items: events, reorders: true),
            CardSection(id: "birthdays", title: "Birthdays", items: birthdays, reorders: false),
            CardSection(id: "past", title: "Past", items: past, reorders: false),
        ]
        .filter { !$0.items.isEmpty }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
                ScrollView {
                    let shown = sections
                    let firstRows = Self.firstRows(of: shown)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, section in
                            if let title = section.title {
                                sectionHeading(title, id: section.id, count: section.items.count)
                                    .padding(.top, index == 0 ? 0 : 16)
                                    .waveIn(cardsShown,
                                            delay: arrival.delay(for: CardSlot(row: firstRows[index] - 1, column: 0)),
                                            from: arrival.edge)
                            }
                            if section.title == nil || !collapsed.contains(section.id) {
                                CardGridLayout {
                                    ForEach(section.items) { countdown in
                                        card(for: countdown, in: section.items, firstRow: firstRows[index],
                                             reorders: section.reorders)
                                            .cardSize(countdown.size)
                                    }
                                }
                                .transition(.blurReplace)
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
                closeSheets()
                path = [id]
                opened = nil
            }
            .onChange(of: linkTick) {
                closeSheets()
            }
            .sensoryFeedback(.selection, trigger: reorderTick)
            .sensoryFeedback(.selection, trigger: countdowns.map(\.sizeRaw))
            .sensoryFeedback(.selection, trigger: countdowns.map(\.styleRaw))
            .sensoryFeedback(.impact(weight: .light), trigger: countdowns.map(\.isArchived))
            .sensoryFeedback(.selection, trigger: countdowns.map(\.isPinned))
            .sensoryFeedback(.success, trigger: countdowns.map(\.doneDay)) { old, new in
                new.compactMap { $0 }.count > old.compactMap { $0 }.count
            }
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
                    // Asked once the picker is gone, so the two sheets don't collide.
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        pickedContacts = contacts
                    }
                }
            }
            .sheet(isPresented: Binding(get: { !pickedContacts.isEmpty }, set: { if !$0 { pickedContacts = [] } })) {
                BirthdayImportSheet(contacts: pickedContacts, existing: countdowns)
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
                if let id = archivedRecentlyID, let countdown = countdowns.first(where: { $0.id == id }) {
                    UndoToast(text: toastIsDone ? "Done" : "Moved to Past", tint: countdown.color.color) {
                        if toastIsDone {
                            undoDone(countdown)
                        } else {
                            setArchived(false, countdown)
                        }
                    }
                    .transition(.blurRise)
                }
            }
            .task(id: archivedRecentlyID) {
                guard archivedRecentlyID != nil else { return }
                // Cancelled when a newer toast replaces this one: then it must not clear that one.
                guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
                withAnimation { archivedRecentlyID = nil }
            }
        }
    }

    private var cardsShown: Bool {
        revealed == arrival.id
    }

    /// A section's heading; tapping it folds the section away (showing how many it holds) and back.
    private func sectionHeading(_ title: String, id: String, count: Int) -> some View {
        let isCollapsed = collapsed.contains(id)
        return Button {
            withAnimation(.smooth(duration: 0.4)) {
                if isCollapsed {
                    collapsed.remove(id)
                } else {
                    collapsed.insert(id)
                }
            }
            UserDefaults.standard.set(Array(collapsed), forKey: "collapsedUntilSections")
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                Spacer(minLength: 0)
                if isCollapsed {
                    Text("\(count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .transition(.blurReplace)
                }
            }
            .padding(.leading, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isCollapsed)
        .accessibilityHint(isCollapsed ? "Shows the \(title.lowercased())" : "Hides the \(title.lowercased())")
    }

    /// The row each section's first card lands on, counting the cards and headings above it, for the wave.
    private static func firstRows(of sections: [CardSection]) -> [Int] {
        var rows: [Int] = []
        var next = 0
        for section in sections {
            if section.title != nil {
                next += 1
            }
            rows.append(next)
            next = (CardGridLayout.slots(for: section.items.map(\.size), firstRow: next).last?.row ?? next - 1) + 1
        }
        return rows
    }

    private func card(for countdown: Countdown, in items: [Countdown], firstRow: Int = 0,
                      reorders: Bool = true) -> some View {
        let index = items.firstIndex(of: countdown) ?? 0
        let slot = CardGridLayout.slots(for: items.map(\.size), firstRow: firstRow)[index]
        // A just-added countdown blurs in on its own, without the wave.
        let isNew = !unrevealed.isEmpty
        return CountdownCard(countdown: countdown, isReshaping: reshaping.contains(countdown.id)) {
            path.append(countdown.id)
        } onCountSince: {
            converting = countdown
        } onArchive: {
            setArchived(true, countdown)
        } onDone: {
            markDone(countdown)
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
        // Dropping onto a card of another section, or of one with its own order, moves nothing.
        .onDrop(of: [.text], delegate: ReorderDropDelegate(target: countdown, items: reorders ? items : [],
                                                           dragged: $dragged, onMove: { reorderTick += 1 }) {
            saveChanges(context)
        })
    }

    /// A just-created countdown stays hidden while the editor sheet slides away, then the grid scrolls to it
    /// and it blurs in at its place.
    private func revealAdded(_ added: Set<UUID>, order: [UUID], scroller: ScrollViewProxy) {
        guard cardsShown, !added.isEmpty else { return }
        unrevealed = added
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            if let last = order.last(where: added.contains) {
                withAnimation(.smooth) { scroller.scrollTo(last, anchor: .center) }
            }
            try? await Task.sleep(for: .milliseconds(150))
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
            if countdown.isDone() {
                Button("Not Done", systemImage: "arrow.uturn.backward") {
                    undoDone(countdown)
                }
            } else if countdown.daysLeft() == 0 && !countdown.isArchived {
                Button("Mark as Done", systemImage: "checkmark.circle") {
                    markDone(countdown)
                }
            }
            if !countdown.isArchived {
                Button(countdown.isPinned ? "Unpin" : "Pin to Top", systemImage: countdown.isPinned ? "pin.slash" : "pin") {
                    setPinned(!countdown.isPinned, countdown)
                }
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

    /// Like on the Since tab: the content fades out while the card takes its new shape, then back in,
    /// and saving waits until the animation is done.
    private func setSize(_ size: CardSize, of countdown: Countdown) {
        let id = countdown.id
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard let target = countdowns.first(where: { $0.id == id }), target.size != size else { return }
            withAnimation(.easeOut(duration: 0.15)) { _ = reshaping.insert(id) }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.smooth(duration: 0.45)) { target.size = size }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.3)) { _ = reshaping.remove(id) }
            try? await Task.sleep(for: .milliseconds(300))
            saveChanges(context)
        }
    }

    private func closeSheets() {
        isAdding = false
        isShowingSettings = false
        isImportingCalendar = false
        isPickingContacts = false
        pickedContacts = []
        editing = nil
        deleting = nil
        converting = nil
    }

    private func setPinned(_ isPinned: Bool, _ countdown: Countdown) {
        let id = countdown.id
        // The menu closes first, then the card moves to its section.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard let target = countdowns.first(where: { $0.id == id }) else { return }
            withAnimation(.smooth(duration: 0.45)) { target.isPinned = isPinned }
            try? await Task.sleep(for: .milliseconds(450))
            saveChanges(context)
        }
    }

    private func setStyle(_ style: CountdownStyle, of countdown: Countdown) {
        let id = countdown.id
        // The menu closes first, then the card changes through a blur.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard let target = countdowns.first(where: { $0.id == id }) else { return }
            withAnimation(.smooth(duration: 0.45)) { target.style = style }
            // Saved once the blur is over, so refreshing widgets doesn't stutter it.
            try? await Task.sleep(for: .milliseconds(450))
            saveChanges(context)
        }
    }

    private func setArchived(_ isArchived: Bool, _ countdown: Countdown) {
        withAnimation(.smooth(duration: 0.45)) {
            countdown.isArchived = isArchived
            archivedRecentlyID = isArchived ? countdown.id : nil
            toastIsDone = false
        }
        saveChanges(context)
    }

    /// On the day: a repeating countdown moves on to its next time, a one-off one goes to Past.
    private func markDone(_ countdown: Countdown) {
        withAnimation(.smooth(duration: 0.45)) {
            countdown.markDone()
            archivedRecentlyID = countdown.id
            toastIsDone = true
        }
        saveChanges(context)
    }

    private func undoDone(_ countdown: Countdown) {
        withAnimation(.smooth(duration: 0.45)) {
            countdown.undoDone()
            archivedRecentlyID = nil
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
