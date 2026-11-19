import Combine
import CryptoKit
import Foundation
import Network

@MainActor
final class CommissionOfflineStore: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var isSyncing = false
    @Published private(set) var message = ""
    @Published private(set) var preparationMessage = ""
    @Published private(set) var deliveryIssues: [String] = []
    @Published private(set) var sendingGroups: Set<Int> = []
    private(set) var snapshot = CommissionOfflineSnapshot() {
        didSet { resourceOverlay = nil }
    }
    private var resourceOverlay: [String: CommissionOfflineResource]?
    private var rootURL: URL?
    private var accountKey: String?
    private var user: AppUser?
    private var transport: APIClient?
    private var generation = 0
    private var dataEpoch = 0
    private var isActive = true
    private var syncTasks: [Int: Task<Void, Never>] = [:]
    private var uploadGroups: Set<Int> = []
    private var resolvingGroups: Set<Int> = []
    private var authenticationRetryAfter: Date?
    private var preparationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private let monitor = NWPathMonitor()
    private let storageDirectory: URL?
    private let networkSession: URLSession

    init(storageDirectory: URL? = nil, session: URLSession = .shared) {
        self.storageDirectory = storageDirectory
        networkSession = session
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                Task { @MainActor [weak self] in self?.resume() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "commission.network"))
    }

    func bind(user: AppUser?, baseURL: URL, token: String?) throws {
        guard let user, let token else { stop(); return }
        let key = SHA256.hash(data: Data("\(baseURL.absoluteString)|\(user.id)".utf8)).map { String(format: "%02x", $0) }.joined()
        if accountKey != key {
            stop()
            let directory = try storageDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("CommissionOffline", isDirectory: true)
            let root = directory.appendingPathComponent(key, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: file.path) {
                snapshot = try JSONDecoder().decode(CommissionOfflineSnapshot.self, from: Data(contentsOf: file))
            }
            for key in snapshot.preparationErrors.keys.sorted() where !snapshot.preparation.contains(key) {
                snapshot.preparation.append(key)
            }
            rootURL = root
            accountKey = key
            if snapshot.queueVersion != 2 || snapshot.deviceID == nil {
                snapshot.deviceID = snapshot.deviceID ?? UUID().uuidString.lowercased()
                snapshot.queueVersion = 2
                for index in snapshot.operations.indices where snapshot.operations[index].scopedDependencies != true {
                    let queued = snapshot.operations[index]
                    if queued.changesStatus || queued.errorCode == "dependency_pending" || queued.errorCode == "operation_reused" {
                        snapshot.operations[index].blocked = false
                        snapshot.operations[index].retryAfter = nil
                    }
                }
                for id in unavailableIDs { try invalidateCommission(id) }
                try persist()
            } else { revision += 1 }
        }
        if transport?.accessToken != token { authenticationRetryAfter = nil }
        self.user = user
        let client = APIClient(baseURL: baseURL, session: networkSession)
        client.accessToken = token
        transport = client
        resume()
    }

    func stop() {
        generation += 1
        for task in syncTasks.values { task.cancel() }
        preparationTask?.cancel(); timerTask?.cancel()
        for task in refreshTasks.values { task.cancel() }
        syncTasks = [:]; preparationTask = nil; timerTask = nil
        sendingGroups = []; uploadGroups = []; resolvingGroups = []; authenticationRetryAfter = nil
        refreshTasks = [:]
        snapshot = CommissionOfflineSnapshot()
        transport = nil; user = nil; rootURL = nil; accountKey = nil
        isSyncing = false; message = ""; preparationMessage = ""; deliveryIssues = []
        revision += 1
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active { resume() } else { timerTask?.cancel(); timerTask = nil }
    }

    func handles(path: String, method: String) -> Bool {
        if path.hasPrefix("offline-commission-photo/") { return true }
        if path.hasPrefix("/api/commissions") || path == "/api/commission-objects/search" { return true }
        return method == "GET" && (["/api/mobile/config", "/api/time-tasks", "/api/time-tasks/search", "/api/inventory/search", "/api/inventory/lookup", "/api/inventory/locations", "/api/appointment-windows", "/api/my-time"].contains(path))
    }

    private func persist() throws {
        guard let rootURL else { throw InspectionOfflineError.message("Der lokale Speicher ist nicht verfügbar. Bitte erneut anmelden.") }
        try JSONEncoder().encode(snapshot).write(to: rootURL.appendingPathComponent("state.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        revision += 1
    }

    private func filename(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func resolvedPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).map { snapshot.idMappings[String($0)].map(String.init) ?? String($0) }.joined(separator: "/")
    }

    private func remapped(_ value: Any, field: String = "") -> Any {
        if let object = value as? [String: Any] { return object.reduce(into: [String: Any]()) { result, pair in result[pair.key] = remapped(pair.value, field: pair.key) } }
        if let items = value as? [Any] { return items.map { remapped($0) } }
        if field == "id" || field.hasSuffix("_id"), let id = value as? Int, let mapped = snapshot.idMappings[String(id)] { return mapped }
        if let text = value as? String, text.hasPrefix("/api/") { return resolvedPath(text) }
        return value
    }

    private func collectionPayload(_ path: String, resources: [String: CommissionOfflineResource]) throws -> [String: Any] {
        var items: [String: [String: Any]] = [:]
        for resource in resources.values where resource.path == path {
            let payload = try CommissionOfflineJSON.object(resource.data)
            for item in payload["items"] as? [[String: Any]] ?? [] {
                if let id = item["id"] { items[String(describing: id)] = item }
            }
        }
        return ["items": Array(items.values)]
    }

    private func effectiveResources() throws -> [String: CommissionOfflineResource] {
        if let resourceOverlay { return resourceOverlay }
        let operations = snapshot.operations.filter { operation in
            !(operation.blocked && (operation.changesStatus || operation.errorCode == "duplicate_booking")) && !isUnavailable(operation.path)
        }
        let resources = try CommissionOfflineJSON.overlay(snapshot.resources, operations: operations)
        resourceOverlay = resources
        return resources
    }

    private var unavailableIDs: Set<Int> {
        snapshot.unavailableCommissionIDs ?? []
    }

    private func commissionID(for path: String) -> Int? {
        let parts = path.split(separator: "/")
        guard parts.count >= 3, parts[0] == "api", parts[1] == "commissions" else { return nil }
        return Int(parts[2])
    }

    private func isUnavailable(_ path: String) -> Bool {
        commissionID(for: path).map { unavailableIDs.contains($0) } ?? false
    }

    private var unavailableCommissionError: APIError {
        .serverStatus(404, "Der Auftrag ist nicht mehr verfügbar.")
    }

    private func invalidateCommission(_ id: Int) throws {
        var ids = unavailableIDs
        if ids.insert(id).inserted { dataEpoch += 1 }
        snapshot.unavailableCommissionIDs = ids
        for (key, var resource) in snapshot.resources {
            if commissionID(for: resource.path) == id {
                snapshot.resources[key] = nil
            } else if resource.path == "/api/commissions" {
                var payload = try CommissionOfflineJSON.object(resource.data)
                let items = payload["items"] as? [[String: Any]] ?? []
                let remaining = items.filter { $0["id"] as? Int != id }
                if remaining.count != items.count {
                    payload["items"] = remaining
                    resource.data = try CommissionOfflineJSON.data(payload)
                    snapshot.resources[key] = resource
                }
            }
        }
        snapshot.preparation.removeAll { commissionID(for: resourceForKey($0).path) == id }
        for key in snapshot.preparationErrors.keys where commissionID(for: resourceForKey(key).path) == id {
            snapshot.preparationErrors[key] = nil
        }
        let message = "Der Auftrag ist nicht mehr verfügbar. Lokale Änderungen bleiben zur Prüfung erhalten."
        let details = try CommissionOfflineJSON.data(["code": "commission_unavailable", "message": message])
        for index in snapshot.operations.indices where snapshot.operations[index].commissionID == id {
            snapshot.operations[index].blocked = true
            snapshot.operations[index].error = message
            snapshot.operations[index].errorDetails = details
        }
    }

    private func cachedResource(path: String, query: [CommissionOfflineQuery], resources: [String: CommissionOfflineResource]) -> CommissionOfflineResource? {
        if path == "/api/commissions" { return fallbackResource(path: path, query: query, resources: resources) }
        return resources[CommissionOfflineResource.key(path, query)] ?? fallbackResource(path: path, query: query, resources: resources)
    }

    private func coversCommissionQuery(_ cached: [CommissionOfflineQuery], requested: [CommissionOfflineQuery]) -> Bool {
        let cachedValues = Dictionary(cached.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
        let requestedValues = Dictionary(requested.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
        func owner(_ values: [String: String]) -> Int? {
            if values["scope"] != "all" { return user?.id ?? Int.min }
            return values["user_id"].flatMap(Int.init)
        }
        let cachedOwner = owner(cachedValues)
        let requestedOwner = owner(requestedValues)
        let cachedStatus = cachedValues["status"] ?? "all"
        let requestedStatus = requestedValues["status"] ?? "all"
        let coversOwner = cachedOwner == nil || cachedOwner == requestedOwner
        let coversStatus = cachedStatus == "all" || cachedStatus == requestedStatus
            || (cachedStatus == "active" && CommissionStatusFilter.activeLocalStatuses.contains(requestedStatus))
        return coversOwner && coversStatus
    }

    func cachedCommissions(scope: CommissionScopeFilter, status: CommissionStatusFilter, userId: Int?) throws -> [Commission]? {
        var query = [CommissionOfflineQuery(name: "scope", value: scope.rawValue)]
        if status != .all { query.append(CommissionOfflineQuery(name: "status", value: status.rawValue)) }
        if let userId { query.append(CommissionOfflineQuery(name: "user_id", value: String(userId))) }
        let resources = try effectiveResources()
        guard let resource = cachedResource(path: "/api/commissions", query: query, resources: resources) else { return nil }
        return try JSONDecoder().decode(ListResponse<Commission>.self, from: presented(resource)).items
    }

    func execute(path: String, method: String, queryItems: [URLQueryItem] = [], body: Data?, contentType: String?, accept: String, refreshBeforeReturning: Bool = false) async throws -> Data {
        guard transport != nil, user != nil, rootURL != nil else { throw APIError.missingToken }
        let resolved = resolvedPath(path)
        if resolved != path { return try await execute(path: resolved, method: method, queryItems: queryItems, body: body, contentType: contentType, accept: accept, refreshBeforeReturning: refreshBeforeReturning) }
        if isUnavailable(path) { throw unavailableCommissionError }
        if method != "GET" { return try enqueue(path: path, method: method, body: body ?? Data("{}".utf8), contentType: contentType ?? "application/json") }
        if accept != "application/json" || path.hasPrefix("offline-commission-photo/") { return try await binary(path) }
        let query = queryItems.map { CommissionOfflineQuery(name: $0.name, value: $0.value ?? "") }
        let available = try effectiveResources()
        if !refreshBeforeReturning, let cached = cachedResource(path: path, query: query, resources: available) {
            if cached.fetchedAt.timeIntervalSinceNow < -30 { refreshInBackground(path, query: query) }
            return try presented(cached)
        }
        let expected = generation
        for attempt in 0..<2 {
            do {
                try await refresh([CommissionOfflineResource(path: path, query: query, data: Data(), fetchedAt: .distantPast)])
                break
            } catch {
                guard generation == expected, !Task.isCancelled else { throw CancellationError() }
                if isUnavailable(path) { throw unavailableCommissionError }
                let available = try effectiveResources()
                if let cached = cachedResource(path: path, query: query, resources: available) { return try presented(cached) }
                if error.isRequestCancellation && attempt == 0 { continue }
                if let result = try localSearch(path: path, query: query) { return result }
                throw error
            }
        }
        if isUnavailable(path) { throw unavailableCommissionError }
        let refreshed = try effectiveResources()
        guard let cached = cachedResource(path: path, query: query, resources: refreshed) else { throw InspectionOfflineError.message("Die angeforderten Daten konnten nicht geladen werden.") }
        return try presented(cached)
    }

    private func fallbackResource(path: String, query: [CommissionOfflineQuery], resources: [String: CommissionOfflineResource]) -> CommissionOfflineResource? {
        if path.hasSuffix("/photos"), let base = resources[path], var payload = try? CommissionOfflineJSON.object(base.data) {
            let context = query.first { $0.name == "context" }?.value
            let entity = query.first { $0.name == "entity" }?.value
            payload["items"] = (payload["items"] as? [[String: Any]] ?? []).filter { item in
                (context == nil || context == "" || context == item["context"] as? String) && (entity == nil || entity == "" || entity?.lowercased() == (item["external_entity_name"] as? String)?.lowercased())
            }
            guard let data = try? CommissionOfflineJSON.data(payload) else { return nil }
            return CommissionOfflineResource(path: path, query: query, data: data, fetchedAt: base.fetchedAt)
        }
        if path == "/api/commissions" {
            let covering = resources.values.filter { $0.path == path && coversCommissionQuery($0.query, requested: query) }.sorted {
                $0.requestDate == $1.requestDate ? $0.key < $1.key : $0.requestDate > $1.requestDate
            }.first
            if let covering {
                return CommissionOfflineResource(path: path, query: query, data: covering.data, fetchedAt: covering.fetchedAt, requestStartedAt: covering.requestStartedAt)
            }
            var items: [Int: [String: Any]] = [:]
            let ordered = resources.values.sorted {
                $0.requestDate == $1.requestDate ? $0.key < $1.key : $0.requestDate < $1.requestDate
            }
            for resource in ordered where resource.path == path || (resource.path.split(separator: "/").count == 3 && commissionID(for: resource.path) != nil) {
                guard let payload = try? CommissionOfflineJSON.object(resource.data) else { continue }
                let values = payload["items"] as? [[String: Any]] ?? (payload["item"] as? [String: Any]).map { [$0] } ?? []
                for item in values { if let id = item["id"] as? Int { items[id] = item } }
            }
            guard !items.isEmpty, let data = try? CommissionOfflineJSON.data(["items": items.keys.sorted().compactMap { items[$0] }]) else { return nil }
            return CommissionOfflineResource(path: path, query: query, data: data, fetchedAt: .distantPast)
        }
        return nil
    }

    private func presented(_ resource: CommissionOfflineResource) throws -> Data {
        if resource.path == "/api/my-time" { return try myTime(resource) }
        if resource.path.hasPrefix("/api/inventory/") {
            var payload = try CommissionOfflineJSON.object(resource.data)
            if let item = payload["item"] as? [String: Any] { payload["item"] = stockAdjusted(item) }
            if let items = payload["items"] as? [[String: Any]] { payload["items"] = items.map { stockAdjusted($0) } }
            return try CommissionOfflineJSON.data(payload)
        }
        guard resource.path == "/api/commissions" else { return resource.data }
        var payload = try CommissionOfflineJSON.object(resource.data)
        let query = Dictionary(resource.query.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
        payload["items"] = (payload["items"] as? [[String: Any]] ?? []).filter { item in
            if let id = item["id"] as? Int, unavailableIDs.contains(id) { return false }
            let status = item["local_status"] as? String ?? ""
            let requestedStatus = query["status"] ?? "all"
            let statusMatches = requestedStatus == "all" || requestedStatus == status || (requestedStatus == "active" && ["waiting_for_acceptance", "open", "in_progress"].contains(status)) || status == "recorded"
            let assigned = (item["assigned_user"] as? [String: Any])?["id"] as? Int
            let ownerMatches = query["scope"] != "mine" || assigned == user?.id
            return statusMatches && ownerMatches && (query["user_id"].flatMap(Int.init).map { $0 == assigned } ?? true)
        }
        return try CommissionOfflineJSON.data(payload)
    }

    private func refreshInBackground(_ path: String, query: [CommissionOfflineQuery]) {
        let key = CommissionOfflineResource.key(path, query)
        guard isActive, refreshTasks[key] == nil else { return }
        let expected = generation
        refreshTasks[key] = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { refreshTasks[key] = nil } }
            do { try await refresh([CommissionOfflineResource(path: path, query: query, data: Data(), fetchedAt: .distantPast)]) }
            catch {
                if generation == expected { _ = recordPreparationFailure(error, keys: [key]) }
            }
        }
    }

    private func recordPreparationFailure(_ error: Error, keys: [String]) -> Bool {
        guard !Task.isCancelled, !error.isRequestCancellation else { return false }
        let availableKeys = keys.filter { !isUnavailable(resourceForKey($0).path) }
        if availableKeys.isEmpty { return true }
        for key in availableKeys where !snapshot.preparation.contains(key) { snapshot.preparation.append(key) }
        if InspectionOfflineError.isConnectionError(error) {
            preparationMessage = "Die Verbindung ist unterbrochen. Aktuelle Daten werden automatisch erneut geladen, sobald die Verbindung wieder verfügbar ist."
            try? persist()
            return false
        }
        let text: String
        if case APIError.serverStatus(_, let details) = error,
           let data = details.data(using: .utf8),
           let value = try? CommissionOfflineJSON.object(data)["message"] as? String {
            text = value
        } else { text = error.localizedDescription }
        for key in availableKeys { snapshot.preparationErrors[key] = text }
        try? persist()
        return true
    }

    private func refresh(_ resources: [CommissionOfflineResource]) async throws {
        guard let transport else { throw APIError.missingToken }
        let expected = generation
        var epoch = dataEpoch
        let requestedAt = Date()
        let ordinary = resources.filter { !["/api/my-time", "/api/mobile/config"].contains($0.path) && !isUnavailable($0.path) }
        if !ordinary.isEmpty {
            let requestData = try CommissionOfflineJSON.data(["resources": ordinary.map { resource -> [String: Any] in ["path": resource.path, "query": resource.query.map { ["name": $0.name, "value": $0.value] }] }])
            let data = try await transport.commissionRemoteData(path: "/api/mobile/offline-data", method: "POST", body: requestData)
            guard generation == expected, dataEpoch == epoch, !Task.isCancelled else { throw CancellationError() }
            let payload = try CommissionOfflineJSON.object(data)
            let responses = payload["items"] as? [[String: Any]] ?? []
            let missingIDs = Set(responses.compactMap { item -> Int? in
                guard item["status"] as? Int == 404, let path = item["path"] as? String,
                      let id = commissionID(for: path), id > 0, path == "/api/commissions/\(id)" else { return nil }
                if let current = snapshot.resources[path], current.requestDate > requestedAt { return nil }
                return id
            })
            for id in missingIDs { try invalidateCommission(id) }
            for item in responses {
                guard let path = item["path"] as? String, let status = item["status"] as? Int else { continue }
                if isUnavailable(path) { continue }
                let query = (item["query"] as? [[String: String]] ?? []).map { CommissionOfflineQuery(name: $0["name"] ?? "", value: $0["value"] ?? "") }
                let key = CommissionOfflineResource.key(path, query)
                if let current = snapshot.resources[key], current.requestDate > requestedAt { continue }
                if status < 400, let value = item["payload"], !(value is NSNull) {
                    var visibleValue = value
                    if path == "/api/commissions", var object = value as? [String: Any] {
                        let items = (object["items"] as? [[String: Any]] ?? []).filter { item in
                            (item["id"] as? Int).map { !missingIDs.contains($0) } ?? true
                        }
                        var unavailable = unavailableIDs
                        unavailable.subtract(items.compactMap { $0["id"] as? Int })
                        let availableAgain = unavailableIDs.subtracting(unavailable)
                        snapshot.unavailableCommissionIDs = unavailable
                        for index in snapshot.operations.indices {
                            let operation = snapshot.operations[index]
                            if availableAgain.contains(operation.groupID), operation.errorCode == "commission_unavailable" {
                                snapshot.operations[index].blocked = false
                                snapshot.operations[index].error = nil
                                snapshot.operations[index].errorDetails = nil
                                snapshot.operations[index].retryAfter = nil
                            }
                        }
                        object["items"] = items
                        visibleValue = object
                    }
                    if var object = visibleValue as? [String: Any], let error = object["sync_error"] as? String, !error.isEmpty {
                        snapshot.preparationErrors[key] = error
                        if !snapshot.preparation.contains(key) { snapshot.preparation.append(key) }
                        object["sync_error"] = NSNull()
                        visibleValue = object
                    } else { snapshot.preparationErrors[key] = nil }
                    let resource = CommissionOfflineResource(path: path, query: query, data: try CommissionOfflineJSON.data(visibleValue), fetchedAt: Date(), requestStartedAt: requestedAt)
                    snapshot.resources[key] = resource
                    if snapshot.preparationErrors[key] == nil { snapshot.preparation.removeAll { $0 == key } }
                    if path == "/api/commissions" { try prepare(resource) }
                    collectMedia(visibleValue)
                } else {
                    let details = item["payload"] as? [String: Any]
                    snapshot.preparationErrors[key] = details?["message"] as? String ?? "Die Daten konnten nicht geladen werden (\(status))."
                    if !snapshot.preparation.contains(key) { snapshot.preparation.append(key) }
                }
            }
            epoch = dataEpoch
        }
        for resource in resources where ["/api/my-time", "/api/mobile/config"].contains(resource.path) {
            let data = try await transport.commissionRemoteData(path: resource.path, query: resource.query.map { URLQueryItem(name: $0.name, value: $0.value) })
            guard generation == expected, dataEpoch == epoch, !Task.isCancelled else { throw CancellationError() }
            if let current = snapshot.resources[resource.key], current.requestDate > requestedAt { continue }
            snapshot.resources[resource.key] = CommissionOfflineResource(path: resource.path, query: resource.query, data: data, fetchedAt: Date(), requestStartedAt: requestedAt)
            snapshot.preparation.removeAll { $0 == resource.key }
            snapshot.preparationErrors[resource.key] = nil
        }
        preparationMessage = ""
        try persist()
        resumePreparation()
    }

    private func resourceForKey(_ key: String) -> CommissionOfflineResource {
        let components = URLComponents(string: key)
        return CommissionOfflineResource(path: components?.path ?? key, query: (components?.queryItems ?? []).map { CommissionOfflineQuery(name: $0.name, value: $0.value ?? "") }, data: Data(), fetchedAt: .distantPast)
    }

    private func prepare(_ list: CommissionOfflineResource) throws {
        let payload = try CommissionOfflineJSON.object(list.data)
        for item in payload["items"] as? [[String: Any]] ?? [] {
            guard let id = item["id"] as? Int, id > 0, ["waiting_for_acceptance", "open", "in_progress", "recorded"].contains(item["local_status"] as? String ?? "") else { continue }
            if unavailableIDs.contains(id) { continue }
            for suffix in ["", "/time", "/materials", "/photos", "/attachments", "/contacts", "/appointments", "/infos", "/history", "/completion-check"] {
                let path = "/api/commissions/\(id)" + suffix
                if (snapshot.resources[path]?.fetchedAt.timeIntervalSinceNow ?? -.infinity) < -60,
                   !snapshot.preparation.contains(path) { snapshot.preparation.append(path) }
            }
        }
        for date in MyTimeMonth(containing: Date()).dates {
            let key = CommissionOfflineResource.key("/api/my-time", [CommissionOfflineQuery(name: "date", value: Formatters.apiDateText(date))])
            if snapshot.resources[key] == nil, !snapshot.preparation.contains(key) { snapshot.preparation.append(key) }
        }
        for path in ["/api/mobile/config", "/api/time-tasks", "/api/inventory/locations", "/api/appointment-windows", "/api/commissions/simple-create-options", "/api/commissions/users"] {
            if snapshot.resources[path] == nil, !snapshot.preparation.contains(path) { snapshot.preparation.append(path) }
        }
    }

    private func collectMedia(_ value: Any) {
        if let object = value as? [String: Any] {
            for key in ["content_path", "thumbnail_path"] {
                if let path = object[key] as? String, snapshot.media[path] == nil,
                   !snapshot.preparation.contains(path) { snapshot.preparation.append(path) }
            }
            for child in object.values { collectMedia(child) }
        } else if let items = value as? [Any] { for child in items { collectMedia(child) } }
    }

    private func binary(_ path: String) async throws -> Data {
        guard let rootURL else { throw APIError.missingToken }
        if let file = snapshot.media[path] { return try Data(contentsOf: rootURL.appendingPathComponent(file)) }
        guard let transport else { throw APIError.missingToken }
        let expected = generation
        let data = try await transport.commissionRemoteData(path: path, accept: "application/octet-stream")
        guard generation == expected, !Task.isCancelled else { throw CancellationError() }
        let name = filename(path) + ".media"
        try data.write(to: rootURL.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        snapshot.media[path] = name
        snapshot.preparation.removeAll { $0 == path }
        snapshot.preparationErrors[path] = nil
        preparationMessage = ""
        try persist()
        return data
    }

    private func resumePreparation() {
        guard isActive, transport != nil, preparationTask == nil, !snapshot.preparation.isEmpty else { return }
        let expected = generation
        preparationTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { preparationTask = nil } }
            var attempted: Set<String> = []
            while generation == expected && isActive && !Task.isCancelled {
                let selected = Array(snapshot.preparation.filter { !attempted.contains($0) }.prefix(20))
                if selected.isEmpty { return }
                attempted.formUnion(selected)
                let documents = selected.filter { !$0.contains("/content") && !$0.contains("/thumbnail") && resourceForKey($0).path != "/api/my-time" }
                if !documents.isEmpty {
                    do { try await refresh(documents.map { self.resourceForKey($0) }) }
                    catch {
                        guard generation == expected, recordPreparationFailure(error, keys: documents) else { return }
                    }
                }
                for key in selected where !documents.contains(key) {
                    guard generation == expected, isActive, !Task.isCancelled else { return }
                    if isUnavailable(resourceForKey(key).path) { continue }
                    do {
                        if resourceForKey(key).path == "/api/my-time" { try await refresh([resourceForKey(key)]) }
                        else { _ = try await binary(key) }
                    } catch {
                        guard generation == expected, recordPreparationFailure(error, keys: [key]) else { return }
                    }
                }
            }
        }
    }

    private func localSearch(path: String, query: [CommissionOfflineQuery]) throws -> Data? {
        guard path.contains("search") || path.hasSuffix("/lookup") else { return nil }
        let term = query.first { ["q", "code"].contains($0.name) }?.value ?? ""
        var matches: [String: [String: Any]] = [:]
        for resource in try effectiveResources().values where resource.path == path || (path.contains("inventory") && resource.path.contains("inventory")) || (path.contains("time-tasks") && resource.path.contains("time-tasks")) {
            let object = try CommissionOfflineJSON.object(resource.data)
            let items = object["items"] as? [[String: Any]] ?? (object["item"] as? [String: Any]).map { [$0] } ?? []
            for item in items {
                let text = ["title", "name", "code", "item_number", "description", "address", "idnum", "label", "tenant_name"].compactMap { item[$0] as? String }.joined(separator: " ")
                let exactMatch = ((item["item_number"] as? String)?.caseInsensitiveCompare(term) == .orderedSame) || ((item["barcodes"] as? [String])?.contains(term) == true)
                let selected = path.hasSuffix("/lookup") ? exactMatch : (term.isEmpty || text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
                let requestedType = query.first { $0.name == "item_type_id" }.flatMap { Int($0.value) }
                let actualType = (item["item_type"] as? [String: Any])?["id"] as? Int
                if selected && (requestedType == nil || requestedType == actualType) {
                    let identity = item["id"].map { String(describing: $0) } ?? "\(item["object_type"] ?? ""):\(item["object_id"] ?? text)"
                    matches[identity] = path.contains("inventory") ? stockAdjusted(item) : item
                }
            }
        }
        if path.hasSuffix("/lookup") { return try matches.values.first.map { try CommissionOfflineJSON.data(["item": $0]) } }
        return try CommissionOfflineJSON.data(["items": Array(matches.values.prefix(50))])
    }
}

private extension CommissionOfflineStore {
    func enqueue(path: String, method: String, body: Data, contentType: String) throws -> Data {
        guard let rootURL, let user else { throw APIError.missingToken }
        let previous = snapshot
        let parts = path.split(separator: "/").map(String.init)
        let parentID = parts.count > 2 ? Int(parts[2]) : nil
        let parent = parentID.map { "/api/commissions/\($0)" }
        let resources = try effectiveResources()
        let fields: [String: Any]
        let multipart = contentType.hasPrefix("multipart/") ? CommissionOfflineJSON.multipart(body, contentType: contentType) : []
        if let dataPart = multipart.first(where: { $0.0 == "data" }) {
            fields = try CommissionOfflineJSON.object(dataPart.1)
        } else if !multipart.isEmpty {
            fields = Dictionary(multipart.filter { !["photo", "photos"].contains($0.0) }.map { ($0.0, String(data: $0.1, encoding: .utf8) ?? "") }, uniquingKeysWith: { _, last in last })
        } else { fields = try CommissionOfflineJSON.object(body) }
        let id = snapshot.nextID
        snapshot.nextID -= 1
        let createdAt = Date()
        let userValue = try CommissionOfflineJSON.object(JSONEncoder().encode(user))
        var result: [String: Any] = [:]
        var file: String?
        var base: Data?
        var photoIDs: [Int] = []
        var commission = parent.flatMap { resources[$0] }.flatMap { try? CommissionOfflineJSON.object($0.data)["item"] as? [String: Any] } ?? [:]
        if let parent {
            guard !commission.isEmpty else { snapshot = previous; throw InspectionOfflineError.message("Bitte den Auftrag zuerst vollständig öffnen.") }
            if method == "POST", parts.count == 4, parts[3] == "time" {
                let configuration = try resources["/api/mobile/config"].map { try CommissionOfflineJSON.object($0.data) } ?? [:]
                let allowOnCompleted = configuration["allow_time_on_completed_commissions"] as? Bool ?? true
                let item = try JSONDecoder().decode(Commission.self, from: CommissionOfflineJSON.data(commission))
                if !item.allowsNewTimeEntries(allowOnCompleted: allowOnCompleted) {
                    snapshot = previous
                    throw InspectionOfflineError.message("Für diesen abgeschlossenen Auftrag können keine neuen Zeiten erfasst werden.")
                }
            }
            var basePath = parent
            var targetID: Int?
            if method == "POST", path.hasSuffix("/appointments") { basePath = parent + "/appointments" }
            if ["PATCH", "DELETE"].contains(method), parts.count > 4, let target = Int(parts[4]), ["time", "photos"].contains(parts[3]) {
                basePath = parent + "/" + parts[3]
                targetID = target
            }
            if path.hasSuffix("/cancel"), parts.count > 4 {
                basePath = parent + "/materials"; targetID = Int(parts[4])
            }
            let source: [String: Any]
            if basePath == parent { source = ["item": commission] }
            else { source = try collectionPayload(basePath, resources: resources) }
            var value: [String: Any] = ["path": basePath, "query": [], "value": CommissionOfflineJSON.normalized(path: basePath, payload: source, targetID: targetID)]
            if let targetID { value["target_id"] = targetID }
            base = try CommissionOfflineJSON.data(value)
        }
        if path == "/api/commissions/simple" {
            commission = ["id": id, "local_status": "recorded", "positions": [], "title": fields["title"] ?? "Auftrag", "description": fields["commission_text"] ?? "", "public_id": fields["client_request_id"] ?? UUID().uuidString, "source": "ios", "is_actionable": false, "erp_sync_state": "pending", "can_edit": true, "is_own": true, "assigned_user": userValue]
            commission["created_by_name"] = user.displayName
            commission["contact_person"] = fields["contact_person"]
            commission["recording_date"] = createdAt.ISO8601Format()
            commission["commission_type_id"] = fields["commission_type_id"]
            result = ["item": commission]
            for suffix in ["time", "materials", "photos", "attachments", "appointments", "infos", "history"] {
                let resourcePath = "/api/commissions/\(id)/" + suffix
                snapshot.resources[resourcePath] = CommissionOfflineResource(path: resourcePath, query: [], data: try CommissionOfflineJSON.data(["items": []]), fetchedAt: Date())
            }
            var photos: [[String: Any]] = []
            for part in multipart where part.0 == "photos" {
                let photoID = snapshot.nextID
                snapshot.nextID -= 1
                photoIDs.append(photoID)
                let imagePath = "offline-commission-photo/" + UUID().uuidString
                let imageFile = filename(imagePath) + ".media"
                try part.1.write(to: rootURL.appendingPathComponent(imageFile), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                snapshot.media[imagePath] = imageFile
                photos.append(["id": photoID, "commission_id": id, "source": "app", "context": "order", "original_filename": "foto.jpg", "mime_type": "image/jpeg", "size_bytes": part.1.count, "content_path": imagePath, "thumbnail_path": imagePath, "uploaded_by": userValue])
            }
            let photosPath = "/api/commissions/\(id)/photos"
            snapshot.resources[photosPath] = CommissionOfflineResource(path: photosPath, query: [], data: try CommissionOfflineJSON.data(["items": photos]), fetchedAt: Date())
        } else if path.hasSuffix("/start") || path.hasSuffix("/reject") || path.hasSuffix("/complete") {
            if path.hasSuffix("/start") { commission["local_status"] = "in_progress" }
            else {
                commission["local_status"] = path.hasSuffix("/reject") || (fields["completed"] as? Bool) == false ? "completion_review" : ((fields["tenant_charge"] as? Bool) == true ? "tenant_charge_review" : "done")
                commission["completion_successful"] = fields["completed"] ?? false
                commission["completion_reason"] = fields["reason"]
                commission["completed_at"] = createdAt.ISO8601Format()
            }
            result = ["item": commission]
        } else if path.hasSuffix("/appointments/accepted") {
            let date = fields["date"] as? String ?? ""
            let time = fields["time"] as? String
            commission["accepted_appointment_from"] = method == "DELETE" ? NSNull() : date + (time.map { "T" + $0 + ":00" } ?? "T00:00:00")
            commission["accepted_appointment_to"] = NSNull()
            commission["accepted_appointment_comment"] = fields["comment"] ?? NSNull()
            commission["accepted_appointment_is_manual"] = method != "DELETE"
            commission["accepted_appointment_has_time"] = time != nil
            result = ["item": commission]
        } else if parts.count >= 4, let parent {
            let section = parts[3]
            let targetID = parts.count > 4 ? Int(parts[4]) : nil
            let source = try collectionPayload(parent + "/" + section, resources: resources)
            let existing = (source["items"] as? [[String: Any]])?.first { ($0["id"] as? Int) == targetID } ?? [:]
            var item = existing.merging(fields) { _, new in new }
            item["id"] = targetID ?? id
            item["commission_id"] = parentID
            if section == "time" {
                let tasks = try snapshot.resources["/api/time-tasks"].map { (try CommissionOfflineJSON.object($0.data)["items"] as? [[String: Any]]) ?? [] } ?? []
                item["task_template"] = tasks.first { ($0["id"] as? Int) == (fields["task_template_id"] as? Int) } ?? existing["task_template"] ?? NSNull()
                item["user"] = existing["user"] ?? userValue
                item["minutes"] = fields["minutes"] as? Int ?? ["work_minutes", "waiting_minutes", "material_minutes", "travel_minutes", "documentation_minutes", "extra_minutes"].reduce(0) { $0 + (fields[$1] as? Int ?? 0) }
                item["deviation_minutes"] = 0; item["deviation_percent"] = 0
                item["review_status"] = "ok"; item["can_edit"] = true
                item["service_date"] = fields["service_date"] ?? Formatters.apiDateText(Date())
                item["created_at"] = existing["created_at"] ?? createdAt.ISO8601Format()
                result = method == "DELETE" ? [:] : ["item": item]
            } else if section == "materials" {
                if path.hasSuffix("/cancel") {
                    item = existing; item["is_cancelled"] = true; item["can_cancel"] = false
                } else {
                    let inventory = try inventoryItem(code: fields["code"] as? String ?? "")
                    item["item"] = inventory; item["movement_type"] = "withdrawal"; item["user"] = userValue
                    item["can_cancel"] = true; item["is_cancelled"] = false
                    let locations = try snapshot.resources["/api/inventory/locations"].map { (try CommissionOfflineJSON.object($0.data)["items"] as? [[String: Any]]) ?? [] } ?? []
                    item["source_location"] = locations.first { ($0["id"] as? Int) == (fields["location_id"] as? Int) } ?? NSNull()
                }
                result = ["item": item, "inventory_item": item["item"] ?? [:]]
            } else if section == "photos" {
                if method == "POST" {
                    let image = multipart.first { $0.0 == "photo" }?.1 ?? Data()
                    guard !image.isEmpty else { snapshot = previous; throw InspectionOfflineError.message("Die Bilddatei fehlt.") }
                    let imagePath = "offline-commission-photo/\(UUID().uuidString)"
                    let imageFile = filename(imagePath) + ".media"
                    try image.write(to: rootURL.appendingPathComponent(imageFile), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    snapshot.media[imagePath] = imageFile
                    item = item.merging(["source": "app", "context": "order", "original_filename": "foto.jpg", "mime_type": "image/jpeg", "size_bytes": image.count, "content_path": imagePath, "thumbnail_path": imagePath, "uploaded_by": userValue, "created_at": createdAt.ISO8601Format()]) { _, new in new }
                }
                result = method == "DELETE" ? [:] : ["item": item, "duplicate": false]
            } else if section == "infos" {
                if path.hasSuffix("/read") {
                    let requested = fields["items"] as? [[String: Any]] ?? []
                    let messages = source["items"] as? [[String: Any]] ?? []
                    let readCount = messages.filter { message in
                        message["is_unread"] as? Bool == true && requested.contains {
                            $0["id"] as? String == message["id"] as? String && $0["version"] as? Int == message["version"] as? Int
                        }
                    }.count
                    var counts = ProcessInfoStore.shared.unreadByCommission
                    if let parentID { counts[parentID] = max(0, (counts[parentID] ?? readCount) - readCount) }
                    result = ["total": max(counts.values.reduce(0, +), ProcessInfoStore.shared.unreadTotal - readCount), "by_commission": Dictionary(uniqueKeysWithValues: counts.map { (String($0.key), $0.value) })]
                }
                else {
                    item = ["id": fields["request_id"] ?? UUID().uuidString, "process_erp_id": 0, "body": fields["body"] ?? "", "author_name": user.displayName, "direction": "craftsman", "created_at": createdAt.ISO8601Format(), "version": 1, "state": "pending", "mail_state": "not_required", "is_unread": false]
                    result = ["item": item]
                }
            } else if section == "appointments" {
                let options = try snapshot.resources["/api/appointment-windows"].map { try CommissionOfflineJSON.object($0.data) } ?? [:]
                let windows = options["items"] as? [[String: Any]] ?? []
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "HH:mm"
                var proposals: [[String: Any]] = []
                for proposal in fields["proposals"] as? [[String: Any]] ?? [] {
                    let window = windows.first { $0["id"] as? Int == proposal["window_id"] as? Int }
                    let start = window?["start_time"] as? String ?? proposal["start_time"] as? String ?? ""
                    let duration = options["custom_time_duration_minutes"] as? Int ?? 60
                    let end = window?["end_time"] as? String ?? formatter.date(from: start).map { formatter.string(from: $0.addingTimeInterval(Double(duration * 60))) } ?? start
                    proposals.append(["id": snapshot.nextID, "window_id": proposal["window_id"] ?? NSNull(), "proposed_date": proposal["date"] ?? "", "start_time": start, "end_time": end, "window_name": window?["name"] ?? "Konkrete Uhrzeit", "accepted": false])
                    snapshot.nextID -= 1
                }
                item["status"] = "pending"; item["proposals"] = proposals; item["created_at"] = createdAt.ISO8601Format()
                item["created_by"] = userValue
                item["recipient_email"] = fields["recipient_email"] ?? ""
                result = ["item": item]
            }
        }
        guard !result.isEmpty || method == "DELETE" else { snapshot = previous; throw InspectionOfflineError.message("Dieser Vorgang kann nicht gespeichert werden.") }
        if path.hasSuffix("/infos") || path.hasSuffix("/infos/read") || method == "POST" && ["/time", "/materials", "/photos"].contains(where: { path.hasSuffix($0) }) { base = nil }
        let response = try CommissionOfflineJSON.data(result)
        let operationID = UUID().uuidString.lowercased()
        if !multipart.isEmpty {
            file = operationID + ".request"
            try body.write(to: rootURL.appendingPathComponent(file!), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        var operation = CommissionOfflineOperation(id: operationID, path: path, method: method, body: try CommissionOfflineJSON.data(fields), contentType: contentType, bodyFilename: file, base: base, localResponse: response, localID: id, createdAt: createdAt)
        operation.scopedDependencies = true
        let sequenceKey = operation.sequenceKey
        operation.predecessorID = snapshot.operations.last {
            $0.sequenceKey == sequenceKey || ($0.path == "/api/commissions/simple" && $0.localID == parentID)
        }?.id
        if operation.createsBooking, let resource = snapshot.resources[path], let payload = try? CommissionOfflineJSON.object(resource.data) {
            let items = payload["items"] as? [[String: Any]] ?? []
            operation.knownBookingIDs = Array(items.compactMap { $0["id"] as? Int }.filter { $0 > 0 }.prefix(2000))
        }
        operation.photoIDs = photoIDs
        snapshot.operations.append(operation)
        do { try persist() } catch {
            let addedFiles = Set(snapshot.media.values).subtracting(previous.media.values)
            snapshot = previous
            for name in addedFiles { try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(name)) }
            if let file { try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(file)) }
            throw error
        }
        resume()
        return response
    }

    func inventoryItem(code: String) throws -> [String: Any] {
        func find(_ value: Any) -> [String: Any]? {
            if let object = value as? [String: Any] {
                if object["item_number"] as? String == code { return object }
                for child in object.values { if let item = find(child) { return item } }
            } else if let items = value as? [Any] {
                for child in items { if let item = find(child) { return item } }
            }
            return nil
        }
        for resource in snapshot.resources.values {
            if let product = find(try CommissionOfflineJSON.object(resource.data)) { return stockAdjusted(product) }
        }
        throw InspectionOfflineError.message("Der Artikel muss zuerst geladen werden.")
    }

    func stockAdjusted(_ product: [String: Any]) -> [String: Any] {
        guard product["item_number"] != nil else { return product }
        var product = product
        for operation in snapshot.operations where operation.path.contains("/materials") && operation.errorCode != "duplicate_booking" {
            guard let result = try? CommissionOfflineJSON.object(operation.localResponse), let movement = result["item"] as? [String: Any], let item = movement["item"] as? [String: Any], item["id"] as? Int == product["id"] as? Int, ["warehouse", "vehicle"].contains(movement["source"] as? String ?? ""), let quantity = movement["quantity"] as? Double else { continue }
            let delta = operation.path.hasSuffix("/cancel") ? quantity : -quantity
            product["stock_quantity"] = max(0, (product["stock_quantity"] as? Double ?? 0) + delta)
            let location = (movement["source_location"] as? [String: Any])?["id"] as? Int
            if var stocks = product["stocks"] as? [[String: Any]] {
                for index in stocks.indices where ((stocks[index]["location"] as? [String: Any])?["id"] as? Int) == location {
                    stocks[index]["quantity"] = max(0, (stocks[index]["quantity"] as? Double ?? 0) + delta)
                }
                product["stocks"] = stocks
            }
        }
        return product
    }

    func replacingInventory(_ value: Any, product: [String: Any]) -> Any {
        if let object = value as? [String: Any] {
            if object["item_number"] != nil, object["id"] as? Int == product["id"] as? Int { return product }
            return object.mapValues { replacingInventory($0, product: product) }
        }
        if let items = value as? [Any] { return items.map { replacingInventory($0, product: product) } }
        return value
    }

    func resume() {
        guard isActive, transport != nil else { return }
        requestSync(); resumePreparation()
        if timerTask == nil {
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard let self, !Task.isCancelled else { return }
                    requestSync(); resumePreparation()
                }
            }
        }
    }

    func requestSync() {
        guard isActive, let transport, let rootURL,
              (authenticationRetryAfter ?? .distantPast) <= Date() else { return }
        var precedingSequences: Set<String> = []
        var pendingTimes: Set<Int> = []
        let config = snapshot.resources["/api/mobile/config"].flatMap { try? CommissionOfflineJSON.object($0.data) }
        let allowLateTime = config?["allow_time_on_completed_commissions"] as? Bool ?? true
        let now = Date()
        let expected = generation
        for operation in snapshot.operations {
            if syncTasks.count >= 4 { break }
            let group = operation.groupID
            let firstInSequence = precedingSequences.insert(operation.sequenceKey).inserted
            if operation.method == "POST", operation.path.hasSuffix("/time") { pendingTimes.insert(group) }
            guard firstInSequence, !operation.blocked, !operation.needsServerID, !isUnavailable(operation.path),
                  (operation.retryAfter ?? .distantPast) <= now, syncTasks[group] == nil, !resolvingGroups.contains(group) else { continue }
            if !allowLateTime, pendingTimes.contains(group), operation.path.hasSuffix("/complete"),
               (try? CommissionOfflineJSON.object(operation.body)["completed"] as? Bool) == true { continue }
            if operation.bodyFilename != nil {
                guard uploadGroups.count < 2 else { continue }
                uploadGroups.insert(group)
            }
            sendingGroups.insert(group)
            syncTasks[group] = Task { [weak self] in
                guard let self else { return }
                defer {
                    if generation == expected {
                        syncTasks[group] = nil
                        sendingGroups.remove(group)
                        uploadGroups.remove(group)
                        if syncTasks.isEmpty {
                            isSyncing = false
                            resumePreparation()
                        }
                        requestSync()
                    }
                }
                await send(operation, using: transport, rootURL: rootURL, generation: expected)
            }
        }
        if !syncTasks.isEmpty && !isSyncing { isSyncing = true }
    }

    private func syncRequest(_ transport: APIClient, path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await transport.commissionRemoteData(path: path, method: method, body: body, contentType: contentType)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(45))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let data = try await group.next() else { throw CancellationError() }
            return data
        }
    }

    private func receipt(for operation: CommissionOfflineOperation, using transport: APIClient) async throws -> [String: Any]? {
        do {
            let data = try await syncRequest(transport, path: "/api/mobile/offline-operations/" + operation.id)
            return try CommissionOfflineJSON.object(data)
        } catch APIError.serverStatus(404, _) {
            return nil
        }
    }

    private func applyReceipt(_ response: [String: Any], to operation: CommissionOfflineOperation) throws {
        guard response["id"] as? String == operation.id, let payload = response["payload"] as? [String: Any] else { throw APIError.invalidResponse }
        try acknowledge(operation, payload: payload, timeDays: response["my_time"] as? [String: Any] ?? [:], references: response["references"] as? [String: Int] ?? [:])
    }

    private func send(_ queued: CommissionOfflineOperation, using transport: APIClient, rootURL: URL, generation expected: Int) async {
        var operation = queued
        do {
            if operation.scopedDependencies != true {
                let existing = try await receipt(for: operation, using: transport)
                guard generation == expected, !Task.isCancelled, let index = snapshot.operations.firstIndex(where: { $0.id == queued.id }) else { return }
                if let existing {
                    try applyReceipt(existing, to: operation)
                    return
                }
                guard !isUnavailable(operation.path) else { return }
                if operation.createsBooking {
                    operation.predecessorID = nil
                } else if let predecessor = snapshot.operations.first(where: { $0.id == operation.predecessorID }),
                          predecessor.sequenceKey != operation.sequenceKey, predecessor.path != "/api/commissions/simple" {
                    operation.predecessorID = nil
                }
                operation.scopedDependencies = true
                snapshot.operations[index] = operation
                do { try persist() } catch {
                    snapshot.operations[index] = queued
                    throw error
                }
            }
            var value: [String: Any] = [
                "id": operation.id, "path": operation.path, "method": operation.method,
                "body": try CommissionOfflineJSON.object(operation.body), "content_type": operation.contentType,
                "local_photo_ids": operation.photoIDs
            ]
            if let base = operation.base { value["base"] = try CommissionOfflineJSON.object(base) }
            if let predecessor = operation.predecessorID { value["predecessor_id"] = predecessor }
            if operation.createsBooking {
                value["device_id"] = snapshot.deviceID
                value["known_booking_ids"] = operation.knownBookingIDs ?? []
                if operation.confirmDuplicate == true { value["confirm_duplicate"] = true }
            }

            let operationData = try CommissionOfflineJSON.data(value)
            let data: Data
            let contentType: String
            if let filename = operation.bodyFilename {
                let file = rootURL.appendingPathComponent(filename)
                let boundary = "WattNu-" + UUID().uuidString
                contentType = "multipart/form-data; boundary=\(boundary)"
                data = try await Task.detached(priority: .utility) {
                    var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"operation\"\r\n\r\n".utf8)
                    body.append(operationData)
                    body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"request_body\"; filename=\"request.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
                    body.append(try Data(contentsOf: file))
                    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
                    return body
                }.value
            } else {
                data = operationData
                contentType = "application/json"
            }
            guard generation == expected, !Task.isCancelled, !isUnavailable(operation.path) else { return }
            let response = try await syncRequest(transport, path: "/api/mobile/offline-operations", method: "POST", body: data, contentType: contentType)
            guard generation == expected, !Task.isCancelled else { return }
            try applyReceipt(CommissionOfflineJSON.object(response), to: operation)
            message = ""
        } catch {
            guard generation == expected, !Task.isCancelled, !isUnavailable(operation.path),
                  let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
            if error.isRequestCancellation {
                snapshot.operations[index].retryAfter = Date().addingTimeInterval(5)
                return
            }
            recordSyncFailure(error, index: index)
        }
    }

    private func recordSyncFailure(_ error: Error, index: Int) {
        let operation = snapshot.operations[index]
        if case APIError.unauthorized = error { authenticationRetryAfter = Date().addingTimeInterval(30) }
        if case APIError.serverStatus(let status, let details) = error {
            let problem = details.data(using: .utf8).flatMap { try? CommissionOfflineJSON.object($0) }
            let code = problem?["code"] as? String
            if code == "commission_unavailable", let commissionID = operation.commissionID {
                do {
                    try invalidateCommission(commissionID)
                    try persist()
                    return
                } catch { message = error.localizedDescription }
            }
            if code == "dependency_pending", let predecessor = operation.predecessorID,
               !snapshot.operations.contains(where: { $0.id == predecessor }) {
                snapshot.operations[index].predecessorID = nil
                snapshot.operations[index].retryAfter = nil
                try? persist()
                return
            }
            if status == 409, let data = details.data(using: .utf8), (try? autoMerge(index: index, details: data)) == true {
                try? persist()
                return
            }
            snapshot.operations[index].blocked = [400, 403, 404, 409, 410, 413, 422].contains(status)
            snapshot.operations[index].errorDetails = details.data(using: .utf8)
            snapshot.operations[index].error = problem?["message"] as? String ?? error.localizedDescription
            if status == 409, operation.changesStatus, let commissionID = operation.commissionID {
                refreshInBackground("/api/commissions/\(commissionID)", query: [])
            }
            if code == "duplicate_booking" { refreshInBackground(operation.path, query: []) }
        } else {
            snapshot.operations[index].error = error.localizedDescription
        }
        snapshot.operations[index].attempts += 1
        snapshot.operations[index].retryAfter = Date().addingTimeInterval(min(300, 30 * pow(2, Double(min(snapshot.operations[index].attempts, 4)))))
        try? persist()
    }

    func autoMerge(index: Int, details: Data) throws -> Bool {
        let operation = snapshot.operations[index]
        guard operation.method == "PATCH", let baseData = operation.base else { return false }
        let error = try CommissionOfflineJSON.object(details)
        guard error["code"] as? String == "conflict", let current = error["current"] as? [String: Any], let original = error["base"] as? [String: Any] else { return false }
        var base = try CommissionOfflineJSON.object(baseData)
        let response = try CommissionOfflineJSON.object(operation.localResponse)
        guard var item = response["item"] as? [String: Any], let path = base["path"] as? String else { return false }
        let local = CommissionOfflineJSON.normalized(path: path, payload: ["items": [item]], targetID: base["target_id"] as? Int) as? [String: Any] ?? [:]
        let keys = Set(original.keys).union(current.keys).union(local.keys)
        func equal(_ lhs: Any?, _ rhs: Any?) throws -> Bool { try CommissionOfflineJSON.data(lhs ?? NSNull()) == CommissionOfflineJSON.data(rhs ?? NSNull()) }
        let remoteChanges = try Set(keys.filter { try !equal(original[$0], current[$0]) })
        let localChanges = try Set(keys.filter { try !equal(original[$0], local[$0]) })
        guard try localChanges.intersection(remoteChanges).allSatisfy({ try equal(local[$0], current[$0]) }) else { return false }
        var body = try CommissionOfflineJSON.object(operation.body)
        for key in remoteChanges {
            item[key] = current[key]
            if body[key] != nil { body[key] = current[key] }
            if key == "task_template" { body["task_template_id"] = (current[key] as? [String: Any])?["id"] ?? NSNull() }
        }
        base["value"] = current
        snapshot.operations[index].base = try CommissionOfflineJSON.data(base)
        snapshot.operations[index].body = try CommissionOfflineJSON.data(body)
        snapshot.operations[index].localResponse = try CommissionOfflineJSON.data(["item": item])
        snapshot.operations[index].predecessorID = nil
        snapshot.operations[index].error = nil
        snapshot.operations[index].blocked = false
        snapshot.operations[index].retryAfter = nil
        return true
    }

    func acknowledge(_ operation: CommissionOfflineOperation, payload: [String: Any], timeDays: [String: Any], references: [String: Int]) throws {
        let previous = snapshot
        var acknowledged = operation
        acknowledged.localResponse = try CommissionOfflineJSON.data(payload)
        if let item = payload["item"] as? [String: Any], let serverID = item["id"] as? Int, operation.localID < 0, operation.method == "POST" {
            let localID = operation.localID
            snapshot.idMappings.merge(references) { _, new in new }
            snapshot.idMappings[String(localID)] = serverID
            var movedResources: [String: CommissionOfflineResource] = [:]
            for resource in snapshot.resources.values {
                let moved = CommissionOfflineResource(path: resolvedPath(resource.path), query: resource.query, data: try CommissionOfflineJSON.data(remapped(CommissionOfflineJSON.object(resource.data))), fetchedAt: resource.fetchedAt)
                movedResources[moved.key] = moved
            }
            snapshot.resources = movedResources
            for index in snapshot.operations.indices {
                snapshot.operations[index].path = resolvedPath(snapshot.operations[index].path)
                snapshot.operations[index].localResponse = try CommissionOfflineJSON.data(remapped(CommissionOfflineJSON.object(snapshot.operations[index].localResponse)))
                snapshot.operations[index].body = try CommissionOfflineJSON.data(remapped(CommissionOfflineJSON.object(snapshot.operations[index].body)))
                if var base = try snapshot.operations[index].base.map(CommissionOfflineJSON.object) {
                    base = remapped(base) as? [String: Any] ?? base
                    snapshot.operations[index].base = try CommissionOfflineJSON.data(base)
                }
            }
            if operation.path.contains("/photos"), let localItem = try CommissionOfflineJSON.object(operation.localResponse)["item"] as? [String: Any], let oldPath = localItem["content_path"] as? String, let file = snapshot.media[oldPath] {
                for key in ["content_path", "thumbnail_path"] { if let path = item[key] as? String { snapshot.media[path] = file } }
            }
            if operation.path == "/api/commissions/simple" {
                let old = "/api/commissions/\(localID)"
                snapshot.resources[old] = nil
            }
        }
        for (date, value) in timeDays {
            let resource = CommissionOfflineResource(path: "/api/my-time", query: [CommissionOfflineQuery(name: "date", value: date)], data: try CommissionOfflineJSON.data(value), fetchedAt: Date())
            snapshot.resources[resource.key] = resource
            if !snapshot.preparation.contains(resource.key) { snapshot.preparation.append(resource.key) }
            snapshot.preparationErrors[resource.key] = nil
        }
        snapshot.resources = try CommissionOfflineJSON.overlay(snapshot.resources, operations: [acknowledged])
        if let product = payload["inventory_item"] as? [String: Any] {
            let itemNumber = Data("\"item_number\"".utf8)
            for (key, var resource) in snapshot.resources where resource.data.range(of: itemNumber) != nil {
                let updatedData = try CommissionOfflineJSON.data(replacingInventory(CommissionOfflineJSON.object(resource.data), product: product))
                guard resource.data != updatedData else { continue }
                resource.data = updatedData
                snapshot.resources[key] = resource
                if ["/api/inventory/search", "/api/inventory/lookup"].contains(resource.path), !snapshot.preparation.contains(key) {
                    snapshot.preparation.append(key)
                }
            }
        }
        snapshot.operations.removeAll { $0.id == operation.id }
        snapshot.lastSynchronizedAt = Date()
        dataEpoch += 1
        do { try persist() } catch { snapshot = previous; throw error }
        if let file = operation.bodyFilename, let rootURL { try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(file)) }
        if let parent = operation.commissionID ?? ((payload["item"] as? [String: Any])?["id"] as? Int), operation.path == "/api/commissions/simple" || operation.commissionID != nil {
            for suffix in ["", "/time", "/materials", "/photos", "/appointments", "/infos"] {
                let path = "/api/commissions/\(parent)" + suffix
                if snapshot.resources[path] != nil { refreshInBackground(path, query: []) }
            }
        }
    }

    func myTime(_ resource: CommissionOfflineResource, operations: [CommissionOfflineOperation]? = nil) throws -> Data {
        var payload = try CommissionOfflineJSON.object(resource.data)
        let date = resource.query.first { $0.name == "date" }?.value ?? payload["date"] as? String ?? ""
        var items = payload["items"] as? [[String: Any]] ?? []
        var minutes = payload["recorded_minutes"] as? Int ?? 0
        for operation in operations ?? snapshot.operations where operation.path.contains("/time") && operation.errorCode != "duplicate_booking" {
            let response = try CommissionOfflineJSON.object(operation.localResponse)
            let new = response["item"] as? [String: Any]
            if let owner = (new?["user"] as? [String: Any])?["id"] as? Int, owner != user?.id { continue }
            let base = try operation.base.map(CommissionOfflineJSON.object)
            let old = base?["value"] as? [String: Any]
            if let owner = (old?["user"] as? [String: Any])?["id"] as? Int, owner != user?.id { continue }
            let oldDate = old?["service_date"] as? String
            if oldDate == date { minutes -= old?["minutes"] as? Int ?? 0 }
            if let id = old?["id"] as? Int { items.removeAll { ($0["id"] as? Int) == id } }
            if let new, new["service_date"] as? String == date, operation.method != "DELETE" {
                minutes += new["minutes"] as? Int ?? 0
                let parent = operation.commissionID ?? 0
                let commission = try snapshot.resources["/api/commissions/\(parent)"].map { (try CommissionOfflineJSON.object($0.data)["item"] as? [String: Any]) ?? [:] } ?? [:]
                items.append(["id": new["id"] ?? operation.localID, "task_template": new["task_template"] ?? NSNull(), "minutes": new["minutes"] ?? 0, "note": new["note"] ?? NSNull(), "service_date": date, "is_free_time": false, "commission": ["id": parent, "number": String(describing: commission["code"] ?? commission["erp_idnum"] ?? parent), "title": commission["title"] ?? "Auftrag"]])
            }
        }
        payload["items"] = items; payload["recorded_minutes"] = minutes
        if let expected = payload["expected_minutes"] as? Int {
            payload["difference_minutes"] = minutes - expected
            payload["status"] = minutes >= expected ? "complete" : "missing"
        }
        return try CommissionOfflineJSON.data(payload)
    }
}

