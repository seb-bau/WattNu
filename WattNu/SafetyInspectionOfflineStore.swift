import Combine
import CryptoKit
import Foundation
import Network
import SwiftData

@Model
final class InspectionOfflineRow {
    @Attribute(.unique) var key: String
    var kind: String
    var jobId: Int
    var createdAt: Date
    var data: Data

    init(key: String, kind: String, jobId: Int, data: Data, createdAt: Date = Date()) {
        self.key = key
        self.kind = kind
        self.jobId = jobId
        self.createdAt = createdAt
        self.data = data
    }
}

struct InspectionOperationRequest: Codable {
    var operationId = UUID().uuidString.lowercased()
    var kind: String
    var jobId: Int
    var resultId: Int?
    var state: String?
    var note: String?
    var immediateAction: String?
    var version: Int?
    var photoId: Int?
    var photoOperationId: String?
    var source: String?
    var caption: String?
    var capturedAt: String?
    var overallNote: String?
    var occurredAt = Date().ISO8601Format()
    var replacesOperationId: String?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case kind
        case jobId = "job_id"
        case resultId = "result_id"
        case state, note
        case immediateAction = "immediate_action"
        case version
        case photoId = "photo_id"
        case photoOperationId = "photo_operation_id"
        case source, caption
        case capturedAt = "captured_at"
        case overallNote = "overall_note"
        case occurredAt = "occurred_at"
        case replacesOperationId = "replaces_operation_id"
    }
}

struct InspectionResultSnapshot: Codable, Equatable {
    let state: String
    let note: String?
    let immediateAction: String?

    init(state: String, note: String?, immediateAction: String?) {
        self.state = state
        self.note = Self.normalized(note)
        self.immediateAction = Self.normalized(immediateAction)
    }

    init(_ result: SafetyInspectionResult) {
        self.init(
            state: result.state,
            note: result.note,
            immediateAction: result.immediateAction
        )
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""

        return text.isEmpty ? nil : text
    }

    func merging(
        local: InspectionResultSnapshot,
        current: InspectionResultSnapshot
    ) throws -> InspectionResultSnapshot {
        if local.state != current.state,
           local != self,
           current != self {
            throw InspectionOfflineError.message(
                "Der Prüfauftrag enthält widersprüchliche Bearbeitungen. Die Eingaben bleiben gespeichert."
            )
        }

        func merged<T: Equatable>(
            _ base: T,
            _ local: T,
            _ remote: T
        ) throws -> T {
            if local == base {
                return remote
            }
            if remote == base || remote == local {
                return local
            }
            throw InspectionOfflineError.message(
                "Der Prüfauftrag enthält widersprüchliche Bearbeitungen. Die Eingaben bleiben gespeichert."
            )
        }

        return try InspectionResultSnapshot(
            state: merged(state, local.state, current.state),
            note: merged(note, local.note, current.note),
            immediateAction: merged(
                immediateAction,
                local.immediateAction,
                current.immediateAction
            )
        )
    }
}

struct InspectionPendingOperation: Codable {
    var request: InspectionOperationRequest
    var localPhoto: SafetyInspectionPhoto?
    var filename: String?
    var resolvedPhotoId: Int?
    var error: String?
    var baseResult: InspectionResultSnapshot?
    var attempts: Int?
    var retryAfter: Date?
}

struct InspectionOperationResponse: Decodable {
    let item: SafetyInspectionJob
    let operationId: String
    let photoId: Int?

    enum CodingKeys: String, CodingKey {
        case item
        case operationId = "operation_id"
        case photoId = "photo_id"
    }
}

struct InspectionOfflineDetailsResponse: Decodable {
    let items: [SafetyInspectionJob]
    let unavailableIds: [Int]

    enum CodingKeys: String, CodingKey {
        case items
        case unavailableIds = "unavailable_ids"
    }
}

struct InspectionSyncIssue: Identifiable {
    let id: Int
    let title: String
    let message: String
}

enum InspectionOfflineError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }

    static func isConnectionError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [
            .notConnectedToInternet, .networkConnectionLost, .timedOut,
            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed
        ].contains(error.code)
    }
}

