import SwiftUI
import Charts

/// Summary card: a sentence and the current and average streak. Tapping it unfolds `StreakPlot` below.
struct StreakSummary: View {
    let streaks: [Streak]
    var kind: CounterKind = .quit
    let tint: Color
    @Binding var isExpanded: Bool

    var body: some View {
        let current = streaks.last?.days ?? 0
        let average = kind.average(of: streaks)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    CardHeader(title: kind.periods, symbol: "chart.dots.scatter", tint: tint,
                               text: insight(current: current, average: average))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }

                Divider()

                HStack(alignment: .top) {
                    legend(label: "Current", value: current, color: tint)
                    legend(label: "Average", value: Int(average.rounded()), color: .secondary)
                }
            }

            // Always laid out and revealed by animating its visible height, so the card grows smoothly
            // while the chart comes in from a blur.
            StreakPlot(streaks: streaks, kind: kind, tint: tint, isShown: isExpanded)
                .blur(radius: isExpanded ? 0 : 12)
                .opacity(isExpanded ? 1 : 0)
                .frame(height: isExpanded ? 216 : 0, alignment: .top)
                .clipped()
                .padding(.top, isExpanded ? 16 : 0)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.smooth(duration: 0.45)) { isExpanded.toggle() }
        }
        .sensoryFeedback(.selection, trigger: isExpanded)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Hides the chart" : "Shows the chart")
    }


    private func legend(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(label)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value, format: .number)
                    .font(.system(size: 34, weight: .semibold))
                    .contentTransition(.numericText(value: Double(value)))
                Text(value == 1 ? "day" : "days")
                    .font(.headline)
            }
            .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insight(current: Int, average: Double) -> String {
        if streaks.count < 2 {
            return kind == .quit
                ? "No resets yet. Every day so far counts toward this streak."
                : "Nothing logged yet. Log it to start tracking the gaps."
        }
        let difference = Double(current) - average
        if abs(difference) < 1 {
            return "Your current \(kind.period) is right at your average."
        }
        switch (kind, difference > 0) {
        case (.quit, true): return "Your current streak is longer than your average."
        case (.quit, false): return "Your current streak is shorter than your average."
        case (.lastTime, true): return "It’s been longer than usual since the last time."
        case (.lastTime, false): return "Still within your usual gap."
        }
    }
}

/// One dot per streak: x = when it ended, y = how many days it lasted. The current streak is in the
/// counter's color, past ones in gray, joined by a thin line, with a dashed line at the average.
struct StreakPlot: View {
    let streaks: [Streak]
    var kind: CounterKind = .quit
    let tint: Color
    /// When this turns true the streaks rise from zero one by one, left to right.
    var isShown = true

    @State private var risen = 0

    var body: some View {
        let now = Date.now
        let average = kind.average(of: streaks)
        let maxDays = max(streaks.map(\.days).max() ?? 0, 7)
        let earliest = streaks.first?.start ?? now
        let weekAgo = Calendar.app.date(byAdding: .day, value: -6, to: now)!
        let domainStart = Calendar.app.startOfDay(for: min(earliest, weekAgo))

        Chart {
            // A thin line through the streaks, under the dots, so the trend reads at a glance.
            ForEach(streaks) { streak in
                LineMark(
                    x: .value("Ended", streak.isCurrent ? now : streak.end),
                    y: .value("Days", height(of: streak)),
                    series: .value("Series", "streaks")
                )
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
            ForEach(streaks) { streak in
                PointMark(
                    x: .value("Ended", streak.isCurrent ? now : streak.end),
                    y: .value("Days", height(of: streak))
                )
                .foregroundStyle(streak.isCurrent ? tint : Color.secondary)
                .symbolSize(streak.isCurrent ? 90 : 60)
                .accessibilityLabel(streak.isCurrent ? "Current streak" : "Streak ended \(streak.end.formatted(date: .abbreviated, time: .omitted))")
                .accessibilityValue("\(streak.days) days")
            }
            RuleMark(y: .value("Average", average))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .chartXScale(domain: domainStart...now, range: .plotDimension(padding: 16))
        .chartYScale(domain: 0...Double(maxDays) * 1.15)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .frame(height: 200)
        .padding(.vertical, 8)
        .task(id: isShown) {
            // On collapse the dots stay where they are while the chart blurs away. They drop back to
            // zero only as the next expand starts, while the chart is still fully transparent.
            guard isShown else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { risen = 0 }
            // About half a second for the whole sweep, however many streaks there are.
            let step = min(0.07, 0.5 / Double(max(streaks.count, 1)))
            for count in 1...max(streaks.count, 1) {
                try? await Task.sleep(for: .seconds(step))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) { risen = count }
            }
        }
    }

    /// Zero until the sweep reaches this streak, then its real length.
    private func height(of streak: Streak) -> Int {
        let index = streaks.firstIndex(of: streak) ?? 0
        return index < risen ? streak.days : 0
    }
}

/// Health-style card title: colored icon and title, then a sentence in the primary color.
struct CardHeader: View {
    let title: String
    let symbol: String
    let tint: Color
    var text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
            if let text {
                Text(text)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    @Previewable @State var isExpanded = true
    let now = Date.now
    let ago = { (n: Int) in Calendar.app.date(byAdding: .day, value: -n, to: now)! }
    let streaks = DayMath.streaks(start: ago(210), resets: [ago(160), ago(95), ago(41)], now: now)
    List {
        Section {
            StreakSummary(streaks: streaks, tint: .mint, isExpanded: $isExpanded)
        }
    }
}
