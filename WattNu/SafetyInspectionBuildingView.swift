import SwiftUI

struct InspectionBuildingId: Hashable {
    let level: String
    let objectId: Int

    init(_ object: SafetyInspectionObjectSummary) {
        if let buildingId = object.buildingErpId
            ?? (object.level == "building" ? object.erpId : nil) {
            level = "building"
            objectId = buildingId
        } else {
            level = object.level
            objectId = object.erpId
        }
    }
}

struct InspectionBuildingRoute: Hashable {
    let id: InspectionBuildingId
    let title: String
    let subtitle: String
    let jobIds: [Int]
    let scope: String
    let userId: Int?
    let initialStatus: String
    var templateId: Int? = nil
}

struct InspectionBuildingGroup: Identifiable {
    let id: InspectionBuildingId
    let jobs: [SafetyInspectionJob]

    private var representative: SafetyInspectionJob {
        jobs.first { $0.object.level == "building" } ?? jobs[0]
    }

    var title: String {
        let object = representative.object
        let address = (object.address ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return address.isEmpty
            ? "\(object.levelLabel) \(object.buildingIdnum ?? String(object.erpId))"
            : address
    }

    var subtitle: String {
        let object = representative.object
        var parts = [
            object.economicUnitName ?? object.economicUnitIdnum ?? ""
        ]

        if let number = object.buildingIdnum {
            parts.append("Gebäude \(number)")
        } else if object.level == "use_unit" {
            parts.append("Gebäudezuordnung fehlt")
        }

        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var summary: String {
        let open = jobs.filter(\.isOpenInspection).count
        let started = jobs.filter {
            $0.status == "in_progress"
        }.count
        let blocked = jobs.filter {
            $0.isOpenInspection && $0.visit?.blocked == true
        }.count

        let base = open > 0
            ? "\(open) offen, davon \(started) begonnen"
            : "\(jobs.count) Prüfungen"

        return blocked > 0
            ? base + " · \(blocked) ohne Zugang"
            : base
    }

    func route(
        scope: String,
        userId: Int?,
        initialStatus: String,
        templateId: Int? = nil
    ) -> InspectionBuildingRoute {
        InspectionBuildingRoute(
            id: id,
            title: title,
            subtitle: subtitle,
            jobIds: jobs.map(\.id),
            scope: scope,
            userId: userId,
            initialStatus: initialStatus,
            templateId: templateId
        )
    }
}

extension SafetyInspectionJob {
    var isOpenInspection: Bool {
        ["planned", "in_progress"].contains(status)
    }

    var inspectionBuildingId: InspectionBuildingId {
        InspectionBuildingId(object)
    }
}

@MainActor
struct InspectionBuildingView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var inspections: SafetyInspectionOfflineStore
    @Environment(\.scenePhase) private var scenePhase

    let route: InspectionBuildingRoute

    @State private var knownIds: Set<Int>
    @State private var jobs: [SafetyInspectionJob] = []
    @State private var statusFilter: SafetyInspectionListFilter
    @State private var expandedAreaId: String?
    @State private var errorMessage: String?
    @State private var visitTarget: InspectionVisitTarget?

    init(route: InspectionBuildingRoute) {
        self.route = route
        _knownIds = State(initialValue: Set(route.jobIds))

        let filter = ["active", "planned", "in_progress"].contains(route.initialStatus)
            ? SafetyInspectionListFilter.active
            : SafetyInspectionListFilter(rawValue: route.initialStatus) ?? .active

        _statusFilter = State(initialValue: filter)
    }

    private struct Area: Identifiable {
        let id: String
        let jobs: [SafetyInspectionJob]

        var isUnit: Bool {
            jobs[0].object.level == "use_unit"
        }

        var title: String {
            let object = jobs[0].object

            if object.level == "building" {
                return "Haus / Allgemeinbereiche"
            }

            if object.level == "economic_unit" {
                return "Wirtschaftseinheit"
            }

            return "Einheit \(object.useUnitIdnum ?? String(object.erpId))"
        }

        var location: String {
            jobs[0].object.location ?? ""
        }
    }

    private var areas: [Area] {
        let selected = jobs.filter { statusFilter.matches($0) }

        return Dictionary(grouping: selected, by: {
            "\($0.object.level):\($0.object.erpId)"
        })
        .map { entry in
            Area(
                id: entry.key,
                jobs: entry.value.sorted { left, right in
                    let comparison = left.template.name
                        .localizedStandardCompare(right.template.name)

                    if comparison != .orderedSame {
                        return comparison == .orderedAscending
                    }

                    if left.periodStart != right.periodStart {
                        return left.periodStart < right.periodStart
                    }

                    return left.id < right.id
                }
            )
        }
        .sorted { left, right in
            if left.isUnit != right.isUnit {
                return !left.isUnit
            }

            let comparison = left.title.localizedStandardCompare(right.title)

            return comparison == .orderedSame
                ? left.id < right.id
                : comparison == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                if !route.subtitle.isEmpty {
                    Text(route.subtitle)
                        .foregroundStyle(.secondary)
                }

                let open = jobs.filter(\.isOpenInspection).count
                let started = jobs.filter { $0.status == "in_progress" }.count

                Text("\(open) offen, davon \(started) begonnen")

                Picker("Anzeigen", selection: $statusFilter) {
                    ForEach(SafetyInspectionListFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
            }

            if areas.isEmpty {
                ContentUnavailableView(
                    statusFilter == .active
                        ? "Keine offenen Prüfungen"
                        : "Keine passenden Prüfungen",
                    systemImage: "checklist"
                )
            }

            ForEach(areas) { area in
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedAreaId == area.id },
                    set: { expandedAreaId = $0 ? area.id : nil }
                )) {
                    visitActions(for: area)
                    ForEach(area.jobs) { job in
                        NavigationLink(value: job.id) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(job.template.name)
                                    .font(.headline)

                                if job.group.name != job.template.name {
                                    Text(job.group.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                InspectionVisitBadge(job: job)

                                Text(job.statusLabel)
                                    .foregroundStyle(
                                        job.isOverdue
                                            ? Color.red
                                            : Color.secondary
                                    )

                                Text(
                                    "\(job.progress.checkedCount) von \(job.progress.resultCount) Prüfpunkten"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Text(
                                    "Fällig bis \(Formatters.dateText(job.dueTo))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(area.title)
                            .font(.headline)

                        if !area.location.isEmpty {
                            Text(area.location)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        let blocked = area.jobs.filter {
                            $0.isOpenInspection
                                && $0.visit?.blocked == true
                        }.count

                        if blocked > 0 {
                            Label(
                                "\(blocked) ohne Zugang",
                                systemImage: "door.left.hand.closed"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }

                        Text("\(area.jobs.count) Prüfungen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(item: $visitTarget) { target in
            SafetyInspectionVisitView(
                target: target,
                onSaved: reload
            )
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refresh()
            inspections.prepare(jobs.filter(\.isOpenInspection))
        }
        .task {
            await refresh()

            while !Task.isCancelled {
                if scenePhase == .active {
                    inspections.prepare(jobs.filter(\.isOpenInspection))
                }

                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
            }
        }
        .onChange(of: inspections.revision) { _, _ in
            reload()
        }
        .onChange(of: statusFilter) { _, _ in
            Task { await loadSelectedStatus() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await refresh()
                    inspections.prepare(jobs.filter(\.isOpenInspection))
                }
            }
        }
        .alert(
            "Prüfungen nicht verfügbar",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func matchesOwner(_ job: SafetyInspectionJob) -> Bool {
        route.scope == "mine"
            ? job.assignedUser?.id == session.user?.id
            : route.userId == nil || job.assignedUser?.id == route.userId
    }

    private func reload() {
        do {
            let active = try inspections.cachedJobs(
                status: "active",
                scope: route.scope,
                userId: route.userId
            ) ?? []

            let selected = try inspections.cachedJobs(
                status: statusFilter.rawValue,
                scope: route.scope,
                userId: route.userId
            ) ?? []

            let related = (active + selected).filter {
                $0.inspectionBuildingId == route.id
            }
            let newJobs = related.filter {
                $0.isOpenInspection && !knownIds.contains($0.id)
            }

            knownIds.formUnion(related.map(\.id))

            jobs = try inspections.cachedInspectionJobs(ids: Array(knownIds))
                .filter {
                    $0.inspectionBuildingId == route.id
                        && matchesOwner($0)
                        && (route.templateId == nil || $0.template.id == route.templateId)
                }

            if !newJobs.isEmpty {
                inspections.prepare(newJobs)
            }
        } catch {
            errorMessage = "Die gespeicherten Prüfungen konnten nicht gelesen werden."
        }
    }

    private func refresh() async {
        reload()

        do {
            let loaded = try await session.apiClient.fetchSafetyInspections(
                status: "active",
                scope: route.scope,
                userId: route.userId
            )

            guard !Task.isCancelled else { return }

            knownIds.formUnion(
                loaded.filter { $0.inspectionBuildingId == route.id }.map(\.id)
            )

            reload()
            await loadSelectedStatus()
        } catch {
            guard !Task.isCancelled, !error.isRequestCancellation else { return }

            if jobs.isEmpty {
                errorMessage = "Die Prüfungen konnten nicht geladen werden."
            }
        }
    }

    private func loadSelectedStatus() async {
        guard !["active", "planned", "in_progress"].contains(statusFilter.rawValue)
        else {
            return
        }

        let requestedStatus = statusFilter.rawValue

        do {
            let loaded = try await session.apiClient.fetchSafetyInspections(
                status: requestedStatus,
                scope: route.scope,
                userId: route.userId
            )

            guard !Task.isCancelled,
                  requestedStatus == statusFilter.rawValue else {
                return
            }

            knownIds.formUnion(
                loaded.filter { $0.inspectionBuildingId == route.id }.map(\.id)
            )
            reload()
        } catch {
            guard !Task.isCancelled, !error.isRequestCancellation else { return }

            if jobs.isEmpty {
                errorMessage = "Die Prüfungen konnten nicht geladen werden."
            }
        }
    }
    
    private func editableJobs(
        in area: Area
    ) -> [SafetyInspectionJob] {
        let object = area.jobs[0].object

        return jobs.filter {
            $0.object.level == object.level
                && $0.object.erpId == object.erpId
                && $0.isOpenInspection
                && $0.canEdit
        }
    }

    @ViewBuilder
    private func visitActions(for area: Area) -> some View {
        let editable = editableJobs(in: area)

        if !editable.isEmpty {
            Menu {
                Button("Kein Zugang melden") {
                    visitTarget = InspectionVisitTarget(
                        jobs: editable,
                        title: area.title,
                        mode: .noAccess
                    )
                }

                Button("Wiedervorlage festlegen") {
                    visitTarget = InspectionVisitTarget(
                        jobs: editable,
                        title: area.title,
                        mode: .followUp
                    )
                }

                if editable.contains(where: \.hasVisitTask) {
                    Button("Besuchsvermerk aufheben") {
                        do {
                            try inspections.recordVisit(
                                jobIds: editable.map(\.id),
                                blocked: false,
                                note: nil,
                                followUpOn: nil
                            )
                            reload()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } label: {
                Label(
                    "Besuch / Wiedervorlage",
                    systemImage: "calendar.badge.clock"
                )
            }
        }
    }
}
