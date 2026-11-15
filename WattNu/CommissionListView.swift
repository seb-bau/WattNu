import SwiftUI

struct CommissionListView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var locationStore: LocationStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @ObservedObject private var processInfos =
        ProcessInfoStore.shared
    @ObservedObject private var preferences = UserPreferencesStore.shared

    @State private var commissions: [Commission] = []
    @State private var commissionUsers: [AppUser] = []
    private var searchText: String { preferences.values.commissionSearch }
    private var ownerFilter: CommissionOwnerFilter { preferences.commissionOwnerFilter }
    private var statusFilter: CommissionStatusFilter { preferences.commissionStatusFilter }
    private var sortMode: CommissionSortMode { preferences.commissionSortMode }
    @State private var isSearchVisible = false
    @State private var hasLoadedCommissions = false
    @State private var loadRevision = 0
    @State private var errorMessage: String?
    @State private var isCreatePresented = false
    
    private var statusFilteredCommissions: [Commission] {
        if statusFilter == .unreadInfos {
            return commissions.filter {
                processInfos.unreadCount(
                    commissionId: $0.id
                ) > 0
            }
        }

        guard statusFilter == .active else {
            return commissions
        }

        return commissions.filter {
            CommissionStatusFilter
                .activeLocalStatuses
                .contains($0.localStatus)
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
            || (commission.economicUnitIdNum ?? "").lowercased().contains(query)
            || (commission.economicUnitName ?? "").lowercased().contains(query)
        }
    }

    private var sortedCommissions: [Commission] {
        sortMode.sorted(searchedCommissions, distance: { locationStore.distanceMeters(to: $0) })
    }
    
    var body: some View {
        let items = sortedCommissions
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
                    ownerFilter: $preferences.commissionOwnerFilter,
                    statusFilter: $preferences.commissionStatusFilter,
                    sortMode: $preferences.commissionSortMode,
                    users: commissionUsers,
                    currentUserId: session.user?.id,
                    resultCount: items.count
                )

                if isSearchVisible || !searchText.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField(
                            "Aufträge durchsuchen",
                            text: $preferences.values.commissionSearch
                        )

                        if !searchText.isEmpty {
                            Button {
                                preferences.values.commissionSearch = ""
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
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(Color(.systemGroupedBackground))
                }

                Group {
                    if !hasLoadedCommissions && errorMessage == nil {
                        ProgressView("Aufträge werden geladen …")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if items.isEmpty {
                        ContentUnavailableView("Keine Aufträge", systemImage: "tray", description: Text("Es sind aktuell keine passenden Aufträge vorhanden."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(items) { commission in
                            Button {
                                navigation.commissionPath.append(
                                    commission.id
                                )
                            } label: {
                                VStack(
                                    alignment: .leading,
                                    spacing: 5
                                ) {
                                    CommissionRowView(
                                        commission: commission
                                    )

                                    let unreadCount =
                                        processInfos.unreadCount(
                                            commissionId:
                                                commission.id
                                        )

                                    if unreadCount > 0 {
                                        Label(
                                            "\(unreadCount) ungelesene Infos",
                                            systemImage:
                                                "text.bubble.fill"
                                        )
                                        .font(
                                            .caption.weight(
                                                .semibold
                                            )
                                        )
                                        .foregroundStyle(.red)
                                    }
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 7,
                                    leading: 16,
                                    bottom: 7,
                                    trailing: 16
                                )
                            )
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
                            if isSearchVisible || !searchText.isEmpty {
                                isSearchVisible = false
                                preferences.values.commissionSearch = ""
                            } else {
                                isSearchVisible = true
                            }
                        }
                    } label: {
                        Image(systemName: isSearchVisible || !searchText.isEmpty ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    }

                    NavigationLink {
                        CommissionMapView(commissions: items)
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
            .onChange(of: session.commissionStore.revision) { _, _ in
                refreshCachedCommissions()
            }
            .task {
                locationStore.requestLocation()
                await loadInitialData()
            }
            .onChange(of: items) { _, items in
                if navigation.mapCommissions != nil {
                    navigation.mapCommissions = items
                }
            }
            .onChange(of: ownerFilter) { _, _ in
                commissions = []
                hasLoadedCommissions = false
                Task {
                    await loadCommissions()
                }
            }
            .onChange(of: statusFilter) { _, _ in
                commissions = []
                hasLoadedCommissions = false
                Task {
                    await loadCommissions()
                }
            }
            .onChange(
                of: navigation.commissionListRevision
            ) { _, _ in
                Task {
                    await loadCommissions()
                }
            }
            .onChange(
                of: pushNotifications.notificationRevision
            ) { _, _ in
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

        guard !Task.isCancelled else {
            return
        }

        await loadCommissions()
    }

    private func loadCommissionUsers() async {
        guard !Task.isCancelled else {
            return
        }

        do {
            let users = try await session.apiClient
                .fetchCommissionUsers()

            commissionUsers = users

            let colleagueUserIds = Set(
                users
                    .filter {
                        $0.id != session.user?.id
                    }
                    .map(\.id)
            )

            switch ownerFilter {
            case .user(let userId)
                where !colleagueUserIds.contains(
                    userId
                ):
                preferences.commissionOwnerFilter = .mine

            case .all
                where colleagueUserIds.isEmpty:
                preferences.commissionOwnerFilter = .mine

            default:
                break
            }
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func loadCommissions() async {
        guard !Task.isCancelled else {
            return
        }

        locationStore.requestLocation()
        loadRevision += 1
        let requestedRevision = loadRevision
        let requestedOwner = ownerFilter
        let requestedStatus = statusFilter
        errorMessage = nil
        refreshCachedCommissions()

        do {
            let loadedCommissions =
                try await session.apiClient
                    .fetchCommissions(
                        scope: requestedOwner.scope,
                        status: requestedStatus.apiFilter,
                        userId: requestedOwner.userId
                    )

            guard !Task.isCancelled, requestedRevision == loadRevision,
                  requestedOwner == ownerFilter, requestedStatus == statusFilter else { return }
            commissions = loadedCommissions
            hasLoadedCommissions = true

            await processInfos.refresh(
                apiClient: session.apiClient
            )
            navigation.mapCommissions = sortedCommissions
        } catch {
            if error.isRequestCancellation || requestedRevision != loadRevision
                || requestedOwner != ownerFilter || requestedStatus != statusFilter {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func refreshCachedCommissions() {
        guard let cached = try? session.commissionStore.cachedCommissions(
            scope: ownerFilter.scope, status: statusFilter.apiFilter, userId: ownerFilter.userId
        ) else { return }
        commissions = cached
        hasLoadedCommissions = true
        navigation.mapCommissions = sortedCommissions
    }
}
