import SwiftUI
import UIKit

struct AppSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var localSettings: LocalAppSettings
    @EnvironmentObject private var pushNotifications: PushNotificationManager

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
                        Toggle(
                            "Neue Aufträge",
                            isOn: Binding(
                                get: {
                                    session.pushPreferences?.newCommissionEnabled ?? true
                                },
                                set: { value in
                                    let changedValue = session.pushPreferences?.changedCommissionEnabled ?? true
                                    Task {
                                        await session.updatePushPreferences(
                                            newCommissionEnabled: value,
                                            changedCommissionEnabled: changedValue
                                        )
                                    }
                                }
                            )
                        )
                        .disabled(arePushPreferenceControlsDisabled)

                        Toggle(
                            "Geänderte Aufträge",
                            isOn: Binding(
                                get: {
                                    session.pushPreferences?.changedCommissionEnabled ?? true
                                },
                                set: { value in
                                    let newValue = session.pushPreferences?.newCommissionEnabled ?? true
                                    Task {
                                        await session.updatePushPreferences(
                                            newCommissionEnabled: newValue,
                                            changedCommissionEnabled: value
                                        )
                                    }
                                }
                            )
                        )
                        .disabled(arePushPreferenceControlsDisabled)
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

                    Button("Backend-Einstellungen aktualisieren") {
                        Task {
                            await session.loadMobileConfig()
                            await session.loadPushPreferences()
                            await synchronizePushDevice()
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
                if session.pushPreferences == nil {
                    await session.loadPushPreferences()
                }
            }
        }
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
