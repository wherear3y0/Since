import AppIntents
import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Counter.sortOrder) private var counters: [Counter]

    /// A counter to open, set by a link from a widget or a notification.
    @Binding var opened: UUID?
    /// Each time the tab comes on screen, the cards blur in as a wave.
    let arrival: TabArrival
    /// Goes up with every link the app opens: the tab's sheets close then.
    var linkTick = 0

    @State private var path: [UUID] = []
    @State private var dragged: Counter?
    @State private var isAddingCounter = false
    @State private var isShowingSettings = false
    // Context menu actions.
    @State private var editingCounter: Counter?
    @State private var pastResetCounter: Counter?
    @State private var deletingCounter: Counter?
    @State private var lettingGo: Counter?
    @State private var undoable: UndoableReset?
    /// Restarts the toast's timer on every new action, even one on the same slip.
    @State private var toastTick = 0
    @State private var reorderTick = 0
    /// Ties each card to its detail screen for the zoom transition.
    @Namespace private var zoom
    /// The arrival whose wave has played; cards are hidden until it matches the current one.
    @State private var revealed: UUID?
    /// A just-created counter stays hidden until the editor sheet is gone, then blurs in at its place.
    @State private var unrevealed: Set<UUID> = []
    /// Cards changing size, their content faded out meanwhile.
    @State private var reshaping: Set<UUID> = []
    /// The grid's width, for laying out XL cards.
    @State private var gridWidth: CGFloat = 0
    /// Sections folded under their heading, remembered between launches. A @State, since stored changes
    /// don't animate; it's written back on every change.
    @State private var collapsed = Set(UserDefaults.standard.stringArray(forKey: "collapsedSinceSections") ?? [])

    /// A group of cards under its own heading.
    private struct CardSection: Identifiable {
        let id: String
        /// Nil for the counters when they're the only cards: no heading is needed then.
        let title: String?
        let items: [Counter]
        /// Cards can be dragged into a new order; Past keeps its own, the latest gone first.
        let reorders: Bool
    }

    /// The counters, then the things owned, then the owned things that are gone.
    private var sections: [CardSection] {
        let had = counters.filter { !$0.isGone }
        let owned = had.filter(\.isOwned)
        let past = counters.filter(\.isGone).sorted { ($0.goneDate ?? .distantPast) > ($1.goneDate ?? .distantPast) }
        return [
            CardSection(id: "counters", title: owned.isEmpty && past.isEmpty ? nil : "Counters",
                        items: had.filter { !$0.isOwned }, reorders: true),
            CardSection(id: "owned", title: "Owned", items: owned, reorders: true),
            CardSection(id: "past", title: "Past", items: past, reorders: false),
        ]
        .filter { !$0.items.isEmpty }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
                cardGrid(scroller: scroller)
            }
            .overlay {
                if counters.isEmpty {
                    ContentUnavailableView("No Counters", systemImage: "calendar",
                                           description: Text("Tap + to start counting days."))
                }
            }
            .navigationTitle("Since")
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
            .sensoryFeedback(.selection, trigger: counters.map(\.sizeRaw))
            .sensoryFeedback(.success, trigger: toastTick)
            .sensoryFeedback(trigger: counters.count) { old, new in
                new > old ? .success : .impact(weight: .medium)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Counter", systemImage: "plus") {
                        isAddingCounter = true
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let counter = counters.first(where: { $0.id == id }) {
                    Group {
                        if counter.isOwned {
                            OwnedDetailView(counter: counter) {
                                path.removeAll()
                            }
                        } else {
                            CounterDetailView(counter: counter) {
                                path.removeAll()
                            }
                        }
                    }
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
            }
            .sheet(isPresented: $isAddingCounter) {
                CounterEditor()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(item: $editingCounter) { counter in
                CounterEditor(counter: counter)
            }
            .sheet(item: $lettingGo) { counter in
                LetGoSheet(counter: counter)
            }
            .sheet(item: $pastResetCounter) { counter in
                ResetEditor(counter: counter, reset: nil) { entry in
                    addReset(to: counter, on: entry.date, note: entry.note, isSlip: entry.isSlip, amount: entry.amount)
                }
            }
            // An alert, not a confirmation dialog: on a grid a dialog's arrow would point at whichever card
            // happens to be under the toolbar rather than the one being deleted.
            .alert("Delete “\(deletingCounter?.title ?? "")”?",
                   isPresented: Binding(get: { deletingCounter != nil }, set: { if !$0 { deletingCounter = nil } })) {
                Button("Delete", role: .destructive) {
                    if let counter = deletingCounter {
                        withAnimation {
                            if undoable?.counter === counter {
                                undoable = nil
                            }
                            context.delete(counter)
                        }
                        saveChanges(context)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deletingCounter?.isOwned == true ? "It will be deleted, with its photo."
                                                      : "The counter and its whole reset history will be deleted.")
            }
            .overlay(alignment: .bottom) {
                if let undoable {
                    UndoToast(text: undoable.text, tint: undoable.counter.color.color) {
                        withAnimation {
                            if undoable.takesOne && undoable.reset.amount > 1 {
                                undoable.reset.amount -= 1
                                if let previous = undoable.previousDate {
                                    undoable.reset.date = previous
                                }
                            } else {
                                undoable.counter.resets.removeAll { $0 === undoable.reset }
                                context.delete(undoable.reset)
                            }
                            self.undoable = nil
                        }
                        saveChanges(context)
                    }
                    .transition(.blurRise)
                }
            }
            .task(id: toastTick) {
                guard undoable != nil else { return }
                // Cancelled when a newer toast replaces this one: then it must not clear that one.
                guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
                withAnimation { undoable = nil }
            }
        }
    }

    private func cardGrid(scroller: ScrollViewProxy) -> some View {
        ScrollView {
            let shown = sections
            let firstRows = CardGridLayout.firstRows(of: shown.map { ($0.title != nil, $0.items.map(\.size)) })
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, section in
                    sectionView(section, index: index, firstRow: firstRows[index])
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.pageBackground)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onChange(of: counters.map(\.id)) { old, new in
            revealAdded(Set(new).subtracting(old), order: new, scroller: scroller)
            // A counter deleted from its editor takes its toast with it.
            if let undoable, !new.contains(undoable.counterID) {
                self.undoable = nil
            }
        }
    }

    private var cardsShown: Bool {
        revealed == arrival.id
    }

    /// A section's heading, and its cards unless it's folded away.
    @ViewBuilder
    private func sectionView(_ section: CardSection, index: Int, firstRow: Int) -> some View {
        if let title = section.title {
            CardSectionHeading(title: title, id: section.id, count: section.items.count, collapsed: $collapsed,
                               storageKey: "collapsedSinceSections")
                .padding(.top, index == 0 ? 0 : 16)
                .waveIn(cardsShown, delay: arrival.delay(for: CardSlot(row: firstRow - 1, column: 0)),
                        from: arrival.edge)
        }
        if section.title == nil || !collapsed.contains(section.id) {
            CardGridLayout {
                ForEach(section.items) { counter in
                    card(for: counter, in: section.items, firstRow: firstRow, reorders: section.reorders)
                        .cardSize(counter.size)
                }
            }
            .transition(.blurReplace)
        }
    }

    private func card(for counter: Counter, in items: [Counter], firstRow: Int, reorders: Bool) -> some View {
        let index = items.firstIndex(of: counter) ?? 0
        let slot = CardGridLayout.slots(for: items.map(\.size), firstRow: firstRow)[index]
        // A just-added counter blurs in on its own, without the wave.
        let isNew = !unrevealed.isEmpty
        return CounterCard(counter: counter, gridWidth: gridWidth, isReshaping: reshaping.contains(counter.id)) {
            path.append(counter.id)
        }
        .waveIn(cardsShown && !unrevealed.contains(counter.id),
                delay: isNew ? 0 : arrival.delay(for: slot), from: isNew ? nil : arrival.edge)
        .id(counter.id)
        // Lets Siri tell which counter "this one" is.
        .appEntityIdentifier(EntityIdentifier(for: CounterEntity.self, identifier: counter.id))
        // The detail screen grows out of this card and shrinks back into it, following the
        // finger when it's swiped away, like an album in Apple Music.
        .matchedTransitionSource(id: counter.id, in: zoom) { source in
            source
                .background(.clear)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        // Outside the transition source: it clips to the card, which cut off the edge of a card swelling under a finger.
        .pressEffect(in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                     glow: counter.color.color.mix(with: .white, by: 0.5))
        .contextMenu {
            menu(for: counter)
        } preview: {
            CounterMenuPreview(counter: counter)
        }
        .onDrag {
            dragged = counter
            return NSItemProvider(object: counter.id.uuidString as NSString)
        }
        // Dropping onto a card of another section, or of Past, moves nothing.
        .onDrop(of: [.text], delegate: ReorderDropDelegate(target: counter, items: reorders ? items : [],
                                                           dragged: $dragged, onMove: { reorderTick += 1 }) {
            saveChanges(context)
        })
    }

    /// A just-created counter stays hidden while the editor sheet slides away, then the grid scrolls to it
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

extension HomeView {
    /// Long-press menu: quick actions in a row on top, then the rest, like Apple Music.
    @ViewBuilder
    private func menu(for counter: Counter) -> some View {
        let kind = counter.kind
        ControlGroup {
            Button("Edit", systemImage: "pencil") {
                editingCounter = counter
            }
            Button(counter.tinted ? "Plain" : "Tinted",
                   systemImage: counter.tinted ? "square.dashed" : "squareshape.on.pattern.diagonalline") {
                withAnimation { counter.tinted.toggle() }
                saveChanges(context)
            }
            Button(counter.notifyMilestones ? "Mute" : "Remind",
                   systemImage: counter.notifyMilestones ? "bell.slash" : "bell") {
                counter.notifyMilestones.toggle()
                saveChanges(context)
                if counter.notifyMilestones {
                    Task {
                        _ = await Milestones.requestPermission()
                        refreshMirrors(context)
                    }
                }
            }
        }

        SizeMenu(current: counter.size) { size in
            setSize(size, of: counter)
        }

        Section {
            Button("Open", systemImage: "arrow.up.forward") {
                path.append(counter.id)
            }
            if kind == .owned {
                if counter.isGone {
                    Button("Still Have It", systemImage: "arrow.uturn.backward") {
                        withAnimation(.smooth) { counter.keep() }
                        saveChanges(context)
                    }
                } else {
                    Button("Let Go…", systemImage: "hand.wave") {
                        lettingGo = counter
                    }
                }
            }
        }

        if kind != .owned {
            resetActions(for: counter)
        }

        Section {
            Button(kind == .owned ? "Delete" : "Delete Counter", systemImage: "trash", role: .destructive) {
                deletingCounter = counter
            }
        }
    }

    /// Resetting, slipping or logging a day, for the counters that have them.
    @ViewBuilder
    private func resetActions(for counter: Counter) -> some View {
        let kind = counter.kind
        Section {
            if kind == .quit {
                Button(counter.slipToday() == nil ? "Log a Slip" : "One More Slip Today",
                       systemImage: "arrow.uturn.backward") {
                    logSlip(on: counter)
                }
                .disabled(!counter.canSlipToday())
            }
            Button(kind.resetAction, systemImage: "arrow.counterclockwise",
                   role: kind == .quit ? .destructive : nil) {
                addReset(to: counter, on: .now, note: nil)
            }
            .disabled(counter.isDoneToday())
            Button("\(kind.addTitle)…", systemImage: "calendar.badge.plus") {
                pastResetCounter = counter
            }
        }
    }

    private func closeSheets() {
        isAddingCounter = false
        isShowingSettings = false
        editingCounter = nil
        pastResetCounter = nil
        deletingCounter = nil
        lettingGo = nil
    }

    /// The menu closes first. Then the card's content fades out, the card takes its new shape while the grid
    /// reflows around it, and the content, already laid out for the new size, fades back in. Saving waits
    /// until it's all done: it refreshes widgets, reminders and Spotlight, which would stutter the animation.
    private func setSize(_ size: CardSize, of counter: Counter) {
        let id = counter.id
        Task {
            // The menu has to be gone first: while it closes, iOS shows a copy of the card in its place,
            // and a change of shape under it only shows once the menu is gone, all at once.
            try? await Task.sleep(for: .milliseconds(700))
            guard let target = counters.first(where: { $0.id == id }), target.size != size else { return }
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

    private func addReset(to counter: Counter, on date: Date, note: String?, isSlip: Bool = false, amount: Int = 1) {
        let reset = Reset(date: date, note: note, isSlip: isSlip, amount: amount)
        withAnimation {
            counter.resets.append(reset)
            undoable = UndoableReset(counter: counter, counterID: counter.id, reset: reset, takesOne: false,
                                     previousDate: nil)
            toastTick += 1
        }
        saveChanges(context)
    }

    private func logSlip(on counter: Counter) {
        withAnimation {
            let logged = counter.logSlip()
            undoable = UndoableReset(counter: counter, counterID: counter.id, reset: logged.slip,
                                     takesOne: logged.addedToToday, previousDate: logged.previousDate)
            toastTick += 1
        }
        saveChanges(context)
    }
}

/// A reset or slip made from the home screen that the toast can still take back.
struct UndoableReset {
    let counter: Counter
    /// Kept apart, so it can be checked without touching a counter that may have been deleted.
    let counterID: UUID
    let reset: Reset
    /// One was added to today's slip: Undo takes it off instead of removing the slip.
    let takesOne: Bool
    /// The slip's time before one was added, which Undo puts back.
    let previousDate: Date?

    var text: String {
        guard reset.isSlip else { return counter.kind.toast }
        return takesOne ? "Slips today: \(reset.amount)" : "Slip logged"
    }
}

#Preview(traits: .sampleData) {
    HomeView(opened: .constant(nil), arrival: TabArrival())
}

#Preview("Dark", traits: .sampleData) {
    HomeView(opened: .constant(nil), arrival: TabArrival())
        .preferredColorScheme(.dark)
}
