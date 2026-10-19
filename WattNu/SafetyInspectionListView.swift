import SwiftUI

struct SafetyInspectionListView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: AppNavigationStore

    @State private var jobs: [SafetyInspectionJob] = []
    @State private var inspectionUsers: [AppUser] = []
    @State private var ownerFilter: CommissionOwnerFilter = .mine
    @State private var sortMode: SafetyInspectionSortMode = .dueDate
    @State private var isSearchVisible = false
    @State private var isLoading = false
    @State private var isLoadingUsers = false
    @State private var usersLoadRevision = 0
    @State private var loadRevision = 0
    @State private var errorMessage: String?

    private var statusFilter: SafetyInspectionListFilter {
        navigation.safetyInspectionStatusFilter
    }

    private var isSearchExpanded: Bool {
        isSearchVisible || !navigation.safetyInspectionSearchText.isEmpty
    }

    private var colleagueUsers: [AppUser] {
        inspectionUsers
            .filter { $0.id != session.user?.id }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
    }

    private var ownerFilterLabel: String {
        switch ownerFilter {
        case .mine:
            return "Meine"
        case .all:
            return "Alle"
        case .user(let userId):
            return inspectionUsers.first {
                $0.id == userId
            }?.displayName ?? "Kollege"
        }
    }

    private var filteredJobs: [SafetyInspectionJob] {
        let selectedJobs = jobs.filter { job in
            let matchesOwner: Bool

            switch ownerFilter {
            case .mine:
                matchesOwner = job.assignedUser?.id == session.user?.id
            case .user(let userId):
                matchesOwner = job.assignedUser?.id == userId
            case .all:
                matchesOwner = true
            }

            return matchesOwner
                && statusFilter.matches(job)
                && job.matchesSearch(navigation.safetyInspectionSearchText)
        }

        return selectedJobs.sorted { left, right in
            switch sortMode {
            case .dueDate:
                return left.dueTo == right.dueTo
                    ? left.id < right.id
                    : left.dueTo < right.dueTo

            case .address:
                let comparison = left.objectTitle
                    .localizedCaseInsensitiveCompare(right.objectTitle)

                return comparison == .orderedSame
                    ? left.id < right.id
                    : comparison == .orderedAscending

            case .status:
                let comparison = left.statusLabel
                    .localizedCaseInsensitiveCompare(right.statusLabel)

                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }

                return left.dueTo == right.dueTo
                    ? left.id < right.id
                    : left.dueTo < right.dueTo
            }
        }
    }

    private var filterHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(selection: $ownerFilter) {
                    Text("Meine")
                        .tag(CommissionOwnerFilter.mine)

                    ForEach(colleagueUsers) { user in
                        Text(user.displayName)
                            .tag(CommissionOwnerFilter.user(user.id))
                    }

                    Text("Alle")
                        .tag(CommissionOwnerFilter.all)
                } label: {
                    Text(ownerFilterLabel)
                        .lineLimit(1)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker(
                    selection: $navigation.safetyInspectionStatusFilter
                ) {
                    ForEach(SafetyInspectionListFilter.allCases) { filter in
                        Text(filter.label)
                            .tag(filter)
                    }
                } label: {
                    Text(statusFilter.label)
                        .lineLimit(1)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .center)

                Picker(selection: $sortMode) {
                    ForEach(SafetyInspectionSortMode.allCases) { mode in
                        Text(mode.label)
                            .tag(mode)
                    }
                } label: {
                    Text(sortMode.label)
                        .lineLimit(1)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text(
                isLoading || isLoadingUsers
                    ? "Prüfaufträge werden geladen …"
                    : "\(filteredJobs.count) Prüfaufträge"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.background)
    }

    var body: some View {
        NavigationStack(path: $navigation.safetyInspectionPath) {
            VStack(spacing: 0) {
                filterHeader

                if isSearchExpanded {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField(
                            "Prüfaufträge durchsuchen",
                            text: $navigation.safetyInspectionSearchText
                        )

                        if !navigation.safetyInspectionSearchText.isEmpty {
                            Button {
                                navigation.safetyInspectionSearchText = ""
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
                    if (isLoading || isLoadingUsers) && filteredJobs.isEmpty {
                        ProgressView("Prüfaufträge werden geladen …")
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                    } else if filteredJobs.isEmpty {
                        ContentUnavailableView(
                            "Keine Prüfaufträge",
                            systemImage: "checklist",
                            description: Text(
                                "Es sind aktuell keine passenden Prüfaufträge vorhanden."
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                    } else {
                        List(filteredJobs) { job in
                            NavigationLink(value: job) {
                                SafetyInspectionRowView(job: job)
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
            .navigationTitle("Prüfaufträge")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearchVisible = !isSearchExpanded

                            if !isSearchVisible {
                                navigation.safetyInspectionSearchText = ""
                            }
                        }
                    } label: {
                        Image(
                            systemName: isSearchExpanded
                                ? "magnifyingglass.circle.fill"
                                : "magnifyingglass"
                        )
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
            .navigationDestination(for: SafetyInspectionJob.self) { job in
                SafetyInspectionDetailView(jobId: job.id)
            }
            .navigationDestination(for: Int.self) { jobId in
                SafetyInspectionDetailView(jobId: jobId)
            }
            .task {
                await loadInitialData()
            }
            .onChange(of: ownerFilter) { _, _ in
                Task {
                    await loadJobs()
                }
            }
            .onChange(of: statusFilter) { _, _ in
                Task {
                    await loadJobs()
                }
            }
            .alert(
                "Fehler",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { visible in
                        if !visible {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func loadInitialData() async {
        guard !Task.isCancelled else { return }

        async let userLoad: Void = loadInspectionUsers()
        async let jobLoad: Void = loadJobs()

        _ = await (userLoad, jobLoad)
    }

    @MainActor
    private func loadInspectionUsers() async {
        guard !Task.isCancelled else { return }

        usersLoadRevision += 1
        let requestedRevision = usersLoadRevision
        isLoadingUsers = true

        defer {
            if requestedRevision == usersLoadRevision {
                isLoadingUsers = false
            }
        }

        do {
            let users = try await session.apiClient.fetchSafetyInspectionUsers()

            guard !Task.isCancelled,
                  requestedRevision == usersLoadRevision else {
                return
            }

            inspectionUsers = users

            if case .user(let userId) = ownerFilter,
               !users.contains(where: { $0.id == userId }) {
                ownerFilter = .mine
            }
        } catch {
            if error.isRequestCancellation
                || Task.isCancelled
                || requestedRevision != usersLoadRevision {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadJobs() async {
        guard !Task.isCancelled else { return }

        loadRevision += 1
        let requestedRevision = loadRevision
        let requestedOwner = ownerFilter
        let requestedStatus = statusFilter
        isLoading = true

        defer {
            if requestedRevision == loadRevision {
                isLoading = false
            }
        }

        do {
            let loadedJobs = try await session.apiClient.fetchSafetyInspections(
                status: requestedStatus.rawValue,
                scope: requestedOwner.scope.rawValue,
                userId: requestedOwner.userId
            )

            guard !Task.isCancelled,
                  requestedRevision == loadRevision,
                  requestedOwner == ownerFilter,
                  requestedStatus == statusFilter else {
                return
            }

            jobs = loadedJobs
        } catch {
            if error.isRequestCancellation
                || Task.isCancelled
                || requestedRevision != loadRevision
                || requestedOwner != ownerFilter
                || requestedStatus != statusFilter {
                return
            }

            errorMessage = error.localizedDescription
        }
    }
}

enum SafetyInspectionListFilter: String, CaseIterable, Identifiable {
    case active
    case planned
    case inProgress = "in_progress"
    case completed
    case completedWithDefects = "completed_with_defects"
    case missed
    case canceled
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active:
            return "Offen"
        case .planned:
            return "Geplant"
        case .inProgress:
            return "In Bearbeitung"
        case .completed:
            return "Erledigt"
        case .completedWithDefects:
            return "Erledigt mit Mängeln"
        case .missed:
            return "Abgelaufen"
        case .canceled:
            return "Abgebrochen"
        case .all:
            return "Alle Status"
        }
    }

    func matches(_ job: SafetyInspectionJob) -> Bool {
        switch self {
        case .active:
            return ["planned", "in_progress"].contains(job.status)
        case .completed:
            return ["completed", "completed_with_defects"].contains(job.status)
        case .all:
            return true
        default:
            return job.status == rawValue
        }
    }
}

enum SafetyInspectionSortMode: String, CaseIterable, Identifiable {
    case dueDate
    case address
    case status

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dueDate:
            return "Fälligkeit"
        case .address:
            return "Adresse"
        case .status:
            return "Status"
        }
    }
}

extension SafetyInspectionJob {
    func matchesSearch(_ searchText: String) -> Bool {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return query.isEmpty
            || group.name.lowercased().contains(query)
            || objectTitle.lowercased().contains(query)
            || (object.location ?? "").lowercased().contains(query)
            || (object.economicUnitIdnum ?? "").lowercased().contains(query)
            || (assignedUser?.displayName ?? "").lowercased().contains(query)
            || statusLabel.lowercased().contains(query)
    }
}
