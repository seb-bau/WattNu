import Foundation
import Combine
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: AppUser?
    @Published var accessToken: String?
    @Published var mobileConfig: MobileConfig?
    @Published var pushPreferences: PushPreferences?
    @Published var isLoading = false
    @Published var isPushPreferencesLoading = false
    @Published var isPushPreferencesSaving = false
    @Published var errorMessage: String?
    @Published var pushRegistrationErrorMessage: String?

    let localSettings: LocalAppSettings
    let apiClient: APIClient
    let inspectionStore = SafetyInspectionOfflineStore()
    
    private let tokenStore = KeychainTokenStore()
    private var lastRegisteredDeviceKey: String?
    private var pendingDeviceRegistrationKey: String?
    private var lastUnregisteredDeviceKey: String?
    private var pendingDeviceUnregistrationKey: String?

    var isAuthenticated: Bool {
        accessToken != nil && user != nil
    }

    var isPasswordLoginAvailable: Bool {
        mobileConfig?.passwordLoginEnabled ?? true
    }

    var isMicrosoftLoginAvailable: Bool {
        mobileConfig?.microsoft != nil
    }
    
    var timeComponentsEnabled: Bool {
        mobileConfig?.timeComponentsEnabled ?? true
    }
    
    var showServiceTargetTimes: Bool {
        mobileConfig?.showServiceTargetTimes ?? true
    }

    var showWorkTimeTargetTimes: Bool {
        mobileConfig?.showWorkTimeTargetTimes ?? true
    }

    init() {
        let settings = LocalAppSettings()
        self.localSettings = settings
        self.apiClient = APIClient(baseURL: settings.baseURL ?? URL(string: "http://127.0.0.1:5000")!)
        self.accessToken = tokenStore.readToken()
        self.user = Self.readStoredUser()
        self.apiClient.accessToken = accessToken
        configureInspectionStorage()
    }

    func bootstrap() async {
        await loadMobileConfig()

        guard accessToken != nil else {
            return
        }

        isLoading = user == nil

        defer {
            isLoading = false
        }

        do {
            applyCurrentBaseURL()
            let response = try await apiClient.getMe()
            user = response.user
            Self.saveStoredUser(response.user)
            configureInspectionStorage()
            await loadPushPreferences(showErrors: false)
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            if user == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMobileConfig() async {
        do {
            applyCurrentBaseURL()
            mobileConfig = try await apiClient.fetchMobileConfig()
        } catch {
            return
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            applyCurrentBaseURL()
            let response = try await apiClient.loginPassword(email: email, password: password)
            setSession(response)
            await loadPushPreferences(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loginWithMicrosoft() async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        guard let microsoftConfig = mobileConfig?.microsoft else {
            errorMessage = "Microsoft-Anmeldung ist nicht verfügbar."
            return
        }

        guard let viewController = UIApplication.shared.currentViewController else {
            errorMessage = "Microsoft-Anmeldung kann nicht geöffnet werden."
            return
        }

        do {
            applyCurrentBaseURL()
            let service = MicrosoftAuthService()
            let idToken = try await service.acquireIdToken(
                tenantId: microsoftConfig.tenantId,
                clientId: microsoftConfig.clientId,
                redirectUri: microsoftConfig.redirectUri,
                scopes: microsoftConfig.scopes,
                from: viewController
            )
            let response = try await apiClient.loginMicrosoft(idToken: idToken)
            setSession(response)
            await loadPushPreferences(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout(installationId: String) async {
        isLoading = true

        if accessToken != nil {
            applyCurrentBaseURL()
            _ = try? await apiClient.unregisterPushDevice(
                installationId: installationId
            )
        }

        clearSession()
        isLoading = false
    }

    func loadPushPreferences(
        showErrors: Bool = true
    ) async {
        guard isAuthenticated else {
            pushPreferences = nil
            return
        }

        if isPushPreferencesLoading {
            return
        }

        isPushPreferencesLoading = true

        defer {
            isPushPreferencesLoading = false
        }

        do {
            applyCurrentBaseURL()
            pushPreferences = try await apiClient.fetchPushPreferences()
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            if showErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func updatePushPreferences(
        event: AppPushEvent,
        enabled: Bool
    ) async {
        guard isAuthenticated,
              !isPushPreferencesSaving,
              !isPushPreferencesLoading,
              let previousPreferences = pushPreferences else {
            return
        }

        let currentAccessToken = accessToken
        pushPreferences = previousPreferences.updating(event, enabled: enabled)
        isPushPreferencesSaving = true

        defer {
            isPushPreferencesSaving = false
        }

        do {
            applyCurrentBaseURL()

            let updatedPreferences = try await apiClient.updatePushPreferences(
                event: event,
                enabled: enabled
            )

            guard accessToken == currentAccessToken else { return }
            pushPreferences = updatedPreferences
        } catch APIError.unauthorized {
            if accessToken == currentAccessToken {
                clearSession()
            }
        } catch {
            guard accessToken == currentAccessToken else { return }
            pushPreferences = previousPreferences
            errorMessage = error.localizedDescription
        }
    }

    func synchronizePushDevice(
        deviceToken: String?,
        notificationsDenied: Bool,
        installationId: String,
        appVersion: String?,
        deviceName: String?
    ) async {
        guard let user, isAuthenticated else {
            return
        }

        applyCurrentBaseURL()

        if notificationsDenied {
            await unregisterPushDeviceIfNeeded(
                userId: user.id,
                installationId: installationId
            )
            return
        }

        guard let deviceToken, !deviceToken.isEmpty else {
            return
        }

        let registrationKey = [
            apiClient.baseURL.absoluteString,
            String(user.id),
            installationId,
            deviceToken,
        ].joined(separator: "|")

        if (
            registrationKey == lastRegisteredDeviceKey
            || registrationKey == pendingDeviceRegistrationKey
        ) {
            return
        }

        pendingDeviceRegistrationKey = registrationKey
        pushRegistrationErrorMessage = nil

        defer {
            if pendingDeviceRegistrationKey == registrationKey {
                pendingDeviceRegistrationKey = nil
            }
        }

        do {
            _ = try await apiClient.registerPushDevice(
                installationId: installationId,
                deviceToken: deviceToken,
                appVersion: appVersion,
                deviceName: deviceName
            )
            lastRegisteredDeviceKey = registrationKey
            lastUnregisteredDeviceKey = nil
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            pushRegistrationErrorMessage = error.localizedDescription
        }
    }

    func applyCurrentBaseURL() {
        guard let baseURL = localSettings.baseURL else {
            return
        }

        if apiClient.baseURL != baseURL {
            apiClient.updateBaseURL(baseURL)
            resetPushRegistration()
            configureInspectionStorage()
        }
    }

    func resetPushRegistration() {
        lastRegisteredDeviceKey = nil
        pendingDeviceRegistrationKey = nil
        lastUnregisteredDeviceKey = nil
        pendingDeviceUnregistrationKey = nil
    }

    private func unregisterPushDeviceIfNeeded(
        userId: Int,
        installationId: String
    ) async {
        let unregistrationKey = [
            apiClient.baseURL.absoluteString,
            String(userId),
            installationId,
        ].joined(separator: "|")

        if (
            unregistrationKey == lastUnregisteredDeviceKey
            || unregistrationKey == pendingDeviceUnregistrationKey
        ) {
            return
        }

        pendingDeviceUnregistrationKey = unregistrationKey
        lastRegisteredDeviceKey = nil
        pushRegistrationErrorMessage = nil

        defer {
            if pendingDeviceUnregistrationKey == unregistrationKey {
                pendingDeviceUnregistrationKey = nil
            }
        }

        do {
            _ = try await apiClient.unregisterPushDevice(
                installationId: installationId
            )
            lastUnregisteredDeviceKey = unregistrationKey
            lastRegisteredDeviceKey = nil
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            pushRegistrationErrorMessage = error.localizedDescription
        }
    }

    private func setSession(_ response: AuthResponse) {
        user = response.user
        accessToken = response.accessToken
        pushPreferences = nil
        apiClient.accessToken = response.accessToken
        tokenStore.saveToken(response.accessToken)
        Self.saveStoredUser(response.user)
        configureInspectionStorage()
        resetPushRegistration()
    }

    private func clearSession() {
        user = nil
        accessToken = nil
        pushPreferences = nil
        pushRegistrationErrorMessage = nil
        apiClient.accessToken = nil
        tokenStore.deleteToken()
        Self.deleteStoredUser()
        configureInspectionStorage()
        resetPushRegistration()
    }
    
    private func configureInspectionStorage() {
        apiClient.safetyInspectionStore = inspectionStore
        do {
            try inspectionStore.bind(
                user: user,
                baseURL: apiClient.baseURL,
                token: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private static func readStoredUser() -> AppUser? {
        guard let data = UserDefaults.standard.data(forKey: Keys.storedUser) else {
            return nil
        }

        return try? JSONDecoder().decode(AppUser.self, from: data)
    }

    private static func saveStoredUser(_ user: AppUser) {
        guard let data = try? JSONEncoder().encode(user) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Keys.storedUser)
    }

    private static func deleteStoredUser() {
        UserDefaults.standard.removeObject(forKey: Keys.storedUser)
    }

    private enum Keys {
        static let storedUser = "storedUser"
    }
}
