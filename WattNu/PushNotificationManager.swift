import Combine
import Foundation
import UIKit
import UserNotifications
import MSAL

@MainActor
final class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    @Published private(set) var registrationErrorMessage: String?
    @Published private(set) var pendingCommissionId: Int?
    @Published private(set)
    var pendingSafetyInspectionId: Int?
    @Published private(set)
    var pendingProcessInfoCommissionId: Int?

    @Published private(set)
    var notificationRevision = 0

    let installationId: String

    private let notificationCenter = UNUserNotificationCenter.current()

    private override init() {
        if let storedValue = UserDefaults.standard.string(
            forKey: Keys.installationId
        ), UUID(uuidString: storedValue) != nil {
            installationId = storedValue
        } else {
            let value = UUID().uuidString.lowercased()
            installationId = value
            UserDefaults.standard.set(
                value,
                forKey: Keys.installationId
            )
        }

        super.init()
    }

    var isDenied: Bool {
        authorizationStatus == .denied
    }

    var canReceiveNotifications: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    var authorizationStatusText: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Noch nicht entschieden"
        case .denied:
            return "Nicht erlaubt"
        case .authorized:
            return "Erlaubt"
        case .provisional:
            return "Vorläufig erlaubt"
        case .ephemeral:
            return "Vorübergehend erlaubt"
        @unknown default:
            return "Unbekannt"
        }
    }

    func prepareAtLaunch() async {
        await refreshAuthorizationStatus()

        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
    }

    func requestAuthorization() async {
        registrationErrorMessage = nil

        do {
            _ = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await refreshAuthorizationStatus()
        } catch {
            registrationErrorMessage = error.localizedDescription
            await refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        if canReceiveNotifications {
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            deviceToken = nil
        }
    }

    func handleDeviceToken(_ tokenData: Data) {
        deviceToken = tokenData.map {
            String(format: "%02x", $0)
        }.joined()
        registrationErrorMessage = nil
    }

    func handleRegistrationError(_ error: Error) {
        deviceToken = nil
        registrationErrorMessage = error.localizedDescription
    }

    func openSystemSettings() {
        guard let url = URL(
            string: UIApplication.openSettingsURLString
        ) else {
            return
        }

        UIApplication.shared.open(url)
    }

    func consumePendingCommission() -> Int? {
        let value = pendingCommissionId
        pendingCommissionId = nil
        return value
    }
    
    func consumePendingProcessInfoCommission()
    -> Int? {
        let value =
            pendingProcessInfoCommissionId

        pendingProcessInfoCommissionId = nil
        return value
    }
    
    func consumePendingSafetyInspection() -> Int? {
        let value = pendingSafetyInspectionId
        pendingSafetyInspectionId = nil
        return value
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.notificationRevision += 1
        }
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response
            .notification
            .request
            .content
            .userInfo

        let safetyInspectionId = Self.integerValue(
            forKey: "safety_inspection_job_id",
            in: userInfo
        )
        let commissionId = Self.integerValue(
            forKey: "commission_id",
            in: userInfo
        )
        let openInfos = Self.booleanValue(
            forKey: "open_infos",
            in: userInfo
        )

        Task { @MainActor [weak self] in
            if let safetyInspectionId {
                self?.pendingSafetyInspectionId =
                    safetyInspectionId
            } else if let commissionId,
                      openInfos {
                self?.pendingProcessInfoCommissionId =
                    commissionId
            } else if let commissionId {
                self?.pendingCommissionId =
                    commissionId
            }
        }

        completionHandler()
    }

    nonisolated private static func integerValue(
        forKey key: String,
        in userInfo: [AnyHashable: Any]
    ) -> Int? {
        if let value = userInfo[key] as? Int {
            return value
        }

        if let value = userInfo[key] as? NSNumber {
            return value.intValue
        }

        if let value = userInfo[key] as? String {
            return Int(value)
        }

        return nil
    }

    nonisolated private static func booleanValue(
        forKey key: String,
        in userInfo: [AnyHashable: Any]
    ) -> Bool {
        if let value = userInfo[key] as? Bool {
            return value
        }

        if let value = userInfo[key] as? NSNumber {
            return value.boolValue
        }

        if let value = userInfo[key] as? String {
            return [
                "true",
                "1",
            ].contains(
                value.lowercased()
            )
        }

        return false
    }

    private enum Keys {
        static let installationId = "pushInstallationId"
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushNotificationManager.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.handleDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationManager.shared.handleRegistrationError(error)
    }
    
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        MSALPublicClientApplication.handleMSALResponse(
            url,
            sourceApplication: options[
                UIApplication.OpenURLOptionsKey.sourceApplication
            ] as? String
        )
    }
}
