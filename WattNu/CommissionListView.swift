import SwiftUI

struct CommissionListView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var locationStore: LocationStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var pushNotifications: PushNotificationManager

    @State private var commissions: [Commission] = []
    @State private var commissionUsers: [AppUser] = []
    @State private var searchText = ""
    @State private var scopeFilter: CommissionScopeFilter = .mine
    @State private var statusFilter: CommissionStatusFilter = .active
    @State private var selectedUserId: Int?
    @State private var sortMode: CommissionSortMode = .defaultOrder
    @State private var isSearchVisible = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isCreatePresented = false
    
    private var statusFilteredCommissions: [Commission] {
        guard statusFilter == .active else {
            return commissions
        }

        return commissions.filter {
            CommissionStatusFilter.activeLocalStatuses.contains(
                $0.localStatus
            )
        }
    }

    private var searchedCommissions: [Commission] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if query.isEmpty {
            return statusFilteredCommissions
        }

        return statusFilteredCommissions.filter { commission in
            commission.displayTitle.lowercased().contains(query)
            || commission.displayNumber.lowercased().contains(query)
            || commission.assigneeName.lowercased().contains(query)
            || commission.erpId.map {
                String($0).contains(query)
            } == true
            || commission.localStatusLabel.lowercased().contains(query)
            || (commission.damageLocation ?? "").lowercased().contains(query)
            || (commission.apartmentAddress ?? "").lowercased().contains(query)
            || (commission.apartmentLocation ?? "").lowercased().contains(query)
            || (commission.tenantName ?? "").lowercased().contains(query)
        }
    }

    private var sortedCommissions: [Commission] {
        let ordered: [Commission]

        switch sortMode {
        case .distance:
            ordered = searchedCommissions.sorted {
                let left = locationStore.distanceMeters(to: $0)
                    ?? Double.greatestFiniteMagnitude
                let right = locationStore.distanceMeters(to: $1)
                    ?? Double.greatestFiniteMagnitude
                return left < right
            }

        case .title:
            ordered = searchedCommissions.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare(
                    $1.displayTitle
                ) == .orderedAscending
            }

        case .defaultOrder:
            ordered = searchedCommissions
        }

        return ordered.filter { $0.isHighPriorityValue }
            + ordered.filter { !$0.isHighPriorityValue }
    }

    var body: some View {
        NavigationStack(path: $navigation.commissionPath) {
            VStack(spacing: 0) {
                if pushNotifications.isDenied {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bell.slash.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mitteilungen sind deaktiviert")
                                .font(.headline)

                            Text("Neue oder geänderte Aufträge können nicht als Push-Mitteilung angezeigt werden.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Button("Einstellungen") {
                            pushNotifications.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.thinMaterial)
                }
                CommissionFilterBarView(
                    scopeFilter: $scopeFilter,
                    statusFilter: $statusFilter,
                    selectedUserId: $selectedUserId,
                    users: commissionUsers,
                    resultCount: sortedCommissions.count
                )

                VStack(spacing: 8) {
                    Picker("Sortierung", selection: $sortMode) {
                        ForEach(CommissionSortMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if isSearchVisible {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)

                            TextField("Aufträge suchen", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Color(.systemGroupedBackground))

                Group {
                    if isLoading && commissions.isEmpty {
                        ProgressView("Aufträge werden geladen …")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if sortedCommissions.isEmpty {
                        ContentUnavailableView("Keine Aufträge", systemImage: "tray", description: Text("Es sind aktuell keine passenden Aufträge vorhanden."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(sortedCommissions) { commission in
                            NavigationLink(value: commission) {
                                CommissionRowView(commission: commission)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemGroupedBackground))
                        .refreshable {
                            await loadInitialData()
                        }
                    }
                }
            }
            .navigationTitle("Aufträge")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isCreatePresented = true
                    } label: {
                        Image(
                            systemName: "plus"
                        )
                    }
                    .disabled(
                        session.user?.craftsmanErpId == nil
                    )
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearchVisible.toggle()
                            if !isSearchVisible {
                                searchText = ""
                            }
                        }
                    } label: {
                        Image(systemName: isSearchVisible ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    }

                    NavigationLink {
                        CommissionMapView(commissions: sortedCommissions)
                    } label: {
                        Image(systemName: "map")
                    }

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
            .navigationDestination(for: Int.self) { commissionId in
                CommissionDetailView(commissionId: commissionId)
            }
            .sheet(
                isPresented: $isCreatePresented
            ) {
                NavigationStack {
                    CommissionCreateView {
                        Task {
                            await loadCommissions()
                        }
                    }
                }
                .environmentObject(session)
            }
            .task {
                locationStore.requestLocation()
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

enum CommissionSortMode: String, CaseIterable, Identifiable {
    case defaultOrder
    case distance
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .defaultOrder:
            return "Standard"
        case .distance:
            return "Entfernung"
        case .title:
            return "Titel"
        }
    }
}
