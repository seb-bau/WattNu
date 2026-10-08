import SwiftUI
import UIKit
import MSAL

@main
struct DatLaeuftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = SessionStore()
    @StateObject private var locationStore = LocationStore()
    @StateObject private var navigation = AppNavigationStore()
    @StateObject private var pushNotifications = PushNotificationManager.shared
    @StateObject private var processInfos =
        ProcessInfoStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(session.localSettings)
                .environmentObject(locationStore)
                .environmentObject(navigation)
                .environmentObject(pushNotifications)
                .environmentObject(processInfos)
                .onOpenURL { url in
                    _ = MSALPublicClientApplication.handleMSALResponse(
                        url,
                        sourceApplication: nil
                    )
                }
                .task {
                    async let sessionTask: Void = session.bootstrap()
                    async let notificationTask: Void = pushNotifications.prepareAtLaunch()
                    _ = await (sessionTask, notificationTask)
                    await synchronizePushDevice()
                    await synchronizeProcessInfoBadge()
                }
                .onChange(of: session.user?.id) { _, _ in
                    Task {
                        await synchronizePushDevice()
                        await synchronizeProcessInfoBadge()
                    }
                }
                .onChange(of: pushNotifications.deviceToken) { _, _ in
                    Task {
                        await synchronizePushDevice()
                    }
                }
                .onChange(of: pushNotifications.authorizationStatus) { _, _ in
                    Task {
                        await synchronizePushDevice()
                    }
                }
                .onChange(of: scenePhase) { _, newValue in
                    if newValue == .active {
                        navigation.commissionListRevision += 1

                        Task {
                            await session.loadMobileConfig()
                            await pushNotifications.refreshAuthorizationStatus()
                            await synchronizePushDevice()
                            await synchronizeProcessInfoBadge()
                        }
                    }
                }
                .onChange(
                    of: pushNotifications.notificationRevision
                ) { _, _ in
                    Task {
                        await synchronizeProcessInfoBadge()
                    }
                }
        }
    }

    private func synchronizePushDevice() async {
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String

        await session.synchronizePushDevice(
            deviceToken: pushNotifications.deviceToken,
            notificationsDenied: pushNotifications.isDenied,
            installationId: pushNotifications.installationId,
            appVersion: appVersion,
            deviceName: UIDevice.current.model
        )
    }
    
    private func synchronizeProcessInfoBadge()
    async {
        if session.user == nil {
            processInfos.reset()
            return
        }

        await processInfos.refresh(
            apiClient: session.apiClient
        )
    }
}
