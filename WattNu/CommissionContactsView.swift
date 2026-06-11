import SwiftUI

struct CommissionContactsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let commission: Commission

    @State private var contacts: [CommissionContactItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && contacts.isEmpty {
                ProgressView("Kontakte werden geladen …")
            } else if contacts.isEmpty {
                ContentUnavailableView("Keine Bewohner gefunden", systemImage: "person.crop.circle.badge.questionmark", description: Text("Für diese Wohnung wurden keine Kontaktdaten gefunden."))
            } else {
                List(contacts) { contact in
                    CommissionContactRowView(contact: contact)
                }
            }
        }
        .navigationTitle("Bewohner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Schließen") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await loadContacts()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await loadContacts()
        }
        .alert("Fehler", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
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

    private func loadContacts() async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            contacts = try await session.apiClient.fetchCommissionContacts(commissionId: commission.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
