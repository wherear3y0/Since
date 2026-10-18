import SwiftUI
import UIKit

/// A readable fallback image and the preview of a native message, including explicitly selected details.
struct MessageCard: View {
    let payload: SharedMessageCard
    var photo: Data?
    var mapImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Since", systemImage: "hourglass").font(.subheadline.weight(.semibold))
                Spacer()
                Text(payload.sharedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption)
            }
            .foregroundStyle(.white.opacity(0.6))
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            Label(payload.title, systemImage: payload.symbol)
                .font(.title2.bold()).foregroundStyle(payload.color.color)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Text(payload.value())
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(.white).minimumScaleFactor(0.4).lineLimit(1)
            Text(payload.dateLine).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            if let summary = payload.summary { detail(summary, symbol: "chart.bar") }
            if let shop = payload.shop { detail(shop, symbol: "bag") }
            if let number = ParcelTracking(payload.trackingInput ?? "").number {
                detail(number, symbol: "shippingbox")
            } else if let host = payload.trackURL?.host {
                detail(host, symbol: "link")
            }
            if let until = payload.storageUntil {
                detail("Pick up by \(until.formatted(date: .abbreviated, time: .omitted))", symbol: "clock")
            }
            if let code = payload.pickupCode { detail("Pickup code: \(code)", symbol: "number") }
            if let mapImage {
                Image(uiImage: mapImage).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if let location = payload.locationLine { detail(location, symbol: "mappin.and.ellipse") }
            if let note = payload.note, !note.isEmpty { detail(note, symbol: "text.alignleft") }
        }
        .padding(28)
        .frame(width: 360, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28).fill(Color(red: 0.06, green: 0.07, blue: 0.09))
            RoundedRectangle(cornerRadius: 28).fill(payload.color.color.opacity(0.12))
        }
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
    }

    private func detail(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline).foregroundStyle(.white.opacity(0.75))
            .lineLimit(5).fixedSize(horizontal: false, vertical: true)
    }

    init(payload: SharedMessageCard, photo: Data? = nil, mapImage: UIImage? = nil) {
        self.payload = payload
        self.photo = photo
        self.mapImage = mapImage
    }

    init(_ counter: Counter) { self.init(payload: SharedMessageCard(counter), photo: counter.photoData) }
    init(_ countdown: Countdown) { self.init(payload: SharedMessageCard(countdown), photo: countdown.photoData) }

    @MainActor
    func image() throws -> UIImage {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        guard let image = renderer.uiImage else { throw MessageCardError.renderFailed }
        return image
    }
}
