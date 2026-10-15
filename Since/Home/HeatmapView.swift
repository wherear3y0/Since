import SwiftUI

/// A grid of the last weeks, one column per week: bright = a day of the current streak,
/// faint = before it, outline = today.
/// When `animated`, the filled cells sweep in from left to right on first appearance.
struct HeatmapView: View {
    let days: [[HeatmapDay]]
    let tint: Color
    var spacing: CGFloat = 3
    var showsWeekdays = false
    /// Fixed cell size; without it the cells stretch to fill the width.
    var cellSize: CGFloat?
    var startDelay: Double = 0

    @State private var revealed: Bool

    init(days: [[HeatmapDay]], tint: Color, spacing: CGFloat = 3, showsWeekdays: Bool = false,
         cellSize: CGFloat? = nil, animated: Bool = true, startDelay: Double = 0) {
        self.days = days
        self.tint = tint
        self.spacing = spacing
        self.showsWeekdays = showsWeekdays
        self.cellSize = cellSize
        self.startDelay = startDelay
        _revealed = State(initialValue: !animated)
    }

    var body: some View {
        let todayIndex = days.flatMap { $0 }.firstIndex(where: \.isToday) ?? 0
        HStack(spacing: spacing) {
            ForEach(Array(days.enumerated()), id: \.offset) { weekIndex, week in
                VStack(spacing: spacing) {
                    ForEach(Array(week.enumerated()), id: \.element.id) { dayIndex, day in
                        let index = weekIndex * 7 + dayIndex
                        cell(for: day,
                             delay: startDelay + Double(weekIndex) * 0.035 + Double(dayIndex) * 0.012,
                             wave: Double(abs(todayIndex - index)) * 0.012)
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
        .aspectRatio(CGFloat(days.count) / 7, contentMode: .fit)
        // Fixed-size cells keep to the trailing edge, so today's column lines up with the card's edge.
        .frame(maxWidth: cellSize == nil ? nil : .infinity, alignment: .trailing)
        // Labels sit in an overlay so they stretch to exactly the grid's height.
        .padding(.leading, showsWeekdays ? 30 : 0)
        .overlay(alignment: .leading) {
            if showsWeekdays {
                weekdayLabels
                    .frame(width: 26, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            revealed = true
        }
    }

    private var weekdayLabels: some View {
        let calendar = Calendar.app
        let symbols = calendar.shortWeekdaySymbols
        let ordered = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(ordered, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// `wave` is the delay for this cell when the grid changes, so a reset clears it in a sweep
    /// from today back into the past (and an undo fills it back in the same way).
    private func cell(for day: HeatmapDay, delay: Double, wave: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let lit = revealed && day.state == .clean
        return shape
            .fill(day.state == .future ? Color.clear : tint.opacity(0.18))
            .overlay {
                shape
                    .fill(tint)
                    .opacity(lit ? 1 : 0)
                    .scaleEffect(lit ? 1 : 0.3)
                    .blur(radius: lit ? 0 : 2)
            }
            .overlay {
                if day.isToday {
                    shape.strokeBorder(.primary.opacity(0.85), lineWidth: 1.5)
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.3).delay(delay), value: revealed)
            .animation(.spring(duration: 0.5, bounce: 0.25).delay(wave), value: day.state)
    }
}

#Preview {
    let now = Date.now
    let start = Calendar.app.date(byAdding: .day, value: -30, to: now)!
    let reset = Calendar.app.date(byAdding: .day, value: -9, to: now)!
    VStack(spacing: 30) {
        HeatmapView(days: DayMath.heatmap(start: start, resets: [reset], now: now), tint: .mint)
            .frame(width: 150)
        HeatmapView(days: DayMath.heatmap(start: start, resets: [reset], now: now, weeks: 16),
                    tint: .orange, showsWeekdays: true)
    }
    .padding()
}
