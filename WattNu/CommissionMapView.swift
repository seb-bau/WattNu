import CoreLocation
import MapKit
import SwiftUI

struct CommissionMapView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: AppNavigationStore

    let commissions: [Commission]

    @State private var safetyInspections: [SafetyInspectionJob] = []
    @State private var displayMode: MapDisplayMode = .both
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var errorMessage: String?

    private var mappableCommissions: [Commission] {
        guard displayMode != .safetyInspections else {
            return []
        }

        return commissions.filter { commission in
            guard let coordinate = commission.coordinate else {
                return false
            }

            return CLLocationCoordinate2DIsValid(coordinate)
        }
    }

    private var mappableSafetyInspections: [SafetyInspectionJob] {
        guard displayMode != .commissions else {
            return []
        }

        return safetyInspections.filter { job in
            guard let coordinate = job.coordinate else {
                return false
            }

            return CLLocationCoordinate2DIsValid(coordinate)
                && job.matchesSearch(navigation.safetyInspectionSearchText)
        }
    }

    private var locations: [OrderMapLocation] {
        var grouped: [OrderMapCoordinateKey: OrderMapLocation] = [:]

        for commission in mappableCommissions {
            guard let coordinate = commission.coordinate else {
                continue
            }

            let key = OrderMapCoordinateKey(coordinate)
            grouped[key, default: OrderMapLocation(key: key)]
                .commissions.append(commission)
        }

        for job in mappableSafetyInspections {
            guard let coordinate = job.coordinate else {
                continue
            }

            let key = OrderMapCoordinateKey(coordinate)
            grouped[key, default: OrderMapLocation(key: key)]
                .safetyInspections.append(job)
        }

        return grouped.values.sorted {
            if $0.key.latitude == $1.key.latitude {
                return $0.key.longitude < $1.key.longitude
            }

            return $0.key.latitude < $1.key.latitude
        }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(locations) { location in
                Annotation(
                    location.title,
                    coordinate: location.coordinate,
                    anchor: .bottom
                ) {
                    OrderMapLocationBadge(location: location)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                Picker("Karteninhalt", selection: $displayMode) {
                    ForEach(MapDisplayMode.allCases) { mode in
                        Text(mode.label)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 16) {
                    Label(
                        "Aufträge: \(mappableCommissions.count)",
                        systemImage: "wrench.and.screwdriver.fill"
                    )
                    .foregroundStyle(.blue)

                    Label(
                        "Prüfungen: \(mappableSafetyInspections.count)",
                        systemImage: "checklist"
                    )
                    .foregroundStyle(.orange)
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Auftragskarte")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: navigation.safetyInspectionStatusFilter) {
            await loadSafetyInspections()
        }
        .onChange(of: displayMode) { _, _ in
            cameraPosition = .automatic
        }
        .onChange(of: locations.map(\.id)) { _, _ in
            cameraPosition = .automatic
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { visible in
                    if !visible {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadSafetyInspections() async {
        let requestedFilter = navigation.safetyInspectionStatusFilter
        safetyInspections = []
        errorMessage = nil

        do {
            let loadedJobs = try await session.apiClient.fetchSafetyInspections(
                status: requestedFilter.rawValue
            )

            guard !Task.isCancelled,
                  requestedFilter == navigation.safetyInspectionStatusFilter else {
                return
            }

            safetyInspections = loadedJobs
            cameraPosition = .automatic
        } catch {
            if error.isRequestCancellation
                || Task.isCancelled
                || requestedFilter != navigation.safetyInspectionStatusFilter {
                return
            }

            errorMessage = error.localizedDescription
        }
    }
}

private struct OrderMapCoordinateKey: Hashable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        let precision = 1_000_000.0
        latitude = (coordinate.latitude * precision).rounded() / precision
        longitude = (coordinate.longitude * precision).rounded() / precision
    }
}

private struct OrderMapLocation: Identifiable {
    let key: OrderMapCoordinateKey
    var commissions: [Commission] = []
    var safetyInspections: [SafetyInspectionJob] = []

    var id: String {
        "location:\(key.latitude):\(key.longitude)"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: key.latitude,
            longitude: key.longitude
        )
    }

    var title: String {
        if commissions.count == 1 && safetyInspections.isEmpty {
            return commissions[0].displayTitle
        }

        if safetyInspections.count == 1 && commissions.isEmpty {
            return safetyInspections[0].group.name
        }

        var parts: [String] = []

        if !commissions.isEmpty {
            parts.append(
                commissions.count == 1
                ? "1 Auftrag"
                : "\(commissions.count) Aufträge"
            )
        }

        if !safetyInspections.isEmpty {
            parts.append(
                safetyInspections.count == 1
                ? "1 Prüfung"
                : "\(safetyInspections.count) Prüfungen"
            )
        }

        return parts.joined(separator: " · ")
    }

    var inspectionColor: Color {
        safetyInspections.contains { $0.isOverdue } ? .red : .orange
    }
}

private struct OrderMapLocationBadge: View {
    let location: OrderMapLocation

    var body: some View {
        HStack(spacing: 8) {
            if !location.commissions.isEmpty {
                Label(
                    "\(location.commissions.count)",
                    systemImage: "wrench.and.screwdriver.fill"
                )
                .foregroundStyle(.blue)
            }

            if !location.safetyInspections.isEmpty {
                Label(
                    "\(location.safetyInspections.count)",
                    systemImage: "checklist"
                )
                .foregroundStyle(location.inspectionColor)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 2)
        .accessibilityLabel(location.title)
    }
}

enum MapDisplayMode: String, CaseIterable, Identifiable {
    case commissions
    case safetyInspections
    case both

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .commissions:
            return "Aufträge"
        case .safetyInspections:
            return "Prüfungen"
        case .both:
            return "Beides"
        }
    }
}
