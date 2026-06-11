import SwiftUI

struct CommissionListView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var commissions: [Commission] = []
    @State private var commissionUsers: [AppUser] = []
    @State private var searchText = ""
    @State private var scopeFilter: CommissionScopeFilter = .mine
    @State private var statusFilter: CommissionStatusFilter = .active
    @State private var selectedUserId: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var searchedCommissions: [Commission] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if query.isEmpty {
            return commissions
        }

        return commissions.filter { commission in
            commission.displayTitle.lowercased().contains(query)
            || commission.displayNumber.lowercased().contains(query)
            || commission.assigneeName.lowercased().contains(query)
            || "\(commission.erpId)".contains(query)
            || commission.localStatusLabel.lowercased().contains(query)
            || (commission.damageLocation ?? "").lowercased().contains(query)
            || (commission.apartmentAddress ?? "").lowercased().contains(query)
            || (commission.apartmentLocation ?? "").lowercased().contains(query)
            || (commission.tenantName ?? "").lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CommissionFilterBarView(
                    scopeFilter: $scopeFilter,
                    statusFilter: $statusFilter,
                    selectedUserId: $selectedUserId,
                    users: commissionUsers,
                    resultCount: searchedCommissions.count
                )

                Divider()

                Group {
                    if isLoading && commissions.isEmpty {
                        ProgressView("Aufträge werden geladen …")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if searchedCommissions.isEmpty {
                        ContentUnavailableView("Keine Aufträge", systemImage: "tray", description: Text("Es sind aktuell keine passenden Aufträge vorhanden."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(searchedCommissions) { commission in
                            NavigationLink(value: commission) {
                                CommissionRowView(commission: commission)
                            }
                        }
                        .refreshable {
                            await loadInitialData()
                        }
                    }
                }
            }
            .navigationTitle("Aufträge")
            .searchable(text: $searchText, prompt: "Aufträge suchen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadInitialData()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(for: Commission.self) { commission in
                CommissionDetailView(commissionId: commission.id)
            }
            .task {
                await loadInitialData()
            }
            .onChange(of: scopeFilter) { _, newValue in
                if newValue == .mine {
                    selectedUserId = nil
                }

                Task {
                    await loadInitialData()
                }
            }
            .onChange(of: statusFilter) { _, _ in
                Task {
                    await loadCommissions()
                }
            }
            .onChange(of: selectedUserId) { _, _ in
                Task {
                    await loadCommissions()
                }
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
    }

    private func loadInitialData() async {
        await loadCommissionUsers()
        await loadCommissions()
    }

    private func loadCommissionUsers() async {
        do {
            if scopeFilter == .all {
                commissionUsers = try await session.apiClient.fetchCommissionUsers()
            } else if let user = session.user {
                commissionUsers = [user]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCommissions() async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            commissions = try await session.apiClient.fetchCommissions(
                scope: scopeFilter,
                status: statusFilter,
                userId: selectedUserId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
