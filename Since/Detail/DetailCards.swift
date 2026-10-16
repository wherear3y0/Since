import SwiftUI
import Charts

// MARK: - Heatmap card

/// Big heatmap of the last weeks, with the day count and progress toward the best streak
/// (or, for "last time" counters, toward the usual gap) underneath.
struct HeatmapCard: View {
    let counter: Counter
    var animated = true

    private let weeks = 16

    var body: some View {
        let tint = counter.color.color.onCard(tinted: counter.tinted)
        let grid = counter.heatmap(weeks: weeks)
        let streaks = counter.streaks()
        let target = counter.kind == .quit
            ? streaks.map(\.days).max() ?? 0
            : Int(counter.kind.average(of: streaks).rounded())
        let showsSlips = grid.joined().contains { $0.state == .slip }

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HeatmapView(days: grid, tint: tint, showsWeekdays: true, animated: animated)
                if showsSlips {
                    SlipLegend(tint: tint)
                        .padding(.leading, 30)
                }
            }

            // Two rows, so each side lines up with the other: the pills sit on the "since" line,
            // the bar sits on the baseline of the big number.
            let targetLabel = counter.kind == .quit ? "Best" : "Avg"
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    // "since Sep 8, 2025" doesn't fit beside the pills; "since 9/8/25" does.
                    ViewThatFits(in: .horizontal) {
                        Text("since \(counter.currentStreakStart.sinceFormat)")
                        Text("since \(counter.currentStreakStart.formatted(date: .numeric, time: .omitted))")
                    }
                    .lineLimit(1)
                    .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        // A reset swaps the date through a blur.
                        .id(counter.currentStreakStart)
                        .transition(.blurReplace)
                    Spacer(minLength: 0)
                    if target > 0 {
                        RecordPills(current: counter.days(), target: target, targetLabel: targetLabel, tint: tint)
                            .frame(width: 170)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    DurationButton(from: counter.currentStreakStart, to: .now)
                    Spacer(minLength: 0)
                    if target > 0 {
                        RecordTrack(current: counter.days(), target: target, tint: tint, animated: animated)
                            .frame(width: 170)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}

/// What the gray squares and the dots on a heatmap with slips mean.
struct SlipLegend: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            item("Slip") {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(tint.opacity(0.18))
                    Circle().fill(tint).scaleEffect(0.34)
                }
            }
            item("Kept from before a slip") {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(tint.slippedDay)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func item<Square: View>(_ text: String, @ViewBuilder square: () -> Square) -> some View {
        HStack(spacing: 5) {
            square()
                .frame(width: 11, height: 11)
            Text(text)
                .lineLimit(1)
        }
    }
}

// MARK: - Progress

/// The progress since the last full reset: a slip starts the count again but doesn't undo the clean days.
struct ProgressCard: View {
    let counter: Counter

