import Combine
import SwiftUI

enum MainTab: Hashable {
    case commissions
    case safetyInspections
    case inventory
    case times
    case settings
}

@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var selectedTab: MainTab = .commissions
    @Published var commissionPath = NavigationPath()
    @Published var safetyInspectionPath = NavigationPath()
    @Published var commissionListRevision = 0
    @Published var mapCommissions: [Commission]?

    private let preferences: UserPreferencesStore
    private var preferenceChanges: AnyCancellable?

    init(preferences: UserPreferencesStore = .shared) {
        self.preferences = preferences
        preferenceChanges = preferences.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var safetyInspectionStatusFilter: SafetyInspectionListFilter {
        get { preferences.inspectionStatusFilter }
        set { preferences.inspectionStatusFilter = newValue }
    }

    var safetyInspectionOwnerFilter: CommissionOwnerFilter {
        get { preferences.inspectionOwnerFilter }
        set { preferences.inspectionOwnerFilter = newValue }
    }

    var safetyInspectionSearchText: String {
        get { preferences.values.inspectionSearch }
        set { preferences.values.inspectionSearch = newValue }
    }

    func openCommission(id: Int) {
        selectedTab = .commissions
        commissionPath = NavigationPath()
        commissionPath.append(id)
    }
    
    func returnToCommissionList() {
        selectedTab = .commissions
        commissionPath = NavigationPath()
        commissionListRevision += 1
    }

    func openSafetyInspection(id: Int) {
        selectedTab = .safetyInspections
        safetyInspectionPath = NavigationPath()
        safetyInspectionPath.append(id)
    }
}
