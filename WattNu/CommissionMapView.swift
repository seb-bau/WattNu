import MapKit
import SwiftUI

struct CommissionMapView: View {
    @EnvironmentObject private var session: SessionStore

    let commissions: [Commission]

    @State private var safetyInspections:
        [SafetyInspectionJob] = []
    @State private var displayMode:
        MapDisplayMode = .both
    @State private var cameraPosition:
        MapCameraPosition = .automatic
    @State private var errorMessage: String?

    private var mappableCommissions:
        [Commission] {

        guard displayMode != .safetyInspections else {
            return []
        }

        return commissions.filter {
            $0.coordinate != nil
        }
    }

    private var mappableSafetyInspections:
        [SafetyInspectionJob] {

        guard displayMode != .commissions else {
            return []
        }

        return safetyInspections.filter {
            $0.coordinate != nil
        }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(mappableCommissions) { commission in
                if let coordinate =
                    commission.coordinate {

                    Marker(
                        commission.displayTitle,
                        systemImage:
                            "wrench.and.screwdriver.fill",
                        coordinate: coordinate
                    )
                    .tint(.blue)
                }
            }

            ForEach(
                mappableSafetyInspections
            ) { job in
                if let coordinate = job.coordinate {
                    Marker(
                        job.group.name,
                        systemImage: "checklist",
                        coordinate: coordinate
                    )
                    .tint(
                        job.isOverdue
                        ? Color.red
                        : Color.orange
                    )
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Picker(
                "Karteninhalt",
                selection: $displayMode
            ) {
                ForEach(MapDisplayMode.allCases) {
                    mode in

                    Text(mode.label)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Auftragskarte")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSafetyInspections()
        }
        .onChange(of: displayMode) { _, _ in
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
        do {
            safetyInspections =
                try await session.apiClient
                    .fetchSafetyInspections(
                        status: "active"
                    )

            cameraPosition = .automatic
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }
}

enum MapDisplayMode: String,
    CaseIterable,
    Identifiable {

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
