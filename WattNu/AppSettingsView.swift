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

                Section {
                    Toggle("Kalendereinladungen per E-Mail", isOn: Binding(
                        get: { session.appointmentPreferences?.calendarEmailEnabled ?? true },
                        set: { enabled in
                            Task { await session.updateAppointmentPreferences(enabled: enabled) }
                        }
                    ))
                    .disabled(session.appointmentPreferences == nil || session.isAppointmentPreferencesLoading || session.isAppointmentPreferencesSaving)

                    if session.isAppointmentPreferencesLoading || session.isAppointmentPreferencesSaving {
                        ProgressView("Einstellung wird übertragen …")
                    }
                    if let message = session.appointmentPreferencesErrorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                        Button("Erneut laden") {
                            Task { await session.loadAppointmentPreferences() }
                        }
                    }
                } header: {
                    Text("Termine")
                } footer: {
                    Text("Sie erhalten eine ICS-Einladung an Ihre E-Mail-Adresse, sobald ein Mieter einen Termin annimmt oder ein Termin eingetragen wird. Die Einstellung gilt auf allen Geräten.")
                }

                Section {
                    NavigationLink {
                        SynchronizationView()
                    } label: {
                        Label("Synchronisierung", systemImage: "arrow.triangle.2.circlepath")
                    }
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
                            await session.loadAppointmentPreferences()
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
                
                Section("Rechtliches") {
                    if let privacyURL = URL(
                        string: "https://www.mach-ma.app/datenschutz.html"
                    ) {
                        Link(destination: privacyURL) {
                            Label("Datenschutz", systemImage: "hand.raised")
                        }
                    }
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
                } footer: {
                    Text(installedVersion)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Einstellungen")
            .task {
                await session.loadPushPreferences()
                await session.loadAppointmentPreferences()
            }
        }
    }

    private var installedVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "WattNu · Version \(version) (Build \(build))"
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
