import SwiftUI

struct LocalConnectionSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingBackendSettings = false

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
                .disabled(isLoadingBackendSettings)

                Button {
                    guard !isLoadingBackendSettings else {
                        return
                    }

                    isLoadingBackendSettings = true

                    Task {
                        defer {
                            isLoadingBackendSettings = false
                        }

                        await session.loadMobileConfig()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isLoadingBackendSettings {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }

                        Text(
                            isLoadingBackendSettings
                                ? "Wird geladen …"
                                : "Backend-Einstellungen laden"
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoadingBackendSettings)
            }

            Section("Anmeldung") {
                if let message = session.mobileConfigErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }

                if session.mobileConfig != nil {
                    Label(
                        session.isPasswordLoginAvailable ? "Kennwort-Anmeldung verfügbar" : "Kennwort-Anmeldung nicht verfügbar",
                        systemImage: session.isPasswordLoginAvailable ? "checkmark.circle" : "xmark.circle"
                    )

                    Label(
                        session.isMicrosoftLoginAvailable ? "Microsoft-Anmeldung verfügbar" : "Microsoft-Anmeldung nicht verfügbar",
                        systemImage: session.isMicrosoftLoginAvailable ? "checkmark.circle" : "xmark.circle"
                    )
                } else if session.mobileConfigErrorMessage == nil && !isLoadingBackendSettings {
                    Text("Backend-Einstellungen noch nicht geladen.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Fertig") {
                    session.applyCurrentBaseURL()
                    Task {
                        await session.loadMobileConfig()
                    }
                    dismiss()
                }
                .disabled(isLoadingBackendSettings)
            }
        }
        .navigationTitle("Verbindung")
    }
}
