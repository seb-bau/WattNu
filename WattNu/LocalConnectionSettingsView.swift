import SwiftUI

struct LocalConnectionSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
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

                Button("Backend-Einstellungen laden") {
                    Task {
                        await session.loadMobileConfig()
                    }
                }
            }

            Section("Anmeldung") {
                Label(
                    session.isPasswordLoginAvailable ? "Kennwort-Anmeldung verfügbar" : "Kennwort-Anmeldung nicht verfügbar",
                    systemImage: session.isPasswordLoginAvailable ? "checkmark.circle" : "xmark.circle"
                )

                Label(
                    session.isMicrosoftLoginAvailable ? "Microsoft-Anmeldung verfügbar" : "Microsoft-Anmeldung nicht verfügbar",
                    systemImage: session.isMicrosoftLoginAvailable ? "checkmark.circle" : "xmark.circle"
                )
            }

            Section {
                Button("Fertig") {
                    session.applyCurrentBaseURL()
                    Task {
                        await session.loadMobileConfig()
                    }
                    dismiss()
                }
            }
        }
        .navigationTitle("Verbindung")
    }
}
