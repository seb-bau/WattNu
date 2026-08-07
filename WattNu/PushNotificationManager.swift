import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    @Published private(set) var registrationErrorMessage: String?
    @Published private(set) var pendingCommissionId: Int?

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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let commissionId = Self.commissionId(
            from: response.notification.request.content.userInfo
        )

        if let commissionId {
            Task { @MainActor [weak self] in
                self?.pendingCommissionId = commissionId
            }
        }

        completionHandler()
    }

    nonisolated private static func commissionId(
        from userInfo: [AnyHashable: Any]
    ) -> Int? {
        if let value = userInfo["commission_id"] as? Int {
            return value
        }

        if let value = userInfo["commission_id"] as? NSNumber {
            return value.intValue
        }

        if let value = userInfo["commission_id"] as? String {
            return Int(value)
        }

        return nil
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
}
