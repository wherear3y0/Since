import SwiftUI

/// Icon button (opens the symbol picker) next to the title field. Shared by both editors.
struct EditorTitleRow: View {
    @Binding var title: String
    let symbol: String
    let color: Color
    var isFocused: FocusState<Bool>.Binding
    let onPickSymbol: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPickSymbol) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
                    .background(Color.cardBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Icon")

            TextField("Title", text: $title)
                .font(.title3.weight(.semibold))
                .focused(isFocused)
                .submitLabel(.done)
                .padding(.horizontal, 20)
                .frame(height: 56)
                .background(Color.cardBackground, in: Capsule())
        }
    }
}

/// One scrolling row of swatches that blur out at the edges. Shared by both editors.
struct ColorRow: View {
    @Binding var color: CounterColor

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(CounterColor.allCases) { option in
                        let isSelected = option == color
                        Button {
                            withAnimation(.easeInOut(duration: 0.45)) { color = option }
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 42, height: 42)
                                .overlay {
                                    Circle()
                                        .fill(.white)
                                        .padding(11)
                                        .scaleEffect(isSelected ? 1 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                        // Swatches blur and fade as they slide past either edge. Worked out from where each one
                        // is drawn, so it's right from the first frame, after the row scrolls to the chosen color.
                        .visualEffect { content, proxy in
                            let hidden = Self.hiddenFraction(proxy)
                            return content
                                .blur(radius: hidden * 7)
                                .opacity(1 - hidden * 0.4)
                        }
                        .id(option)
                        .accessibilityLabel(option.rawValue.capitalized)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                // Room for the edge blur, so it isn't cut off flat at the top and bottom.
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                proxy.scrollTo(color, anchor: .center)
            }
        }
    }

    /// 0 for a swatch well inside the row, rising to 1 as its center reaches either edge,
    /// so the ends of the row always melt into a blur, however far it's scrolled.
    nonisolated private static func hiddenFraction(_ proxy: GeometryProxy) -> CGFloat {
        guard let visible = proxy.bounds(of: .scrollView) else { return 0 }
        let center = proxy.size.width / 2
        let distance = min(center - visible.minX, visible.maxX - center)
        // About one swatch wide.
        let zone: CGFloat = 46
        return min(1, max(0, (zone - distance) / zone))
    }
}

extension View {
    /// The live preview at the top of an editor: comes in from a blur once the sheet is on screen.
    func editorPreview(isShown: Bool) -> some View {
        self
            .blur(radius: isShown ? 0 : 18)
            .opacity(isShown ? 1 : 0.3)
            .scaleEffect(isShown ? 1 : 0.97)
            .animation(.easeOut(duration: 0.8), value: isShown)
            .accessibilityHidden(true)
    }
}