    var body: some View {
        let tint = counter.color.color
        // Today included, like the Summary's "Days tracked" and "Clean days" below.
        let tracked = counter.trackedDays() + 1
        let clean = counter.cleanDays(includingToday: true)
        let slips = counter.slipsSinceProgressStart
        let percent = Int((Double(clean) / Double(max(tracked, 1)) * 100).rounded())

        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: "Progress", symbol: "chart.line.uptrend.xyaxis", tint: tint,
                       text: insight(tracked: tracked, clean: clean, slips: slips))
            HStack(alignment: .top) {
                stat("Clean days", value: clean, tint: tint)
                stat("Slips", value: slips, tint: tint)
                stat("Overall", value: percent, unit: "%", tint: tint)
            }
            RecordTrack(current: clean, target: tracked, tint: tint)
        }
        .padding(.vertical, 8)
    }

    private func insight(tracked: Int, clean: Int, slips: Int) -> String {
        let since = counter.progressStart.formatted(date: .abbreviated, time: .omitted)
        if tracked <= 1 {
            return "Day one. Every clean day from here counts."
        }
        if slips == 0 {
            return "No slips since \(since). Every day so far counts."
        }
        return "\(clean) of \(tracked) days clean since \(since). A slip starts the count again, but doesn’t undo them."
    }

    private func stat(_ label: String, value: Int, unit: String? = nil, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value, format: .number)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: Double(value)))
                if let unit {
                    Text(unit)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Savings

/// Money, time and cigarettes (or cups, or drinks) saved over the clean days since the last full reset.
struct SavingsCard: View {
    let counter: Counter

    var body: some View {
        let tint = counter.color.color
        let savings = counter.savings
        let units = counter.savedUnits()
        let unit = counter.unitName.isEmpty ? "Not had" : counter.unitName.capitalized

        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: "Saved", symbol: "banknote.fill", tint: tint,
                       text: insight(days: counter.trackedDays(), slipped: counter.slippedAmountSinceProgressStart))
            HStack(alignment: .top) {
                if savings.price > 0 {
                    stat("Money", value: money(savings.money(units: units)), tint: tint)
                }
                if savings.minutesPerUnit > 0 {
                    stat("Time", value: Savings.timeText(minutes: savings.minutes(units: units)), tint: tint)
                }
                stat(unit, value: units.formatted(.number.precision(.fractionLength(0))), tint: tint)
            }
            if savings.price > 0 {
                Text("\(money(savings.moneyPerDay * 30)) a month, \(money(savings.moneyPerDay * 365)) a year.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func insight(days: Int, slipped: Int) -> String {
        let since = counter.progressStart.formatted(date: .abbreviated, time: .omitted)
        let over = switch days {
        case 0: "Counted from the first whole day since \(since)."
        case 1: "Over 1 day since \(since)."
        default: "Over \(days) days since \(since)."
        }
        guard slipped > 0 else { return over }
        let what = counter.unitName.isEmpty ? "" : " \(counter.unitName)"
        return "\(over) Less \(slipped)\(what) had in slips."
    }

    private func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: Savings.currencyCode).precision(.fractionLength(amount < 100 ? 2 : 0)))
    }

    private func stat(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Health

/// How the body recovers after the last cigarette. Folded, a ring of the steps behind and the next step;
/// tapped open, every step on a timeline. Whether it's open is remembered.
struct HealthCard: View {
    let counter: Counter

    /// Remembered between openings; the animation runs on a @State copy, since stored changes don't animate.
    @AppStorage("healthCardExpanded") private var storedExpanded = false
    @State private var isExpanded = UserDefaults.standard.bool(forKey: "healthCardExpanded")

    var body: some View {
        // The first steps are minutes and hours apart, so the card follows the clock while it's on screen.
        TimelineView(.everyMinute) { context in
            card(now: context.date)
        }
    }

    @ViewBuilder
    private func card(now: Date) -> some View {
        let tint = counter.color.color
        let start = counter.currentStreakStart
        let progress = HealthMilestone.progress(since: start, now: now)
        let total = HealthMilestone.smoking.count
        let overall = (Double(progress.reached.count) + (progress.next == nil ? 0 : progress.fraction)) / Double(total)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                HealthRing(fraction: overall, reached: progress.reached.count, total: total, tint: tint)
                    .frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Health", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundStyle(tint)
                    if let next = progress.next {
                        Text(next.text)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Next, \(next.date(from: start).formatted(.relative(presentation: .named, unitsStyle: .wide)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Every step is behind you.")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }

            if isExpanded {
                HealthTimeline(start: start, reached: Set(progress.reached.map(\.id)), nextID: progress.next?.id,
                               fraction: progress.fraction, tint: tint)
                    .padding(.top, 20)
                    .transition(.blurReplace.combined(with: .opacity))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.smooth(duration: 0.4)) { isExpanded.toggle() }
            storedExpanded = isExpanded
        }
        .sensoryFeedback(.selection, trigger: isExpanded)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Hides the steps" : "Shows every step")
    }
}

/// The steps behind, and the way to the next one, around a ring. Fills in once when it first appears.
private struct HealthRing: View {
    let fraction: Double
    let reached: Int
    let total: Int
    let tint: Color

    @State private var isShown = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: isShown ? max(0.02, min(1, fraction)) : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text(reached, format: .number)
                    .font(.title3.bold())
                Text("of \(total)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(3.5)
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.2).delay(0.25)) { isShown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reached) of \(total) steps behind")
    }
}

/// Every step, joined by a line: filled with a check once reached, a ring filling up for the next one,
/// hollow for the ones ahead.
private struct HealthTimeline: View {
    let start: Date
    let reached: Set<Int>
    let nextID: Int?
    let fraction: Double
    let tint: Color

    private enum StepState { case reached, next, ahead }

    var body: some View {
        let steps = HealthMilestone.smoking
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                let state: StepState = reached.contains(step.id) ? .reached : (step.id == nextID ? .next : .ahead)
                let isLast = index == steps.count - 1
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .top) {
                        if !isLast {
                            Rectangle()
                                .fill(lineColor(after: state, nextReached: reached.contains(steps[index + 1].id)))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                                .padding(.top, 24)
                        }
                        marker(state)
                    }
                    .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(step.when)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(state == .ahead ? Color.secondary : Color.primary)
                            Spacer(minLength: 8)
                            Text(dateText(of: step, state: state))
                                .font(.caption)
                                .foregroundStyle(state == .next ? tint : Color.secondary)
                        }
                        Text(step.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, isLast ? 0 : 16)
                }
                // The row takes the height of its text, and the line beside it stretches to that height.
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("From the WHO. It counts from the last slip or reset.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func marker(_ state: StepState) -> some View {
        switch state {
        case .reached:
            Circle()
                .fill(tint)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                }
                .frame(width: 22, height: 22)
        case .next:
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.03, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 22, height: 22)
        case .ahead:
            Circle()
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 2)
                .frame(width: 22, height: 22)
        }
    }

    /// The line down to the next step: colored once that one is reached, half-colored on the way to it.
    private func lineColor(after state: StepState, nextReached: Bool) -> Color {
        if nextReached {
            return tint
        }
        return state == .reached ? tint.opacity(0.4) : Color.secondary.opacity(0.25)
    }

    /// When a step was reached ("Oct 3"), or when it comes ("in 5 days").
    private func dateText(of step: HealthMilestone, state: StepState) -> String {
        let date = step.date(from: start)
        if state == .reached {
            return date.sinceFormat
        }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}