extension CommissionOfflineStore {
    var preparationIssues: [SynchronizationPreparationIssue] {
        let groups = Dictionary(grouping: snapshot.preparationErrors.keys) { key in
            resourceForKey(key).path == "/api/my-time" ? "/api/my-time" : key
        }
        return groups.keys.sorted().map { key in
            let paths = (groups[key] ?? []).sorted()
            return SynchronizationPreparationIssue(id: key, title: key == "/api/my-time" ? "Tagesübersichten konnten nicht aktualisiert werden" : "Daten konnten nicht aktualisiert werden", messages: Array(Set(paths.compactMap { snapshot.preparationErrors[$0] })).sorted(), paths: paths)
        }
    }

    func cachedMonthTotals(_ month: MyTimeMonth) -> [Date: Int]? {
        var totals: [Date: Int] = [:]
        for date in month.dates {
            let key = CommissionOfflineResource.key("/api/my-time", [CommissionOfflineQuery(name: "date", value: Formatters.apiDateText(date))])
            guard let resource = snapshot.resources[key], let data = try? myTime(resource), let value = try? CommissionOfflineJSON.object(data)["recorded_minutes"] as? Int else { return nil }
            totals[date] = value
        }
        return totals
    }

    func retrySynchronization() throws {
        preparationMessage = ""
        authenticationRetryAfter = nil
        for index in snapshot.operations.indices {
            let operation = snapshot.operations[index]
            guard !operation.blocked || (operation.changesStatus && operation.errorCode == "conflict") else { continue }
            snapshot.operations[index].blocked = false
            snapshot.operations[index].error = nil
            snapshot.operations[index].retryAfter = nil
        }
        try persist()
        resume()
    }

