import SwiftUI

enum CommissionDetailSection: String, CaseIterable, Identifiable {
    case order = "Auftrag"
    case materials = "Lager"
    case time = "Zeit"
    case history = "Verlauf"

    var id: String {
        rawValue
    }
}

struct CommissionDetailView: View {
    @EnvironmentObject private var session: SessionStore

    let commissionId: Int

    @State private var commission: Commission?
    @State private var selectedSection: CommissionDetailSection = .order
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isCompletionPresented = false

    var body: some View {
        Group {
            if isLoading && commission == nil {
                ProgressView("Auftrag wird geladen …")
            } else if let commission {
                VStack(spacing: 0) {
                    Picker("Bereich", selection: $selectedSection) {
                        ForEach(CommissionDetailSection.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
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
                            completeAction: {
                                isCompletionPresented = true
                            }
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
        .task {
            await loadCommission()
        }
        .refreshable {
            await loadCommission()
        }
        .sheet(
            isPresented: $isCompletionPresented
        ) {
            NavigationStack {
                if let commission {
                    CommissionCompletionView(
                        commission: commission
                    ) { updatedCommission in
                        self.commission = updatedCommission
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

    private func loadCommission() async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            commission = try await session.apiClient.fetchCommission(id: commissionId)
        } catch {
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