/// "16 days" between two days, big. Tapping it cycles 127 days → 18w 1d → 4m 5d, everywhere at once.
struct DurationButton: View {
    let from: Date
    let to: Date

    @AppStorage("durationStyle") private var styleRaw = DurationStyle.days.rawValue

    var body: some View {
        let style = DurationStyle(rawValue: styleRaw) ?? .days
        let parts = DayMath.parts(from: from, to: to, style: style)

        Button {
            withAnimation(.snappy) { styleRaw = style.next.rawValue }
        } label: {
            // Spelled out ("18 weeks 1 day") when it fits, short ("18w 1d") when it doesn't.
            ViewThatFits(in: .horizontal) {
                durationText(parts, long: true)
                durationText(parts, long: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: styleRaw)
        .accessibilityHint("Changes the format")
        .layoutPriority(1)
    }

    private func durationText(_ parts: [DurationPart], long: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ForEach(parts, id: \.unit) { part in
                let unit = long ? part.longUnit : part.unit
                HStack(alignment: .firstTextBaseline, spacing: unit.count > 1 ? 4 : 1) {
                    Text(part.value, format: .number)
                        .font(.system(size: 34, weight: .bold))
                        .contentTransition(.numericText(value: Double(part.value)))
                    Text(unit)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.interpolate)
                }
                // Switching 127 days → 18w 1d blurs the old parts out and the new ones in.
                .transition(.blurReplace)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// "Now 7d … Best 65d" — or "Record" once the current count matches the best.
struct RecordPills: View {
    let current: Int
    let target: Int
    let targetLabel: String
    let tint: Color

    var body: some View {
        // Matching or beating the best streak is worth calling out.
        let isRecord = targetLabel == "Best" && current >= target
        HStack(alignment: .firstTextBaseline) {
            pill("Now \(current)d")
            Spacer(minLength: 4)
            if isRecord {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                    Text("Record")
                }
                .font(.caption.bold())
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.black.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint, in: Capsule())
            } else {
                pill("\(targetLabel) \(target)d")
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.25), in: Capsule())
    }
}

/// A bar showing how far the current count is toward the target. Fills in once when it first appears.
struct RecordTrack: View {
    let current: Int
    let target: Int
    let tint: Color

    @State private var isShown: Bool

    init(current: Int, target: Int, tint: Color, animated: Bool = true) {
        self.current = current
        self.target = target
        self.tint = tint
        _isShown = State(initialValue: !animated)
    }

    var body: some View {
        let fraction = target == 0 ? 1 : min(1, Double(current) / Double(target))
        GeometryReader { proxy in
            let width = max(12, proxy.size.width * fraction * (isShown ? 1 : 0))
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.25))
                Capsule().fill(tint).frame(width: width)
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .offset(x: width - 10)
            }
        }
        .frame(height: 12)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.2).delay(0.3)) { isShown = true }
        }
    }
}

