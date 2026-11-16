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

struct CommissionDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @ObservedObject private var processInfos =
        ProcessInfoStore.shared

    let commissionId: Int

    @State private var commission: Commission?
    @State private var selectedSection: CommissionDetailSection = .order
    @State private var isLoading = false
    @State private var errorMessage: String?
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

                    switch selectedSection {
                    case .order:
                        OrderSectionView(
                            commission: commission,
                            startAction: {
                                Task {
                                    await startCommission()
                                }
                            },
                            rejectAction: {
                                isRejectionPresented = true
                            },
                            completeAction: {
                                isCompletionPresented = true
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
            ToolbarItem(placement: .topBarTrailing) {
                if let useUnitId = commission?.useUnitId, useUnitId > 0 {
                    Button {
                        openTeBe(useUnitId: useUnitId)
                    } label: {
                        Image(systemName: "hammer.fill")
                            .font(.footnote)
                    }
                    .accessibilityLabel("Wohnung in TeBe öffnen")
                }
            }
        }
        .refreshForCommissionChanges { await loadCommission(refresh: false) }
        .refreshWhileActive(id: commissionId) {
            await loadCommission()
        }
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
}
