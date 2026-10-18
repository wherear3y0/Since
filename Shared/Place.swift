import CoreLocation
import Foundation

/// How to get to a countdown's place, for the travel time.
nonisolated enum TravelMode: String, CaseIterable, Identifiable {
    case car, transit, walk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .car: "By Car"
        case .transit: "By Transit"
        case .walk: "On Foot"
        }
    }

    var symbol: String {
        switch self {
        case .car: "car.fill"
        case .transit: "tram.fill"
        case .walk: "figure.walk"
        }
    }

    /// "by car", for a sentence.
    var phrase: String {
        switch self {
        case .car: "by car"
        case .transit: "by transit"
        case .walk: "on foot"
        }
    }
}

extension Countdown {
    var hasPlace: Bool {
        !(placeName ?? "").isEmpty || coordinate != nil
    }

    /// Where it is on the map, when that's known.
    var coordinate: CLLocationCoordinate2D? {
        get {
            guard let placeLatitude, let placeLongitude else { return nil }
            return CLLocationCoordinate2D(latitude: placeLatitude, longitude: placeLongitude)
        }
        set {
            placeLatitude = newValue?.latitude
            placeLongitude = newValue?.longitude
        }
    }

    var travelMode: TravelMode {
        get { TravelMode(rawValue: travelModeRaw) ?? .car }
        set { travelModeRaw = newValue.rawValue }
    }

    /// Clears the place and everything worked out from it.
    func removePlace() {
        placeName = nil
        placeAddress = nil
        coordinate = nil
        travelMinutes = nil
        remindsToLeave = false
    }

    /// Minutes to spare on top of the travel time: to get ready and find the door.
    static let leaveBuffer = 10

    /// When to set off to be there on time: its time, less the travel time and a few minutes to spare.
    /// Nil without a time or a travel time.
    func leaveTime(now: Date = .now, calendar: Calendar = .app) -> Date? {
        guard let moment = moment(now: now, calendar: calendar), let travelMinutes else { return nil }
        return moment.addingTimeInterval(-Double(travelMinutes + Self.leaveBuffer) * 60)
    }
}
