import SwiftUI
import UIKit

/// A parcel on its page: its picture, the shop, the tracking number to copy, and Track and Order.
struct ParcelCard: View {
    let countdown: Countdown

    @Environment(\.openURL) private var openURL
    @State private var copied = false
    @State private var codeCopied = false

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

            if !countdown.isArchived {
                pickup(tint: tint)
            }

            if !countdown.trackingInput.isEmpty {
                let number = countdown.trackingInput
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
                            Text(countdown.parsedTracking.url?.host ?? number)
                                .font(.title3.monospaced().weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .textSelection(.enabled)
                            Text(countdown.parsedTracking.url != nil ? "Tracking link" : (countdown.carrier?.title ?? "Carrier unknown"))
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
                if countdown.parcelTrackingDestination != nil {
                    Button {
                        track()
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

            if copied && countdown.parsedTracking.url == nil && countdown.carrier?.takesNumber != true {
                Text("The number is copied: paste it on the page that opened.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.blurReplace)
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    /// The code to show at the pickup point, big, copied with a tap; and how long it's kept there.
    @ViewBuilder
    private func pickup(tint: Color) -> some View {
        if let code = countdown.spacedPickupCode {
            Button {
                UIPasteboard.general.string = countdown.pickupCode
                withAnimation(.smooth) { codeCopied = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.smooth) { codeCopied = false }
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(codeCopied ? "Copied" : "Pickup Code")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .contentTransition(.opacity)
                    Text(code)
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                }
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: codeCopied) { _, new in new }
        }
        if let left = countdown.storageDaysLeft(), let until = countdown.storageUntil {
            let day = until.formatted(.dateTime.month(.abbreviated).day())
            Label(left < 0 ? "It was kept until \(day): it may be on its way back."
                  : left == 0 ? "Today is the last day to pick it up."
                  : left == 1 ? "Kept until tomorrow, \(day)."
                  : "Kept until \(day), \(left) days left.",
                  systemImage: "clock.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(left <= 1 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
        }
    }

    /// The carrier's tracking page with the number; for an unknown carrier, the number is copied and
    /// a service that finds the carrier opens. A page that doesn't take the number gets it copied too.
    private func track() {
        guard let destination = countdown.parcelTrackingDestination else { return }
        if countdown.parsedTracking.url == nil, countdown.carrier?.takesNumber != true,
           let number = countdown.parsedTracking.number {
            UIPasteboard.general.string = number
            withAnimation(.smooth) { copied = true }
        }
        openURL(destination)
    }
}
