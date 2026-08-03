import SwiftUI

struct CommissionCompletionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    let commission: Commission
    let completionAction: (Commission) -> Void

    @State private var completed = true
    @State private var tenantCharge = false
    @State private var reason = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var normalizedReason: String? {
        let value = reason.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return value.isEmpty ? nil : value
    }

    private var canSubmit: Bool {
        !isSaving
            && (
                completed
                || normalizedReason != nil
            )
    }

    var body: some View {
        Form {
            Section("Abschluss") {
                Picker(
                    "Konnte der Auftrag abgeschlossen werden?",
                    selection: $completed
                ) {
                    Text("Ja")
                        .tag(true)

                    Text("Nein")
                        .tag(false)
                }
                .pickerStyle(.segmented)
            }

            if completed {
                Section("Mieterbelastung") {
                    Toggle(
                        "Rechnung an den Mieter",
                        isOn: $tenantCharge
                    )

                    if tenantCharge {
                        Text(
                            "Der Auftrag wird in Wowiport auf „Warte auf Rechnung“ gesetzt. Der Sachbearbeiter kann ihn dort weiterbearbeiten."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(
                            "Der Auftrag wird in Wowiport abgeschlossen."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Kommentar") {
                    TextField(
                        "Kommentar zum Abschluss (optional)",
                        text: $reason,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                }
            } else {
                Section {
                    TextEditor(text: $reason)
                        .frame(minHeight: 130)
                } header: {
                    Text("Grund")
                } footer: {
                    Text(
                        "Der Grund ist erforderlich und wird als Ablehnungsgrund an Wowiport übertragen."
                    )
                }
            }

            Section {
                LabeledContent(
                    "Auftrag",
                    value: commission.displayNumber
                )

                LabeledContent(
                    "Status",
                    value: commission.localStatusLabel
                )
            }
        }
        .navigationTitle("Auftrag abschließen")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .toolbar {
            ToolbarItem(
                placement: .cancellationAction
            ) {
                Button("Abbrechen") {
                    dismiss()
                }
            }

            ToolbarItem(
                placement: .confirmationAction
            ) {
                Button("Übermitteln") {
                    Task {
                        await submit()
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .overlay {
            if isSaving {
                ProgressView(
                    "Abschluss wird übertragen …"
                )
                .padding()
                .background(.regularMaterial)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14
                    )
                )
            }
        }
        .onChange(of: completed) {
            _, newValue in

            if !newValue {
                tenantCharge = false
            }
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { newValue in
                    if !newValue {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(
                "OK",
                role: .cancel
            ) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func submit() async {
        guard canSubmit else {
            errorMessage = (
                "Bitte einen Grund angeben."
            )
            return
        }

        isSaving = true

        defer {
            isSaving = false
        }

        do {
            let updatedCommission = try await session
                .apiClient
                .completeCommission(
                    id: commission.id,
                    completed: completed,
                    tenantCharge: (
                        completed
                        && tenantCharge
                    ),
                    reason: normalizedReason
                )

            completionAction(
                updatedCommission
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
