import CoreLocation
import MapKit
import SwiftUI

struct CommissionMapView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var inspections: SafetyInspectionOfflineStore

    let commissions: [Commission]?

    @State private var safetyInspections: [SafetyInspectionJob] = []
    @State private var fallbackCommissions: [Commission] = []
    @State private var displayMode: MapDisplayMode
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var errorMessage: String?

    init(
        commissions: [Commission]? = nil,
        initialDisplayMode: MapDisplayMode = .both
    ) {
        self.commissions = commissions
        _displayMode = State(initialValue: initialDisplayMode)
    }

    private struct InspectionFilter: Equatable {
        let owner: CommissionOwnerFilter
        let status: SafetyInspectionListFilter
    }

    private var inspectionFilter: InspectionFilter {
        InspectionFilter(
            owner: navigation.safetyInspectionOwnerFilter,
            status: navigation.safetyInspectionStatusFilter
        )
    }

    private var inspectionFilterLabel: String {
        let ownerLabel: String

        switch inspectionFilter.owner {
        case .mine:
            ownerLabel = "Meine"
        case .all:
            ownerLabel = "Alle"
        case .user(let userId):
            ownerLabel = safetyInspections.first {
                $0.assignedUser?.id == userId
            }?.assignedUser?.displayName ?? "Ausgewählter Kollege"
        }

        var parts = [ownerLabel, inspectionFilter.status.label]
        let query = navigation.safetyInspectionSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !query.isEmpty {
            parts.append("Suche: \(query)")
        }

        return parts.joined(separator: " · ")
    }

    private var mappableCommissions: [Commission] {
        guard displayMode != .safetyInspections else {
            return []
        }

        let selectedCommissions = commissions
            ?? navigation.mapCommissions
            ?? fallbackCommissions

        return selectedCommissions.filter { commission in
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
            guard let coordinate = job.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate) else {
                return false
            }

            let matchesOwner: Bool

            switch inspectionFilter.owner {
            case .mine:
                matchesOwner = job.assignedUser?.id == session.user?.id
            case .user(let userId):
                matchesOwner = job.assignedUser?.id == userId
            case .all:
                matchesOwner = true
            }

            return matchesOwner
                && inspectionFilter.status.matches(job)
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
                if displayMode != .commissions {
                    Text("Prüfungen: \(inspectionFilterLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Karte")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCommissionsIfNeeded()
        }
        .task(id: inspectionFilter) {
            await loadSafetyInspections()
        }
        .onChange(of: inspections.revision) { _, _ in
            updateCachedSafetyInspections()
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

    private func loadCommissionsIfNeeded() async {
        guard commissions == nil,
              navigation.mapCommissions == nil else {
            return
        }

        do {
            let loadedCommissions = try await session.apiClient.fetchCommissions()

            guard !Task.isCancelled else {
                return
            }

            fallbackCommissions = loadedCommissions.filter {
                CommissionStatusFilter.activeLocalStatuses.contains($0.localStatus)
            }
        } catch {
            guard !error.isRequestCancellation, !Task.isCancelled else {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func updateCachedSafetyInspections() {
        if let cached = try? inspections.cachedJobs(
            status: inspectionFilter.status.rawValue,
            scope: inspectionFilter.owner.scope.rawValue,
            userId: inspectionFilter.owner.userId
        ) {
            safetyInspections = cached
        }
    }

    private func loadSafetyInspections() async {
        let requestedFilter = inspectionFilter
        safetyInspections = []
        errorMessage = nil
        updateCachedSafetyInspections()

        do {
            let loadedJobs = try await session.apiClient.fetchSafetyInspections(
                status: requestedFilter.status.rawValue,
                scope: requestedFilter.owner.scope.rawValue,
                userId: requestedFilter.owner.userId
            )

            guard !Task.isCancelled,
                  requestedFilter == inspectionFilter else {
                return
            }

            safetyInspections = loadedJobs
            cameraPosition = .automatic
        } catch {
            if error.isRequestCancellation
                || Task.isCancelled
                || requestedFilter != inspectionFilter {
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
            if commissions[0].isEconomicUnitOrder {
                return [commissions[0].objectDisplayTitle, commissions[0].economicUnitDisplayName]
                    .compactMap { $0 }.joined(separator: " · ")
            }
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
