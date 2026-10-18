import SwiftUI
import UIKit

/// A parcel on its page: its picture, the shop, the tracking number to copy, and Track and Order.
struct ParcelCard: View {
    let countdown: Countdown

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        let tint = countdown.color.color

        VStack(alignment: .leading, spacing: 14) {
            if let data = countdown.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            CardHeader(title: "Parcel", symbol: "shippingbox.fill", tint: tint, text: countdown.shopName)

            if let number = countdown.trackingNumber {
                Button {
                    UIPasteboard.general.string = number
                    withAnimation(.smooth) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.smooth) { copied = false }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(number)
                                .font(.title3.monospaced().weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .textSelection(.enabled)
                            Text(countdown.carrier?.title ?? "Carrier unknown")
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer(minLength: 8)
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(tint)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                if let number = countdown.trackingNumber {
                    Button {
                        track(number)
                    } label: {
                        Label("Track", systemImage: "shippingbox.and.arrow.backward")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                }
                if let link = countdown.orderURL, let url = URL(string: link) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Order", systemImage: "bag")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .controlSize(.large)

            if copied && countdown.carrier?.takesNumber != true {
                Text("The number is copied: paste it on the page that opened.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.blurReplace)
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    /// The carrier's tracking page with the number; for an unknown carrier, the number is copied and
    /// a service that finds the carrier opens. A page that doesn't take the number gets it copied too.
    private func track(_ number: String) {
        if let carrier = countdown.carrier, let url = carrier.trackURL(number) {
            if !carrier.takesNumber {
                UIPasteboard.general.string = number
                withAnimation(.smooth) { copied = true }
            }
            openURL(url)
        } else {
            UIPasteboard.general.string = number
            withAnimation(.smooth) { copied = true }
            openURL(Carrier.lookUpURL)
        }
    }
}
