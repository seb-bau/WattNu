import SwiftUI

struct CommissionContactsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    private let commission: Commission?
    private let inspectionJobId: Int?

    init(commission: Commission) {
        self.commission = commission
        inspectionJobId = nil
    }

    init(inspectionJobId: Int) {
        commission = nil
        self.inspectionJobId = inspectionJobId
    }

    @State private var contacts: [CommissionContactItem] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && contacts.isEmpty {
                ProgressView("Kontakte werden geladen …")
            } else if contacts.isEmpty {
                ContentUnavailableView("Keine Mieter gefunden", systemImage: "person.crop.circle.badge.questionmark", description: Text("Für dieses Objekt wurden keine Kontaktdaten aktueller oder zukünftiger Mieter gefunden."))
            } else {
                List {
                    ForEach(CommissionContactGroup.groups(from: contacts)) { group in
                        if let title = group.title {
                            Section {
                                ForEach(group.contacts) { contact in
                                    CommissionContactRowView(contact: contact)
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(title)
                                    if let location = group.location, !location.isEmpty {
                                        Text(location)
                                            .font(.caption)
                                    }
                                }
                            }
                        } else {
                            ForEach(group.contacts) { contact in
                                CommissionContactRowView(contact: contact)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Mieterkontakte")
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
        .refreshForCommissionChanges { await loadContacts(refresh: false) }
        .refreshOnActivation(id: commission?.id ?? inspectionJobId) {
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

    private func loadContacts(refresh: Bool = true) async {
        let showLoading = !hasLoaded
        if showLoading { isLoading = true }

        defer {
            if showLoading { isLoading = false }
        }

        do {
            let loadedContacts: [CommissionContactItem]
            if let inspectionJobId {
                loadedContacts = try await session.apiClient.fetchSafetyInspectionContacts(
                    jobId: inspectionJobId
                )
            } else if let commission {
                loadedContacts = try await session.apiClient.fetchCommissionContacts(
                    commissionId: commission.id,
                    refresh: refresh
                )
            } else {
                return
            }
            guard !Task.isCancelled else { return }
            if contacts != loadedContacts { contacts = loadedContacts }
            if !hasLoaded { hasLoaded = true }
        } catch {
            if error.isRequestCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
