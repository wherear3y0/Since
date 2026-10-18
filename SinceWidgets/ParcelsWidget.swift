import SwiftUI
import UIKit
import WidgetKit

/// A parcel on its way at one moment of the timeline: its countdown, and its picture made small.
struct ParcelSnapshot: Identifiable {
    let countdown: CountdownSnapshot
    let photo: UIImage?
    let shop: String?
    /// The last day a pickup point keeps it.
    let storageUntil: Date?

    var id: UUID { countdown.id }

    /// "Pick up by Oct 25" once it waits at a pickup point, else when it's due.
    var line: String {
        storageUntil.map { "Pick up by \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? countdown.dateLine
    }
}

extension ParcelSnapshot {
    init(_ parcel: Countdown, at date: Date) {
        self.init(countdown: CountdownSnapshot(parcel, at: date),
                  // Small, so a few of them stay well inside a widget's memory.
                  photo: parcel.photoData.flatMap(UIImage.init(data:))?.preparingThumbnail(of: CGSize(width: 300, height: 300)),
                  shop: parcel.shopName, storageUntil: parcel.storageUntil)
    }

    static func samples(at date: Date = .now) -> [ParcelSnapshot] {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: date)
        let rows: [(String, String, CounterColor, Int)] = [("Headphones", "headphones", .orange, 3),
                                                           ("Sneakers", "shoe.fill", .green, 6),
                                                           ("Lamp", "lamp.desk.fill", .yellow, 11)]
        return rows.map { title, symbol, color, days in
            ParcelSnapshot(countdown: CountdownSnapshot(id: UUID(), title: title, symbol: symbol, color: color,
                                                        tinted: true, style: .calendar,
                                                        target: calendar.date(byAdding: .day, value: days, to: today)!,
                                                        waitStart: calendar.date(byAdding: .day, value: -4, to: today)!,
                                                        date: date),
                           photo: nil, shop: "Ozon", storageUntil: nil)
        }
    }
}

struct ParcelsEntry: TimelineEntry {
    let date: Date
    let parcels: [ParcelSnapshot]
}

/// The parcels on their way, soonest first. Refreshes at local midnight.
struct ParcelsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ParcelsEntry {
        ParcelsEntry(date: .now, parcels: ParcelSnapshot.samples())
    }

    func getSnapshot(in context: Context, completion: @escaping (ParcelsEntry) -> Void) {
        let entry = entry(at: .now)
        completion(entry.parcels.isEmpty && context.isPreview ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ParcelsEntry>) -> Void) {
        completion(Timeline(entries: WidgetData.timelineDates().map(entry(at:)), policy: .atEnd))
    }

    private func entry(at date: Date) -> ParcelsEntry {
        let parcels = Store.countdowns()
            .filter { $0.isParcel && !$0.isArchived }
            .sorted { $0.target(now: date) < $1.target(now: date) }
            .prefix(4)
            .map { ParcelSnapshot($0, at: date) }
        return ParcelsEntry(date: date, parcels: parcels)
    }
}

/// The parcels on their way, each with its picture: the next one in small, three in medium, four in large.
struct ParcelsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ParcelsWidget", provider: ParcelsProvider()) { entry in
            ParcelsWidgetView(entry: entry)
                .containerBackground(Color.cardBackground, for: .widget)
        }
        .configurationDisplayName("Parcels")
        .description("The parcels on their way, with their pictures and the days until they come.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct ParcelsWidgetView: View {
    let entry: ParcelsEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.parcels.isEmpty {
            NoCountersView(text: "No parcels on the way")
                .padding()
        } else {
            switch family {
            case .systemSmall: small(entry.parcels[0])
            case .systemMedium: medium
            default: large
            }
        }
    }

    /// The next parcel: its picture across the top, edge to edge, and the days under it.
    private func small(_ parcel: ParcelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ParcelWidgetPicture(parcel: parcel)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                Text(parcel.countdown.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(parcel.countdown.tint)
                    .lineLimit(1)
                WidgetDaysLeft(parcel.countdown, size: 26)
                Text(parcel.line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .widgetURL(parcel.countdown.url)
    }

    /// Three side by side: each its picture in a rounded square, the days and when under it.
    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(entry.parcels.prefix(3)) { parcel in
                Link(destination: parcel.countdown.url) {
                    VStack(alignment: .leading, spacing: 4) {
                        ParcelWidgetPicture(parcel: parcel)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        WidgetDaysLeft(parcel.countdown, size: 20)
                        Text(parcel.line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // The same width for each, however many there are.
            ForEach(entry.parcels.count..<3, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .padding(14)
    }

    /// Up to four rows: the picture, the name and when, the days on the right.
    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Parcels", systemImage: "shippingbox.fill")
                .font(.headline)
            ForEach(entry.parcels.prefix(4)) { parcel in
                Link(destination: parcel.countdown.url) {
                    HStack(spacing: 12) {
                        ParcelWidgetPicture(parcel: parcel)
                            .frame(width: 62, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(parcel.countdown.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(parcel.countdown.tint)
                                .lineLimit(1)
                            Text([parcel.line, parcel.shop].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        WidgetDaysLeft(parcel.countdown, size: 24)
                            .fixedSize()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

/// A parcel's picture filling its frame, or its icon on its color.
struct ParcelWidgetPicture: View {
    let parcel: ParcelSnapshot

    var body: some View {
        Color.clear
            .overlay {
                if let photo = parcel.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        parcel.countdown.tint.opacity(0.16)
                        Image(systemName: parcel.countdown.symbol)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(parcel.countdown.tint)
                    }
                }
            }
            .clipped()
    }
}
