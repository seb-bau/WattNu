
import SwiftUI

struct ManualAppointmentEntryView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let commission: Commission
    let onSaved: (Commission) -> Void

    @State private var appointmentDate = Date()
    @State private var appointmentTime = Date()
    @State private var includesTime = false
    @State private var comment = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Vereinbarter Termin") {
                DatePicker(
                    "Datum",
                    selection: $appointmentDate,
                    displayedComponents: .date
                )

                Toggle("Uhrzeit angeben", isOn: $includesTime)

                if includesTime {
                    DatePicker(
                        "Uhrzeit",
                        selection: $appointmentTime,
                        displayedComponents: .hourAndMinute
                    )
                }

                TextField(
                    "Notiz (optional)",
                    text: $comment,
                    axis: .vertical
                )
            }
        }
        .environment(\.locale, Locale(identifier: "de_DE"))
        .disabled(isSaving)
        .navigationTitle("Termin eintragen")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
                .disabled(isSaving)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        await saveAppointment()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Speichern")
                    }
                }
                .disabled(isSaving)
            }
        }
        .alert("Fehler", isPresented: Binding(
            get: { errorMessage != nil },
            set: { visible in
                if !visible {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func saveAppointment() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"

        do {
            let updatedCommission = try await session.apiClient.enterCommissionAppointment(
                commissionId: commission.id,
                date: dateFormatter.string(from: appointmentDate),
                time: includesTime
                    ? timeFormatter.string(from: appointmentTime)
                    : nil,
                comment: comment.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
            onSaved(updatedCommission)
            dismiss()
        } catch {
            if error.isRequestCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
