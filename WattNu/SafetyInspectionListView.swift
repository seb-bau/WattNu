
import SwiftUI

struct SafetyInspectionListView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: AppNavigationStore

    @State private var jobs: [SafetyInspectionJob] = []
    private var searchText: String {
        navigation.safetyInspectionSearchText
    }

    private var statusFilter: SafetyInspectionListFilter {
        navigation.safetyInspectionStatusFilter
    }
    @State private var sortMode: SafetyInspectionSortMode = .dueDate
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredJobs: [SafetyInspectionJob] {
        let query = searchText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        let searchedJobs = jobs.filter {
            $0.matchesSearch(searchText)
        }

        switch sortMode {
        case .dueDate:
            return searchedJobs.sorted {
                if $0.dueTo == $1.dueTo {
                    return $0.id < $1.id
                }

                return $0.dueTo < $1.dueTo
            }

        case .address:
            return searchedJobs.sorted {
                $0.objectTitle
                    .localizedCaseInsensitiveCompare(
                        $1.objectTitle
                    ) == .orderedAscending
            }

        case .status:
            return searchedJobs.sorted {
                if $0.statusLabel == $1.statusLabel {
                    return $0.dueTo < $1.dueTo
                }

                return $0.statusLabel
                    .localizedCaseInsensitiveCompare(
                        $1.statusLabel
                    ) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack(
            path: $navigation.safetyInspectionPath
        ) {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Picker(
                        "Status",
                        selection: $navigation.safetyInspectionStatusFilter
                    ) {
                        ForEach(SafetyInspectionListFilter.allCases) { filter in
                            Text(filter.label)
                                .tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(
                        "Sortierung",
                        selection: $sortMode
                    ) {
                        ForEach(
                            SafetyInspectionSortMode.allCases
                        ) { mode in
                            Text(mode.label)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(
                    Color(.systemGroupedBackground)
                )

                Group {
                    if isLoading && jobs.isEmpty {
                        ProgressView(
                            "Prüfaufträge werden geladen …"
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                    } else if filteredJobs.isEmpty {
                        ContentUnavailableView(
                            "Keine Prüfaufträge",
                            systemImage: "checklist",
                            description: Text(
                                "Es sind aktuell keine passenden "
                                + "Prüfaufträge vorhanden."
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                    } else {
                        List(filteredJobs) { job in
                            NavigationLink(value: job) {
                                SafetyInspectionRowView(
                                    job: job
                                )
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
                        .background(
                            Color(.systemGroupedBackground)
                        )
                        .refreshable {
                            await loadJobs()
                        }
                    }
                }
            }
            .navigationTitle("Prüfaufträge")
            .searchable(
                text: $navigation.safetyInspectionSearchText,
                prompt: "Prüfaufträge suchen"
            )
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button {
                        Task {
                            await loadJobs()
                        }
                    } label: {
                        Image(
                            systemName: "arrow.clockwise"
                        )
                    }
                }
            }
            .navigationDestination(
                for: SafetyInspectionJob.self
            ) { job in
                SafetyInspectionDetailView(
                    jobId: job.id
                )
            }
            .navigationDestination(
                for: Int.self
            ) { jobId in
                SafetyInspectionDetailView(
                    jobId: jobId
                )
            }
            .task {
                await loadJobs()
            }
            .onChange(of: statusFilter) { _, _ in
                Task {
                    await loadJobs()
                }
            }
            .alert(
                "Fehler",
                isPresented: Binding(
                    get: {
                        errorMessage != nil
                    },
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

    private func loadJobs() async {
        let requestedFilter = statusFilter
        isLoading = true

        defer {
            if requestedFilter == statusFilter {
                isLoading = false
            }
        }

        do {
            let loadedJobs = try await session.apiClient.fetchSafetyInspections(
                status: requestedFilter.rawValue
            )

            guard !Task.isCancelled, requestedFilter == statusFilter else {
                return
            }

            jobs = loadedJobs
        } catch {
            if error.isRequestCancellation
                || Task.isCancelled
                || requestedFilter != statusFilter {
                return
            }

            errorMessage = error.localizedDescription
        }
    }
}

enum SafetyInspectionListFilter: String,
    CaseIterable,
    Identifiable {

    case active
    case completed
    case all

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .active:
            return "Offen"
        case .completed:
            return "Erledigt"
        case .all:
            return "Alle"
        }
    }
}

enum SafetyInspectionSortMode: String,
    CaseIterable,
    Identifiable {

    case dueDate
    case address
    case status

    var id: String {
        rawValue
    }

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
            || statusLabel.lowercased().contains(query)
    }
}
