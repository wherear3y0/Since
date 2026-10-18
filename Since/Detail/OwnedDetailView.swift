import AppIntents
import SwiftUI
import SwiftData

/// An owned thing's page: its picture, the days it's been had, its next whole year, and letting it go.
struct OwnedDetailView: View {
    @Environment(\.modelContext) private var context

    let counter: Counter
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var isLettingGo = false
    /// The heatmap wave plays once per opening, not again when the card scrolls back into view.
    @State private var heatmapRevealed = false
    /// Turns true when the page opens; the blocks under the heatmap then blur in one after another.
    @State private var contentShown = false

    var body: some View {
        let tint = counter.color.color

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let data = counter.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        // Dimmed a little once it's gone.
                        .saturation(counter.isGone ? 0.4 : 1)
                }

                HeatmapCard(counter: counter, animated: !heatmapRevealed)
                    .onAppear { heatmapRevealed = true }
                    .detailCard {
                        if counter.tinted {
                            Color.cardBackground
                            tint.opacity(0.16)
                        } else {
                            SoftColorFill(tint: tint.onCard(tinted: false))
                        }
                    }

                if counter.isGone {
                    goneCard(tint: tint)
                        .detailCard()
                        .blurIn(contentShown, delay: 0.06)
                }

                Group {
                    sectionHeader("Summary")
                    summary
                        .detailCard(vertical: 4)
                }
                .blurIn(contentShown, delay: 0.12)

                if let note = counter.note {
                    sectionHeader("Note")
                    Text(note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .detailCard()
                }

                if !counter.isGone {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            isLettingGo = true
                        } label: {
                            Label("Let Go…", systemImage: "hand.wave")
                                .foregroundStyle(tint)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Color.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Text("Sold it, gave it away, or it broke: it goes to Past, with how long you had it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 4)
                    .blurIn(contentShown, delay: 0.18)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Color.pageBackground)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(counter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    ItemPhoto(data: counter.photoData, symbol: counter.symbol, tint: tint, side: 22)
                    Text(counter.title)
                }
                .font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .sensoryFeedback(.success, trigger: counter.isGone)
        .onAppear { contentShown = true }
        // Siri knows this is the thing on screen: "how long have I had this".
        .userActivity("me.wherar3y0.since.counter") { activity in
            activity.title = counter.title
            activity.appEntityIdentifier = EntityIdentifier(for: CounterEntity.self, identifier: counter.id)
        }
        .sheet(isPresented: $isEditing) {
            CounterEditor(counter: counter, onDelete: onDelete)
        }
        .sheet(isPresented: $isLettingGo) {
            LetGoSheet(counter: counter)
        }
    }

    /// Gone: how long it was had and why it left, and a way back if it's still had after all.
    private func goneCard(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: counter.goneReason?.title ?? "Gone", symbol: counter.goneReason?.symbol ?? "hand.wave",
                       tint: tint, text: "It was with you for \(counter.hadFor()). It’s kept in Past.")
            Button {
                withAnimation(.smooth) { counter.keep() }
                saveChanges(context)
            } label: {
                Label("Still Have It", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
    }

    private var summary: some View {
        var rows = [
            SummaryRow(symbol: "bag", title: "Got It",
                       subtitle: counter.startDate.formatted(date: .long, time: .omitted),
                       value: counter.startDate.relativeDayDescription),
            SummaryRow(symbol: "hourglass", title: counter.isGone ? "Had It For" : "With You For",
                       value: counter.hadFor()),
        ]
        if let next = counter.nextAnniversary() {
            let days = DayMath.days(from: .now, to: next.date)
            rows.append(SummaryRow(symbol: "gift", title: next.years == 1 ? "A Year" : "\(next.years) Years",
                                   subtitle: next.date.formatted(date: .long, time: .omitted),
                                   value: days == 0 ? "Today" : "in \(days) \(days == 1 ? "day" : "days")"))
        }
        if let goneDate = counter.goneDate {
            rows.append(SummaryRow(symbol: counter.goneReason?.symbol ?? "hand.wave",
                                   title: counter.goneReason?.title ?? "Gone",
                                   subtitle: goneDate.formatted(date: .long, time: .omitted),
                                   value: goneDate.relativeDayDescription))
        }

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().padding(.leading, 42)
                }
                row
                    .frame(minHeight: 44)
                    .padding(.vertical, 8)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}
