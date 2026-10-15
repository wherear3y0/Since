import SwiftUI
import SwiftData

struct CounterCard: View {
    let counter: Counter
    let onOpen: () -> Void

    /// Width of an XL card's heatmap, which sets how many weeks fit across it.
    @State private var largeWidth: CGFloat = 334

    var body: some View {
        let tint = counter.color.color.onCard(tinted: counter.tinted)

        Group {
            switch counter.size {
            case .m: compact(tint: tint)
            case .l: wide(tint: tint)
            case .xl: large(tint: tint)
            }
        }
        .homeCard(size: counter.size, color: counter.color.color, tinted: counter.tinted, onOpen: onOpen)
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

    /// L: title and date on the left, number on the right, about three months of days underneath.
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
            heatmap(weeks: 14, tint: tint)
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
            let cell = CardSize.mCellSize(xlContentWidth: largeWidth)
            let weeks = max(Int((largeWidth - 30 + 3) / (cell + 3)), 1)
            HeatmapView(days: DayMath.heatmap(start: counter.startDate, resets: counter.resetDates, now: .now,
                                              weeks: weeks),
                        tint: tint, showsWeekdays: true, cellSize: cell, animated: false)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeWidth = $0 }
            if target > 0 {
                VStack(spacing: 8) {
                    RecordPills(current: counter.days(), target: target,
                                targetLabel: counter.kind == .quit ? "Best" : "Avg", tint: tint)
                    RecordTrack(current: counter.days(), target: target, tint: tint, animated: false)
                }
            }
            HStack(alignment: .top) {
                stat(counter.kind.longest.capitalized, value: "\(best)d")
                stat("Average", value: "\(average)d")
                stat(counter.kind.resetsTitle, value: "\(counter.resets.count)")
            }
        }
    }

    // MARK: - Parts

    private func title(tint: Color) -> some View {
        CardTitle(title: counter.title, symbol: counter.symbol, tint: tint)
    }

    private func dayCount(size: CGFloat) -> some View {
        let days = counter.days()
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(days, format: .number)
                .font(.system(size: size, weight: .bold))
                .contentTransition(.numericText(value: Double(days)))
            Text(days == 1 ? "day" : "days")
                .font(size > 44 ? .headline : .subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private var since: some View {
        Text("since \(counter.currentStreakStart.sinceFormat)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            // A reset swaps the date through a blur.
            .id(counter.currentStreakStart)
            .transition(.blurReplace)
    }

    /// No wave on the home screen: it would replay every time a card comes back on screen.
    private func heatmap(weeks: Int, tint: Color) -> some View {
        HeatmapView(days: DayMath.heatmap(start: counter.startDate, resets: counter.resetDates, now: .now, weeks: weeks),
                    tint: tint, animated: false)
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
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
        let week = DayMath.recentDays(7, start: counter.startDate, resets: counter.resetDates, now: .now)

        VStack(alignment: .leading, spacing: 0) {
            Label(counter.title, systemImage: counter.symbol)
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
            Text("since \(counter.currentStreakStart.sinceFormat)")
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
            case .clean: shape.fill(tint)
            case .before: shape.fill(tint.opacity(0.18))
            case .future: Color.clear
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
