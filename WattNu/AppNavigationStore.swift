import Combine
import SwiftUI

enum MainTab: Hashable {
    case commissions
    case safetyInspections
    case inventory
    case settings
}

@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var selectedTab: MainTab = .commissions
    @Published var commissionPath = NavigationPath()
    @Published var safetyInspectionPath = NavigationPath()

    func openCommission(id: Int) {
        selectedTab = .commissions
        commissionPath = NavigationPath()
        commissionPath.append(id)
    }

    func openSafetyInspection(id: Int) {
        selectedTab = .safetyInspections
        safetyInspectionPath = NavigationPath()
        safetyInspectionPath.append(id)
    }
}
