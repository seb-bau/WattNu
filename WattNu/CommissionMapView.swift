import SwiftUI
import MapKit

struct CommissionMapView: View {
    let commissions: [Commission]

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var mappableCommissions: [Commission] {
        commissions.filter { commission in
            commission.latitude != nil && commission.longitude != nil
        }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(mappableCommissions) { commission in
                if let latitude = commission.latitude, let longitude = commission.longitude {
                    Marker(
                        commission.displayTitle,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    )
                }
            }
        }
        .navigationTitle("Auftragskarte")
        .navigationBarTitleDisplayMode(.inline)
    }
}