    func canResolve(groupID: Int) -> Bool {
        !sendingGroups.contains(groupID) && !resolvingGroups.contains(groupID)
    }

    func resolve(operationID: String, keepLocal: Bool) async throws {
        guard let operation = snapshot.operations.first(where: { $0.id == operationID }),
              let transport, canResolve(groupID: operation.groupID) else {
            throw InspectionOfflineError.message("Bitte die Übertragung dieses Auftrags abwarten.")
        }
        let expected = generation
        let group = operation.groupID
        resolvingGroups.insert(group)
        defer {
            if generation == expected {
                resolvingGroups.remove(group)
                resume()
            }
        }

        let existing = try await receipt(for: operation, using: transport)
        guard generation == expected, let index = snapshot.operations.firstIndex(where: { $0.id == operationID }) else { throw CancellationError() }
        if let existing {
            try applyReceipt(existing, to: operation)
            return
        }
        if keepLocal {
            if isUnavailable(operation.path) || operation.errorCode == "commission_closed" || operation.errorCode == "local_dependency_discarded" {
                throw InspectionOfflineError.message(operation.error ?? "Der Vorgang benötigt Prüfung.")
            }
            var updated = snapshot.operations[index]
            if operation.errorCode == "duplicate_booking" { updated.confirmDuplicate = true }
            if operation.errorCode == "material_booking_confirmation_required" {
                var body = try CommissionOfflineJSON.object(updated.body)
                body["confirm_missing_material"] = true
                updated.body = try CommissionOfflineJSON.data(body)
            }
            if operation.blocked, let baseData = operation.base {
                var base = try CommissionOfflineJSON.object(baseData)
                if let path = base["path"] as? String {
                    try await refresh([CommissionOfflineResource(path: path, query: [], data: Data(), fetchedAt: .distantPast)])
                    guard generation == expected else { throw CancellationError() }
                    guard let resource = snapshot.resources[path] else { throw unavailableCommissionError }
                    base["value"] = CommissionOfflineJSON.normalized(path: path, payload: try CommissionOfflineJSON.object(resource.data), targetID: base["target_id"] as? Int)
                    updated.base = try CommissionOfflineJSON.data(base)
                    updated.predecessorID = nil
                }
            }
            guard generation == expected, let currentIndex = snapshot.operations.firstIndex(where: { $0.id == operationID }) else { throw CancellationError() }
            let previous = snapshot
            updated.blocked = false
            updated.error = nil
            updated.errorDetails = nil
            updated.retryAfter = nil
            snapshot.operations[currentIndex] = updated
            do { try persist() } catch { snapshot = previous; throw error }
        } else {
            let previous = snapshot
            snapshot.operations.remove(at: index)
            let missingMessage = "Der zugehörige lokale Auftrag oder Eintrag wurde verworfen. Diese Änderung bleibt zur Prüfung erhalten."
            let missingDetails = try CommissionOfflineJSON.data(["code": "local_dependency_discarded", "message": missingMessage])
            let localIDs = Set([operation.localID] + operation.photoIDs)
            for index in snapshot.operations.indices {
                let queued = snapshot.operations[index]
                if queued.predecessorID == operationID { snapshot.operations[index].predecessorID = nil }
                if operation.method == "POST", queued.needsServerID,
                   queued.path.split(separator: "/").dropFirst(2).compactMap({ Int($0) }).contains(where: { localIDs.contains($0) }) {
                    snapshot.operations[index].blocked = true
                    snapshot.operations[index].error = missingMessage
                    snapshot.operations[index].errorDetails = missingDetails
                } else if queued.predecessorID == operationID, queued.errorCode == "dependency_pending" {
                    snapshot.operations[index].blocked = false
                    snapshot.operations[index].error = nil
                    snapshot.operations[index].errorDetails = nil
                    snapshot.operations[index].retryAfter = nil
                }
            }
            do { try persist() } catch { snapshot = previous; throw error }
            if let file = operation.bodyFilename, let rootURL { try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(file)) }
            if group > 0 { refreshInBackground("/api/commissions/\(group)", query: []) }
        }
    }

    func retryServerDeliveries() async {
        guard let transport else { return }
        let expected = generation
        do {
            _ = try await transport.commissionRemoteData(path: "/api/mobile/delivery-issues/retry", method: "POST", body: Data("{}".utf8))
            guard generation == expected else { return }
            await loadDeliveryIssues()
        } catch { if generation == expected, !error.isRequestCancellation { message = error.localizedDescription } }
    }

    func loadDeliveryIssues() async {
        guard let transport else { return }
        let expected = generation
        do {
            let data = try await transport.commissionRemoteData(path: "/api/mobile/delivery-issues")
            guard generation == expected else { return }
            deliveryIssues = (try CommissionOfflineJSON.object(data)["items"] as? [[String: Any]] ?? []).compactMap { $0["message"] as? String }
        } catch { if generation == expected, !error.isRequestCancellation { message = error.localizedDescription } }
    }
}
