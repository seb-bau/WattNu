import SwiftUI

struct SynchronizationItem: Identifiable {
    let id: String
    let entityID: Int
    let title: String
    let createdAt: Date
    let error: String?
    let details: String?
    var errorCode: String? = nil
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

private struct CommissionRefreshRevisionKey: EnvironmentKey {
    nonisolated static let defaultValue = 0
}

extension EnvironmentValues {
    var commissionRefreshRevision: Int {
        get { self[CommissionRefreshRevisionKey.self] }
        set { self[CommissionRefreshRevisionKey.self] = newValue }
    }
}

private struct CommissionActivationRefreshID<ID: Equatable>: Equatable {
    let value: ID
    let scenePhase: ScenePhase
    let revision: Int
}

private struct CommissionActivationRefreshModifier<ID: Equatable>: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.commissionRefreshRevision) private var refreshRevision
    @State private var loadedID: ID?
    let id: ID
    let action: @MainActor () async -> Void
    let refreshAction: (@MainActor () async -> Void)?

    func body(content: Content) -> some View {
        content.task(id: CommissionActivationRefreshID(value: id, scenePhase: scenePhase, revision: refreshRevision)) {
            guard scenePhase == .active else { return }
            if let loadedID, loadedID == id {
                await (refreshAction ?? action)()
            } else {
                await action()
                guard !Task.isCancelled else { return }
                loadedID = id
            }
        }
    }
}

extension View {
    func refreshForCommissionChanges(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(CommissionOfflineRefreshModifier(action: action))
    }

    func refreshOnActivation<ID: Equatable>(id: ID, refreshAction: (@MainActor () async -> Void)? = nil, _ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(CommissionActivationRefreshModifier(id: id, action: action, refreshAction: refreshAction))
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
        var errorCode: String? = nil
    }

    var body: some View {
        List {
            Section("Aufträge") {
                statusRow(isSyncing: commissions.isSyncing, pending: commissions.snapshot.operations.count, lastSync: commissions.snapshot.lastSynchronizedAt)
                if !commissions.message.isEmpty { Text(commissions.message).font(.footnote).foregroundStyle(.secondary) }
                ForEach(commissions.snapshot.operations) { operation in
                    entry(SynchronizationItem(id: operation.id, entityID: operation.groupID, title: operation.title, createdAt: operation.createdAt, error: operation.error, details: operation.errorDetails.flatMap { String(data: $0, encoding: .utf8) }, errorCode: operation.errorCode), module: "commissions")
                }
                if !commissions.preparationMessage.isEmpty || !commissions.preparationIssues.isEmpty {
                    Text("Datenaktualisierung").font(.subheadline).bold()
                }
                if !commissions.preparationMessage.isEmpty { Text(commissions.preparationMessage).font(.footnote).foregroundStyle(.secondary) }
                ForEach(commissions.preparationIssues) { issue in
                    DisclosureGroup(issue.title) {
                        if issue.paths.count > 1 { Text("\(issue.paths.count) Tagesübersichten betroffen.").font(.footnote) }
                        ForEach(issue.messages, id: \.self) { text in Text(text).font(.footnote) }
                        DisclosureGroup("Technische Details") {
                            ForEach(issue.paths, id: \.self) { path in Text(path).font(.caption).textSelection(.enabled) }
                        }
                    }
                }
                ForEach(Array(commissions.deliveryIssues.enumerated()), id: \.offset) { _, issue in
                    Label(issue, systemImage: "exclamationmark.triangle").font(.footnote)
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
                .disabled(isResolving)
            } footer: {
                Text("Diese Seite zeigt ausstehende Änderungen und Probleme des angemeldeten Kontos auf diesem Gerät. Die Übertragung wird bei aktiver App automatisch fortgesetzt.")
            }
        }
        .navigationTitle("Synchronisierung")
        .navigationBarTitleDisplayMode(.inline)
        .task { await commissions.loadDeliveryIssues() }
        .refreshable { await commissions.loadDeliveryIssues() }
        .confirmationDialog(
            resolution?.keepLocal == true ? "Lokale Änderungen erneut anwenden?" : "Lokale Änderungen verwerfen?",
            isPresented: Binding(get: { resolution != nil }, set: { if !$0 { resolution = nil } }),
            titleVisibility: .visible,
            presenting: resolution
        ) { item in
            Button(confirmationLabel(item), role: item.keepLocal ? nil : .destructive) {
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
            Text(confirmationMessage(item))
        }
        .alert("Synchronisierung", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func confirmationLabel(_ item: Resolution) -> String {
        if !item.keepLocal { return "Lokale Änderungen verwerfen" }
        if item.errorCode == "duplicate_booking" { return "Zusätzlich buchen" }
        if item.errorCode == "material_booking_confirmation_required" { return "Trotzdem abschließen" }
        return "Erneut prüfen und anwenden"
    }

    private func confirmationMessage(_ item: Resolution) -> String {
        if !item.keepLocal {
            return item.module == "commissions"
                ? "Nur dieser lokale Vorgang wird verworfen. Weitere Änderungen bleiben zur Übertragung oder Prüfung erhalten."
                : "Alle ausstehenden Änderungen dieser Prüfung werden verworfen."
        }
        if item.errorCode == "duplicate_booking" { return "Eine gleichartige Buchung ist am Server vorhanden. Bestätige hier, dass beide Buchungen gewollt sind." }
        if item.errorCode == "material_booking_confirmation_required" { return "Für diesen Auftrag ist eine Materialbuchung vorgesehen. Möchtest du den Auftrag trotzdem abschließen?" }
        return "Der aktuelle Serverstand wird erneut geprüft. Lagerbestände, Berechtigungen und fachliche Regeln gelten weiterhin."
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
                if !["commission_unavailable", "commission_closed", "local_dependency_discarded", "operation_reused"].contains(item.errorCode ?? "") {
                    let retry = Resolution(id: item.id, entityID: item.entityID, module: module, keepLocal: true, errorCode: item.errorCode)
                    Button(confirmationLabel(retry)) { resolution = retry }
                }
                Button(module == "commissions" ? "Diesen Vorgang verwerfen" : "Serverstand übernehmen", role: .destructive) { resolution = Resolution(id: item.id, entityID: item.entityID, module: module, keepLocal: false) }
            } else { Text("Wartet auf Übertragung").font(.footnote).foregroundStyle(.secondary) }
            Text(item.createdAt, format: .dateTime.day().month().year().hour().minute()).font(.caption)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.entityID > 0 ? "\(module == "inspections" ? "Prüfauftrag" : "Auftrag") \(item.entityID) · \(item.title)" : item.title)
                Text(item.error == nil ? "Ausstehend" : "Übertragung benötigt Prüfung").font(.caption).foregroundStyle(item.error == nil ? Color.secondary : Color.orange)
            }
        }
        .disabled(isResolving || (module == "commissions" ? !commissions.canResolve(groupID: item.entityID) : inspections.isSyncing))
    }
}
