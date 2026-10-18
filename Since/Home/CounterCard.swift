import SwiftUI
import SwiftData

struct CounterCard: View {
    let counter: Counter
    /// The width of the grid the card is in, which sets how many weeks fit across an XL card.
    /// Known before the card turns XL, so its first layout is already the right one.
    var gridWidth: CGFloat = 0
    /// The card is changing size: its content is faded out meanwhile.
    var isReshaping = false
    let onOpen: () -> Void

    var body: some View {
        let tint = counter.color.color.onCard(tinted: counter.tinted)

        // A ZStack, not a Group: a Group would hand the frame below to each size's layout separately,
        // so a new size would fade in a new card instead of reshaping this one.
        ZStack(alignment: .topLeading) {
            switch counter.size {
            case .m: compact(tint: tint)
            case .l: wide(tint: tint)
            case .xl: large(tint: tint)
            }
        }
        .reshaping(isReshaping)
        .homeCard(size: counter.size, color: counter.color.color, tinted: counter.tinted, onOpen: onOpen)
    }

    /// The width of the grid; a typical iPhone's until it has been measured.
    private var rowWidth: CGFloat {
        gridWidth > 0 ? gridWidth : 361
    }

    // MARK: - Sizes

    /// M: title, number, date, and the last 7 weeks.
    private func compact(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title(tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                dayCount(size: 40)
                since
            }
            heatmap(weeks: 7, tint: tint)
        }
    }

    /// L: title and date on the left, number on the right, about three months of days underneath,
    /// in cells as big as an M card's, with weekday labels like XL.
    private func wide(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    title(tint: tint)
                    since
                }
                Spacer(minLength: 8)
                dayCount(size: 40)
            }
            HeatmapView(days: counter.heatmap(weeks: CardSize.l.weeksAcross(rowWidth: rowWidth)), tint: tint,
                        showsWeekdays: true, cellSize: CardSize.mCellSize(rowWidth: rowWidth), animated: false)
        }
    }

    /// XL: a big number, as many weeks of days as fit with weekday labels, progress toward the record, and stats.
    private func large(tint: Color) -> some View {
        let streaks = counter.streaks()
        let best = streaks.map(\.days).max() ?? 0
        let average = Int(counter.kind.average(of: streaks).rounded())
        let target = counter.kind == .quit ? best : average

        return VStack(alignment: .leading, spacing: 14) {
            title(tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                dayCount(size: 56)
                since
            }
            // Cells exactly as big as on an M card; the extra width holds more weeks instead.
            HeatmapView(days: counter.heatmap(weeks: CardSize.xl.weeksAcross(rowWidth: rowWidth)), tint: tint,
                        showsWeekdays: true, cellSize: CardSize.mCellSize(rowWidth: rowWidth), animated: false)
            if counter.isOwned {
                ownedFooter(tint: tint)
            } else {
                recordAndStats(target: target, best: best, average: average, tint: tint)
            }
        }
    }

    /// Toward its next whole year, then when it was got and when that year comes; or, once it's gone, why.
    @ViewBuilder
    private func ownedFooter(tint: Color) -> some View {
        let got = counter.startDate.formatted(date: .abbreviated, time: .omitted)
        if let next = counter.nextAnniversary() {
            let target = DayMath.days(from: counter.startDate, to: next.date)
            VStack(spacing: 8) {
                RecordPills(current: counter.days(), target: target, targetLabel: "\(next.years)y", tint: tint)
                RecordTrack(current: counter.days(), target: target, tint: tint, animated: false)
            }
            HStack(alignment: .top) {
                stat("Got", value: got)
                stat(next.years == 1 ? "A Year" : "\(next.years) Years",
                     value: next.date.formatted(.dateTime.month(.abbreviated).day()))
            }
        } else {
            HStack(alignment: .top) {
                stat("Got", value: got)
                stat(counter.goneReason?.title ?? "Gone",
                     value: (counter.goneDate ?? .now).formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    @ViewBuilder
    private func recordAndStats(target: Int, best: Int, average: Int, tint: Color) -> some View {
        Group {
            if target > 0 {
                VStack(spacing: 8) {
                    RecordPills(current: counter.days(), target: target,
                                targetLabel: counter.kind == .quit ? "Best" : "Avg", tint: tint)
                    RecordTrack(current: counter.days(), target: target, tint: tint, animated: false)
                }
            }
            HStack(alignment: .top) {
                stat(counter.kind.longest.capitalized, value: "\(best)d")
                // A counter that tracks money shows what's been saved instead of the average.
                if counter.tracksSavings && counter.price > 0 {
                    let saved = counter.savings.money(units: counter.savedUnits())
                    stat("Saved", value: saved.formatted(.currency(code: Savings.currencyCode).precision(.fractionLength(0))))
                } else {
                    stat("Average", value: "\(average)d")
                }
                stat(counter.kind.resetsTitle,
                     value: "\(counter.resets.count + (counter.kind == .quit ? counter.extraSlips : 0))")
            }
        }
    }

    // MARK: - Parts

    private func title(tint: Color) -> some View {
        PhotoCardTitle(title: counter.title, symbol: counter.symbol,
                       photo: counter.isOwned ? counter.photoData : nil, tint: tint)
    }

    @ViewBuilder
    private func dayCount(size: CGFloat) -> some View {
        let days = counter.days()
        if counter.numberStyle != .days {
            DurationPartsText(parts: counter.durationParts(), size: size)
        } else {
            daysText(days, size: size)
        }
    }

    private func daysText(_ days: Int, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(days, format: .number)
                .font(.system(size: size, weight: .bold))
                .contentTransition(.numericText(value: Double(days)))
            Text(days == 1 ? "day" : "days")
                .font(size > 44 ? .headline : .subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    /// "since Sep 2", or for an owned thing that's gone, "Sold · Oct 18, 2026".
    private var since: some View {
        Text(counter.goneLine ?? "since \(counter.currentStreakStart.sinceFormat)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            // A reset swaps the date through a blur.
            .id(counter.currentStreakStart)
            .transition(.blurReplace)
    }

    /// No wave on the home screen: it would replay every time a card comes back on screen.
    private func heatmap(weeks: Int, tint: Color) -> some View {
        HeatmapView(days: counter.heatmap(weeks: weeks), tint: tint, animated: false)
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What the card shrinks into above its context menu: the same layout as the small widget.
struct CounterMenuPreview: View {
    let counter: Counter

    var body: some View {
        let tint = counter.color.color.onCard(tinted: counter.tinted)
        let days = counter.days()
        let week = counter.recentDays(7)

        VStack(alignment: .leading, spacing: 0) {
            Group {
                if counter.isOwned && counter.photoData != nil {
                    HStack(spacing: 6) {
                        ItemPhoto(data: counter.photoData, symbol: counter.symbol, tint: tint, side: 18)
                        Text(counter.title)
                    }
                } else {
                    Label(counter.title, systemImage: counter.symbol)
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(days, format: .number)
                    .font(.system(size: 40, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(days == 1 ? "day" : "days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(counter.goneLine ?? "since \(counter.currentStreakStart.sinceFormat)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(week) { day in
                    WeekCell(day: day, tint: tint)
                }
            }
        }
        .padding(16)
        .frame(width: 170, height: 170, alignment: .leading)
        // The card keeps its edge as it lifts into the menu.
        .cardEdge(tint: tint)
        .background {
            if counter.tinted {
                ZStack {
                    Color.pageBackground
                    tint.opacity(0.17)
                }
            } else {
                SoftColorFill(tint: tint)
            }
        }
    }
}

/// One day of the small widget's week strip.
private struct WeekCell: View {
    let day: HeatmapDay
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            switch day.state {
            case .clean, .logged:
                shape.fill(tint)
            case .before:
                shape.fill(tint.opacity(0.18))
            case .slipped:
                shape.fill(tint.slippedDay)
            case .slip:
                shape.fill(tint.opacity(0.18))
                Circle().fill(tint).scaleEffect(0.34)
            case .future:
                Color.clear
            }
            if day.isToday {
                shape.strokeBorder(.primary.opacity(0.85), lineWidth: 1.5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Environment(\.modelContext) var context
    let counter = try! context.fetch(.init(sortBy: [SortDescriptor(\Counter.sortOrder)])).first!
    VStack(spacing: 12) {
        CounterCard(counter: counter, onOpen: {})
            .frame(width: 180, height: 290)
    }
    .padding()
}
