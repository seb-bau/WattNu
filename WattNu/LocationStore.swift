import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        let status = manager.authorizationStatus
        authorizationStatus = status

        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }

        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }

    func distanceText(to commission: Commission) -> String? {
        guard let currentLocation else {
            return nil
        }

        guard let latitude = commission.latitude, let longitude = commission.longitude else {
            return nil
        }

        let target = CLLocation(latitude: latitude, longitude: longitude)
        let meters = currentLocation.distance(from: target)

        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }

        return String(format: "%.1f km", meters / 1000)
    }

    func distanceMeters(to commission: Commission) -> Double? {
        guard let currentLocation else {
            return nil
        }

        guard let latitude = commission.latitude, let longitude = commission.longitude else {
            return nil
        }

        return currentLocation.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }
}
