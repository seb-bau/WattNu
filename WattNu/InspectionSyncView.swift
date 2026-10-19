import SwiftUI

struct InspectionSyncView: View {
    @EnvironmentObject private var inspections: SafetyInspectionOfflineStore
    @State private var selectedJobId: Int?
    @State private var keepLocal = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Status") {
                LabeledContent(
                    "Ausstehende Vorgänge",
                    value: String(inspections.pendingCount)
                )
                LabeledContent(
                    "Offline gespeicherte Prüfungen",
                    value: String(inspections.preparedCount)
                )
                if !inspections.message.isEmpty {
                    Text(inspections.message)
                }
                Button("Übertragung erneut versuchen") {
                    do {
                        try inspections.retry()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(inspections.isSyncing)
            }

            ForEach(inspections.issues) { issue in
                Section(issue.title) {
                    Text(issue.message)
                    Button("Meine Änderungen übernehmen") {
                        keepLocal = true
                        selectedJobId = issue.id
                    }
                    Button("Serverstand übernehmen", role: .destructive) {
                        keepLocal = false
                        selectedJobId = issue.id
                    }
                }
                .disabled(inspections.isSyncing)
            }
        }
        .navigationTitle("Übertragung")
        .confirmationDialog(
            keepLocal
                ? "Meine Änderungen übernehmen?"
                : "Lokale Änderungen verwerfen?",
            isPresented: Binding(
                get: { selectedJobId != nil },
                set: {
                    if !$0 {
                        selectedJobId = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(
                keepLocal
                    ? "Meine Änderungen übernehmen"
                    : "Lokale Änderungen verwerfen",
                role: keepLocal ? nil : .destructive
            ) {
                guard let jobId = selectedJobId else { return }
                let shouldKeepLocal = keepLocal
                selectedJobId = nil
                Task {
                    do {
                        try await inspections.resolve(
                            jobId: jobId,
                            keepLocal: shouldKeepLocal
                        )
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(
                keepLocal
                    ? "Die gespeicherten Eingaben werden auf den aktuellen Serverstand angewendet."
                    : "Alle noch nicht bestätigten Eingaben und Fotos dieser Prüfung werden verworfen."
            )
        }
        .alert("Fehler", isPresented: Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
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
}
