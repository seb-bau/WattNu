import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    
    @ObservedObject private var processInfos =
        ProcessInfoStore.shared

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
                .badge(processInfos.unreadTotal)

            SafetyInspectionListView()
                .tabItem {
                    Label(
                        "Prüfungen",
                        systemImage: "checklist"
                    )
                }
                .tag(MainTab.safetyInspections)

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
            openPendingDestination()
        }
        .onChange(
            of: pushNotifications
                .pendingCommissionId
        ) { _, _ in
            openPendingDestination()
        }
        .onChange(
            of: pushNotifications
                .pendingSafetyInspectionId
        ) { _, _ in
            openPendingDestination()
        }
        .onChange(
            of: pushNotifications
                .pendingProcessInfoCommissionId
        ) { _, _ in
            openPendingDestination()
        }
    }

    private func openPendingDestination() {
        if let commissionId =
            pushNotifications
                .consumePendingProcessInfoCommission()
        {
            processInfos.requestInfos(
                commissionId: commissionId
            )

            navigation.openCommission(
                id: commissionId
            )
            return
        }
        
        if let inspectionId = pushNotifications
            .consumePendingSafetyInspection()
        {
            navigation.openSafetyInspection(
                id: inspectionId
            )
            return
        }

        guard let commissionId = pushNotifications
            .consumePendingCommission()
        else {
            return
        }

        navigation.openCommission(
            id: commissionId
        )
    }
}
