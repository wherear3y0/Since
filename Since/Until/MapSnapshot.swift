import MapKit
import SwiftUI

/// A small still map of a place with its marker, for cards: a picture rather than a live map, so a grid of
/// cards stays light. Drawn once per place, size and light or dark, and kept.
struct MapSnapshot: View {
    let coordinate: CLLocationCoordinate2D
    let symbol: String
    let tint: Color
    var height: CGFloat = 96

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.primary.opacity(0.06)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(tint, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
            .frame(width: size.width, height: size.height)
            .task(id: "\(coordinate.latitude),\(coordinate.longitude),\(Int(size.width)),\(colorScheme == .dark)") {
                guard size.width > 0 else { return }
                let snapshot = await Self.snapshot(of: coordinate, size: size, isDark: colorScheme == .dark,
                                                   scale: displayScale)
                withAnimation(.easeOut(duration: 0.3)) { image = snapshot }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    private static let cache = NSCache<NSString, UIImage>()

    private static func snapshot(of coordinate: CLLocationCoordinate2D, size: CGSize, isDark: Bool,
                                 scale: CGFloat) async -> UIImage? {
        let key = "\(coordinate.latitude),\(coordinate.longitude),\(Int(size.width))x\(Int(size.height)),\(isDark)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)
        options.size = size
        options.scale = scale
        options.traitCollection = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        guard let image = try? await MKMapSnapshotter(options: options).start().image else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