// MARK: - Streak timeline

/// One row per month, one bar per run of days without a reset.
struct StreakTimelineCard: View {
    let counter: Counter

    private enum Kind { case longest, current, past }

    private struct Segment: Identifiable {
        let id = UUID()
        let monthIndex: Int
        let from: Int
        let to: Int
        let kind: Kind
    }

    var body: some View {
        let tint = counter.color.color
        let (months, segments, hasSeparateCurrent, longest) = layout()
        // Rows are numbered from the bottom, so the oldest month (index 0) gets the highest row.
        let row = { (index: Int) in Double(months.count - 1 - index) }

        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: "\(counter.kind.period.capitalized) Timeline", symbol: "calendar", tint: tint,
                       text: counter.kind == .quit
                           ? "Days without a reset over the past year."
                           : "Days between entries over the past year.")

            Chart(segments) { segment in
                BarMark(
                    xStart: .value("From", Double(segment.from) - 0.45),
                    xEnd: .value("To", Double(segment.to) + 0.45),
                    y: .value("Month", row(segment.monthIndex)),
                    height: .fixed(7)
                )
                .cornerRadius(3.5)
                .foregroundStyle(color(for: segment.kind, tint: tint))
            }
            .chartYScale(domain: -0.5...Double(months.count) - 0.5)
            .chartXScale(domain: 0.5...31.5)
            .chartXAxis {
                AxisMarks(values: [1, 7, 14, 21, 28]) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel(anchor: .top)
                }
            }
            .chartYAxis {
                // Lines between months, labels centered on each month's row.
                AxisMarks(position: .leading, values: (0...months.count).map { Double($0) - 0.5 }) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                }
                AxisMarks(position: .leading, values: months.indices.map(row)) { value in
                    AxisValueLabel {
                        if let y = value.as(Double.self) {
                            Text(months[months.count - 1 - Int(y.rounded())])
                        }
                    }
                }
            }
            .frame(height: CGFloat(months.count) * 26 + 24)

            HStack(spacing: 16) {
                legendItem("\(counter.kind.longest) – \(longest) days", color: tint)
                if hasSeparateCurrent {
                    legendItem("Current", color: tint.opacity(0.5))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func color(for kind: Kind, tint: Color) -> Color {
        switch kind {
        case .longest: tint
        case .current: tint.opacity(0.5)
        case .past: Color.secondary.opacity(0.45)
        }
    }

    private func legendItem(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text)
        }
    }

    /// Month labels (oldest first), bar segments, whether the current run is drawn separately,
    /// and the length of the highlighted run, so the legend names the bar it highlights.
    private func layout() -> ([String], [Segment], Bool, Int) {
        let calendar = Calendar.app
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let runs = DayMath.cleanRuns(start: counter.startDate, resets: counter.resetDates, now: now)
        let lengths = runs.map { DayMath.days(from: $0.lowerBound, to: $0.upperBound) + 1 }
        // `<=` makes ties resolve to the latest run.
        let longestIndex = lengths.indices.max { lengths[$0] <= lengths[$1] }

        let thisMonth = calendar.dateInterval(of: .month, for: now)!.start
        let yearAgo = calendar.date(byAdding: .month, value: -11, to: thisMonth)!
        let startMonth = calendar.dateInterval(of: .month, for: counter.startDate)!.start
        let firstMonth = max(startMonth, yearAgo)

        var months: [String] = []
        var month = firstMonth
        while month <= thisMonth {
            months.append(month.formatted(.dateTime.month(.abbreviated)))
            month = calendar.date(byAdding: .month, value: 1, to: month)!
        }

        var segments: [Segment] = []
        for (index, run) in runs.enumerated() {
            let isCurrent = index == runs.count - 1 && run.upperBound == today
            let kind: Kind = index == longestIndex ? .longest : (isCurrent ? .current : .past)

            var monthStart = calendar.dateInterval(of: .month, for: run.lowerBound)!.start
            while monthStart <= run.upperBound {
                let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
                if monthStart >= firstMonth {
                    let from = max(run.lowerBound, monthStart)
                    let to = min(run.upperBound, monthEnd)
                    let monthIndex = calendar.dateComponents([.month], from: firstMonth, to: monthStart).month ?? 0
                    segments.append(Segment(monthIndex: monthIndex,
                                            from: calendar.component(.day, from: from),
                                            to: calendar.component(.day, from: to),
                                            kind: kind))
                }
                monthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            }
        }

        let currentIsSeparate = runs.last?.upperBound == today && longestIndex != runs.count - 1
        return (months, segments, currentIsSeparate, longestIndex.map { lengths[$0] } ?? 0)
    }
}

