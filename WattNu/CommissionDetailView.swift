import SwiftUI
import UIKit

enum CommissionDetailSection:
    String,
    CaseIterable,
    Identifiable {

    case order = "Auftrag"
    case photos = "Fotos"
    case materials = "Lager"
    case infos = "Infos"
    case time = "Zeit"
    case history = "Verlauf"

    var id: String {
        rawValue
    }
}

struct CommissionDetailRefreshID: Equatable {
    let commissionId: Int
    let section: CommissionDetailSection
}

struct CommissionDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @ObservedObject private var processInfos =
        ProcessInfoStore.shared

    let commissionId: Int

    @State private var commission: Commission?
    @State private var selectedSection: CommissionDetailSection = .order
    @State private var refreshRevision = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isCheckingCompletionTime = false
    @State private var completionTimeWarning: String?
    @State private var isCompletionPresented = false
    @State private var isRejectionPresented = false

    var body: some View {
        Group {
            if isLoading && commission == nil {
                ProgressView("Auftrag wird geladen …")
            } else if let commission {
                VStack(spacing: 0) {
                    ScrollView(
                        .horizontal,
                        showsIndicators: false
                    ) {
                        HStack(spacing: 8) {
                            ForEach(
                                CommissionDetailSection.allCases
                            ) { section in
                                Button(section.rawValue) {
                                    selectedSection = section
                                }
                                .buttonStyle(.plain)
                                .font(
                                    .subheadline.weight(
                                        .semibold
                                    )
                                )
                                .foregroundStyle(
                                    selectedSection == section
                                    ? Color.white
                                    : Color.primary
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedSection == section
                                    ? Color.accentColor
                                    : Color(
                                        .secondarySystemGroupedBackground
                                    )
                                )
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding()

                    Divider()

                    PendingCommissionStatusView(store: session.commissionStore, commissionID: commissionId)

                    switch selectedSection {
                    case .order:
                        OrderSectionView(
                            commission: commission,
                            isCheckingCompletionTime: isCheckingCompletionTime,
                            startAction: {
                                Task {
                                    await startCommission()
                                }
                            },
                            rejectAction: {
                                isRejectionPresented = true
                            },
                            completeAction: {
                                isCheckingCompletionTime = true
                            },
                            commissionUpdatedAction: { updatedCommission in
                                self.commission = updatedCommission
                                navigation.commissionListRevision += 1
                            }
                        )
                    case .photos:
                        CommissionObjectPhotosView(
                            commission: commission
                        )
                    case .materials:
                        if commission.isActionableValue {
                            MaterialsSectionView(
                                commission: commission
                            )
                        } else {
                            ContentUnavailableView(
                                "Übertragung ausstehend",
                                systemImage: "clock.arrow.circlepath",
                                description: Text(
                                    "Material kann erst nach der Wowiport-Bestätigung gebucht werden."
                                )
                            )
                        }

                    case .time:
                        if commission.isActionableValue {
                            TimeSectionView(
                                commission: commission
                            )
                        } else {
                            ContentUnavailableView(
                                "Übertragung ausstehend",
                                systemImage: "clock.arrow.circlepath",
                                description: Text(
                                    "Zeiten können erst nach der Wowiport-Bestätigung erfasst werden."
                                )
                            )
                        }
                    case .infos:
                        ProcessInfoView(
                            commissionId: commission.id
                        )
                    case .history:
                        CommissionHistoryView(
                            commission: commission
                        )
                    }
                }
            } else {
                ContentUnavailableView("Auftrag nicht gefunden", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(commission?.displayNumber ?? "Auftrag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let useUnitId = commission?.useUnitId, useUnitId > 0 {
                    Button {
                        openTeBe(useUnitId: useUnitId)
                    } label: {
                        Image(systemName: "hammer.fill")
                            .font(.footnote)
                    }
                    .accessibilityLabel("Wohnung in TeBe öffnen")
                }

                Button {
                    refreshRevision += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Auftrag und aktuellen Reiter aktualisieren")
                .accessibilityIdentifier("commission.reload")
                .disabled(commission == nil && isLoading)
            }
        }
        .refreshForCommissionChanges { await loadCommission(refresh: false) }
        .refreshOnActivation(id: CommissionDetailRefreshID(commissionId: commissionId, section: selectedSection)) {
            await loadCommission()
        }
        .environment(\.commissionRefreshRevision, refreshRevision)
        .task {
            if processInfos.consumeInfoRequest(
                commissionId: commissionId
            ) {
                selectedSection = .infos
            }
        }
        .onChange(
            of: processInfos.requestedCommissionId
        ) { _, _ in
            if processInfos.consumeInfoRequest(
                commissionId: commissionId
            ) {
                selectedSection = .infos
            }
        }
        .refreshable {
            await loadCommission()
        }
        .task(id: isCheckingCompletionTime) {
            if isCheckingCompletionTime {
                await prepareCompletion()
            }
        }
        .confirmationDialog(
            "Zeiten vor dem Abschluss",
            isPresented: Binding(
                get: { completionTimeWarning != nil },
                set: { if !$0 { completionTimeWarning = nil } }
            ),
            titleVisibility: .visible,
            presenting: completionTimeWarning
        ) { _ in
            Button("Zeit erfassen") {
                selectedSection = .time
            }
            Button("Trotzdem zum Abschluss") {
                isCompletionPresented = true
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { warning in
            Text(warning)
        }
        .sheet(
            isPresented: $isRejectionPresented
        ) {
            NavigationStack {
                if let commission {
                    CommissionRejectionView(
                        commission: commission
                    ) { _ in
                        navigation.returnToCommissionList()
                    }
                }
            }
            .environmentObject(session)
        }
        .sheet(
            isPresented: $isCompletionPresented
        ) {
            NavigationStack {
                if let commission {
                    CommissionCompletionView(
                        commission: commission
                    ) { _ in
                        navigation.returnToCommissionList()
                    }
                }
            }
            .environmentObject(session)
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
    
    @MainActor
    private func openTeBe(useUnitId: Int) {
        var components = URLComponents()
        components.scheme = "de.bytewish.tebe"
        components.host = "unit"
        components.queryItems = [
            URLQueryItem(name: "useUnitId", value: String(useUnitId))
        ]

        guard let url = components.url else {
            errorMessage = "Der TeBe-Link konnte nicht erstellt werden."
            return
        }

        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened else { return }

            Task { @MainActor in
                errorMessage = "TeBe konnte nicht geöffnet werden. Prüfe, ob die aktualisierte TeBe-App installiert ist."
            }
        }
    }

    private func loadCommission(refresh: Bool = true) async {
        if commission == nil { isLoading = true }

        defer {
            if isLoading { isLoading = false }
        }

        do {
            let loadedCommission = try await session.apiClient.fetchCommission(id: commissionId, refresh: refresh)
            guard !Task.isCancelled else { return }
            if commission != loadedCommission { commission = loadedCommission }
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func startCommission() async {
        do {
            commission = try await session.apiClient.startCommission(id: commissionId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareCompletion() async {
        defer { isCheckingCompletionTime = false }

        let warning: String?
        do {
            let hasTime = try await session.apiClient.hasRecordedTime(commissionId: commissionId)
            warning = hasTime ? nil : "Für diesen Auftrag wurden noch keine Zeiten erfasst."
        } catch {
            if error.isRequestCancellation { return }
            warning = "Die Zeiten für diesen Auftrag konnten gerade nicht geprüft werden."
        }

        guard !Task.isCancelled, selectedSection == .order else { return }
        if let warning {
            completionTimeWarning = warning
        } else {
            isCompletionPresented = true
        }
    }
}

private struct PendingCommissionStatusView: View {
    @ObservedObject var store: CommissionOfflineStore
    let commissionID: Int

    var body: some View {
        if let operation = store.snapshot.operations.first(where: { $0.groupID == commissionID && $0.changesStatus }) {
            Label(
                operation.blocked ? "Statusänderung benötigt Prüfung" : "Statusänderung wartet auf Synchronisierung",
                systemImage: operation.blocked ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath"
            )
            .font(.footnote)
            .padding(.vertical, 6)
        }
    }
}
