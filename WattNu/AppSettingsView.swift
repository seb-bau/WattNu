import SwiftUI
import UIKit

struct AppSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var localSettings: LocalAppSettings
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var isRefreshingBackendSettings = false

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

                Section {
                    DetailRowView(
                        title: "Systemberechtigung",
                        value: pushNotifications.authorizationStatusText
                    )

                    if pushNotifications.authorizationStatus == .notDetermined {
                        Button("Mitteilungen erlauben") {
                            Task {
                                await pushNotifications.requestAuthorization()
                            }
                        }
                    } else if pushNotifications.isDenied {
                        Button("Systemeinstellungen öffnen") {
                            pushNotifications.openSystemSettings()
                        }
                    }

                    if session.isPushPreferencesLoading && session.pushPreferences == nil {
                        ProgressView("Einstellungen werden geladen …")
                    } else {
                        ForEach(AppPushEvent.allCases) { event in
                            Toggle(
                                event.title,
                                isOn: pushPreferenceBinding(for: event)
                            )
                            .disabled(arePushPreferenceControlsDisabled)
                        }
                    }

                    if let message = session.pushRegistrationErrorMessage
                        ?? pushNotifications.registrationErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Mitteilungen")
                } footer: {
                    Text("Diese Auswahl gilt für den Benutzer auf allen Geräten. Die Systemberechtigung wird auf jedem Gerät separat verwaltet.")
                }

                Section("Darstellung") {
                    Picker("Design", selection: $localSettings.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                Section("Backend") {
                    DetailRowView(
                        title: "Backend-URL",
                        value: localSettings.baseURLString
                    )

                    Button {
                        guard !isRefreshingBackendSettings else {
                            return
                        }

                        isRefreshingBackendSettings = true

                        Task {
                            defer {
                                isRefreshingBackendSettings = false
                            }

                            await session.loadMobileConfig()
                            await session.loadPushPreferences()
                            await synchronizePushDevice()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isRefreshingBackendSettings {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }

                            Text(
                                isRefreshingBackendSettings
                                    ? "Wird aktualisiert …"
                                    : "Backend-Einstellungen aktualisieren"
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isRefreshingBackendSettings)
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
                        Task {
                            await session.logout(
                                installationId: pushNotifications.installationId
                            )
                        }
                    } label: {
                        Text("Abmelden")
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .task {
                await session.loadPushPreferences()
            }
        }
    }
    
    private func pushPreferenceBinding(
        for event: AppPushEvent
    ) -> Binding<Bool> {
        Binding(
            get: {
                session.pushPreferences?.isEnabled(event) ?? true
            },
            set: { enabled in
                Task {
                    await session.updatePushPreferences(
                        event: event,
                        enabled: enabled
                    )
                }
            }
        )
    }

    private var arePushPreferenceControlsDisabled: Bool {
        session.isPushPreferencesSaving
        || session.isPushPreferencesLoading
        || session.pushPreferences == nil
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
}
