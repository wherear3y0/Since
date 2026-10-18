import SwiftData
import SwiftUI
import UIKit

struct ReceivedMessageView: View {
    let card: SharedMessageCard
    let image: UIImage?
    let onBack: () -> Void
    @State private var alreadySaved = false
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().listRowInsets(EdgeInsets())
                }
                Section {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        LabeledContent(card.title, value: card.value(now: timeline.date))
                    }
                    Text(card.dateLine).foregroundStyle(.secondary)
                    if let location = card.locationLine { Label(location, systemImage: "mappin.and.ellipse") }
                }
                Section {
                    Button(alreadySaved ? "Already in Since" : "Save to My Since", systemImage: "plus.circle") {
                        save()
                    }
                    .disabled(alreadySaved)
                    if let url = card.mapsURL { Link(destination: url) { Label("Open Maps", systemImage: "map") } }
                    if let url = card.trackURL {
                        Link(destination: url) { Label("Track Parcel", systemImage: "shippingbox") }
                    }
                    if let number = ParcelTracking(card.trackingInput ?? "").number {
                        Button(copied ? "Copied" : "Copy Tracking Number", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = number
                            copied = true
                        }
                    }
                } footer: {
                    Text("A snapshot shared in chat. Saving creates your own item; changes here do not update the sender’s item.")
                }
                if let note = card.note { Section("Note") { Text(note) } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Since Card")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Your Cards", action: onBack) } }
            .task {
                do { alreadySaved = try SharedMessageImport.contains(card, in: ModelContext(Store.container)) }
                catch { self.error = "Couldn’t check the saved cards." }
            }
        }
    }

    private func save() {
        let context = ModelContext(Store.container)
        do {
            try SharedMessageImport.save(card, in: context)
            alreadySaved = true
            if card.isParcel {
                let id = card.id
                if let parcel = try context.fetch(FetchDescriptor<Countdown>(predicate: #Predicate { $0.id == id })).first {
                    Milestones.scheduleStorage(for: parcel)
                }
            }
        } catch { self.error = "Couldn’t save this card. Try again." }
    }
}
