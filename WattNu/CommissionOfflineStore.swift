import Combine
import CryptoKit
import Foundation
import Network

@MainActor
final class CommissionOfflineStore: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var isSyncing = false
    @Published private(set) var message = ""
    @Published private(set) var deliveryIssues: [String] = []
    private(set) var snapshot = CommissionOfflineSnapshot()
    private var rootURL: URL?
    private var accountKey: String?
    private var user: AppUser?
    private var transport: APIClient?
    private var generation = 0
    private var dataEpoch = 0
    private var isActive = true
    private var syncTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private let monitor = NWPathMonitor()
    private let storageDirectory: URL?

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
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
            rootURL = root
            accountKey = key
            revision += 1
        }
        self.user = user
        let client = APIClient(baseURL: baseURL)
        client.accessToken = token
        transport = client
        resume()
    }

    func stop() {
        generation += 1
        syncTask?.cancel(); preparationTask?.cancel(); timerTask?.cancel()
        for task in refreshTasks.values { task.cancel() }
        syncTask = nil; preparationTask = nil; timerTask = nil
        refreshTasks = [:]
        snapshot = CommissionOfflineSnapshot()
        transport = nil; user = nil; rootURL = nil; accountKey = nil
        isSyncing = false; message = ""; deliveryIssues = []
        revision += 1
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active { resume() } else { timerTask?.cancel(); timerTask = nil }
    }

    func handles(path: String, method: String) -> Bool {
        if path.hasPrefix("offline-commission-photo/") { return true }
        if path.hasPrefix("/api/commissions") || path == "/api/commission-objects/search" { return true }
        return method == "GET" && (["/api/time-tasks", "/api/time-tasks/search", "/api/inventory/search", "/api/inventory/lookup", "/api/inventory/locations", "/api/appointment-windows", "/api/my-time"].contains(path))
    }

    private func persist() throws {
        guard let rootURL else { throw InspectionOfflineError.message("Der lokale Speicher ist nicht verfügbar. Bitte erneut anmelden.") }
        try JSONEncoder().encode(snapshot).write(to: rootURL.appendingPathComponent("state.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        revision += 1
    }

    private func filename(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func effectiveResources() throws -> [String: CommissionOfflineResource] {
        try CommissionOfflineJSON.overlay(snapshot.resources, operations: snapshot.operations)
    }

    func execute(path: String, method: String, queryItems: [URLQueryItem] = [], body: Data?, contentType: String?, accept: String) async throws -> Data {
        guard transport != nil, user != nil, rootURL != nil else { throw APIError.missingToken }
        if method != "GET" { return try enqueue(path: path, method: method, body: body ?? Data("{}".utf8), contentType: contentType ?? "application/json") }
        if accept != "application/json" || path.hasPrefix("offline-commission-photo/") { return try await binary(path) }
        let query = queryItems.map { CommissionOfflineQuery(name: $0.name, value: $0.value ?? "") }
        let key = CommissionOfflineResource.key(path, query)
        if let cached = try effectiveResources()[key] {
            if cached.fetchedAt.timeIntervalSinceNow < -30 { refreshInBackground(path, query: query) }
            return try presented(cached)
        }
        do {
            try await refresh([CommissionOfflineResource(path: path, query: query, data: Data(), fetchedAt: .distantPast)])
        } catch {
            if let result = try localSearch(path: path, query: query) { return result }
            throw error
        }
        guard let cached = try effectiveResources()[key] else { throw InspectionOfflineError.message("Die angeforderten Daten konnten nicht geladen werden.") }
        return try presented(cached)
    }

    private func presented(_ resource: CommissionOfflineResource) throws -> Data {
        if resource.path == "/api/my-time" { return try myTime(resource) }
        guard resource.path == "/api/commissions" else { return resource.data }
        var payload = try CommissionOfflineJSON.object(resource.data)
        let query = Dictionary(resource.query.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
        payload["items"] = (payload["items"] as? [[String: Any]] ?? []).filter { item in
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
            catch { if generation == expected { message = error.localizedDescription } }
        }
    }

    private func refresh(_ resources: [CommissionOfflineResource]) async throws {
        guard let transport else { throw APIError.missingToken }
        let expected = generation
        let epoch = dataEpoch
        let ordinary = resources.filter { $0.path != "/api/my-time" }
        if !ordinary.isEmpty {
            let requestData = try CommissionOfflineJSON.data(["resources": ordinary.map { resource -> [String: Any] in ["path": resource.path, "query": resource.query.map { ["name": $0.name, "value": $0.value] }] }])
            let data = try await transport.commissionRemoteData(path: "/api/mobile/offline-data", method: "POST", body: requestData)
            guard generation == expected, dataEpoch == epoch, !Task.isCancelled else { throw CancellationError() }
            let payload = try CommissionOfflineJSON.object(data)
            for item in payload["items"] as? [[String: Any]] ?? [] {
                guard let path = item["path"] as? String, let status = item["status"] as? Int else { continue }
                let query = (item["query"] as? [[String: String]] ?? []).map { CommissionOfflineQuery(name: $0["name"] ?? "", value: $0["value"] ?? "") }
                let key = CommissionOfflineResource.key(path, query)
                if status < 400, let value = item["payload"], !(value is NSNull) {
                    let resource = CommissionOfflineResource(path: path, query: query, data: try CommissionOfflineJSON.data(value), fetchedAt: Date())
                    snapshot.resources[key] = resource
                    snapshot.preparationErrors[key] = nil
                    snapshot.preparation.removeAll { $0 == key }
                    if path == "/api/commissions" { try prepare(resource) }
                    collectMedia(value)
                } else {
                    let details = item["payload"] as? [String: Any]
                    snapshot.preparationErrors[key] = details?["message"] as? String ?? "Die Daten konnten nicht geladen werden (\(status))."
                }
            }
        }
        for resource in resources where resource.path == "/api/my-time" {
            let data = try await transport.commissionRemoteData(path: resource.path, query: resource.query.map { URLQueryItem(name: $0.name, value: $0.value) })
            guard generation == expected, dataEpoch == epoch, !Task.isCancelled else { throw CancellationError() }
            snapshot.resources[resource.key] = CommissionOfflineResource(path: resource.path, query: resource.query, data: data, fetchedAt: Date())
        }
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
        for path in ["/api/time-tasks", "/api/inventory/locations", "/api/appointment-windows", "/api/commissions/simple-create-options", "/api/commissions/users"] {
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
                do {
                    let documents = selected.filter { !$0.contains("/content") && !$0.contains("/thumbnail") }
                    if !documents.isEmpty {
                        try await refresh(documents.map { resourceForKey($0) })
                    }
                    for path in selected where path.contains("/content") || path.contains("/thumbnail") { _ = try await binary(path) }
                } catch {
                    if generation == expected, !error.isRequestCancellation {
                        message = error.localizedDescription
                        for path in selected { snapshot.preparationErrors[path] = error.localizedDescription }
                        try? persist()
                    }
                    return
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
                let text = ["title", "name", "code", "item_number", "description", "address", "idnum"].compactMap { item[$0] as? String }.joined(separator: " ")
                if term.isEmpty || text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil { matches[String(describing: item["id"] ?? text)] = item }
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
        var commission = parent.flatMap { resources[$0] }.flatMap { try? CommissionOfflineJSON.object($0.data)["item"] as? [String: Any] } ?? [:]
        if let parent {
            guard !commission.isEmpty else { snapshot = previous; throw InspectionOfflineError.message("Bitte den Auftrag zuerst vollständig öffnen.") }
            var basePath = parent
            var targetID: Int?
            if ["PATCH", "DELETE"].contains(method), parts.count > 4, let target = Int(parts[4]), ["time", "photos"].contains(parts[3]) {
                basePath = parent + "/" + parts[3]
                targetID = target
            }
            if path.hasSuffix("/cancel"), parts.count > 4 {
                basePath = parent + "/materials"; targetID = Int(parts[4])
            }
            let source = try resources[basePath].map { try CommissionOfflineJSON.object($0.data) } ?? ["item": commission]
            var value: [String: Any] = ["path": basePath, "query": [], "value": CommissionOfflineJSON.normalized(path: basePath, payload: source, targetID: targetID)]
            if let targetID { value["target_id"] = targetID }
            base = try CommissionOfflineJSON.data(value)
        }
        if path == "/api/commissions/simple" {
            commission = ["id": id, "local_status": "recorded", "positions": [], "title": fields["title"] ?? "Auftrag", "description": fields["commission_text"] ?? "", "public_id": fields["client_request_id"] ?? UUID().uuidString, "source": "ios", "is_actionable": false, "erp_sync_state": "pending", "can_edit": true, "is_own": true, "assigned_user": userValue]
            commission["contact_person"] = fields["contact_person"]
            commission["commission_type_id"] = fields["commission_type_id"]
            result = ["item": commission]
        } else if path.hasSuffix("/start") || path.hasSuffix("/reject") || path.hasSuffix("/complete") {
            if path.hasSuffix("/start") { commission["local_status"] = "in_progress" }
            else {
                commission["local_status"] = path.hasSuffix("/reject") || (fields["completed"] as? Bool) == false ? "completion_review" : ((fields["tenant_charge"] as? Bool) == true ? "tenant_charge_review" : "done")
                commission["completion_successful"] = fields["completed"] ?? false
                commission["completion_reason"] = fields["reason"]
                commission["completed_at"] = createdAt.ISO8601Format()
                commission["can_edit"] = false
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
            let source = try resources[parent + "/" + section].map { try CommissionOfflineJSON.object($0.data) } ?? [:]
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
                if path.hasSuffix("/read") { result = ["total": 0, "by_commission": [:]] }
                else {
                    item = ["id": fields["request_id"] ?? UUID().uuidString, "process_erp_id": 0, "body": fields["body"] ?? "", "author_name": user.displayName, "direction": "craftsman", "created_at": createdAt.ISO8601Format(), "version": 1, "state": "pending", "mail_state": "not_required", "is_unread": false]
                    result = ["item": item]
                }
            } else if section == "appointments" {
                item["status"] = "pending"; item["proposals"] = []; item["created_at"] = createdAt.ISO8601Format()
                item["recipient_email"] = fields["recipient_email"] ?? ""
                result = ["item": item]
            }
        }
        guard !result.isEmpty || method == "DELETE" else { snapshot = previous; throw InspectionOfflineError.message("Dieser Vorgang kann nicht gespeichert werden.") }
        let response = try CommissionOfflineJSON.data(result)
        let operationID = UUID().uuidString.lowercased()
        if !multipart.isEmpty {
            file = operationID + ".request"
            try body.write(to: rootURL.appendingPathComponent(file!), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let previousID = snapshot.operations.last { $0.commissionID == parentID }?.id ?? parent.flatMap { snapshot.lastOperations[$0] }
        let operation = CommissionOfflineOperation(id: operationID, path: path, method: method, body: try CommissionOfflineJSON.data(fields), contentType: contentType, bodyFilename: file, base: base, predecessorID: previousID, localResponse: response, localID: id, createdAt: createdAt)
        snapshot.operations.append(operation)
        do { try persist() } catch { snapshot = previous; if let file { try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(file)) }; throw error }
        resume()
        return response
    }

    func inventoryItem(code: String) throws -> [String: Any] {
        for resource in snapshot.resources.values {
            let value = try CommissionOfflineJSON.object(resource.data)
            var items = value["items"] as? [[String: Any]] ?? []
            if let item = value["item"] as? [String: Any] { items.append(item) }
            for item in items {
                if (item["item_number"] as? String) == code { return item }
                if let product = item["item"] as? [String: Any], (product["item_number"] as? String) == code { return product }
            }
        }
        throw InspectionOfflineError.message("Der Artikel muss zuerst geladen werden.")
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
        guard isActive, syncTask == nil, transport != nil else { return }
        let expected = generation
        syncTask = Task { [weak self] in
            guard let self else { return }
            isSyncing = true
            defer { if generation == expected { isSyncing = false; syncTask = nil } }
            var blocked: Set<Int> = []
            for operationID in snapshot.operations.map(\.id) {
                guard let queued = snapshot.operations.first(where: { $0.id == operationID }) else { continue }
                guard generation == expected, !Task.isCancelled, let transport, let rootURL else { return }
                let group = queued.commissionID ?? queued.localID
                if blocked.contains(group) || queued.blocked || (queued.retryAfter ?? .distantPast) > Date() { blocked.insert(group); continue }
                do {
                    var value: [String: Any] = ["id": queued.id, "path": queued.path, "method": queued.method, "body": try CommissionOfflineJSON.object(queued.body), "content_type": queued.contentType]
                    if let base = queued.base { value["base"] = try CommissionOfflineJSON.object(base) }
                    if let predecessor = queued.predecessorID { value["predecessor_id"] = predecessor }
                    let operationData = try CommissionOfflineJSON.data(value)
                    let data: Data
                    if let file = queued.bodyFilename {
                        let boundary = "WattNu-" + UUID().uuidString
                        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"operation\"\r\n\r\n".utf8)
                        body.append(operationData)
                        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"request_body\"; filename=\"request.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
                        body.append(try Data(contentsOf: rootURL.appendingPathComponent(file)))
                        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
                        data = try await transport.commissionRemoteData(path: "/api/mobile/offline-operations", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
                    } else { data = try await transport.commissionRemoteData(path: "/api/mobile/offline-operations", method: "POST", body: operationData) }
                    guard generation == expected, !Task.isCancelled else { return }
                    let response = try CommissionOfflineJSON.object(data)
                    guard response["id"] as? String == queued.id, let payload = response["payload"] as? [String: Any] else { throw APIError.invalidResponse }
                    try acknowledge(queued, payload: payload, timeDays: response["my_time"] as? [String: Any] ?? [:])
                    message = ""
                } catch {
                    guard generation == expected, !error.isRequestCancellation else { return }
                    guard let index = snapshot.operations.firstIndex(where: { $0.id == queued.id }) else { continue }
                    snapshot.operations[index].error = error.localizedDescription
                    snapshot.operations[index].attempts += 1
                    if case APIError.serverStatus(let status, let details) = error {
                        snapshot.operations[index].blocked = [400, 403, 404, 409, 413, 422].contains(status)
                        snapshot.operations[index].errorDetails = details.data(using: .utf8)
                        if let data = details.data(using: .utf8), let text = try? CommissionOfflineJSON.object(data)["message"] as? String { snapshot.operations[index].error = text }
                    }
                    snapshot.operations[index].retryAfter = Date().addingTimeInterval(min(300, 30 * pow(2, Double(min(snapshot.operations[index].attempts, 4)))))
                    message = error.localizedDescription
                    try? persist()
                    blocked.insert(group)
                    if InspectionOfflineError.isConnectionError(error) || (error as? APIError).map({ if case .unauthorized = $0 { return true }; return false }) == true { return }
                }
            }
        }
    }

    func acknowledge(_ operation: CommissionOfflineOperation, payload: [String: Any], timeDays: [String: Any]) throws {
        let previous = snapshot
        var acknowledged = operation
        acknowledged.localResponse = try CommissionOfflineJSON.data(payload)
        if let item = payload["item"] as? [String: Any], let serverID = item["id"] as? Int, operation.localID < 0, operation.method == "POST" {
            let localID = operation.localID
            let oldSegment = "/\(localID)"
            let newSegment = "/\(serverID)"
            for index in snapshot.operations.indices {
                snapshot.operations[index].path = snapshot.operations[index].path.replacingOccurrences(of: oldSegment + "/", with: newSegment + "/")
                if snapshot.operations[index].path.hasSuffix(oldSegment) { snapshot.operations[index].path = String(snapshot.operations[index].path.dropLast(oldSegment.count)) + newSegment }
                if var base = try snapshot.operations[index].base.map(CommissionOfflineJSON.object) {
                    if let path = base["path"] as? String { base["path"] = path.replacingOccurrences(of: oldSegment, with: newSegment) }
                    if base["target_id"] as? Int == localID { base["target_id"] = serverID }
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
        }
        snapshot.resources = try CommissionOfflineJSON.overlay(snapshot.resources, operations: [acknowledged])
        snapshot.operations.removeAll { $0.id == operation.id }
        if let parent = operation.commissionID { snapshot.lastOperations["/api/commissions/\(parent)"] = operation.id }
        snapshot.lastSynchronizedAt = Date()
        dataEpoch += 1
        do { try persist() } catch { snapshot = previous; throw error }
        if let file = operation.bodyFilename, let rootURL { try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(file)) }
        if let parent = operation.commissionID {
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
        for operation in operations ?? snapshot.operations where operation.path.contains("/time") {
            let response = try CommissionOfflineJSON.object(operation.localResponse)
            let new = response["item"] as? [String: Any]
            if let owner = (new?["user"] as? [String: Any])?["id"] as? Int, owner != user?.id { continue }
            let base = try operation.base.map(CommissionOfflineJSON.object)
            let old = base?["value"] as? [String: Any]
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
        for index in snapshot.operations.indices where !snapshot.operations[index].blocked {
            snapshot.operations[index].error = nil; snapshot.operations[index].retryAfter = nil
        }
        try persist()
        resume()
    }

    func resolve(operationID: String, keepLocal: Bool) async throws {
        guard !isSyncing, let index = snapshot.operations.firstIndex(where: { $0.id == operationID }) else { throw InspectionOfflineError.message("Bitte die laufende Übertragung abwarten.") }
        let expected = generation
        let operation = snapshot.operations[index]
        if keepLocal {
            if !operation.blocked {
                snapshot.operations[index].error = nil
                snapshot.operations[index].retryAfter = nil
                try persist(); resume(); return
            }
            if let details = operation.errorDetails, (try? CommissionOfflineJSON.object(details)["code"] as? String) == "operation_reused" {
                throw InspectionOfflineError.message("Dieser Vorgang wurde bereits bestätigt. Bitte den Serverstand übernehmen und den Auftrag prüfen.")
            }
            if let baseData = operation.base {
                var base = try CommissionOfflineJSON.object(baseData)
                if let path = base["path"] as? String {
                    try await refresh([CommissionOfflineResource(path: path, query: [], data: Data(), fetchedAt: .distantPast)])
                    guard generation == expected, let resource = snapshot.resources[path], let currentIndex = snapshot.operations.firstIndex(where: { $0.id == operationID }) else { throw CancellationError() }
                    base["value"] = CommissionOfflineJSON.normalized(path: path, payload: try CommissionOfflineJSON.object(resource.data), targetID: base["target_id"] as? Int)
                    snapshot.operations[currentIndex].base = try CommissionOfflineJSON.data(base)
                    snapshot.operations[currentIndex].predecessorID = nil
                }
            }
            guard let currentIndex = snapshot.operations.firstIndex(where: { $0.id == operationID }) else { return }
            snapshot.operations[currentIndex].blocked = false; snapshot.operations[currentIndex].error = nil; snapshot.operations[currentIndex].retryAfter = nil
        } else {
            let group = operation.commissionID ?? operation.localID
            let discarded = snapshot.operations.filter { $0.id == operationID || (($0.commissionID ?? $0.localID) == group && $0.createdAt >= operation.createdAt) }
            snapshot.operations.removeAll { queued in discarded.contains { $0.id == queued.id } }
        }
        try persist(); resume()
    }

    func loadDeliveryIssues() async {
        guard let transport else { return }
        let expected = generation
        do {
            let data = try await transport.commissionRemoteData(path: "/api/mobile/delivery-issues")
            guard generation == expected else { return }
            deliveryIssues = (try CommissionOfflineJSON.object(data)["items"] as? [[String: Any]] ?? []).compactMap { $0["message"] as? String }
        } catch { if generation == expected { message = error.localizedDescription } }
    }
}
