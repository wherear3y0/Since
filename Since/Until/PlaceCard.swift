import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Where a countdown happens: the map, directions in the maps app of your choice, how long it takes to get
/// there from where you are, and a reminder when it's time to set off.
struct PlaceCard: View {
    @Environment(\.modelContext) private var context
    let countdown: Countdown

    @State private var isWorkingOut = false
    @State private var locationDenied = false
    /// Apple Maps didn't know the way this way (transit isn't everywhere).
    @State private var noWay = false

    var body: some View {
        let tint = countdown.color.color

        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Place", symbol: "mappin.and.ellipse", tint: tint, text: countdown.placeName)
            if let address = countdown.placeAddress {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, -8)
            }

            // A picture, not a live map: next to the time ticking down on the day, a live map was made
            // again on every tick and froze the page. Tapping it shows the place in Apple Maps.
            if let coordinate = countdown.coordinate {
                MapSnapshot(coordinate: coordinate, symbol: countdown.symbol, tint: tint, height: 170)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude,
                                                                  longitude: coordinate.longitude), address: nil)
                        item.name = countdown.placeName
                        item.openInMaps()
                    }
            }

            HStack(spacing: 8) {
                DirectionsMenu(countdown: countdown)
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                Button {
                    workOutTravelTime()
                } label: {
                    Label(countdown.travelMinutes == nil ? "How Long?" : "Update", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(countdown.coordinate == nil || isWorkingOut)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .controlSize(.large)

            if isWorkingOut {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if locationDenied {
                Text("Since needs your location to work out the way there. Turn it on in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if noWay {
                VStack(alignment: .leading, spacing: 12) {
                    modePicker
                    Text("Apple Maps doesn’t know the way \(countdown.travelMode.phrase) from here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .transition(.blurReplace)
            } else if let minutes = countdown.travelMinutes {
                travel(minutes: minutes, tint: tint)
                    .transition(.blurReplace)
            }
        }
        .padding(.vertical, 8)
        .task(id: countdown.placeName) {
            await findOnMap()
        }
        .sensoryFeedback(.selection, trigger: countdown.travelMode)
        .sensoryFeedback(.success, trigger: countdown.travelMinutes)
    }

    @ViewBuilder
    private func travel(minutes: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            modePicker

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Self.duration(minutes)) \(countdown.travelMode.phrase)")
                        .font(.title3.bold())
                        .contentTransition(.numericText())
                    Text("from where you are now")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let leave = countdown.leaveTime() {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(leave.formatted(date: .omitted, time: .shortened))
                            .font(.title3.bold())
                            .foregroundStyle(tint)
                        Text("leave by")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if countdown.moment() != nil {
                Toggle("Remind When to Leave", isOn: remindsToLeave)
                    .tint(tint)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var modePicker: some View {
        Picker("How", selection: travelMode) {
            ForEach(TravelMode.allCases) { mode in
                Image(systemName: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var travelMode: Binding<TravelMode> {
        Binding {
            countdown.travelMode
        } set: { mode in
            countdown.travelMode = mode
            workOutTravelTime()
        }
    }

    private var remindsToLeave: Binding<Bool> {
        Binding {
            countdown.remindsToLeave
        } set: { isOn in
            countdown.remindsToLeave = isOn
            saveChanges(context)
            if isOn {
                Task {
                    _ = await Milestones.requestPermission()
                    refreshMirrors(context)
                }
            }
        }
    }

    /// "25 min", "1 h 10 min".
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
    }

    /// A place known only by name (from a Calendar event) is looked up once and kept.
    private func findOnMap() async {
        guard countdown.coordinate == nil, let name = countdown.placeName, !name.isEmpty,
              let found = await PickedPlace.search(name) else { return }
        withAnimation(.smooth) {
            countdown.coordinate = found.coordinate
            countdown.placeAddress = countdown.placeAddress ?? found.address
        }
        saveChanges(context)
    }

    /// Asks where you are (only now, when tapped) and how long the way takes from there.
    private func workOutTravelTime() {
        guard let destination = countdown.coordinate else { return }
        withAnimation(.smooth) {
            isWorkingOut = true
            locationDenied = false
        }
        Task {
            let minutes: Int?
            if let here = await CurrentLocation.get() {
                minutes = await Travel.minutes(from: here, to: destination, mode: countdown.travelMode,
                                               arriving: countdown.moment())
            } else {
                minutes = nil
                locationDenied = CurrentLocation.isDenied
            }
            withAnimation(.smooth) {
                // An old time for another way of getting there would be wrong.
                countdown.travelMinutes = minutes
                noWay = minutes == nil && !locationDenied
                if minutes == nil {
                    countdown.remindsToLeave = false
                }
                isWorkingOut = false
            }
            saveChanges(context)
        }
    }
}

/// Directions in Apple Maps, Yandex Maps or Google Maps: whichever are on the iPhone. With only Apple Maps,
/// it opens right away.
struct DirectionsMenu: View {
    let countdown: Countdown

    @State private var isChoosing = false

    var body: some View {
        Button {
            if otherApps.isEmpty {
                openAppleMaps()
            } else {
                isChoosing = true
            }
        } label: {
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .frame(maxWidth: .infinity)
                .foregroundStyle(.black.opacity(0.8))
        }
        .disabled(countdown.coordinate == nil && (countdown.placeName ?? "").isEmpty)
        .confirmationDialog("Directions", isPresented: $isChoosing) {
            Button("Apple Maps") {
                openAppleMaps()
            }
            ForEach(otherApps, id: \.name) { app in
                Button(app.name) {
                    UIApplication.shared.open(app.url)
                }
            }
        }
    }

    /// The other maps apps on the iPhone that can take directions there.
    private var otherApps: [(name: String, url: URL)] {
        [("Yandex Maps", yandexURL), ("Google Maps", googleURL)].compactMap { app in
            guard let url = app.1, UIApplication.shared.canOpenURL(url) else { return nil }
            return (app.0, url)
        }
    }

    private var yandexURL: URL? {
        guard let coordinate = countdown.coordinate else { return nil }
        return URL(string: "yandexmaps://maps.yandex.ru/?rtext=~\(coordinate.latitude),\(coordinate.longitude)&rtt=\(yandexMode)")
    }

    private var googleURL: URL? {
        guard let coordinate = countdown.coordinate else { return nil }
        return URL(string: "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=\(googleMode)")
    }

    private var yandexMode: String {
        switch countdown.travelMode {
        case .car: "auto"
        case .transit: "mt"
        case .walk: "pd"
        }
    }

    private var googleMode: String {
        switch countdown.travelMode {
        case .car: "driving"
        case .transit: "transit"
        case .walk: "walking"
        }
    }

    private func openAppleMaps() {
        let mode = switch countdown.travelMode {
        case .car: MKLaunchOptionsDirectionsModeDriving
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .walk: MKLaunchOptionsDirectionsModeWalking
        }
        if let coordinate = countdown.coordinate {
            let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                 address: nil)
            item.name = countdown.placeName
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
        } else if let name = countdown.placeName,
                  let url = URL(string: "maps://?daddr=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url)
        }
    }
}

/// Where the iPhone is, asked for only when the travel time is wanted.
enum CurrentLocation {
    static var isDenied: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .denied || status == .restricted
    }

    static func get() async -> CLLocation? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    return location
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    return nil
                }
            }
        } catch {}
        return nil
    }
}

/// How long the way takes, from Apple Maps.
enum Travel {
    static func minutes(from here: CLLocation, to destination: CLLocationCoordinate2D, mode: TravelMode,
                        arriving: Date?) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: here, address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude,
                                                             longitude: destination.longitude), address: nil)
        request.transportType = switch mode {
        case .car: .automobile
        case .transit: .transit
        case .walk: .walking
        }
        if let arriving, arriving > .now {
            request.arrivalDate = arriving
        }
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return nil }
        return max(1, Int((eta.expectedTravelTime / 60).rounded(.up)))
    }
}
