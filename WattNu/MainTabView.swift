import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var pushNotifications: PushNotificationManager

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            CommissionListView()
                .tabItem {
                    Label(
                        "Aufträge",
                        systemImage: "list.bullet.clipboard"
                    )
                }
                .tag(MainTab.commissions)

            InventoryView()
                .tabItem {
                    Label(
                        "Lager",
                        systemImage: "shippingbox"
                    )
                }
                .tag(MainTab.inventory)

            AppSettingsView()
                .tabItem {
                    Label(
                        "Einstellungen",
                        systemImage: "gearshape"
                    )
                }
                .tag(MainTab.settings)
        }
        .task {
            openPendingCommission()
        }
        .onChange(of: pushNotifications.pendingCommissionId) { _, _ in
            openPendingCommission()
        }
    }

    private func openPendingCommission() {
        guard let commissionId = pushNotifications.consumePendingCommission() else {
            return
        }

        navigation.openCommission(id: commissionId)
    }
}
