import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var email = ""
    @State private var password = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)

                    Text("MachMa!")
                        .font(.largeTitle.bold())

                    Text("Auftrag rein. Haken dran. Feierabend!")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    if session.isPasswordLoginAvailable {
                        TextField("E-Mail", text: $email)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        SecureField("Kennwort", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        Button {
                            Task {
                                await session.login(email: email, password: password)
                            }
                        } label: {
                            if session.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Anmelden")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || password.isEmpty || session.isLoading)
                    }

                    if session.isMicrosoftLoginAvailable {
                        Button {
                            Task {
                                await session.loginWithMicrosoft()
                            }
                        } label: {
                            Text("Mit Microsoft anmelden")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(session.isLoading)
                    }

                    if !session.isPasswordLoginAvailable && !session.isMicrosoftLoginAvailable {
                        Text("Keine Anmeldeart verfügbar. Bitte Backend-Verbindung prüfen.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let message = session.mobileConfigErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showSettings.toggle()
                    } label: {
                        Label("Verbindung einrichten", systemImage: "gearshape")
                    }
                    .foregroundStyle(.secondary)

                    if let privacyURL = URL(
                        string: "https://www.mach-ma.app/datenschutz.html"
                    ) {
                        Link("Datenschutz", destination: privacyURL)
                            .font(.footnote)
                    }
                }
            }
            .padding()
            .task {
                await session.loadMobileConfig()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    LocalConnectionSettingsView()
                }
            }
        }
    }
}
