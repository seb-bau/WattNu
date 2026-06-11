import Foundation
import Combine
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: AppUser?
    @Published var accessToken: String?
    @Published var mobileConfig: MobileConfig?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let localSettings: LocalAppSettings
    let apiClient: APIClient

    private let tokenStore = KeychainTokenStore()

    var isAuthenticated: Bool {
        accessToken != nil && user != nil
    }

    var isPasswordLoginAvailable: Bool {
        mobileConfig?.passwordLoginEnabled ?? true
    }

    var isMicrosoftLoginAvailable: Bool {
        mobileConfig?.microsoft != nil
    }

    init() {
        let settings = LocalAppSettings()
        self.localSettings = settings
        self.apiClient = APIClient(baseURL: settings.baseURL ?? URL(string: "http://127.0.0.1:5000")!)
        self.accessToken = tokenStore.readToken()
        self.user = Self.readStoredUser()
        self.apiClient.accessToken = accessToken
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
        } catch APIError.unauthorized {
            logout()
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
            mobileConfig = nil
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        user = nil
        accessToken = nil
        apiClient.accessToken = nil
        tokenStore.deleteToken()
        Self.deleteStoredUser()
    }

    func applyCurrentBaseURL() {
        guard let baseURL = localSettings.baseURL else {
            return
        }

        apiClient.updateBaseURL(baseURL)
    }

    private func setSession(_ response: AuthResponse) {
        user = response.user
        accessToken = response.accessToken
        apiClient.accessToken = response.accessToken
        tokenStore.saveToken(response.accessToken)
        Self.saveStoredUser(response.user)
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
