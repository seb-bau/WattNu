import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            Form {
                if let user = session.user {
                    Section("Angemeldet") {
                        DetailRowView(title: "Name", value: user.displayName)
                        DetailRowView(title: "E-Mail", value: user.email)
                        DetailRowView(title: "ERP-Handwerker-ID", value: user.craftsmanErpId.map(String.init) ?? "-")
                    }
                }

                Section("Backend") {
                    TextField("Backend-URL", text: Binding(
                        get: { session.localSettings.baseURLString },
                        set: { value in
                            session.localSettings.baseURLString = value
                            session.applyCurrentBaseURL()
                        }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                    Button("Backend-Einstellungen aktualisieren") {
                        Task {
                            await session.loadMobileConfig()
                        }
                    }
                }

                Section("Anmeldung") {
                    DetailRowView(
                        title: "Kennwort",
                        value: session.isPasswordLoginAvailable ? "Verfügbar" : "Nicht verfügbar"
                    )

                    DetailRowView(
                        title: "Microsoft",
                        value: session.isMicrosoftLoginAvailable ? "Verfügbar" : "Nicht verfügbar"
                    )
                }

                Section {
                    Button(role: .destructive) {
                        session.logout()
                    } label: {
                        Text("Abmelden")
                    }
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}
