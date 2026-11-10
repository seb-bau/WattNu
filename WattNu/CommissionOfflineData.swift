import Foundation

struct CommissionOfflineQuery: Codable, Equatable {
    let name: String
    let value: String
}

struct CommissionOfflineResource: Codable {
    let path: String
    let query: [CommissionOfflineQuery]
    var data: Data
    var fetchedAt: Date

    var key: String {
        Self.key(path, query)
    }

    static func key(_ path: String, _ query: [CommissionOfflineQuery] = []) -> String {
        guard !query.isEmpty else { return path }
        var components = URLComponents()
        components.path = path
        components.queryItems = query.sorted { ($0.name, $0.value) < ($1.name, $1.value) }.map {
            URLQueryItem(name: $0.name, value: $0.value)
        }
        return path + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
}

struct CommissionOfflineOperation: Codable, Identifiable {
    var id = UUID().uuidString.lowercased()
    var path: String
    let method: String
    var body: Data
    let contentType: String
    let bodyFilename: String?
    var base: Data?
    var predecessorID: String?
    var localResponse: Data
    let localID: Int
    let createdAt: Date
    var error: String?
    var errorDetails: Data?
    var attempts = 0
    var retryAfter: Date?
    var blocked = false
    var photoIDs: [Int] = []

    var commissionID: Int? {
        let parts = path.split(separator: "/")
        return parts.count > 2 ? Int(parts[2]) : nil
    }

    var title: String {
        if path == "/api/commissions/simple" { return "Auftrag anlegen" }
        if path.contains("/time") { return "Zeitbuchung" }
        if path.contains("/materials") { return "Materialbuchung" }
        if path.contains("/photos") { return "Foto" }
        if path.contains("/appointments") { return "Termin" }
        if path.contains("/infos") { return "Vorgangsinformation" }
        if path.hasSuffix("/start") { return "Auftrag starten" }
        if path.hasSuffix("/reject") { return "Auftrag ablehnen" }
        return "Auftrag abschließen"
    }
}

struct CommissionOfflineSnapshot: Codable {
    var resources: [String: CommissionOfflineResource] = [:]
    var operations: [CommissionOfflineOperation] = []
    var media: [String: String] = [:]
    var preparation: [String] = []
    var preparationErrors: [String: String] = [:]
    var lastOperations: [String: String] = [:]
    var idMappings: [String: Int] = [:]
    var nextID = -1
    var lastSynchronizedAt: Date?
}

enum CommissionOfflineJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    static func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }

    static func normalized(path: String, payload: [String: Any], targetID: Int? = nil) -> Any {
        if path.split(separator: "/").count == 3 {
            let item = payload["item"] as? [String: Any] ?? payload
            return Dictionary(uniqueKeysWithValues: ["local_status", "assigned_user", "can_edit", "is_actionable", "accepted_appointment_from", "accepted_appointment_to", "accepted_appointment_comment", "accepted_appointment_is_manual"].map {
                ($0, item[$0] ?? NSNull())
            })
        }
        if let targetID {
            guard let item = (payload["items"] as? [[String: Any]])?.first(where: { ($0["id"] as? Int) == targetID }) else { return NSNull() }
            let keys = ["id", "user", "task_template", "service_date", "minutes", "note", "work_minutes", "waiting_minutes", "material_minutes", "travel_minutes", "documentation_minutes", "extra_minutes", "review_status", "review_level", "quantity", "usage_status", "cancelled", "caption", "source", "updated_at"]
            return item.filter { keys.contains($0.key) }
        }
        return payload
    }

    static func multipart(_ data: Data, contentType: String) -> [(String, Data)] {
        guard let boundary = contentType.components(separatedBy: "boundary=").last,
              let delimiter = ("--" + boundary.trimmingCharacters(in: CharacterSet(charactersIn: "\""))).data(using: .utf8),
              let separator = "\r\n\r\n".data(using: .utf8) else { return [] }
        var parts: [(String, Data)] = []
        var position = data.startIndex
        while let start = data.range(of: delimiter, in: position..<data.endIndex),
              let next = data.range(of: delimiter, in: start.upperBound..<data.endIndex) {
            let range = start.upperBound..<next.lowerBound
            if let split = data.range(of: separator, in: range),
               let headers = String(data: data[range.lowerBound..<split.lowerBound], encoding: .utf8),
               let nameStart = headers.range(of: "name=\""),
               let nameEnd = headers[nameStart.upperBound...].firstIndex(of: "\"") {
                let name = String(headers[nameStart.upperBound..<nameEnd])
                let end = max(split.upperBound, next.lowerBound - 2)
                parts.append((name, Data(data[split.upperBound..<end])))
            }
            position = next.lowerBound
        }
        return parts
    }

    static func overlay(_ resources: [String: CommissionOfflineResource], operations: [CommissionOfflineOperation]) throws -> [String: CommissionOfflineResource] {
        var result = resources
        for operation in operations {
            let response = try object(operation.localResponse)
            let item = response["item"] as? [String: Any]
            let parts = operation.path.split(separator: "/").map(String.init)
            let parent = operation.commissionID.map { "/api/commissions/\($0)" }
            let isCommission = operation.path == "/api/commissions/simple" || ["start", "reject", "complete", "accepted"].contains(parts.last ?? "")
            for (key, var resource) in result {
                var payload = try object(resource.data)
                if isCommission, let item {
                    if resource.path == "/api/commissions" {
                        var items = payload["items"] as? [[String: Any]] ?? []
                        items.removeAll { ($0["id"] as? Int) == (item["id"] as? Int) }
                        items.insert(item, at: 0)
                        payload["items"] = items
                    } else if resource.path == parent || resource.path == "/api/commissions/\(operation.localID)" {
                        payload["item"] = item
                    }
                } else if let parent, resource.path.hasPrefix(parent + "/"), parts.count >= 4 {
                    let section = parts[3]
                    if resource.path == parent + "/" + section {
                        var items = payload["items"] as? [[String: Any]] ?? []
                        let targetID = parts.count > 4 ? Int(parts[4]) : operation.localID
                        if section == "infos", operation.path.hasSuffix("/read") {
                            let requested = try object(operation.body)["items"] as? [[String: Any]] ?? []
                            for index in items.indices where requested.contains(where: {
                                $0["id"] as? String == items[index]["id"] as? String && $0["version"] as? Int == items[index]["version"] as? Int
                            }) {
                                items[index]["is_unread"] = false
                            }
                        } else if section == "materials", operation.path.hasSuffix("/cancel"),
                           let index = items.firstIndex(where: { ($0["id"] as? Int) == targetID }) {
                            items[index]["is_cancelled"] = true
                            items[index]["can_cancel"] = false
                        } else {
                            items.removeAll { value in
                                if let id = item?["id"] as? String { return (value["id"] as? String) == id }
                                return (value["id"] as? Int) == (item?["id"] as? Int ?? targetID)
                            }
                            if operation.method != "DELETE", let item {
                                let context = resource.query.first { $0.name == "context" }?.value
                                if section != "photos" || context == nil || context == "" || context == (item["context"] as? String) { items.insert(item, at: 0) }
                            }
                        }
                        payload["items"] = items
                    }
                }
                resource.data = try data(payload)
                result[key] = resource
            }
            if isCommission, let item, let id = item["id"] as? Int {
                let path = "/api/commissions/\(id)"
                result[path] = CommissionOfflineResource(path: path, query: [], data: try data(["item": item]), fetchedAt: .distantPast)
            }
        }
        return result
    }
}
