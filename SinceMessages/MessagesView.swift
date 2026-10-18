import SwiftData
import SwiftUI
import UIKit

struct MessagesView: View {
    let container: ModelContainer
    let insert: @MainActor (UIImage, SharedMessageCard, MessageFormat) async throws -> Void
    let expand: () -> Void
    let collapse: () -> Void

    @State private var context: ModelContext?
    @State private var counters: [Counter] = []
    @State private var countdowns: [Countdown] = []
    @State private var search = ""
    @State private var creating = false
    @State private var sending = false
    @State private var selected: MessageCard?
    @State private var newlyCreated: MessageCard?
    @State private var previewImage: UIImage?
    @State private var inserted = false
    @State private var format: MessageFormat = .interactive
    @State private var shareLocation = true
    @State private var shareNote = false
    @State private var sharePickupCode = false
    @State private var preparing = false
    @State private var renderedPayload: SharedMessageCard?
    @State private var renderedKey = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("New Countdown", systemImage: "plus.circle.fill") {
                        expand()
                        creating = true
                    }
                }
                if !countdowns.isEmpty {
                    Section("Until") {
                        ForEach(countdowns.filter { matches($0.title) }) { countdown in
                            Button { preview(MessageCard(countdown)) } label: {
                                row(countdown.title, symbol: countdown.symbol, color: countdown.color,
                                    subtitle: countdown.dateLine())
                            }
                        }
                    }
                }
                if !counters.isEmpty {
                    Section("Since") {
                        ForEach(counters.filter { matches($0.title) }) { counter in
                            Button { preview(MessageCard(counter)) } label: {
                                row(counter.title, symbol: counter.symbol, color: counter.color,
                                    subtitle: "\(counter.days()) days · \(counter.kind.title)")
                            }
                        }
                    }
                }
                if counters.isEmpty && countdowns.isEmpty {
                    Text("Create a countdown here, or add counters in Since.").foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                    Button("Try Again") { reload() }
                }
            }
            .navigationTitle("Since")
            .searchable(text: $search, prompt: "Find a card")
            .task { reload() }
            .sheet(isPresented: $creating, onDismiss: {
                if let card = newlyCreated {
                    newlyCreated = nil
                    preview(card)
                }
            }) {
                MessageCountdownEditor { countdown in
                    reload()
                    newlyCreated = MessageCard(countdown)
                }
            }
            .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), onDismiss: {
                previewImage = nil
                if inserted {
                    inserted = false
                    collapse()
                }
            }) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Send As", selection: $format) {
                                ForEach(MessageFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if selected?.payload.locationLine != nil {
                                Toggle("Include Place and Map", isOn: $shareLocation)
                            }
                            if selected?.payload.note != nil { Toggle("Include Note", isOn: $shareNote) }
                            if selected?.payload.pickupCode != nil {
                                Toggle("Include Pickup Code", isOn: $sharePickupCode)
                            }
                        }
                        .padding().disabled(sending)
                        if preparing { ProgressView("Preparing card…").padding() }
                        if let previewImage {
                            Image(uiImage: previewImage).resizable().scaledToFit().padding()
                        }
                        if let error { Text(error).foregroundStyle(.red).padding() }
                        if let interactiveIssue { Text(interactiveIssue).font(.footnote).foregroundStyle(.orange).padding() }
                        Text(format == .interactive
                             ? "Tap the sent card to save it, open its place or track the parcel. Actions require Since; the preview stays readable as an image. Tap Send in Messages to share."
                             : "Adds a picture with the details shown above. Tap Send in Messages to share it.")
                            .font(.footnote).foregroundStyle(.secondary).padding()
                    }
                    .navigationTitle("Card Preview")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { selected = nil }.disabled(sending)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add to Message") { Task { await addCard() } }
                                .disabled(sending || preparing || renderedKey != previewKey || previewImage == nil
                                          || interactiveIssue != nil)
                        }
                    }
                }
                .interactiveDismissDisabled(sending)
                .task(id: previewKey) { await renderPreview() }
            }
        }
    }

    private var previewKey: String {
        "\(selected?.payload.id.uuidString ?? "")-\(shareLocation)-\(shareNote)-\(sharePickupCode)"
    }

    private var interactiveIssue: String? {
        guard format == .interactive, let renderedPayload else { return nil }
        do { _ = try renderedPayload.encodedURL(); return nil }
        catch { return error.localizedDescription }
    }

    private func preview(_ card: MessageCard) {
        error = nil
        previewImage = nil
        renderedPayload = nil
        renderedKey = ""
        sharePickupCode = false
        shareNote = false
        expand()
        selected = card
    }

    private func renderPreview() async {
        guard let selected else { return }
        let key = previewKey
        let payload = selected.payload.sharing(location: shareLocation, note: shareNote, pickupCode: sharePickupCode)
        preparing = true
        previewImage = nil
        defer { if previewKey == key { preparing = false } }
        let map = await MessageMap.image(for: payload)
        guard !Task.isCancelled, previewKey == key else { return }
        do {
            previewImage = try MessageCard(payload: payload, photo: selected.photo, mapImage: map).image()
            renderedPayload = payload
            renderedKey = key
        } catch { self.error = "Couldn’t prepare this card. Check its text and tracking link, then try again." }
    }

    private func row(_ title: String, symbol: String, color: CounterColor, subtitle: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(Color.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: symbol).foregroundStyle(color.color) }
    }

    private func matches(_ title: String) -> Bool {
        search.isEmpty || title.localizedCaseInsensitiveContains(search)
    }

    private func reload() {
        let context = ModelContext(container)
        self.context = context
        error = nil
        do {
            counters = try context.fetch(FetchDescriptor<Counter>(sortBy: [SortDescriptor(\.sortOrder)]))
                .filter { !$0.isGone }
            countdowns = try context.fetch(FetchDescriptor<Countdown>(sortBy: [SortDescriptor(\.sortOrder)]))
                .filter { !$0.isArchived && !$0.isTimer }
        } catch { self.error = "Couldn’t read the cards. Close and reopen Since in Messages." }
    }

    private func addCard() async {
        guard let previewImage, let renderedPayload, renderedKey == previewKey, !sending else { return }
        sending = true
        error = nil
        do {
            try await insert(previewImage, renderedPayload, format)
            inserted = true
            self.selected = nil
        } catch { self.error = error.localizedDescription }
        sending = false
    }
}

struct MessageCountdownEditor: View {
    let onCreated: (Countdown) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date.now
    @State private var hasTime = false
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("Exact Time", isOn: $hasTime)
                if hasTime { DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("New Countdown")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(saved || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard !saved else { return }
        do {
            let context = ModelContext(try Store.open())
            let rows = try context.fetch(FetchDescriptor<Countdown>())
            let countdown = Countdown(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                      symbol: "hourglass", color: .cyan, date: date,
                                      sortOrder: (rows.map(\.sortOrder).min() ?? 0) - 1)
            countdown.hasTime = hasTime
            context.insert(countdown)
            try ExtensionChanges.save(context)
            saved = true
            onCreated(countdown)
            dismiss()
        } catch { self.error = "Couldn’t save the countdown. Try again." }
    }
}
