import EventKit
import MapKit
import SwiftUI

/// A place picked for a countdown: what it's called, its address, and where it is on the map.
struct PickedPlace: Equatable {
    var name: String
    var address: String?
    var coordinate: CLLocationCoordinate2D?

    static func == (lhs: PickedPlace, rhs: PickedPlace) -> Bool {
        lhs.name == rhs.name && lhs.address == rhs.address
            && lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
    }
}

extension PickedPlace {
    init(_ item: MKMapItem) {
        let address = item.address?.shortAddress ?? item.address?.fullAddress
        self.init(name: item.name ?? address ?? "Dropped Pin", address: address == item.name ? nil : address,
                  coordinate: item.location.coordinate)
    }

    /// The first place Apple Maps finds for some words, like the location of a Calendar event.
    static func search(_ text: String, near region: MKCoordinateRegion? = nil) async -> PickedPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let region {
            request.region = region
        }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        // Keep the words it was found by as its name: they're what was written in the event.
        var place = PickedPlace(item)
        if item.name != text {
            place.address = place.address ?? item.name
        }
        place.name = text.components(separatedBy: "\n").first ?? text
        return place
    }
}

/// Picks where a countdown happens: by searching Apple Maps as you type, from its Calendar event, or by tapping
/// a point on the map when there's no address (a dacha, a forest).
struct PlacePicker: View {
    @Environment(\.dismiss) private var dismiss

    /// The location written in the countdown's Calendar event, if it came from one.
    var calendarLocation: String?
    /// The place it has now, where the map starts.
    var current: PickedPlace?
    let tint: Color
    let onPick: (PickedPlace) -> Void

    @State private var search = PlaceSearch()
    @State private var text = ""
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var dropped: PickedPlace?
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            List {
                if text.isEmpty {
                    if let calendarLocation, !calendarLocation.isEmpty {
                        Section("From Calendar") {
                            Button {
                                pick(calendarLocation)
                            } label: {
                                row(title: calendarLocation, subtitle: nil, symbol: "calendar")
                            }
                        }
                    }
                    Section {
                        map
                            .frame(height: 260)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        Text("Or Tap the Map")
                    } footer: {
                        Text("For a place without an address.")
                    }
                } else {
                    Section {
                        ForEach(search.results, id: \.self) { result in
                            Button {
                                pick(result)
                            } label: {
                                row(title: result.title, subtitle: result.subtitle.isEmpty ? nil : result.subtitle,
                                    symbol: "mappin.circle.fill")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or Address")
            .onChange(of: text) { _, new in
                search.query = new
            }
            .overlay {
                if isResolving {
                    ProgressView()
                }
            }
            .onAppear {
                if let coordinate = current?.coordinate {
                    camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500,
                                                        longitudinalMeters: 1500))
                    dropped = current
                }
            }
            .navigationTitle("Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
                if let dropped {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use This Point", systemImage: "checkmark", role: .confirm) {
                            onPick(dropped)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let coordinate = dropped?.coordinate {
                    Marker(dropped?.name ?? "", coordinate: coordinate)
                        .tint(tint)
                }
                UserAnnotation()
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                drop(at: coordinate)
            }
        }
    }

    private func row(title: String, subtitle: String?, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                // Plain colors: in a button, `.primary` and `.secondary` take on the tint.
                Text(title)
                    .foregroundStyle(Color.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
                onPick(PickedPlace(item))
            } else {
                onPick(PickedPlace(name: completion.title, address: completion.subtitle.isEmpty ? nil : completion.subtitle))
            }
            isResolving = false
            dismiss()
        }
    }

    /// The Calendar event's location as written, placed on the map if Apple Maps can find it.
    private func pick(_ location: String) {
        isResolving = true
        Task {
            onPick(await PickedPlace.search(location) ?? PickedPlace(name: location))
            isResolving = false
            dismiss()
        }
    }

    /// A tap on the map: a pin there, named after what's at that spot.
    private func drop(at coordinate: CLLocationCoordinate2D) {
        dropped = PickedPlace(name: "Dropped Pin", coordinate: coordinate)
        Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first else { return }
            let address = item.address?.shortAddress ?? item.name
            dropped = PickedPlace(name: address ?? "Dropped Pin", address: nil, coordinate: coordinate)
        }
    }
}

/// Apple Maps' suggestions as you type.
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []

    var query = "" {
        didSet {
            completer.queryFragment = query
        }
    }

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        results = []
    }
}

extension Countdown {
    /// The location written in the Calendar event it came from, if any.
    @MainActor
    var calendarLocation: String? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess, let id = calendarItemID,
              let event = EKEventStore.shared.calendarItem(withIdentifier: id) as? EKEvent else { return nil }
        return event.location
    }

    func setPlace(_ place: PickedPlace?) {
        guard let place else {
            removePlace()
            return
        }
        if place.coordinate?.latitude != placeLatitude || place.coordinate?.longitude != placeLongitude {
            // The way there was worked out for the old place.
            travelMinutes = nil
        }
        placeName = place.name
        placeAddress = place.address
        coordinate = place.coordinate
    }

    var pickedPlace: PickedPlace? {
        hasPlace ? PickedPlace(name: placeName ?? "Dropped Pin", address: placeAddress, coordinate: coordinate) : nil
    }
}
