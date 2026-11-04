import SwiftUI
import SwiftUI
import CoreLocation

struct SafetyInspectionListView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var inspections: SafetyInspectionOfflineStore
    @EnvironmentObject private var locationStore: LocationStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var jobs: [SafetyInspectionJob] = []
    @State private var inspectionUsers: [AppUser] = []
    @State private var isSearchVisible = false
    @State private var isFilterPresented = false
    @State private var isLoading = false
    @State private var isLoadingUsers = false
    @State private var usersLoadRevision = 0
    @State private var loadRevision = 0
    @State private var errorMessage: String?
    @State private var visitFilter: InspectionVisitFilter = .all
    
    @State private var selectedTemplateId: Int?

    private var availableTemplates: [SafetyInspectionTemplateSummary] {
        Dictionary(grouping: jobs, by: \.template.id)
            .compactMap { $0.value.first?.template }
            .sorted { left, right in
                let comparison = left.name.localizedStandardCompare(right.name)
                return comparison == .orderedSame
                    ? left.id < right.id
                    : comparison == .orderedAscending
            }
    }
    
    private var ownerFilter: CommissionOwnerFilter {
        navigation.safetyInspectionOwnerFilter
    }

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
    
    private var loadStatus: SafetyInspectionListFilter {
        switch statusFilter {
        case .active, .planned, .inProgress:
            return .active
        default:
            return statusFilter
        }
    }

    private var visibleBuildings: [InspectionBuildingGroup] {
        let grouped = Dictionary(grouping: filteredJobs, by: \.inspectionBuildingId)

        return grouped.map { entry -> (
            building: InspectionBuildingGroup,
            distance: Double,
            title: String
        ) in
            let building = InspectionBuildingGroup(
                id: entry.key,
                jobs: entry.value.sorted { $0.id < $1.id }
            )
            let coordinate = building.coordinate

            return (
                building: building,
                distance: locationStore.distanceMeters(
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude
                ) ?? .infinity,
                title: building.title
            )
        }
        .sorted { left, right in
            if left.distance != right.distance {
                return left.distance < right.distance
            }

            let comparison = left.title.localizedStandardCompare(right.title)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }

            if left.building.id.level != right.building.id.level {
                return left.building.id.level < right.building.id.level
            }

            return left.building.id.objectId < right.building.id.objectId
        }
        .map { $0.building }
    }

    private var filteredJobs: [SafetyInspectionJob] {
        let today = Formatters.apiDateText(Date())
        let searchText = navigation.safetyInspectionSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return jobs.filter { job in
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
                && (selectedTemplateId == nil || job.template.id == selectedTemplateId)
                && statusFilter.matches(job)
                && visitFilter.matches(job, today: today)
                && (searchText.isEmpty || job.matchesSearch(searchText))
        }
    }

        private var filterSummary: String {
            var parts = [ownerFilterLabel, statusFilter.label]

            if let selectedTemplateId {
                let name = availableTemplates.first {
                    $0.id == selectedTemplateId
                }?.name ?? "Prüfdetailplan \(selectedTemplateId)"
                parts.append(name)
            }

            if visitFilter != .all {
                parts.append(visitFilter.label)
            }

            return parts.joined(separator: " · ")
        }

    private func filterHeader(buildingCount: Int, jobCount: Int) -> some View {
        HStack(spacing: 8) {
            Text(filterSummary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(
                isLoading || isLoadingUsers
                    ? "Wird geladen …"
                    : "\(buildingCount) Gebäude · \(jobCount) Prüfungen"
            )
            .layoutPriority(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

        private var filterSheet: some View {
            NavigationStack {
                Form {
                    Section("Auswahl") {
                        Picker(
                            "Zuständigkeit",
                            selection: $navigation.safetyInspectionOwnerFilter
                        ) {
                            Text("Meine")
                                .tag(CommissionOwnerFilter.mine)

                            ForEach(colleagueUsers) { user in
                                Text(user.displayName)
                                    .tag(CommissionOwnerFilter.user(user.id))
                            }

                            Text("Alle")
                                .tag(CommissionOwnerFilter.all)
                        }

                        Picker(
                            "Status",
                            selection: $navigation.safetyInspectionStatusFilter
                        ) {
                            ForEach(SafetyInspectionListFilter.allCases) { filter in
                                Text(filter.label).tag(filter)
                            }
                        }

                        Picker(
                            "Prüfdetailplan",
                            selection: $selectedTemplateId
                        ) {
                            Text("Alle Prüfdetailpläne")
                                .tag(Int?.none)

                            ForEach(availableTemplates, id: \.id) { template in
                                Text(template.name)
                                    .tag(Optional(template.id))
                            }

                            if let selectedTemplateId,
                               !availableTemplates.contains(
                                   where: { $0.id == selectedTemplateId }
                               ) {
                                Text("Prüfdetailplan \(selectedTemplateId)")
                                    .tag(Optional(selectedTemplateId))
                            }
                        }

                        Picker(
                            "Besuchsvermerke",
                            selection: $visitFilter
                        ) {
                            ForEach(InspectionVisitFilter.allCases) { filter in
                                Text(filter.label).tag(filter)
                            }
                        }
                    }

                    Section {
                        Button("Filter zurücksetzen") {
                            navigation.safetyInspectionOwnerFilter = .mine
                            navigation.safetyInspectionStatusFilter = .active
                            selectedTemplateId = nil
                            visitFilter = .all
                        }
                    }
                }
                .pickerStyle(.navigationLink)
                .navigationTitle("Filter")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") {
                            isFilterPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }

    var body: some View {
        let buildings = visibleBuildings
        let jobCount = buildings.reduce(0) { $0 + $1.jobs.count }
        NavigationStack(path: $navigation.safetyInspectionPath) {
            VStack(spacing: 0) {
                filterHeader(
                    buildingCount: buildings.count,
                    jobCount: jobCount
                )
                
                if isSearchExpanded {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField(
                            "Adresse, Gebäude oder Prüfdetailplan",
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
                    if (isLoading || isLoadingUsers) && buildings.isEmpty {
                        ProgressView("Prüfaufträge werden geladen …")
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                    } else if buildings.isEmpty {
                        ContentUnavailableView(
                            "Keine passenden Gebäude",
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
                        List {
                            ForEach(buildings) { building in
                                Section {
                                    NavigationLink(value: building.route(
                                        scope: ownerFilter.scope.rawValue,
                                        userId: ownerFilter.userId,
                                        initialStatus: statusFilter.rawValue,
                                        templateId: selectedTemplateId
                                    )) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(building.title)
                                                .font(.headline)

                                            if !building.subtitle.isEmpty {
                                                Text(building.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Text(building.summary)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .listSectionSpacing(.compact)
                        .refreshable {
                            await loadInitialData()
                        }
                    }
                }
            }
            .navigationTitle("Prüfungen")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isFilterPresented) {
                filterSheet
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isFilterPresented = true
                    } label: {
                        Image(
                            systemName: "line.3.horizontal.decrease.circle"
                        )
                    }
                    .accessibilityLabel("Filter anzeigen")
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
                    
                    NavigationLink {
                        CommissionMapView(
                            initialDisplayMode: .safetyInspections
                        )
                    } label: {
                        Image(systemName: "map")
                    }
                    .accessibilityLabel("Karte anzeigen")

                    Button {
                        Task {
                            await loadInitialData()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(for: InspectionBuildingRoute.self) { route in
                InspectionBuildingView(route: route)
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
            .onChange(of: inspections.revision) { _, _ in
                if let cached = try? inspections.cachedUsers() {
                    inspectionUsers = cached
                }

                if let cached = try? inspections.cachedJobs(
                    status: loadStatus.rawValue,
                    scope: ownerFilter.scope.rawValue,
                    userId: ownerFilter.userId
                ) {
                    jobs = cached
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await loadInitialData()
                    }
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

        locationStore.requestLocation()

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
        if let cached = try? inspections.cachedUsers() {
            inspectionUsers = cached
        }

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
                navigation.safetyInspectionOwnerFilter = .mine
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
        let requestedLoadStatus = loadStatus
        isLoading = true
        if let cached = try? inspections.cachedJobs(
            status: requestedLoadStatus.rawValue,
            scope: requestedOwner.scope.rawValue,
            userId: requestedOwner.userId
        ) {
            jobs = cached
        }

        defer {
            if requestedRevision == loadRevision {
                isLoading = false
            }
        }

        do {
            let loadedJobs = try await session.apiClient.fetchSafetyInspections(
                status: requestedLoadStatus.rawValue,
                scope: requestedOwner.scope.rawValue,
                userId: requestedOwner.userId
            )

            guard !Task.isCancelled,
                  requestedRevision == loadRevision,
                  requestedOwner == ownerFilter,
                  requestedStatus == statusFilter else {
                return
            }

            if session.apiClient.safetyInspectionStore != nil {
                jobs = try inspections.cachedJobs(
                    status: requestedLoadStatus.rawValue,
                    scope: requestedOwner.scope.rawValue,
                    userId: requestedOwner.userId
                ) ?? []
            } else {
                jobs = loadedJobs
            }
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
        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive
        ]
        let locale = Locale(identifier: "de_DE")
        let terms = searchText
            .folding(options: options, locale: locale)
            .split(whereSeparator: { $0.isWhitespace })

        let text = [
            group.name,
            template.name,
            objectTitle,
            object.location ?? "",
            object.economicUnitIdnum ?? "",
            object.economicUnitName ?? "",
            object.buildingIdnum ?? "",
            object.useUnitIdnum ?? "",
            assignedUser?.displayName ?? "",
            statusLabel
        ]
        .joined(separator: " ")
        .folding(options: options, locale: locale)

        return terms.allSatisfy { text.contains(String($0)) }
    }
}
