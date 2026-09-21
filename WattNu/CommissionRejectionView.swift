import SwiftUI

struct CommissionRejectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    let commission: Commission
    let rejectionAction: (Commission) -> Void

    @State private var reason = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var normalizedReason: String {
        reason.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $reason)
                    .frame(minHeight: 140)
            } header: {
                Text("Ablehnungsgrund")
            } footer: {
                Text(
                    "Der Grund wird an Wowiport "
                    + "übertragen und dem "
                    + "Sachbearbeiter per E-Mail "
                    + "mitgeteilt."
                )
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
        .navigationTitle("Auftrag ablehnen")
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
                Button(
                    "Ablehnen",
                    role: .destructive
                ) {
                    Task {
                        await submit()
                    }
                }
                .disabled(
                    isSaving
                    || normalizedReason.isEmpty
                )
            }
        }
        .overlay {
            if isSaving {
                ProgressView(
                    "Ablehnung wird übertragen …"
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
        .alert(
            "Fehler",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
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
        guard !normalizedReason.isEmpty else {
            errorMessage = (
                "Bitte einen Ablehnungsgrund angeben."
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
                .rejectCommission(
                    id: commission.id,
                    reason: normalizedReason
                )

            rejectionAction(
                updatedCommission
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
