import SwiftUI

struct RelatedCommissionsSectionView: View {
    @EnvironmentObject private var session: SessionStore
    let commissionId: Int
    @State private var response: RelatedCommissionsResponse?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let response, response.total > 0 {
                Label("Weitere Aufträge am Objekt (\(response.total))", systemImage: "square.stack.3d.up")
                    .font(.headline)
                ForEach(response.items.prefix(3)) { item in
                    RelatedCommissionLink(commissionId: commissionId, item: item)
                }
                if response.total > 3 {
                    NavigationLink("Alle weiteren Aufträge anzeigen") {
                        RelatedCommissionsListView(commissionId: commissionId)
                    }
                }
            } else if let errorMessage {
                Text("Weitere Aufträge konnten nicht geladen werden.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Erneut laden") { Task { await load() } }
                    .accessibilityHint(errorMessage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: commissionId) { await load() }
        .refreshForCommissionChanges { await load() }
    }

    private func load() async {
        guard commissionId > 0 else { return }
        do {
            response = try await session.apiClient.fetchRelatedCommissions(commissionId: commissionId)
            errorMessage = nil
        } catch {
            if error.isRequestCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct RelatedCommissionLink: View {
    let commissionId: Int
    let item: RelatedCommission

    var body: some View {
        NavigationLink {
            if item.directAccess {
                CommissionDetailView(commissionId: item.id)
            } else {
                RelatedCommissionDetailView(commissionId: commissionId, relatedId: item.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Label(item.relationshipLabel, systemImage: item.relationshipIcon)
                    .font(.caption).foregroundStyle(.secondary)
                Text(item.commission.displayTitle).font(.subheadline.weight(.semibold))
                Text("\(item.commission.displayNumber) · \(item.commission.localStatusLabel)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(item.commission.assigneeName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct RelatedCommissionsListView: View {
    @EnvironmentObject private var session: SessionStore
    let commissionId: Int
    @State private var items: [RelatedCommission] = []
    @State private var page = 0
    @State private var pages = 1
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(items) { item in
                RelatedCommissionLink(commissionId: commissionId, item: item)
            }
            if isLoading {
                ProgressView("Aufträge werden geladen …")
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
                Button("Erneut versuchen") { Task { await load(page: page + 1) } }
            } else if page < pages {
                Button("Weitere Aufträge laden") { Task { await load(page: page + 1) } }
            } else if items.isEmpty {
                Text("Keine weiteren Aufträge am Objekt vorhanden.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Weitere Aufträge")
        .task { if page == 0 { await load(page: 1) } }
        .refreshable { await load(page: 1) }
    }

    private func load(page requestedPage: Int) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await session.apiClient.fetchRelatedCommissions(commissionId: commissionId, page: requestedPage)
            let previousItems = requestedPage == 1 ? [] : items
            items = previousItems + response.items.filter { item in !previousItems.contains { $0.id == item.id } }
            page = response.page
            pages = response.pages
            errorMessage = nil
        } catch {
            if error.isRequestCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct RelatedCommissionDetailView: View {
    @EnvironmentObject private var session: SessionStore
    let commissionId: Int
    let relatedId: Int
    @State private var commission: Commission?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let commission {
                Section("Auftrag") {
                    Text(commission.displayTitle).font(.headline)
                    DetailRowView(title: "Auftragsnummer", value: commission.displayNumber)
                    DetailRowView(title: "Status", value: commission.localStatusLabel)
                    DetailRowView(title: "Handwerker", value: commission.assigneeName)
                    DetailRowView(title: "Mieter", value: commission.tenantName ?? "–")
                    DetailRowView(title: commission.addressLabel, value: commission.apartmentAddress ?? "–")
                    DetailRowView(title: "Lage", value: commission.apartmentLocation ?? "–")
                }
                if let description = commission.description, !description.isEmpty {
                    Section("Beschreibung") { Text(description) }
                }
                if !commission.positions.isEmpty {
                    Section("Auftragspositionen") {
                        ForEach(commission.positions) { position in Text(position.displayTextValue) }
                    }
                }
                if let start = commission.acceptedAppointmentFrom {
                    Section("Bestätigter Termin") {
                        Text(Formatters.appointmentRangeText(fromValue: start, toValue: commission.acceptedAppointmentTo) ?? start)
                    }
                }
                Section {
                    Text("Dieser Auftrag ist nur zur Ansicht geöffnet.").foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
                Button("Erneut laden") { Task { await load() } }
            } else {
                ProgressView("Auftrag wird geladen …")
            }
        }
        .navigationTitle(commission?.displayNumber ?? "Auftrag")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            commission = try await session.apiClient.fetchRelatedCommission(commissionId: commissionId, relatedId: relatedId)
            errorMessage = nil
        } catch {
            if error.isRequestCancellation { return }
            commission = nil
            errorMessage = error.localizedDescription
        }
    }
}
