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
    @Published var safetyInspectionStatusFilter: SafetyInspectionListFilter = .active
    @Published var safetyInspectionSearchText = ""
    @Published var safetyInspectionOwnerFilter: CommissionOwnerFilter = .mine
    @Published var mapCommissions: [Commission]?

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
