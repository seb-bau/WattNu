import Combine
import SwiftUI

enum MainTab: Hashable {
    case commissions
    case inventory
    case settings
}

@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var selectedTab: MainTab = .commissions
    @Published var commissionPath = NavigationPath()

    func openCommission(id: Int) {
        selectedTab = .commissions
        commissionPath = NavigationPath()
        commissionPath.append(id)
    }
}
