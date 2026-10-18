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
    @State private var isAddingTimer = false
    @State private var isAddingParcel = false
    /// Timers that have just ended, playing their ending before they go.
    @State private var finishing: Set<UUID> = []
    @State private var isPickingContacts = false
    @State private var isImportingCalendar = false
    @State private var isShowingSettings = false
    // Context menu and card actions.
    @State private var editing: Countdown?
    @State private var deleting: Countdown?
    @State private var converting: Countdown?
    @State private var postponing: Countdown?
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

    /// Running timers first, then pinned, then the other days ahead, then birthdays (soonest first),
    /// then the ones kept in Past.
    private var sections: [CardSection] {
        let timers = countdowns.filter(\.isTimer).sorted { $0.date < $1.date }
        let upcoming = countdowns.filter { !$0.isArchived && !$0.isTimer }
        let pinned = upcoming.filter(\.isPinned)
        let events = upcoming.filter { !$0.isPinned && !$0.isBirthday && !$0.isSynced && !$0.isParcel }
        // On their way: soonest first.
        let parcels = upcoming.filter { !$0.isPinned && $0.isParcel && !$0.isSynced }
            .sorted { $0.target() < $1.target() }
        // Kept in step with Calendar and Reminders: soonest first, in sections of their own under Events.
        let fromCalendar = upcoming.filter { !$0.isPinned && !$0.isBirthday && $0.syncSource == .calendar }
            .sorted { $0.target() < $1.target() }
        let fromReminders = upcoming.filter { !$0.isPinned && $0.syncSource == .reminders }
            .sorted { $0.target() < $1.target() }
        let birthdays = upcoming.filter { !$0.isPinned && $0.isBirthday }
            .sorted { $0.daysLeft() < $1.daysLeft() }
        // Kept after their day, latest first.
        let past = countdowns.filter { $0.isArchived && !$0.isTimer }.sorted { $0.target() > $1.target() }
        let needsHeadings = !pinned.isEmpty || !birthdays.isEmpty || !timers.isEmpty || !fromCalendar.isEmpty
            || !parcels.isEmpty
            || !fromReminders.isEmpty
        return [
            CardSection(id: "timers", title: "Timers", items: timers, reorders: false),
            CardSection(id: "pinned", title: "Pinned", items: pinned, reorders: true),
            CardSection(id: "events", title: needsHeadings ? "Events" : nil, items: events, reorders: true),
            CardSection(id: "parcels", title: "Parcels", items: parcels, reorders: false),
            CardSection(id: "calendar", title: "Calendar", items: fromCalendar, reorders: false),
            CardSection(id: "reminders", title: "Reminders", items: fromReminders, reorders: false),
            CardSection(id: "birthdays", title: "Birthdays", items: birthdays, reorders: false),
            CardSection(id: "past", title: "Past", items: past, reorders: false),
        ]
        .filter { !$0.items.isEmpty }
    }

    // The body is split into parts the compiler checks one at a time: as one long chain of modifiers
    // it gave up on type-checking it.
    var body: some View {
        NavigationStack(path: $path) {
            presentations(feedback(navigation(grid)))
        }
    }

    /// The sections of cards, or the empty state.
    private var grid: some View {
        ScrollViewReader { scroller in
            ScrollView {
                let shown = sections
                let firstRows = CardGridLayout.firstRows(of: shown.map { ($0.title != nil, $0.items.map(\.size)) })
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, section in
                        sectionView(section, index: index, firstRow: firstRows[index])
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
    }

    /// A section's heading, and its cards unless it's folded away.
    @ViewBuilder
    private func sectionView(_ section: CardSection, index: Int, firstRow: Int) -> some View {
        if let title = section.title {
            CardSectionHeading(title: title, id: section.id, count: section.items.count, collapsed: $collapsed,
                               storageKey: "collapsedUntilSections")
                .padding(.top, index == 0 ? 0 : 16)
                .waveIn(cardsShown, delay: arrival.delay(for: CardSlot(row: firstRow - 1, column: 0)),
                        from: arrival.edge)
        }
        if section.title == nil || !collapsed.contains(section.id) {
            CardGridLayout {
                ForEach(section.items) { countdown in
                    card(for: countdown, in: section.items, firstRow: firstRow, reorders: section.reorders)
                        .cardSize(countdown.size)
                }
            }
            .transition(.blurReplace)
        }
    }

    /// The title, toolbar and detail screens, and opening a countdown from a link.
    private func navigation(_ content: some View) -> some View {
        content
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
            .toolbar { toolbarItems }
            .navigationDestination(for: UUID.self) { id in
                detail(for: id)
            }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
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
                Button("Timer", systemImage: "timer") {
                    isAddingTimer = true
                }
                Button("Parcel", systemImage: "shippingbox") {
                    isAddingParcel = true
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

    @ViewBuilder
    private func detail(for id: UUID) -> some View {
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

    /// Haptics for reordering, resizing, restyling, moving to Past, pinning, Done, adding and deleting.
    private func feedback(_ content: some View) -> some View {
        content
            .sensoryFeedback(.selection, trigger: reorderTick)
            .sensoryFeedback(.selection, trigger: countdowns.map(\.sizeRaw))
            .sensoryFeedback(.selection, trigger: countdowns.map(\.styleRaw))
            .sensoryFeedback(.impact(weight: .light), trigger: countdowns.map(\.isArchived))
            .sensoryFeedback(.selection, trigger: countdowns.map(\.isPinned))
            .sensoryFeedback(.success, trigger: doneCount) { old, new in
                new > old
            }
            .sensoryFeedback(trigger: countdowns.count) { old, new in
                new > old ? .success : .impact(weight: .medium)
            }
    }

    /// How many countdowns are marked done today, so marking one plays a haptic.
    private var doneCount: Int {
        countdowns.filter { $0.isDone() }.count
    }

    /// The sheets, the alerts and the undo toast.
    private func presentations(_ content: some View) -> some View {
        content
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
            .sheet(isPresented: isChoosingBirthdayFormat) {
                BirthdayImportSheet(contacts: pickedContacts, existing: countdowns)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isAddingTimer) {
                TimerSheet()
            }
            .sheet(isPresented: $isAddingParcel) {
                CountdownEditor(isParcel: true)
            }
            .sheet(item: $postponing) { countdown in
                PostponeSheet(countdown: countdown)
            }
            .sheet(item: $editing) { countdown in
                CountdownEditor(countdown: countdown)
            }
            .alert(deleteTitle, isPresented: isDeleting) {
                Button("Delete", role: .destructive) {
                    if let countdown = deleting {
                        SyncSettings.skip(countdown)
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
                toast
            }
            .task(id: countdowns.filter(\.isTimer).map(\.date)) {
                await endTimers()
            }
            .task(id: archivedRecentlyID) {
                guard archivedRecentlyID != nil else { return }
                // Cancelled when a newer toast replaces this one: then it must not clear that one.
                guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
                withAnimation { archivedRecentlyID = nil }
            }
    }

    private var isChoosingBirthdayFormat: Binding<Bool> {
        Binding(get: { !pickedContacts.isEmpty }, set: { if !$0 { pickedContacts = [] } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var deleteTitle: String {
        "Delete “\(deleting?.title ?? "")”?"
    }

    /// Undo for a countdown just moved to Past or marked done.
    @ViewBuilder
    private var toast: some View {
        if let id = archivedRecentlyID, let countdown = countdowns.first(where: { $0.id == id }) {
            UndoToast(text: toastIsDone ? (countdown.isParcel ? "Received" : "Done") : "Moved to Past", tint: countdown.color.color) {
                if toastIsDone {
                    undoDone(countdown)
                } else {
                    setArchived(false, countdown)
                }
            }
            .transition(.blurRise)
        }
    }

    private var cardsShown: Bool {
        revealed == arrival.id
    }

    private func card(for countdown: Countdown, in items: [Countdown], firstRow: Int = 0,
                      reorders: Bool = true) -> some View {
        let index = items.firstIndex(of: countdown) ?? 0
        let slot = CardGridLayout.slots(for: items.map(\.size), firstRow: firstRow)[index]
        // A just-added countdown blurs in on its own, without the wave.
        let isNew = !unrevealed.isEmpty
        return CountdownCard(countdown: countdown, isReshaping: reshaping.contains(countdown.id),
                             isFinishing: finishing.contains(countdown.id)) {
            // A timer has no page of its own.
            if !countdown.isTimer {
                path.append(countdown.id)
            }
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
    /// Long-press menu, laid out like the one on the Since tab. A timer's has just more time and Stop.
    @ViewBuilder
    private func menu(for countdown: Countdown) -> some View {
        if countdown.isTimer {
            timerMenu(for: countdown)
        } else {
            countdownMenu(for: countdown)
        }
    }

    @ViewBuilder
    private func timerMenu(for timer: Countdown) -> some View {
        Button("5 More Minutes", systemImage: "plus") {
            withAnimation(.smooth) { timer.date = max(timer.date, .now).addingTimeInterval(5 * 60) }
            saveChanges(context)
        }
        Button("Stop Timer", systemImage: "stop.fill", role: .destructive) {
            withAnimation(.smooth) { context.delete(timer) }
            saveChanges(context)
        }
    }

    @ViewBuilder
    private func countdownMenu(for countdown: Countdown) -> some View {
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
        // Buttons rather than a Picker, for the same reason as the size menu. A parcel's card is its picture.
        if !countdown.isParcel {
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
        }

        Section {
            Button("Open", systemImage: "arrow.up.forward") {
                path.append(countdown.id)
            }
            if countdown.isDone() {
                Button(countdown.isParcel ? "Not Received" : "Not Done", systemImage: "arrow.uturn.backward") {
                    undoDone(countdown)
                }
            } else if (countdown.isTheDay() || countdown.isParcel) && !countdown.isArchived {
                Button(countdown.isParcel ? "Received" : "Mark as Done", systemImage: "checkmark.circle") {
                    markDone(countdown)
                }
            }
            if countdown.isParcel && countdown.isArchived {
                Button("Add to Owned", systemImage: "bag.badge.plus") {
                    addToOwned(countdown)
                }
            }
            // A synced one follows its calendar; it's postponed there.
            if !countdown.rule.repeats && !countdown.isTimer && !countdown.isSynced {
                Button("Postpone…", systemImage: "calendar.badge.clock") {
                    postponing = countdown
                }
            }
            if !countdown.isArchived && !countdown.hasPassed() {
                LockScreenButton(countdown: countdown)
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
            // The menu has to be gone first, as on the Since tab.
            try? await Task.sleep(for: .milliseconds(700))
            guard let target = countdowns.first(where: { $0.id == id }), target.size != size else { return }
            withAnimation(.easeOut(duration: 0.15)) { _ = reshaping.insert(id) }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.smooth(duration: 0.45)) { target.size = size }
            // The content comes back once the card has its new shape, not while it's still changing.
            try? await Task.sleep(for: .milliseconds(450))
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

    /// Waits for the next timer to end, then lets it play its ending and go. Started again whenever
    /// a timer is added, extended or stopped.
    private func endTimers() async {
        let timers = countdowns.filter(\.isTimer)
        guard let next = timers.map(\.date).min() else { return }
        let wait = next.timeIntervalSinceNow
        if wait > 0 {
            guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
        }
        let ended = timers.filter { $0.date <= .now }
        withAnimation(.smooth) { finishing.formUnion(ended.map(\.id)) }
        guard (try? await Task.sleep(for: .seconds(1.6))) != nil else { return }
        withAnimation(.smooth(duration: 0.5)) {
            for timer in ended {
                context.delete(timer)
            }
            finishing.subtract(ended.map(\.id))
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
        RemindersBridge.setCompleted(true, for: countdown)
        saveChanges(context)
    }

    /// A parcel that came turns into a thing owned, which blurs in on the Since tab.
    private func addToOwned(_ countdown: Countdown) {
        let counters = (try? context.fetch(FetchDescriptor<Counter>())) ?? []
        context.insert(Counter(owning: countdown, sortOrder: (counters.map(\.sortOrder).max() ?? -1) + 1))
        if archivedRecentlyID == countdown.id {
            archivedRecentlyID = nil
        }
        context.delete(countdown)
        saveChanges(context)
        onCountedSince()
    }

    private func undoDone(_ countdown: Countdown) {
        withAnimation(.smooth(duration: 0.45)) {
            countdown.undoDone()
            archivedRecentlyID = nil
        }
        RemindersBridge.setCompleted(false, for: countdown)
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
        SyncSettings.skip(countdown)
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