@MainActor
final class SafetyInspectionOfflineStore: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var pendingCount = 0
    @Published private(set) var preparedCount = 0
    @Published private(set) var pendingJobIds: Set<Int> = []
    @Published private(set) var completionJobIds: Set<Int> = []
    @Published private(set) var issues: [InspectionSyncIssue] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var isPreparing = false
    @Published private(set) var preparationText = ""
    @Published private(set) var message = ""

    private var container: ModelContainer?
    private var context: ModelContext?
    private var rootURL: URL?
    private var user: AppUser?
    private var transport: APIClient?
    private var accountKey: String?
    private var generation = 0
    private var jobRevisions: [Int: Int] = [:]
    private var syncTask: Task<Void, Never>?
    private var syncRequested = false
    private var timerTask: Task<Void, Never>?
    private var isActive = true
    private var isResolving = false
    private let monitor = NWPathMonitor()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var refreshTasks: [String: Task<Void, Never>] = [:]

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                Task { @MainActor [weak self] in self?.requestSync() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "inspection.network"))
    }

    func bind(user: AppUser?, baseURL: URL, token: String?) throws {
        guard let user, let token else {
            stop()
            return
        }
        let key = SHA256.hash(
            data: Data("\(baseURL.absoluteString)|\(user.id)".utf8)
        ).map { String(format: "%02x", $0) }.joined()
        if accountKey != key {
            stop()
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("InspectionOffline/\(key)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: root.path
            )
            let configuration = ModelConfiguration(
                url: root.appendingPathComponent("inspections.store"),
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: InspectionOfflineRow.self, configurations: configuration
            )
            self.container = container
            context = ModelContext(container)
            context?.autosaveEnabled = false
            rootURL = root
            accountKey = key
            try publish()
            try? cleanUnreferencedPhotos()
        }
        self.user = user
        let client = APIClient(baseURL: baseURL)
        client.accessToken = token
        transport = client
        requestSync()
        startTimer()
    }

    func stop() {
        generation += 1
        for task in refreshTasks.values {
            task.cancel()
        }
        refreshTasks.removeAll()
        syncTask?.cancel()
        timerTask?.cancel()
        syncTask = nil
        syncRequested = false
        timerTask = nil
        transport = nil
        user = nil
        context = nil
        container = nil
        rootURL = nil
        accountKey = nil
        jobRevisions = [:]
        pendingCount = 0
        preparedCount = 0
        pendingJobIds = []
        completionJobIds = []
        issues = []
        isSyncing = false
        isPreparing = false
        isResolving = false
        preparationText = ""
        message = ""
        revision += 1
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            requestSync()
            startTimer()
        } else {
            timerTask?.cancel()
            timerTask = nil
        }
    }

    private func startTimer() {
        guard isActive, transport != nil, timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.requestSync()
            }
        }
    }

    private func database() throws -> ModelContext {
        guard let context else {
            throw InspectionOfflineError.message(
                "Der Offline-Speicher ist nicht verfügbar. Bitte erneut anmelden."
            )
        }
        return context
    }

    private func row(_ key: String) throws -> InspectionOfflineRow? {
        var descriptor = FetchDescriptor<InspectionOfflineRow>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        return try database().fetch(descriptor).first
    }

    private func rows(_ kind: String) throws -> [InspectionOfflineRow] {
        try database().fetch(FetchDescriptor<InspectionOfflineRow>(
            predicate: #Predicate { $0.kind == kind },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.key)]
        ))
    }

    private func put<T: Encodable>(
        _ value: T,
        key: String,
        kind: String,
        jobId: Int = 0
    ) throws {
        let data = try encoder.encode(value)

        if let existing = try row(key) {
            existing.data = data
        } else {
            try database().insert(InspectionOfflineRow(
                key: key,
                kind: kind,
                jobId: jobId,
                data: data
            ))
        }

        if kind == "job", var summary = value as? SafetyInspectionJob {
            summary.results = nil
            try put(
                summary,
                key: "summary:\(summary.id)",
                kind: "summary",
                jobId: summary.id
            )
        }
    }

    private func save() throws {
        let context = try database()
        do {
            if context.hasChanges { try context.save() }
        } catch {
            context.rollback()
            throw error
        }
    }

    private func transaction(_ block: () throws -> Void) throws {
        let context = try database()
        do {
            try block()
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func changed() {
        do { try publish() }
        catch {
            message = "Speicherstatus konnte nicht gelesen werden: \(error.localizedDescription)"
        }
    }

    private func cleanUnreferencedPhotos() throws {
        guard let rootURL else { return }
        let names = Set(try operations().compactMap(\.filename))
        let urls = try FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil
        )
        for url in urls where url.pathExtension == "jpg" {
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  !names.contains(url.lastPathComponent) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func operations() throws -> [InspectionPendingOperation] {
        try rows("operation").map {
            try decoder.decode(InspectionPendingOperation.self, from: $0.data)
        }
    }

    private func publish() throws {
        let pending = try operations()
        pendingCount = pending.count
        pendingJobIds = Set(pending.map { $0.request.jobId })
        completionJobIds = Set(pending.filter {
            $0.request.kind == "complete"
        }.map { $0.request.jobId })

        preparedCount = try database().fetchCount(
            FetchDescriptor<InspectionOfflineRow>(
                predicate: #Predicate { $0.kind == "job" }
            )
        )

        var seen: Set<Int> = []
        issues = pending.compactMap { operation in
            guard let error = operation.error,
                  seen.insert(operation.request.jobId).inserted else {
                return nil
            }

            return InspectionSyncIssue(
                id: operation.request.jobId,
                title: "Prüfauftrag \(operation.request.jobId)",
                message: error
            )
        }

        revision += 1
    }

    func cachedUsers() throws -> [AppUser]? {
        if let value = try row("users") {
            return try decoder.decode([AppUser].self, from: value.data)
        }

        var known: [Int: AppUser] = [:]

        if let user {
            known[user.id] = user
        }

        for job in try cachedJobs(
            status: "all",
            scope: "all",
            userId: nil
        ) ?? [] {
            if let owner = job.assignedUser {
                known[owner.id] = owner
            }
        }

        return known.isEmpty ? nil : Array(known.values)
    }

    private func loadCached<T>(
        key: String,
        cached: @escaping @MainActor () throws -> T?,
        fetch: @escaping @MainActor (APIClient) async throws -> T,
        store: @escaping @MainActor (T) throws -> Void
    ) async throws -> T {
        guard let transport else {
            throw InspectionOfflineError.message("Bitte anmelden.")
        }

        let expectedGeneration = generation

        if let value = try cached() {
            if isActive, refreshTasks[key] == nil {
                refreshTasks[key] = Task { [weak self] in
                    guard let self else { return }

                    defer {
                        if self.generation == expectedGeneration {
                            self.refreshTasks[key] = nil
                        }
                    }

                    do {
                        let value = try await fetch(transport)
                        guard self.generation == expectedGeneration else {
                            return
                        }

                        try store(value)
                        self.changed()
                    } catch {
                        return
                    }
                }
            }

            requestSync()
            return value
        }

        do {
            let value = try await fetch(transport)
            guard generation == expectedGeneration else {
                throw CancellationError()
            }

            try store(value)
            changed()
            return try cached() ?? value
        } catch {
            guard generation == expectedGeneration else {
                throw CancellationError()
            }

            if InspectionOfflineError.isConnectionError(error),
               let value = try cached() {
                return value
            }

            throw error
        }
    }

    func fetchUsers() async throws -> [AppUser] {
        try await loadCached(
            key: "users",
            cached: {
                try self.cachedUsers()
            },
            fetch: {
                try await $0.fetchSafetyInspectionUsersRemote()
            },
            store: { users in
                try self.transaction {
                    try self.put(users, key: "users", kind: "users")
                }
            }
        )
    }

    private func listKey(
        status: String, scope: String, overdue: Bool, userId: Int?
    ) -> String {
        "list:\(status):\(scope):\(overdue):\(userId.map(String.init) ?? "-")"
    }

    func cachedJobs(
        status: String, scope: String, overdue: Bool = false, userId: Int?
    ) throws -> [SafetyInspectionJob]? {
        let key = listKey(
            status: status, scope: scope, overdue: overdue, userId: userId
        )
        var items: [SafetyInspectionJob]
        if let value = try row(key) {
            items = try decoder.decode([SafetyInspectionJob].self, from: value.data)
        } else {
            let lists = try rows("list")
            let summaries = try rows("summary")
            var byId: [Int: SafetyInspectionJob] = [:]

            for list in lists {
                for job in try decoder.decode(
                    [SafetyInspectionJob].self,
                    from: list.data
                ) {
                    byId[job.id] = job
                }
            }

            for value in summaries {
                let job = try decoder.decode(
                    SafetyInspectionJob.self,
                    from: value.data
                )
                byId[job.id] = job
            }

            if lists.isEmpty && summaries.isEmpty {
                for value in try rows("job") {
                    var job = try decoder.decode(
                        SafetyInspectionJob.self,
                        from: value.data
                    )
                    job.results = nil
                    byId[job.id] = job
                }
            }

            guard !byId.isEmpty || !lists.isEmpty else {
                return nil
            }

            items = Array(byId.values)
        }
        let pending = try operations()
        let grouped = Dictionary(grouping: pending, by: { $0.request.jobId })
        var knownIds = Set(items.map(\.id))
        for jobId in grouped.keys where !knownIds.contains(jobId) {
            if let detail = try row("job:\(jobId)") {
                items.append(
                    try decoder.decode(SafetyInspectionJob.self, from: detail.data)
                )
                knownIds.insert(jobId)
            }
        }
        for index in items.indices {
            guard let changes = grouped[items[index].id],
                  let detail = try row("job:\(items[index].id)") else { continue }
            var job = try decoder.decode(SafetyInspectionJob.self, from: detail.data)
            for operation in changes {
                apply(operation, to: &job)
            }
            items[index] = job
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return items.filter { job in
            let ownerMatches = scope == "mine"
                ? job.assignedUser?.id == user?.id
                : userId == nil || job.assignedUser?.id == userId
            let statusMatches: Bool
            switch status {
            case "active":
                statusMatches = ["planned", "in_progress"].contains(job.status)
            case "completed":
                statusMatches = ["completed", "completed_with_defects"].contains(job.status)
            case "all":
                statusMatches = true
            default:
                statusMatches = job.status == status
            }
            return ownerMatches && statusMatches && (!overdue || job.dueTo < today)
        }.sorted {
            $0.dueTo == $1.dueTo ? $0.id < $1.id : $0.dueTo < $1.dueTo
        }
    }

    func fetchJobs(
        status: String,
        scope: String,
        overdue: Bool,
        userId: Int?
    ) async throws -> [SafetyInspectionJob] {
        let revisions = jobRevisions
        let key = listKey(
            status: status,
            scope: scope,
            overdue: overdue,
            userId: userId
        )

        return try await loadCached(
            key: key,
            cached: {
                try self.cachedJobs(
                    status: status,
                    scope: scope,
                    overdue: overdue,
                    userId: userId
                )
            },
            fetch: {
                try await $0.fetchSafetyInspectionsRemote(
                    status: status,
                    scope: scope,
                    overdueOnly: overdue,
                    userId: userId
                )
            },
            store: { response in
                var items = response

                for index in items.indices
                where revisions[items[index].id, default: 0]
                    != self.jobRevisions[items[index].id, default: 0] {
                    if var latest = try self.cachedJob(items[index].id) {
                        latest.results = nil
                        items[index] = latest
                    }
                }

                try self.transaction {
                    try self.put(items, key: key, kind: "list")
                }
            }
        )
    }

    func cachedJob(_ jobId: Int) throws -> SafetyInspectionJob? {
        guard let value = try row("job:\(jobId)") else { return nil }
        var job = try decoder.decode(SafetyInspectionJob.self, from: value.data)
        let changes = try database().fetch(FetchDescriptor<InspectionOfflineRow>(
            predicate: #Predicate {
                $0.kind == "operation" && $0.jobId == jobId
            },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.key)]
        ))
        for value in changes {
            apply(
                try decoder.decode(InspectionPendingOperation.self, from: value.data),
                to: &job
            )
        }
        return job
    }

    func fetchJob(_ jobId: Int) async throws -> SafetyInspectionJob {
        let expectedRevision = jobRevisions[jobId, default: 0]

        do {
            return try await loadCached(
                key: "job:\(jobId)",
                cached: {
                    try self.cachedJob(jobId)
                },
                fetch: {
                    try await $0.fetchSafetyInspectionRemote(id: jobId)
                },
                store: { job in
                    guard expectedRevision
                        == self.jobRevisions[jobId, default: 0] else {
                        return
                    }

                    try self.transaction {
                        try self.put(
                            job,
                            key: "job:\(jobId)",
                            kind: "job",
                            jobId: jobId
                        )
                        try self.updateLists(job)
                    }
                }
            )
        } catch {
            if InspectionOfflineError.isConnectionError(error) {
                throw InspectionOfflineError.message(
                    "Dieser Prüfauftrag wurde auf diesem Gerät noch nicht geöffnet. Zum ersten Öffnen ist eine Internetverbindung erforderlich."
                )
            }

            throw error
        }
    }

    func prepare(_ jobs: [SafetyInspectionJob]) async {
        guard !isPreparing, let transport else { return }
        isPreparing = true
        let expectedGeneration = generation
        defer {
            if generation == expectedGeneration {
                isPreparing = false
            }
        }
        do {
            let ids = jobs.map(\.id)
            for offset in stride(from: 0, to: ids.count, by: 50) {
                try Task.checkCancellation()
                let batch = Array(ids[offset..<min(offset + 50, ids.count)])
                let revisions = Dictionary(uniqueKeysWithValues: batch.map {
                    ($0, jobRevisions[$0, default: 0])
                })
                let response = try await transport.fetchInspectionOfflineDetails(ids: batch)
                guard generation == expectedGeneration else { return }
                try transaction {
                    for job in response.items
                    where revisions[job.id] == jobRevisions[job.id, default: 0] {
                        try put(job, key: "job:\(job.id)", kind: "job", jobId: job.id)
                    }
                }
                changed()
                preparationText = "\(min(offset + batch.count, ids.count)) von \(ids.count) vorbereitet"
                if !response.unavailableIds.isEmpty {
                    throw InspectionOfflineError.message(
                        "Einige Prüfungen sind nicht mehr verfügbar. Bitte die Liste aktualisieren."
                    )
                }
            }
            preparationText = "Prüfungen sind offline vorbereitet."
        } catch {
            guard generation == expectedGeneration else { return }
            context?.rollback()
            preparationText = "Vorbereitung unterbrochen: \(error.localizedDescription)"
        }
    }

    private func enqueue(_ operation: InspectionPendingOperation) throws {
        let context = try database()
        let existing = try rows("operation").last?.createdAt.timeIntervalSince1970 ?? 0
        let createdAt = Date(timeIntervalSince1970: max(
            Date().timeIntervalSince1970, existing + 0.000001
        ))
        try transaction {
            context.insert(InspectionOfflineRow(
                key: "operation:\(operation.request.operationId)",
                kind: "operation",
                jobId: operation.request.jobId,
                data: try encoder.encode(operation),
                createdAt: createdAt
            ))
        }
        jobRevisions[operation.request.jobId, default: 0] += 1
        changed()
        requestSync()
    }

    private func editableJob(_ jobId: Int) throws -> SafetyInspectionJob {
        guard let job = try cachedJob(jobId), job.results != nil else {
            throw InspectionOfflineError.message(
                "Diesen Prüfauftrag bitte zuerst mit Internet öffnen."
            )
        }
        guard !isResolving else {
            throw InspectionOfflineError.message(
                "Bitte die Konfliktklärung abwarten."
            )
        }
        guard job.canEdit, !completionJobIds.contains(jobId) else {
            throw InspectionOfflineError.message(
                "Diese Prüfung ist nicht mehr bearbeitbar."
            )
        }
        return job
    }

    func saveResult(
        jobId: Int,
        resultId: Int,
        state: String,
        note: String?,
        immediateAction: String?,
        version: Int,
        baseResult: InspectionResultSnapshot? = nil
    ) throws -> SafetyInspectionResult {
        let job = try editableJob(jobId)

        guard let result = job.results?.first(
            where: { $0.id == resultId }
        ) else {
            throw InspectionOfflineError.message(
                "Der Prüfpunkt fehlt im Offline-Speicher."
            )
        }

        let current = InspectionResultSnapshot(result)
        var origin = current
        var expectedVersion = result.version
        var local = InspectionResultSnapshot(
            state: state,
            note: note,
            immediateAction: immediateAction
        )

        if result.version != version {
            guard let baseResult else {
                throw InspectionOfflineError.message(
                    "Der Prüfpunkt wurde zwischenzeitlich geändert."
                )
            }

            do {
                local = try baseResult.merging(
                    local: local,
                    current: current
                )
            } catch {
                origin = baseResult
                expectedVersion = version
            }
        }

        let request = InspectionOperationRequest(
            kind: "result",
            jobId: jobId,
            resultId: resultId,
            state: local.state,
            note: local.note,
            immediateAction: local.immediateAction,
            version: expectedVersion
        )

        try enqueue(InspectionPendingOperation(
            request: request,
            baseResult: origin
        ))

        guard let updated = try cachedJob(jobId)?.results?.first(
            where: { $0.id == resultId }
        ) else {
            throw InspectionOfflineError.message(
                "Der gespeicherte Prüfpunkt konnte nicht gelesen werden."
            )
        }

        return updated
    }

    func addPhoto(
        jobId: Int, resultId: Int, data: Data, source: String,
        caption: String?, capturedAt: Date
    ) throws -> SafetyInspectionPhotoUploadResponse {
        let job = try editableJob(jobId)
        guard job.results?.contains(where: { $0.id == resultId }) == true else {
            throw InspectionOfflineError.message(
                "Der Prüfpunkt fehlt im Offline-Speicher."
            )
        }
        guard let rootURL, let user else {
            throw InspectionOfflineError.message("Der Offline-Speicher fehlt.")
        }
        let request = InspectionOperationRequest(
            kind: "photo", jobId: jobId, resultId: resultId,
            source: source, caption: caption, capturedAt: capturedAt.ISO8601Format()
        )
        guard !data.isEmpty, data.count <= 15 * 1024 * 1024 else {
            throw InspectionOfflineError.message(
                "Das Foto muss kleiner als 15 MB sein."
            )
        }
        let filename = "\(request.operationId).jpg"
        let url = rootURL.appendingPathComponent(filename)
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        let id = -max(1, Int(
            request.operationId.replacingOccurrences(of: "-", with: "").prefix(15),
            radix: 16
        ) ?? 1)
        let photo = SafetyInspectionPhoto(
            id: id, publicId: request.operationId, source: source,
            originalFilename: "prueffoto.jpg", mimeType: "image/jpeg",
            sizeBytes: data.count, caption: caption,
            capturedAt: capturedAt.ISO8601Format(), createdAt: request.occurredAt,
            updatedAt: request.occurredAt, uploadedBy: user,
            contentPath: "offline-photo/\(request.operationId)",
            thumbnailPath: "offline-photo/\(request.operationId)"
        )
        do {
            try enqueue(InspectionPendingOperation(
                request: request, localPhoto: photo, filename: filename
            ))
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return SafetyInspectionPhotoUploadResponse(item: photo, duplicate: false)
    }

    func deletePhoto(jobId: Int, resultId: Int, photoId: Int) throws {
        let job = try editableJob(jobId)
        guard let photo = job.results?.first(where: { $0.id == resultId })?
            .photos.first(where: { $0.id == photoId }) else { return }
        let request = InspectionOperationRequest(
            kind: "delete_photo", jobId: jobId, resultId: resultId,
            photoId: photoId > 0 ? photoId : nil,
            photoOperationId: photoId < 0 ? photo.publicId : nil
        )
        try enqueue(InspectionPendingOperation(request: request))
    }

    func complete(jobId: Int, note: String?) throws -> SafetyInspectionJob {
        let job = try editableJob(jobId)
        for result in job.results ?? [] {
            if result.required && result.state == "not_checked" {
                throw InspectionOfflineError.message(
                    "„\(result.title)“ wurde noch nicht bearbeitet."
                )
            }
            if ["not_present", "defect_info", "defect_urgent"].contains(result.state)
                && (result.note ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                throw InspectionOfflineError.message(
                    "Für „\(result.title)“ fehlt die Beschreibung."
                )
            }
            let required: Bool
            switch result.state {
            case "no_defect":
                required = result.photoRequirements.noDefect
            case "not_present":
                required = result.photoRequirements.notPresent
            case "defect_info":
                required = result.photoRequirements.defectInfo
            case "defect_urgent":
                required = result.photoRequirements.defectUrgent
            default:
                required = false
            }
            if required && result.photos.isEmpty {
                throw InspectionOfflineError.message(
                    "Für „\(result.title)“ fehlt ein Foto."
                )
            }
        }
        try enqueue(InspectionPendingOperation(request: InspectionOperationRequest(
            kind: "complete", jobId: jobId, overallNote: note
        )))
        guard let updated = try cachedJob(jobId) else {
            throw InspectionOfflineError.message(
                "Der gespeicherte Prüfauftrag konnte nicht gelesen werden."
            )
        }
        return updated
    }

    func localPhoto(_ path: String) throws -> Data {
        let id = String(path.dropFirst("offline-photo/".count))
        guard UUID(uuidString: id) != nil, let rootURL else {
            throw InspectionOfflineError.message("Die lokale Bilddatei fehlt.")
        }
        return try Data(contentsOf: rootURL.appendingPathComponent("\(id).jpg"))
    }

    private func apply(
        _ operation: InspectionPendingOperation,
        to job: inout SafetyInspectionJob
    ) {
        let request = operation.request
        if request.kind == "complete" {
            job.status = (job.results ?? []).contains {
                ["defect_info", "defect_urgent"].contains($0.state)
            } ? "completed_with_defects" : "completed"
            job.canEdit = false
            job.isTerminal = true
            job.overallNote = request.overallNote
            return
        }
        guard var results = job.results,
              let index = results.firstIndex(
                  where: { $0.id == request.resultId }
              ) else { return }
        switch request.kind {
        case "result":
            results[index].state = request.state ?? results[index].state
            results[index].note = request.note
            results[index].immediateAction = request.immediateAction
            results[index].version = (request.version ?? results[index].version) + 1
            if job.status == "planned" {
                job.status = "in_progress"
            }
        case "photo":
            if let photo = operation.localPhoto,
               !results[index].photos.contains(
                   where: { $0.publicId == photo.publicId }
               ) {
                results[index].photos.append(photo)
            }
        case "delete_photo":
            results[index].photos.removeAll {
                $0.id == (operation.resolvedPhotoId ?? request.photoId)
                    || $0.publicId == request.photoOperationId
            }
        default:
            break
        }
        job.results = results
        job.progress.checkedCount = results.filter {
            $0.state != "not_checked"
        }.count
        job.progress.photoCount = results.reduce(0) {
            $0 + $1.photos.count
        }
    }

    func requestSync() {
        guard isActive, !isResolving, transport != nil, context != nil else {
            return
        }
        guard syncTask == nil else {
            syncRequested = true
            return
        }
        syncRequested = false
        let expectedGeneration = generation
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.synchronize(generation: expectedGeneration)
            if self.generation == expectedGeneration {
                self.syncTask = nil
                if self.syncRequested {
                    self.requestSync()
                }
            }
        }
    }
    
    private func rebasePendingResults(
        after failed: InspectionOperationRequest,
        generation expectedGeneration: Int
    ) async throws -> Bool {
        guard failed.kind == "result", let transport else {
            return false
        }

        let serverJob = try await transport.fetchSafetyInspectionRemote(
            id: failed.jobId
        )

        guard generation == expectedGeneration else {
            throw CancellationError()
        }

        guard serverJob.canEdit,
              let failedResult = serverJob.results?.first(
                  where: { $0.id == failed.resultId }
              ),
              failedResult.version != failed.version else {
            return false
        }

        let entries = try rows("operation").filter {
            $0.jobId == failed.jobId
        }
        var current = Dictionary(
            uniqueKeysWithValues: (serverJob.results ?? []).map {
                ($0.id, $0)
            }
        )
        var updates: [(InspectionOfflineRow, InspectionPendingOperation)] = []

        for entry in entries {
            var operation = try decoder.decode(
                InspectionPendingOperation.self,
                from: entry.data
            )

            if operation.request.kind == "result" {
                guard let resultId = operation.request.resultId,
                      var result = current[resultId],
                      let base = operation.baseResult else {
                    return false
                }

                let remote = InspectionResultSnapshot(result)
                let local = InspectionResultSnapshot(
                    state: operation.request.state ?? base.state,
                    note: operation.request.note,
                    immediateAction: operation.request.immediateAction
                )
                let merged = try base.merging(
                    local: local,
                    current: remote
                )

                operation.request.replacesOperationId =
                    operation.request.operationId
                operation.request.operationId =
                    UUID().uuidString.lowercased()
                operation.request.version = result.version
                operation.request.state = merged.state
                operation.request.note = merged.note
                operation.request.immediateAction = merged.immediateAction
                operation.baseResult = remote

                result.state = merged.state
                result.note = merged.note
                result.immediateAction = merged.immediateAction
                result.version += 1
                current[resultId] = result
            }

            operation.error = nil
            operation.attempts = nil
            operation.retryAfter = nil
            updates.append((entry, operation))
        }

        try transaction {
            try put(
                serverJob,
                key: "job:\(failed.jobId)",
                kind: "job",
                jobId: failed.jobId
            )

            for (entry, operation) in updates {
                entry.key = "operation:\(operation.request.operationId)"
                entry.data = try encoder.encode(operation)
            }

            try updateLists(serverJob)
        }

        jobRevisions[failed.jobId, default: 0] += 1
        changed()
        return true
    }

    private func synchronize(generation expectedGeneration: Int) async {
        guard let transport, let rootURL else { return }

        isSyncing = true
        var hadFailures = false
        var serverFailures = 0

        defer {
            if generation == expectedGeneration {
                isSyncing = false
                if hadFailures {
                    changed()
                }
            }
        }

        do {
            let pending = try operations()
            var blocked: Set<Int> = []

            for operation in pending {
                try Task.checkCancellation()
                guard generation == expectedGeneration else { return }

                let jobId = operation.request.jobId

                if let retryAfter = operation.retryAfter,
                   retryAfter > Date(),
                   retryAfter.timeIntervalSinceNow <= 300 {
                    blocked.insert(jobId)
                }

                if blocked.contains(jobId) {
                    continue
                }

                do {
                    let data = try operation.filename.map {
                        try Data(contentsOf: rootURL.appendingPathComponent($0))
                    }

                    let response = try await transport.sendInspectionOperation(
                        operation.request,
                        photo: data
                    )

                    serverFailures = 0
                    guard generation == expectedGeneration else { return }

                    guard response.operationId == operation.request.operationId else {
                        throw InspectionOfflineError.message(
                            "Die Serverbestätigung passt nicht zum Vorgang."
                        )
                    }

                    try transaction {
                        try put(
                            response.item,
                            key: "job:\(jobId)",
                            kind: "job",
                            jobId: jobId
                        )

                        if operation.request.kind == "photo",
                           let photoId = response.photoId {
                            for value in try rows("operation")
                            where value.jobId == jobId {
                                var pending = try decoder.decode(
                                    InspectionPendingOperation.self,
                                    from: value.data
                                )

                                if pending.request.photoOperationId
                                    == operation.request.operationId {
                                    pending.resolvedPhotoId = photoId
                                    value.data = try encoder.encode(pending)
                                }
                            }
                        }

                        if let entry = try row(
                            "operation:\(operation.request.operationId)"
                        ) {
                            try database().delete(entry)
                        }

                        try updateLists(response.item)
                    }

                    jobRevisions[jobId, default: 0] += 1
                    changed()

                    if let filename = operation.filename {
                        try? FileManager.default.removeItem(
                            at: rootURL.appendingPathComponent(filename)
                        )
                    }

                    message = ""
                } catch APIError.unauthorized {
                    message = "Übertragung pausiert – bitte erneut anmelden."
                    return
                } catch {
                    guard generation == expectedGeneration else { return }

                    var reason = error

                    if case APIError.serverStatus(409, _) = reason,
                       operation.request.kind == "result" {
                        do {
                            if try await rebasePendingResults(
                                after: operation.request,
                                generation: expectedGeneration
                            ) {
                                blocked.insert(jobId)
                                syncRequested = true
                                continue
                            }
                        } catch {
                            reason = error
                        }
                    }

                    guard generation == expectedGeneration else { return }

                    if reason.isRequestCancellation {
                        return
                    }
                    if case APIError.unauthorized = reason {
                        return
                    }
                    if InspectionOfflineError.isConnectionError(reason) {
                        message = "Offline – Änderungen bleiben auf dem Gerät."
                        return
                    }

                    if case APIError.serverStatus(let status, _) = reason,
                       status >= 500 || [408, 425, 429].contains(status) {
                        serverFailures += 1
                        if serverFailures >= 3 {
                            return
                        }
                    } else {
                        serverFailures = 0
                    }

                    var failed = operation

                    if let entry = try row(
                        "operation:\(operation.request.operationId)"
                    ) {
                        failed = try decoder.decode(
                            InspectionPendingOperation.self,
                            from: entry.data
                        )
                    }

                    failed.error = reason.localizedDescription
                    failed.attempts = min((failed.attempts ?? 0) + 1, 5)

                    let delay = min(
                        300.0,
                        30.0 * pow(
                            2.0,
                            Double((failed.attempts ?? 1) - 1)
                        )
                    )
                    failed.retryAfter = Date().addingTimeInterval(delay)

                    try transaction {
                        try put(
                            failed,
                            key: "operation:\(operation.request.operationId)",
                            kind: "operation",
                            jobId: jobId
                        )
                    }

                    blocked.insert(jobId)
                    hadFailures = true
                }
            }
        } catch {
            message = "Synchronisierung pausiert: \(error.localizedDescription)"
        }
    }

    private func updateLists(_ job: SafetyInspectionJob) throws {
        for value in try rows("list") {
            var items = try decoder.decode(
                [SafetyInspectionJob].self,
                from: value.data
            )
            if let index = items.firstIndex(where: { $0.id == job.id }) {
                var summary = job
                summary.results = nil
                items[index] = summary
                value.data = try encoder.encode(items)
            }
        }
    }

    func resolve(jobId: Int, keepLocal: Bool) async throws {
        guard !isSyncing, !isResolving, let transport else {
            throw InspectionOfflineError.message(
                "Bitte die laufende Übertragung abwarten."
            )
        }
        isResolving = true
        let expectedGeneration = generation
        defer {
            if generation == expectedGeneration {
                isResolving = false
                requestSync()
            }
        }
        let serverJob = try await transport.fetchSafetyInspectionRemote(id: jobId)
        guard generation == expectedGeneration else {
            throw CancellationError()
        }
        if keepLocal && !serverJob.canEdit {
            throw InspectionOfflineError.message(
                "Die Prüfung ist serverseitig gesperrt. Bitte die Zuordnung oder den Status klären."
            )
        }
        let entries = try rows("operation").filter {
            $0.jobId == jobId
        }
        var versions = Dictionary(
            uniqueKeysWithValues: (serverJob.results ?? []).map {
                ($0.id, $0.version)
            }
        )
        var filenames: [String] = []
        try transaction {
            try put(
                serverJob,
                key: "job:\(jobId)",
                kind: "job",
                jobId: jobId
            )
            for entry in entries {
                var operation = try decoder.decode(
                    InspectionPendingOperation.self,
                    from: entry.data
                )
                if keepLocal {
                    if operation.request.kind == "result" {
                        guard let resultId = operation.request.resultId,
                              let version = versions[resultId] else {
                            throw InspectionOfflineError.message(
                                "Die Prüfpunkte wurden geändert. Bitte die Prüfung im Büro klären."
                            )
                        }
                        operation.request.version = version
                        operation.request.operationId = UUID().uuidString.lowercased()
                        versions[resultId] = version + 1
                        entry.key = "operation:\(operation.request.operationId)"
                    }
                    operation.error = nil
                    entry.data = try encoder.encode(operation)
                } else {
                    if let filename = operation.filename {
                        filenames.append(filename)
                    }
                    try database().delete(entry)
                }
            }
            try updateLists(serverJob)
        }
        jobRevisions[jobId, default: 0] += 1
        changed()
        for filename in filenames {
            if let rootURL {
                try? FileManager.default.removeItem(
                    at: rootURL.appendingPathComponent(filename)
                )
            }
        }
    }

    func retry() throws {
        guard !isSyncing, !isResolving else { return }
        try transaction {
            for value in try rows("operation") {
                var operation = try decoder.decode(
                    InspectionPendingOperation.self,
                    from: value.data
                )
                operation.error = nil
                value.data = try encoder.encode(operation)
            }
        }
        changed()
        requestSync()
    }
}
