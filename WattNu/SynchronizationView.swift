import SwiftUI

struct SynchronizationItem: Identifiable {
    let id: String
    let entityID: Int
    let title: String
    let createdAt: Date
    let error: String?
    let details: String?
}

private struct CommissionOfflineRefreshModifier: ViewModifier {
    @EnvironmentObject private var commissions: CommissionOfflineStore
    @State private var task: Task<Void, Never>?
    let action: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content.onChange(of: commissions.revision) { _, _ in
            task?.cancel()
            task = Task { await action() }
        }
        .onDisappear { task?.cancel() }
    }
}

extension View {
    func refreshForCommissionChanges(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(CommissionOfflineRefreshModifier(action: action))
    }
}

struct SynchronizationView: View {
    @EnvironmentObject private var commissions: CommissionOfflineStore
    @EnvironmentObject private var inspections: SafetyInspectionOfflineStore
    @State private var errorMessage: String?
    @State private var resolution: Resolution?
    @State private var isResolving = false

    private struct Resolution: Identifiable {
        let id: String
        let entityID: Int
        let module: String
        let keepLocal: Bool
    }

    var body: some View {
        List {
            Section("Aufträge") {
                statusRow(isSyncing: commissions.isSyncing, pending: commissions.snapshot.operations.count, lastSync: commissions.snapshot.lastSynchronizedAt)
                if !commissions.message.isEmpty { Text(commissions.message).font(.footnote).foregroundStyle(.secondary) }
                ForEach(commissions.snapshot.operations) { operation in
                    entry(SynchronizationItem(id: operation.id, entityID: operation.commissionID ?? operation.localID, title: operation.title, createdAt: operation.createdAt, error: operation.error, details: operation.errorDetails.flatMap { String(data: $0, encoding: .utf8) }), module: "commissions")
                }
                ForEach(commissions.snapshot.preparationErrors.keys.sorted(), id: \.self) { key in
                    DisclosureGroup("Daten konnten nicht aktualisiert werden") {
                        Text(key).font(.caption).textSelection(.enabled)
                        Text(commissions.snapshot.preparationErrors[key] ?? "").font(.footnote)
                    }
                }
                ForEach(Array(commissions.deliveryIssues.enumerated()), id: \.offset) { _, issue in
                    Label(issue, systemImage: "envelope.badge").font(.footnote)
                }
            }

            Section("Verkehrssicherung") {
                statusRow(isSyncing: inspections.isSyncing, pending: inspections.pendingCount, lastSync: inspections.lastSynchronizationDate)
                if !inspections.message.isEmpty { Text(inspections.message).font(.footnote).foregroundStyle(.secondary) }
                if !inspections.preparationText.isEmpty { Text(inspections.preparationText).font(.footnote).foregroundStyle(.secondary) }
                ForEach(inspections.synchronizationItems) { item in entry(item, module: "inspections") }
            }

            Section {
                Button("Synchronisierung erneut versuchen") {
                    do {
                        try commissions.retrySynchronization()
                        try inspections.retry()
                    } catch { errorMessage = error.localizedDescription }
                    Task { await commissions.retryServerDeliveries() }
                }
                .disabled(commissions.isSyncing || inspections.isSyncing || isResolving)
            } footer: {
                Text("Diese Seite zeigt ausstehende Änderungen und Probleme des angemeldeten Kontos auf diesem Gerät. Die Übertragung wird bei aktiver App automatisch fortgesetzt.")
            }
        }
        .navigationTitle("Synchronisierung")
        .navigationBarTitleDisplayMode(.inline)
        .task { await commissions.loadDeliveryIssues() }
        .refreshable { await commissions.loadDeliveryIssues() }
        .confirmationDialog(
            resolution?.keepLocal == true ? "Lokale Änderungen erneut anwenden?" : "Serverstand übernehmen?",
            isPresented: Binding(get: { resolution != nil }, set: { if !$0 { resolution = nil } }),
            titleVisibility: .visible,
            presenting: resolution
        ) { item in
            Button(item.keepLocal ? "Erneut prüfen und anwenden" : "Lokale Änderungen verwerfen", role: item.keepLocal ? nil : .destructive) {
                isResolving = true
                Task {
                    defer { isResolving = false; resolution = nil }
                    do {
                        if item.module == "commissions" { try await commissions.resolve(operationID: item.id, keepLocal: item.keepLocal) }
                        else { try await inspections.resolve(jobId: item.entityID, keepLocal: item.keepLocal) }
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            Button("Abbrechen", role: .cancel) { resolution = nil }
        } message: { item in
            Text(item.keepLocal ? "Der aktuelle Serverstand wird erneut geprüft. Lagerbestände, Berechtigungen und fachliche Regeln gelten weiterhin." : "Die betroffenen lokalen Änderungen und davon abhängige Vorgänge werden verworfen. Bei Prüfaufträgen betrifft dies alle ausstehenden Änderungen dieser Prüfung.")
        }
        .alert("Synchronisierung", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func statusRow(isSyncing: Bool, pending: Int, lastSync: Date?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(isSyncing ? "Übertragung läuft" : (pending == 0 ? "Keine ausstehenden Änderungen" : "\(pending) ausstehende Änderungen"), systemImage: isSyncing ? "arrow.triangle.2.circlepath" : "tray")
            if let lastSync { Text("Zuletzt übertragen: \(lastSync.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: "de_DE"))))").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func entry(_ item: SynchronizationItem, module: String) -> some View {
        DisclosureGroup {
            if let error = item.error {
                Text(error).font(.footnote).textSelection(.enabled)
                if let details = item.details, !details.isEmpty {
                    DisclosureGroup("Details") { Text(details).font(.caption).textSelection(.enabled) }
                }
                Button("Lokale Änderungen erneut anwenden") { resolution = Resolution(id: item.id, entityID: item.entityID, module: module, keepLocal: true) }
                Button("Serverstand übernehmen", role: .destructive) { resolution = Resolution(id: item.id, entityID: item.entityID, module: module, keepLocal: false) }
            } else { Text("Wartet auf Übertragung").font(.footnote).foregroundStyle(.secondary) }
            Text(item.createdAt, format: .dateTime.day().month().year().hour().minute()).font(.caption)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.entityID > 0 ? "\(module == "inspections" ? "Prüfauftrag" : "Auftrag") \(item.entityID) · \(item.title)" : item.title)
                Text(item.error == nil ? "Ausstehend" : "Übertragung benötigt Prüfung").font(.caption).foregroundStyle(item.error == nil ? Color.secondary : Color.orange)
            }
        }
        .disabled(isResolving || commissions.isSyncing || inspections.isSyncing)
    }
}
