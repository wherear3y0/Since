import PhotosUI
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
            .blur(radius: isShown ? 0 : 12)
            .opacity(isShown ? 1 : 0.3)
            .scaleEffect(isShown ? 1 : 0.97)
            .animation(.easeOut(duration: 0.45), value: isShown)
            .accessibilityHidden(true)
    }
}

/// A round button under a countdown's date, like the ones under a new reminder: gray while off,
/// in the countdown's color once on. Turning one on brings up its setting underneath.
struct OptionChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                // Plain colors: inside a button, `.primary` and the like take on the button's tint.
                .foregroundStyle(isOn ? tint : Color.primary.opacity(0.75))
                .frame(width: 46, height: 46)
                .background(isOn ? tint.opacity(0.22) : Color.primary.opacity(0.08), in: Circle())
                .animation(.smooth(duration: 0.3), value: isOn)
        }
        // Borderless, so each chip in the row is its own button rather than the whole row being one.
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Picks a screenshot of an order or a receipt; the form fills in from it as soon as it's picked.
struct ScreenshotFillRow: View {
    @Binding var selection: PhotosPickerItem?
    let isScanning: Bool
    let note: String
    let tint: Color

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.18))
                    if isScanning {
                        ProgressView()
                            .tint(tint)
                    } else {
                        Image(systemName: "text.viewfinder")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isScanning ? "Reading…" : "Fill In from Screenshot")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isScanning)
        .padding(.vertical, 4)
    }
}

/// A thing's own picture, picked by hand apart from any screenshot: Choose or Change, and Remove.
struct ItemPhotoRow: View {
    let title: String
    @Binding var photoData: Data?
    let symbol: String
    let tint: Color

    @State private var item: PhotosPickerItem?

    var body: some View {
        let pick = photoData == nil ? "Choose" : "Change"
        HStack(spacing: 14) {
            ItemPhoto(data: photoData, symbol: symbol, tint: tint, side: 52)
            Text(title)
            Spacer(minLength: 8)
            if photoData != nil {
                Button("Remove Photo", systemImage: "trash", role: .destructive) {
                    withAnimation(.smooth) { photoData = nil }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            PhotosPicker(selection: $item, matching: .images) {
                Text(pick)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(tint)
        }
        .padding(.vertical, 4)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    withAnimation(.smooth) { photoData = ParcelScanner.smallPhoto(image) }
                }
                item = nil
            }
        }
    }
}