// MARK: - Weekdays

/// Which days of the week resets happen on.
struct WeekdaysCard: View {
    let counter: Counter

    var body: some View {
        let tint = counter.color.color
        let calendar = Calendar.app
        let resets = counter.resetDates
        // Weekday indices (0 = Sunday) in the order of the user's week.
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
        let counts = order.map { weekday in resets.filter { calendar.component(.weekday, from: $0) == weekday + 1 }.count }
        let weekends = resets.filter { calendar.isDateInWeekend($0) }.count
        let workdays = resets.count - weekends
        let maxCount = counts.max() ?? 0
        let busiest = counts.firstIndex(of: maxCount).map { calendar.standaloneWeekdaySymbols[order[$0]] }

        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: "Weekdays", symbol: "chart.bar.fill", tint: tint,
                       text: weekdayInsight(empty: resets.isEmpty, busiest: busiest ?? ""))

            if !resets.isEmpty {
                HStack(spacing: 14) {
                    Chart {
                        SectorMark(angle: .value("Resets", workdays), innerRadius: .ratio(0.68), angularInset: 2)
                            .cornerRadius(3)
                            .foregroundStyle(tint)
                        SectorMark(angle: .value("Resets", weekends), innerRadius: .ratio(0.68), angularInset: 2)
                            .cornerRadius(3)
                            .foregroundStyle(Color.secondary.opacity(0.35))
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 8) {
                        share("Workdays", count: workdays, total: resets.count, color: tint)
                        share("Weekends", count: weekends, total: resets.count, color: .secondary)
                    }

                    Chart {
                        ForEach(0..<7, id: \.self) { index in
                            BarMark(x: .value("Day", index), y: .value("Resets", counts[index]), width: .fixed(11))
                                .cornerRadius(3)
                                .foregroundStyle(counts[index] == maxCount ? tint : Color.secondary.opacity(0.35))
                        }
                    }
                    .chartXScale(domain: -0.6...6.6)
                    .chartXAxis {
                        AxisMarks(values: Array(0..<7)) { value in
                            AxisValueLabel(anchor: .top) {
                                if let index = value.as(Int.self) {
                                    Text(calendar.veryShortStandaloneWeekdaySymbols[order[index]])
                                }
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 84)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func weekdayInsight(empty: Bool, busiest: String) -> String {
        switch (counter.kind, empty) {
        case (.quit, true): "No resets yet."
        case (.quit, false): "Most resets happen on \(busiest)s."
        case (.lastTime, true): "Nothing logged yet."
        case (.lastTime, false): "Most often on \(busiest)s."
        }
    }

    private func share(_ label: String, count: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("\(Int((Double(count) / Double(max(total, 1)) * 100).rounded()))%")
                .font(.subheadline.bold())
                .padding(.leading, 13)
        }
    }
}

// MARK: - Summary

struct SummaryRow: View {
    let symbol: String
    let title: String
    var subtitle: String?
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

extension Date {
    /// "Today", "Yesterday", "2 weeks ago" — by calendar day, not by hours.
    var relativeDayDescription: String {
        let days = DayMath.days(from: self, to: .now)
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default:
            return Calendar.app.startOfDay(for: self).formatted(.relative(presentation: .numeric, unitsStyle: .wide))
        }
    }
}
