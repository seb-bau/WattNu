import SwiftUI

struct CommissionListView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var locationStore: LocationStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @ObservedObject private var processInfos =
        ProcessInfoStore.shared

    @State private var commissions: [Commission] = []
    @State private var commissionUsers: [AppUser] = []
    @State private var searchText = ""
    @State private var ownerFilter:
        CommissionOwnerFilter = .mine
    @State private var statusFilter:
        CommissionStatusFilter = .active
    @State private var sortMode:
        CommissionSortMode = .distance
    @State private var isSearchVisible = false
    @State private var isLoading = false
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
        }
    }

    private var sortedCommissions: [Commission] {
        let selected: [Commission] = searchedCommissions
        let ordered: [Commission]

        switch sortMode {
        case .distance:
            var distances: [Double] = []
            distances.reserveCapacity(selected.count)

            for commission in selected {
                let meters: Double =
                    locationStore.distanceMeters(to: commission)
                    ?? Double.infinity

                distances.append(meters)
            }

            var indices: [Int] = Array(selected.indices)

            indices.sort { (leftIndex: Int, rightIndex: Int) -> Bool in
                let leftDistance: Double = distances[leftIndex]
                let rightDistance: Double = distances[rightIndex]

                if leftDistance == rightDistance {
                    return leftIndex < rightIndex
                }

                return leftDistance < rightDistance
            }

            var nearby: [Commission] = []
            nearby.reserveCapacity(selected.count)

            for index in indices {
                nearby.append(selected[index])
            }

            ordered = nearby

        case .title:
            ordered = selected.sorted {
                (left: Commission, right: Commission) -> Bool in

                let comparison = left.displayTitle
                    .localizedCaseInsensitiveCompare(right.displayTitle)

                return comparison == .orderedAscending
            }

        case .defaultOrder:
            ordered = selected
        }

        let currentDate = Date()
        var urgent: [Commission] = []
        var today: [Commission] = []
        var scheduled: [Commission] = []
        var remaining: [Commission] = []

        for commission in ordered {
            if commission.isHighPriorityValue {
                urgent.append(commission)
            } else if Formatters.isAppointmentToday(
                commission.acceptedAppointmentFrom,
                at: currentDate
            ) {
                today.append(commission)
            } else if commission.acceptedAppointmentFrom != nil {
                scheduled.append(commission)
            } else {
                remaining.append(commission)
            }
        }

        var result: [Commission] = []
        result.reserveCapacity(ordered.count)
        result.append(contentsOf: urgent)
        result.append(contentsOf: today)
        result.append(contentsOf: scheduled)
        result.append(contentsOf: remaining)

        return result
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
                    ownerFilter: $ownerFilter,
                    statusFilter: $statusFilter,
                    sortMode: $sortMode,
                    users: commissionUsers,
                    currentUserId: session.user?.id,
                    resultCount: items.count
                )

                if isSearchVisible {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField(
                            "Aufträge durchsuchen",
                            text: $searchText
                        )

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
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(Color(.systemGroupedBackground))
                }

                Group {
                    if isLoading && commissions.isEmpty {
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
                            isSearchVisible.toggle()
                            if !isSearchVisible {
                                searchText = ""
                            }
                        }
                    } label: {
                        Image(systemName: isSearchVisible ? "magnifyingglass.circle.fill" : "magnifyingglass")
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
                Task {
                    await loadCommissions()
                }
            }
            .onChange(of: statusFilter) { _, _ in
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
                ownerFilter = .mine

            case .all
                where colleagueUserIds.isEmpty:
                ownerFilter = .mine

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
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            commissions =
                try await session.apiClient
                    .fetchCommissions(
                        scope: ownerFilter.scope,
                        status: statusFilter.apiFilter,
                        userId: ownerFilter.userId
                    )

            await processInfos.refresh(
                apiClient: session.apiClient
            )
            navigation.mapCommissions = sortedCommissions
        } catch {
            if error.isRequestCancellation {
                return
            }

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
            return "Sortierung"
        case .distance:
            return "Entfernung"
        case .title:
            return "Titel"
        }
    }
}
