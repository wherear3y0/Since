import MapKit
import UIKit

enum MessageMap {
    /// Only the event's saved coordinates; never asks for the phone's current location.
    static func image(for card: SharedMessageCard) async -> UIImage? {
        guard let latitude = card.latitude, let longitude = card.longitude,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1400, longitudinalMeters: 1400)
        options.size = CGSize(width: 304, height: 124)
        options.scale = 2
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll
        let snapshotter = MKMapSnapshotter(options: options)
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(3)); snapshotter.cancel() }
            catch { }
        }
        defer { timeout.cancel() }
        guard let snapshot = try? await snapshotter.start(), !Task.isCancelled else { return nil }
        return UIGraphicsImageRenderer(size: options.size).image { _ in
            snapshot.image.draw(in: CGRect(origin: .zero, size: options.size))
            let point = snapshot.point(for: coordinate)
            UIImage(systemName: "mappin.circle.fill")?.withTintColor(.systemCyan, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: point.x - 14, y: point.y - 28, width: 28, height: 28))
        }
    }
}
