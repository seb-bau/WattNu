import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var localSettings: LocalAppSettings

    var body: some View {
        Group {
            if session.isLoading && session.accessToken != nil && session.user == nil {
                ProgressView("Wird geladen …")
            } else if session.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(localSettings.preferredColorScheme)
        .alert("Hinweis", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    session.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                session.errorMessage = nil
            }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}
