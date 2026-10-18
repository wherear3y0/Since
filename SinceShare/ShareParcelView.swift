import SwiftData
import SwiftUI
import UIKit

struct ShareParcelView: View {
    let extensionContext: NSExtensionContext

    @State private var loading = true
    @State private var saving = false
    @State private var title = ""
    @State private var shop = ""
    @State private var number = ""
    @State private var carrierRaw = ""
    @State private var orderLink = ""
    @State private var date = Date.now
    @State private var hasWindow = false
    @State private var endDate = Date.now
    @State private var photo: Data?
    @State private var code = ""
    @State private var hasStorage = false
    @State private var storageUntil = Date.now
    @State private var pickupPoint: String?
    @State private var style: CountdownStyle = .calendar
    @State private var dateWasFound = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    ProgressView("Reading shared content…")
                } else {
                    Section {
                        if let photo, let image = UIImage(data: photo) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                                .frame(maxWidth: .infinity)
                        }
                        TextField("Parcel Name", text: $title)
                        TextField("Shop", text: $shop)
                        TextField("Tracking Number or Link", text: $number)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Picker("Carrier", selection: $carrierRaw) {
                            Text("Auto").tag("")
                            ForEach(Carrier.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        TextField("Order Link", text: $orderLink)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    if !ParcelTracking(number).isValid {
                        Text("Enter a tracking number or a valid http/https link.").foregroundStyle(.red)
                    }
                    Section {
                        DatePicker("Expected", selection: Binding(get: { date }, set: {
                            date = $0
                            dateWasFound = true
                        }), displayedComponents: .date)
                        Toggle("Delivery Window", isOn: $hasWindow)
                        if hasWindow {
                            DatePicker("Through", selection: $endDate, in: date..., displayedComponents: .date)
                        }
                        Picker("Style", selection: $style) {
                            ForEach(CountdownStyle.allCases) { Text($0.title).tag($0) }
                        }
                    } footer: {
                        if !dateWasFound {
                            Text("No delivery date was found. Choose the expected date before adding.")
                            Button("Use Today") {
                                date = .now
                                dateWasFound = true
                            }
                        }
                    }
                    Section("Pickup") {
                        TextField("Pickup Code", text: $code).keyboardType(.numberPad)
                        Toggle("Pickup Deadline", isOn: $hasStorage)
                        if hasStorage {
                            DatePicker("Kept Until", selection: $storageUntil, displayedComponents: .date)
                        }
                        if let pickupPoint { Text(pickupPoint).foregroundStyle(.secondary) }
                    }
                    if let error { Section { Text(error).foregroundStyle(.red) } }
                }
            }
            .navigationTitle("Add Parcel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { extensionContext.completeRequest(returningItems: nil) }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(loading || saving || !dateWasFound || !ParcelTracking(number).isValid
                                  || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { if loading { await load() } }
            .onChange(of: date) { _, new in if endDate < new { endDate = new } }
        }
    }

    private func load() async {
        let content = await ShareInput.read(extensionContext.inputItems.compactMap { $0 as? NSExtensionItem })
        let shared = ParcelShare(text: content.text, url: content.url)
        var draft = shared.draft
        if let image = content.image {
            let scanned = await ParcelScanner.scan(image)
            let found = scanned.draft
            draft.title = found.title ?? draft.title
            draft.shop = found.shop ?? draft.shop
            draft.trackingNumber = found.trackingNumber ?? draft.trackingNumber
            draft.carrier = found.carrier ?? draft.carrier
            draft.from = found.from ?? draft.from
            draft.to = found.to ?? draft.to
            draft.pickupCode = found.pickupCode ?? draft.pickupCode
            draft.storageUntil = found.storageUntil ?? draft.storageUntil
            draft.pickupPoint = found.pickupPoint ?? draft.pickupPoint
            photo = scanned.photo
        }
        title = draft.title ?? ""
        shop = draft.shop ?? ""
        number = shared.trackingURL?.absoluteString ?? draft.trackingNumber ?? ""
        carrierRaw = draft.carrier?.rawValue ?? ""
        orderLink = shared.orderURL?.absoluteString ?? ""
        date = draft.from ?? .now
        endDate = draft.to ?? date
        hasWindow = draft.to != nil
        dateWasFound = draft.from != nil
        code = draft.pickupCode ?? ""
        hasStorage = draft.storageUntil != nil
        storageUntil = draft.storageUntil ?? .now
        pickupPoint = draft.pickupPoint
        loading = false
    }

    private func save() {
        saving = true
        let context = ModelContext(Store.container)
        do {
            let rows = try context.fetch(FetchDescriptor<Countdown>())
            let parcel = Countdown(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                   symbol: "shippingbox.fill", color: .orange, date: date,
                                   sortOrder: (rows.map(\.sortOrder).min() ?? 0) - 1)
            parcel.isParcel = true
            parcel.style = style
            parcel.windowEnd = hasWindow ? max(date, endDate) : nil
            parcel.photoData = photo
            parcel.shopName = cleaned(shop)
            parcel.setTrackingInput(number)
            parcel.carrierRaw = carrierRaw
            let link = orderLink.trimmingCharacters(in: .whitespacesAndNewlines)
            if !link.isEmpty {
                guard let url = ParcelShare.webURL(URL(string: link)) else {
                    error = "Enter a valid http or https order link."
                    saving = false
                    return
                }
                parcel.orderURL = url.absoluteString
            }
            parcel.pickupCode = cleaned(code)
            parcel.storageUntil = hasStorage ? storageUntil : nil
            parcel.placeName = pickupPoint
            parcel.placeAddress = pickupPoint
            context.insert(parcel)
            try ExtensionChanges.save(context)
            Milestones.scheduleStorage(for: parcel)
            extensionContext.completeRequest(returningItems: nil)
        } catch {
            self.error = "Couldn’t save the parcel. Try again."
            saving = false
        }
    }

    private func cleaned(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
