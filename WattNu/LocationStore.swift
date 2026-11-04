import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus?

    private struct CoordinateKey: Hashable {
        let latitude: Double
        let longitude: Double
    }

    private let manager = CLLocationManager()
    private var distances: [CoordinateKey: Double] = [:]
    private var isRequestPending = false
    private var hasRequestedAuthorization = false
    private var lastRequestedAt = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        let status = manager.authorizationStatus
        if authorizationStatus != status {
            authorizationStatus = status
        }

        if status == .notDetermined {
            if !hasRequestedAuthorization {
                hasRequestedAuthorization = true
                manager.requestWhenInUseAuthorization()
            }
            return
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            clearLocation()
            return
        }

        if let currentLocation, !isUsable(currentLocation) {
            distances.removeAll(keepingCapacity: true)
            self.currentLocation = nil
        }

        if let cachedLocation = manager.location {
            accept(cachedLocation)
        }

        guard !isRequestPending,
              Date().timeIntervalSince(lastRequestedAt) >= 15 else {
            return
        }

        isRequestPending = true
        lastRequestedAt = Date()
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if authorizationStatus != status {
            authorizationStatus = status
        }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            requestLocation()
        case .denied, .restricted:
            clearLocation()
        default:
            break
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        isRequestPending = false

        guard manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways,
              let location = locations.last(where: { isUsable($0) }) else {
            return
        }

        accept(location)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        isRequestPending = false
    }

    func distanceText(to commission: Commission) -> String? {
        guard let meters = distanceMeters(to: commission) else { return nil }

        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }

        return String(format: "%.1f km", meters / 1000)
    }

    func distanceMeters(to commission: Commission) -> Double? {
        distanceMeters(
            latitude: commission.latitude,
            longitude: commission.longitude
        )
    }

    func distanceMeters(latitude: Double?, longitude: Double?) -> Double? {
        guard let currentLocation, let latitude, let longitude,
              latitude.isFinite, longitude.isFinite,
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else {
            return nil
        }

        let key = CoordinateKey(latitude: latitude, longitude: longitude)
        if let cachedDistance = distances[key] {
            return cachedDistance
        }

        let target = CLLocation(latitude: latitude, longitude: longitude)
        let meters = currentLocation.distance(from: target)
        distances[key] = meters
        return meters
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy.isFinite
            && location.horizontalAccuracy >= 0
            && abs(location.timestamp.timeIntervalSinceNow) <= 300
    }

    private func accept(_ location: CLLocation) {
        guard isUsable(location) else { return }
        if let currentLocation, currentLocation.timestamp >= location.timestamp {
            return
        }

        distances.removeAll(keepingCapacity: true)
        currentLocation = location
    }

    private func clearLocation() {
        manager.stopUpdatingLocation()
        isRequestPending = false
        lastRequestedAt = .distantPast
        distances.removeAll(keepingCapacity: true)

        if currentLocation != nil {
            currentLocation = nil
        }
    }
}
